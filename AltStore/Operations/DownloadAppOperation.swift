//
//  DownloadAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 6/10/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import WebKit
import UniformTypeIdentifiers
import AltStoreCore
import AltSign

@objc(DownloadAppOperation)
final class DownloadAppOperation: ResultOperation<ALTApplication> {
    @Managed
    private(set) var app: AppProtocol

    let context: InstallAppOperationContext

    private let appName: String
    private let bundleIdentifier: String
    private var sourceURL: URL?
    private let destinationURL: URL

    private let session = URLSession(configuration: .default)
    private let temporaryDirectory = FileManager.default.uniqueTemporaryURL()

    init(app: AppProtocol, destinationURL: URL, context: InstallAppOperationContext) {
        self.app = app
        self.context = context

        self.appName = app.name
        self.bundleIdentifier = context.bundleIdentifier
        self.sourceURL = app.url
        self.destinationURL = destinationURL

        super.init()

        // App = 3, Dependencies = 1
        self.progress.totalUnitCount = 4
    }

    override func main() {
        super.main()

        if let error = self.context.error {
            self.finish(.failure(error))
            return
        }

        debugLog("Downloading App: \(self.bundleIdentifier)")

        // Set _after_ checking self.context.error to prevent overwriting localized failure for previous errors.
        self.localizedFailure = String(format: NSLocalizedString("%@ could not be downloaded.", comment: ""), self.appName)

        Task { [weak self] in
            guard let self else { return }
            do {
                let appVal = await self.$app.perform {_ in 
                    self.app
                }
                try await self.performAppValidationAndDownload(app: appVal)
            } catch {
                self.finish(.failure(error))
            }
        }
    }

    override func finish(_ result: Result<ALTApplication, Error>) {
        if(FileManager.default.fileExists(atPath: self.temporaryDirectory.path)){
            do {
                try FileManager.default.removeItem(at: self.temporaryDirectory)
            } catch {
                debugLog("Failed to remove DownloadAppOperation temporary directory: \(self.temporaryDirectory). \(error)")
            }
        }

        super.finish(result)
    }
    
    private func performAppValidationAndDownload(app: AppProtocol) async throws {
        do {
            var appVersion: AppVersion?

            if let version = app as? AppVersion {
                appVersion = version
            } else if let storeApp = app as? StoreApp {
                guard let latestVersion = storeApp.latestAvailableVersion else {
                    let failureReason = String(format: NSLocalizedString("The latest version of %@ could not be downloaded.", comment: ""), self.appName)
                    throw OperationError.unknown(failureReason: failureReason)
                }

                // Attempt to download latest _available_ version, and fall back to older versions if necessary.
                appVersion = latestVersion
            }

            if let appVersion {
                try self.verify(appVersion)
            }

            try await self.download(appVersion ?? app)
        } catch let error as VerificationError where error.code == .iOSVersionNotSupported {
            guard let presentingViewController = self.context.presentingViewController, let storeApp = app.storeApp, let latestSupportedVersion = storeApp.latestSupportedVersion,
                  case let version = latestSupportedVersion.version,
                  version != storeApp.installedApp?.version
            else {
                self.finish(.failure(error))
                return
            }

            if let installedApp = storeApp.installedApp {
                // guard !installedApp.matches(latestSupportedVersion) else { return self.finish(.failure(error)) }
                guard installedApp.hasUpdate else {
                    self.finish(.failure(error))
                    return
                }
            }

            let title = NSLocalizedString("Unsupported iOS Version", comment: "")
            let message = error.localizedDescription + "\n\n" + NSLocalizedString("Would you like to download the last version compatible with this device instead?", comment: "")
            let localizedVersion = latestSupportedVersion.localizedVersion

            await MainActor.run {
                let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
                alertController.addAction(UIAlertAction(title: UIAlertAction.cancel.title, style: UIAlertAction.cancel.style) { _ in
                    self.finish(.failure(OperationError.cancelled))
                })
                alertController.addAction(UIAlertAction(title: String(format: NSLocalizedString("Download %@ %@", comment: ""), self.appName, localizedVersion), style: .default) { _ in
                    Task {
                        do {
                            try await self.download(latestSupportedVersion)
                        } catch {
                            self.finish(.failure(error))
                        }
                    }
                })
                presentingViewController.present(alertController, animated: true)
            }
        } catch {
            self.finish(.failure(error))
        }
    }

    private func verify(_ version: AppVersion) throws {
        if let minOSVersion = version.minOSVersion, !ProcessInfo.processInfo.isOperatingSystemAtLeast(minOSVersion) {
            throw VerificationError.iOSVersionNotSupported(app: version, requiredOSVersion: minOSVersion)
        } else if let maxOSVersion = version.maxOSVersion, ProcessInfo.processInfo.operatingSystemVersion > maxOSVersion {
            throw VerificationError.iOSVersionNotSupported(app: version, requiredOSVersion: maxOSVersion)
        }
    }
    
    private func printWithTid(_ msg: String){
        verboseLog("DownloadAppOperation: Thread: \(Thread.current.name ?? Thread.current.description) - " + msg)
    }
    
    private func download(@Managed _ app: AppProtocol) async throws {
        guard let sourceURL = self.sourceURL else {
            throw OperationError.appNotFound(name: self.appName)
        }
        if let appVersion = app as? AppVersion {
            // All downloads go through this path, and `app` is
            // always an AppVersion if downloading from a source,
            // so context.appVersion != nil means downloading from source.
            self.context.appVersion = appVersion
        }
        
        let application = try await downloadIPA(from: sourceURL)
        
        if self.context.bundleIdentifier == StoreApp.dolphinAppID, self.context.bundleIdentifier != application.bundleIdentifier {
            if var infoPlist = NSDictionary(contentsOf: application.bundle.infoPlistURL) as? [String: Any] {
                // Manually update the app's bundle identifier to match the one specified in the source.
                // This allows people who previously installed the app to still update and refresh normally.
                infoPlist[kCFBundleIdentifierKey as String] = StoreApp.dolphinAppID
                (infoPlist as NSDictionary).write(to: application.bundle.infoPlistURL, atomically: true)
            }
        }
        
        _ = try await self.downloadDependencies(for: application)
        
        try FileManager.default.copyItem(at: application.fileURL, to: self.destinationURL, shouldReplace: true)
        
        guard let copiedApplication = ALTApplication(fileURL: self.destinationURL) else { throw OperationError.invalidApp }
        self.finish(.success(copiedApplication))
        
        self.progress.completedUnitCount += 1
        
        func downloadIPA(from sourceURL: URL) async throws -> ALTApplication {
            let fileURL: URL
            
            if sourceURL.isFileURL {
                fileURL = sourceURL
                self.progress.completedUnitCount += 3
            } else {
                // Regular app
                fileURL = try await downloadFile(from: sourceURL)
                self.printWithTid("downloadFile: completed at \(fileURL.path)")
            }
            
            defer {
                if !sourceURL.isFileURL && FileManager.default.fileExists(atPath: fileURL.path) {
                    try? FileManager.default.removeItem(at: fileURL)
                }
            }
            
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) else {
                throw OperationError.appNotFound(name: self.appName)
            }
            
            try FileManager.default.createDirectory(at: self.temporaryDirectory, withIntermediateDirectories: true, attributes: nil)
            
            let appBundleURL: URL
            
            if isDirectory.boolValue {
                // Directory, so assuming this is .app bundle.
                guard Bundle(url: fileURL) != nil else { throw OperationError.invalidApp }
                
                appBundleURL = self.temporaryDirectory.appendingPathComponent(fileURL.lastPathComponent)
                try FileManager.default.copyItem(at: fileURL, to: appBundleURL)
            } else {
                // File, so assuming this is a .ipa file.
                appBundleURL = try FileManager.default.unzipAppBundle(at: fileURL, toDirectory: self.temporaryDirectory)
                
                // Use context's temporaryDirectory to ensure .ipa isn't deleted before we're done installing.
                let ipaURL = self.context.temporaryDirectory.appendingPathComponent("App.ipa")
                try FileManager.default.copyItem(at: fileURL, to: ipaURL)
                
                self.context.ipaURL = ipaURL
            }
            
            guard let application = ALTApplication(fileURL: appBundleURL) else { throw OperationError.invalidApp }

            // perform cleanup of the temp files
            if(FileManager.default.fileExists(atPath: fileURL.path)){
                self.printWithTid("Removing downloaded temp file at: \(fileURL.path)")
                do {
                    try FileManager.default.removeItem(at: fileURL)
                } catch {
                    self.printWithTid("Removing downloaded temp error: \(error)")
                }
            }

            return application
        }
        
        func downloadFile(from downloadURL: URL) async throws -> URL {
            self.printWithTid("download started: \(downloadURL)")
            let (fileURL, response) = try await self.session.download(from: downloadURL)
            if let response = response as? HTTPURLResponse {
                guard response.statusCode != 403 else { throw URLError(.noPermissionsToReadFile) }
                guard response.statusCode != 404 else { throw CocoaError(.fileNoSuchFile, userInfo: [NSURLErrorKey: downloadURL]) }
            }
            self.progress.completedUnitCount += 3
            return fileURL
        }
    }

    struct AltStorePlist: Decodable {
        private enum CodingKeys: String, CodingKey {
            case dependencies = "ALTDependencies"
        }

        var dependencies: [Dependency]
    }

    struct Dependency: Decodable {
        var downloadURL: URL
        var path: String?
        
        var preferredFilename: String {
            let preferredFilename = self.path.map { ($0 as NSString).lastPathComponent } ?? self.downloadURL.lastPathComponent
            return preferredFilename
        }
        
        init(from decoder: Decoder) throws {
            enum CodingKeys: String, CodingKey {
                case downloadURL
                case path
            }
            
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            let urlString = try container.decode(String.self, forKey: .downloadURL)
            let path = try container.decodeIfPresent(String.self, forKey: .path)
            
            guard let downloadURL = URL(string: urlString) else {
                throw DecodingError.dataCorruptedError(forKey: .downloadURL, in: container, debugDescription: "downloadURL is not a valid URL.")
            }
            
            self.downloadURL = downloadURL
            self.path = path
        }
    }
    
    private func downloadDependencies(for application: ALTApplication) async throws -> Set<URL> {
        guard FileManager.default.fileExists(atPath: application.bundle.altstorePlistURL.path) else {
            return []
        }
        
        let data = try Data(contentsOf: application.bundle.altstorePlistURL)
        let altstorePlist = try PropertyListDecoder().decode(AltStorePlist.self, from: data)
                    
        var dependencyURLs = Set<URL>()
        
        for dependency in altstorePlist.dependencies {
            let fileURL = try await self.download(dependency, for: application)
            dependencyURLs.insert(fileURL)
        }
        
        return dependencyURLs
    }
    
    private func download(_ dependency: Dependency, for application: ALTApplication) async throws -> URL {
        do {
            let (fileURL, response) = try await self.session.download(from: dependency.downloadURL)
            defer { try? FileManager.default.removeItem(at: fileURL) }
            
            let path = dependency.path ?? dependency.preferredFilename
            let destinationURL = application.fileURL.appendingPathComponent(path)
            
            let directoryURL = destinationURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: directoryURL.path) {
                try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            }
            
            try FileManager.default.copyItem(at: fileURL, to: destinationURL, shouldReplace: true)
            return destinationURL
        } catch let error as NSError {
            let localizedFailure = String(format: NSLocalizedString("The dependency '%@' could not be downloaded.", comment: ""), dependency.preferredFilename)
            throw error.withLocalizedFailure(localizedFailure)
        }
    }

    private func debugLog(_ text: String) {
        print(text)
    }

    private func verboseLog(_ text: String) {
        let isLoggingEnabled = OperationsLoggingControl.getFromDatabase(for: DownloadAppOperation.self)
        if isLoggingEnabled {
            print(text)
        }
    }
}
