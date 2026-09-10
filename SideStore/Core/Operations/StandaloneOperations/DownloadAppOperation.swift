//
//  DownloadAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 6/10/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import UniformTypeIdentifiers
import SideSign

final class DownloadAppOperation: BasePipelineOperation<InstallAppOperationContext, ALTApplication>, @unchecked Sendable {
    private(set) var app: AppProtocol

    private let appName: String
    private let bundleIdentifier: String
    private var sourceURL: URL?
    private let destinationURL: URL

    private let session = URLSession(configuration: .default)
    private let temporaryDirectory = FileManager.default.uniqueTemporaryURL()

    init(app: AppProtocol, destinationURL: URL, context: InstallAppOperationContext) throws {
        self.app = app

        self.appName = app.name
        self.bundleIdentifier = context.bundleIdentifier
        self.sourceURL = app.url
        self.destinationURL = destinationURL

        try super.init(context: context)
    }

    override func execute(parentProgress: Progress?) async throws -> ALTApplication {
        let startTime = CFAbsoluteTimeGetCurrent()
        debugLog("[DownloadAppOperation] execute() started")
        defer {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            debugLog("[DownloadAppOperation] execute() took: \(String(format: "%.3fs", elapsed))")
        }
        try await super.executePreconditionCheck(parentProgress: parentProgress)
        
        defer {
            if FileManager.default.fileExists(atPath: self.temporaryDirectory.path) {
                do {
                    try FileManager.default.removeItem(at: self.temporaryDirectory)
                } catch {
                    debugLog("[DownloadAppOperation] Failed to remove DownloadAppOperation temporary directory: \(self.temporaryDirectory). \(error)")
                }
            }
        }
        
        if self.isCancelled { throw OperationError.cancelled }
        if let error = self.context.error { throw error }
        
        debugLog("[DownloadAppOperation] Downloading App: \(self.bundleIdentifier)")

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
                
                // set release Track for install/update
                if let track = appVersion.releaseTrack {
                    self.context.releaseTrack = track
                }
            }

            return try await self.download(appVersion ?? app)
            
        } catch let error as VerificationError where error.code == .iOSVersionNotSupported {
            let handler = self.context.handler.unsupportedVersionHandler
            guard let storeApp = app.storeApp,
                  let latestSupportedVersion = storeApp.latestSupportedVersion,
                  case let version = latestSupportedVersion.version,
                  version != storeApp.installedApp?.version
            else {
                throw error
            }

            if let installedApp = storeApp.installedApp {
                // guard !installedApp.matches(latestSupportedVersion) else { return self.finish(.failure(error)) }
                guard installedApp.hasUpdate else {
                    throw error
                }
            }

            let localizedVersion = latestSupportedVersion.localizedVersion
            let shouldDownload = try await handler.resolveUnsupportediOSVersion(
                errorDescription: error.localizedDescription,
                appName: self.appName,
                compatibleVersion: localizedVersion
            )

            if shouldDownload {
                return try await self.download(latestSupportedVersion)
            } else {
                throw OperationError.cancelled
            }
        }
    }

    private func verify(_ version: AppVersion) throws {
        if let minOSVersion = version.minOSVersion, !ProcessInfo.processInfo.isOperatingSystemAtLeast(minOSVersion) {
            throw VerificationError.iOSVersionNotSupported(app: version, requiredOSVersion: minOSVersion)
        } else if let maxOSVersion = version.maxOSVersion, ProcessInfo.processInfo.operatingSystemVersion > maxOSVersion {
            throw VerificationError.iOSVersionNotSupported(app: version, requiredOSVersion: maxOSVersion)
        }
    }
    
    private func download(@Managed _ app: AppProtocol) async throws -> ALTApplication {
        guard let sourceURL = self.sourceURL else {
            throw OperationError.appNotFound(name: self.appName)
        }
        if let appVersion = app as? AppVersion {
            // All downloads go through this path, and `app` is
            // always an AppVersion if downloading from a source,
            // so context.appVersion != nil means downloading from source.
            self.context.appVersion = appVersion
        }
        
        let appBundle = try await downloadIPA(from: sourceURL)
        
        if self.context.bundleIdentifier == StoreApp.dolphinAppID, self.context.bundleIdentifier != appBundle.bundleIdentifier {
            if var infoPlist = NSDictionary(contentsOf: appBundle.bundle.infoPlistURL) as? [String: Any] {
                // Manually update the app's bundle identifier to match the one specified in the source.
                // This allows people who previously installed the app to still update and refresh normally.
                infoPlist[kCFBundleIdentifierKey as String] = StoreApp.dolphinAppID
                (infoPlist as NSDictionary).write(to: appBundle.bundle.infoPlistURL, atomically: true)
            }
        }
        
        let dependencies = try await self.downloadDependencies(for: appBundle)
        if !dependencies.isEmpty {
            self.debugLog("[DownloadAppOperation] Downloaded \(dependencies.count) dependencies for \(appBundle.name): \(dependencies.map(\.lastPathComponent))")
        }
        
        debugLog("[DownloadAppOperation] Moving extracted bundle from \(appBundle.fileURL.path) to destination \(self.destinationURL.path)")
        try FileManager.default.moveItem(at: appBundle.fileURL, to: self.destinationURL, shouldReplace: true)
        debugLog("[DownloadAppOperation] Moving bundle to destination succeeded")
        
        guard let movedAppBundle = ALTApplication(fileURL: self.destinationURL) else { throw OperationError.invalidApp }
        self.setProgress(100)
        return movedAppBundle
    }
    
    func downloadIPA(from sourceURL: URL) async throws -> ALTApplication {
        let fileURL: URL
        
        if sourceURL.isFileURL {
            fileURL = sourceURL
            self.setProgress(75)
        } else {
            // Regular app
            fileURL = try await downloadFile(from: sourceURL)
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
        
        guard let appBundle = ALTApplication(fileURL: appBundleURL) else { throw OperationError.invalidApp }

        // perform cleanup of the temp files
        if !sourceURL.isFileURL && FileManager.default.fileExists(atPath: fileURL.path) {
            verboseLog("[DownloadAppOperation] Removing downloaded temp file at: \(fileURL.path)")
            do {
                try FileManager.default.removeItem(at: fileURL)
            } catch {
                verboseLog("[DownloadAppOperation] Removing downloaded temp error: \(error)")
            }
        }

        return appBundle
    }
    
    func downloadFile(from downloadURL: URL) async throws -> URL {
        debugLog("[DownloadAppOperation] download started: \(downloadURL)")
        let delegate = DownloadProgressDelegate(progress: self.progress)
        do {
            let (fileURL, response) = try await self.session.download(from: downloadURL, delegate: delegate)
            let resp = response as? HTTPURLResponse
            if let resp {
                debugLog("[DownloadAppOperation] downloadFile: completed with status \(resp.statusCode) at \(fileURL.path)")
                guard resp.statusCode != 403 else { throw URLError(.noPermissionsToReadFile) }
                guard resp.statusCode != 404 else { throw CocoaError(.fileNoSuchFile, userInfo: [NSURLErrorKey: downloadURL]) }
            } else {
                debugLog("[DownloadAppOperation] downloadFile: completed at \(fileURL.path)")
            }
            self.setProgress(75)
            return fileURL
        }catch{
            debugLog("[DownloadAppOperation] download failed for url: \(downloadURL)")
            throw error
        }
    }
    
    
    private func downloadDependencies(for appBundle: ALTApplication) async throws -> Set<URL> {
        guard FileManager.default.fileExists(atPath: appBundle.bundle.altstorePlistURL.path) else {
            return []
        }
        
        let data = try Data(contentsOf: appBundle.bundle.altstorePlistURL)
        let altstorePlist = try PropertyListDecoder().decode(AltStorePlist.self, from: data)
                    
        var dependencyURLs = Set<URL>()
        
        for dependency in altstorePlist.dependencies {
            let fileURL = try await self.download(dependency, for: appBundle)
            dependencyURLs.insert(fileURL)
        }
        
        return dependencyURLs
    }
    
    private func download(_ dependency: Dependency, for appBundle: ALTApplication) async throws -> URL {
        do {
            let (fileURL, _) = try await self.session.download(from: dependency.downloadURL)
            defer { try? FileManager.default.removeItem(at: fileURL) }
            
            let path = dependency.path ?? dependency.preferredFilename
            let destinationURL = appBundle.fileURL.appendingPathComponent(path)
            
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
}


extension DownloadAppOperation {
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
}

private class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate {
    let progress: Progress
    private var lastLoggedPercent: Int = -1
    
    init(progress: Progress) {
        self.progress = progress
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 {
            let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            self.progress.completedUnitCount = Int64(fraction * 75.0)
            let percent = Int(fraction * 100.0)
            if percent % 25 == 0 && percent != self.lastLoggedPercent {
                self.lastLoggedPercent = percent
                debugLog("[DownloadAppOperation] Download transfer: \(percent)% (\(ByteCountFormatter.string(fromByteCount: totalBytesWritten, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: totalBytesExpectedToWrite, countStyle: .file)))")
            }
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Unused as download(from:delegate:) returns the file URL directly
    }
}
