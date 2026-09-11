//
//  SideBackupApp.swift
//  SideBackup
//
//  Created by Magesh K on 2/7/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import Combine

extension Bundle {
    var appName: String? {
        let appName =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ??
            Bundle.main.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String
        return appName
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    fileprivate static let startBackupNotification = Notification.Name("io.sidestore.StartBackup")
    fileprivate static let startRestoreNotification = Notification.Name("io.sidestore.StartRestore")
    
    fileprivate static let operationDidFinishNotification = Notification.Name("io.sidestore.BackupOperationFinished")
    
    fileprivate static let operationResultKey = "result"
    fileprivate static let skipNonCopyableKey = "skipNonCopyable"
    
    private var currentBackupReturnURL: URL?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        NotificationCenter.default.addObserver(self, selector: #selector(AppDelegate.operationDidFinish(_:)), name: AppDelegate.operationDidFinishNotification, object: nil)
        return true
    }
    
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        return self.open(url)
    }
    
    func open(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        guard let command = components.host?.lowercased() else { return false }
        
        if let verboseValue = components.queryItems?.first(where: { $0.name == "verbose" })?.value {
            let isVerbose = (verboseValue.lowercased() == "true" || verboseValue == "1")
            ConsoleLog.setVerbose(isVerbose)
        }
        
        let skipNonCopyable: Bool = {
            guard let value = components.queryItems?.first(where: { $0.name == "skipNonCopyable" })?.value else { return false }
            return value.lowercased() == "true" || value == "1"
        }()
        let userInfo: [String: Any] = [AppDelegate.skipNonCopyableKey: skipNonCopyable]
        
        switch command {
        case "backup":
            guard let returnString = components.queryItems?.first(where: { $0.name == "returnURL" })?.value, let returnURL = URL(string: returnString) else { return false }
            self.currentBackupReturnURL = returnURL
            NotificationCenter.default.post(name: AppDelegate.startBackupNotification, object: nil, userInfo: userInfo)
            return true
            
        case "restore":
            guard let returnString = components.queryItems?.first(where: { $0.name == "returnURL" })?.value, let returnURL = URL(string: returnString) else { return false }
            self.currentBackupReturnURL = returnURL
            NotificationCenter.default.post(name: AppDelegate.startRestoreNotification, object: nil, userInfo: userInfo)
            return true
            
        default:
            return false
        }
    }
    
    @objc func operationDidFinish(_ notification: Notification) {
        defer {
            self.currentBackupReturnURL = nil
        }
        
        // TODO: @mahee96: This doesn't account cases where backup is too long and user switched to other apps
        //                 The check for self.currentBackupReturnURL when backup/restore was still in progress but app switched
        //                 between FG/BG is improper, since it will ignore(eat up) the response(success/failure) to parent
        //
        //                 This leaves the backup/restore to show dummy animation forever
        //
        //                 This is bad (Needs fixing - never eat up response like this unless there is no context to post response to!)
        guard
            let returnURL = self.currentBackupReturnURL,
            let result = notification.userInfo?[AppDelegate.operationResultKey] as? Result<Void, Error>
        else {
            return
        }
                
        guard var components = URLComponents(url: returnURL, resolvingAgainstBaseURL: false) else {
            return      // This is ASSERTION Failure, ie RETURN URL needs to be valid. So ignoring (eating up) response is not the solution
        }
        
        switch result {
        case .success:
            components.path = "/success"
            
        case .failure(let error as NSError):
            components.path = "/failure"
            components.queryItems = ["errorDomain": error.domain,
                                     "errorCode": String(error.code),
                                     "errorDescription": error.localizedDescription].map { URLQueryItem(name: $0, value: $1) }
        }
        
        guard let responseURL = components.url else { return }
        
        guard let scheme = responseURL.scheme, scheme.hasPrefix("sidestore") else {
            if let logger = try? ConsoleLog.getConsoleLog() {
                debugLog(logger, "[SideBackup]: Error: responseURL scheme '\(responseURL.scheme ?? "nil")' does not start with 'sidestore'. Aborting launch.")
            }
            return
        }
        
        guard let bundleID = Bundle.main.bundleIdentifier else {
            if let logger = try? ConsoleLog.getConsoleLog() {
                debugLog(logger, "[SideBackup]: Error: Bundle.main.bundleIdentifier is nil. Aborting launch.")
            }
            return
        }
        
        let queryItems = components.queryItems?.reduce(into: [String: String]()) { $0[$1.name] = $1.value } ?? [:]
        
        let targetSideStoreBundleID: String
        if let queryTargetBundleID = queryItems["targetBundleID"] {
            targetSideStoreBundleID = queryTargetBundleID
        } else if scheme.hasPrefix("sidestore-") {
            targetSideStoreBundleID = String(scheme.dropFirst("sidestore-".count))
        } else {
            targetSideStoreBundleID = bundleID.hasSuffix(".SideBackup") 
                    ? (bundleID as NSString).deletingPathExtension 
                    : bundleID
        }
        
        Task { @MainActor in
            let logger = try? ConsoleLog.getConsoleLog()
            if let logger = logger {
                debugLog(logger, "[SideBackup]: Attempting to open target SideStore app '\(targetSideStoreBundleID)' via LSApplicationWorkspace with return URL: \(responseURL.absoluteString)")
            }
            
            let success = await withCheckedContinuation { continuation in
                SideBackupAppLauncher.openApplication(withBundleIdentifier: targetSideStoreBundleID, url: responseURL) { success, error in
                    continuation.resume(returning: success)
                }
            }
            
            if let logger = logger {
                debugLog(logger, "[SideBackup]: LSApplicationWorkspace launch completed with success: \(success)")
            }
            
            if !success {
                if let logger = logger {
                    debugLog(logger, "[SideBackup]: LSApplicationWorkspace launch failed. Falling back to UIApplication.shared.open...")
                }
                let fallbackSuccess = await UIApplication.shared.open(responseURL, options: [:])
                if let logger = logger {
                    debugLog(logger, "[SideBackup]: Fallback UIApplication.shared.open success: \(fallbackSuccess)")
                }
            }
        }
    }
}

enum BackupOperation {
    case backup
    case restore
}

@MainActor
class AppState: ObservableObject {
    @Published var currentOperation: BackupOperation? = nil
    @Published var bootCheckError: Error? = nil
    @Published var progressFraction: Double = 0.0
    @Published var progressText: String = ""
    
    private var cancellables = Set<AnyCancellable>()
    private let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB, .useKB]
        formatter.countStyle = .file
        return formatter
    }()
    
    init() {
        if let error = ConsoleLog.bootCheckError {
            NSLog("[SideBackup] Boot Check ERROR: %@", error.localizedDescription)
            self.bootCheckError = error
        }
        NotificationCenter.default.publisher(for: AppDelegate.startBackupNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self = self else { return }
                let skipNonCopyable = notification.userInfo?[AppDelegate.skipNonCopyableKey] as? Bool ?? false
                Task {
                    await self.backup(skipNonCopyable: skipNonCopyable)
                }
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: AppDelegate.startRestoreNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self = self else { return }
                let skipNonCopyable = notification.userInfo?[AppDelegate.skipNonCopyableKey] as? Bool ?? false
                Task {
                    await self.restore(skipNonCopyable: skipNonCopyable)
                }
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.currentOperation = nil
                self?.progressFraction = 0.0
                self?.progressText = ""
            }
            .store(in: &cancellables)
    }
    
    private func updateProgress(copied: Int64, total: Int64) {
        if total > 0 {
            self.progressFraction = Double(copied) / Double(total)
            let copiedStr = self.byteFormatter.string(fromByteCount: copied)
            let totalStr = self.byteFormatter.string(fromByteCount: total)
            let percent = Int(self.progressFraction * 100)
            self.progressText = "\(copiedStr) / \(totalStr) (\(percent)%)"
        } else {
            self.progressFraction = 0.0
            self.progressText = NSLocalizedString("Processing…", comment: "")
        }
    }

    private func backup(skipNonCopyable: Bool = false) async {
        if let error = self.bootCheckError ?? ConsoleLog.bootCheckError {
            let appName = Bundle.main.appName ?? NSLocalizedString("App", comment: "")
            let title = String(format: NSLocalizedString("%@ could not be backed up.", comment: ""), appName)
            self.process(.failure(error), errorTitle: title)
            return
        }
        self.currentOperation = .backup
        self.progressFraction = 0.0
        self.progressText = NSLocalizedString("Calculating size…", comment: "")
        
        let appName = Bundle.main.appName ?? NSLocalizedString("App", comment: "")
        
        do {
            try await BackupEngine.shared.performBackup(skipNonCopyable: skipNonCopyable) { [weak self] copied, total in
                Task { @MainActor in
                    self?.updateProgress(copied: copied, total: total)
                }
            }
            self.process(.success(()), errorTitle: "")
        } catch {
            let title = String(format: NSLocalizedString("%@ could not be backed up.", comment: ""), appName)
            self.process(.failure(error), errorTitle: title)
        }
    }
    
    private func restore(skipNonCopyable: Bool = false) async {
        if let error = self.bootCheckError ?? ConsoleLog.bootCheckError {
            let appName = Bundle.main.appName ?? NSLocalizedString("App", comment: "")
            let title = String(format: NSLocalizedString("%@ could not be restored.", comment: ""), appName)
            self.process(.failure(error), errorTitle: title)
            return
        }
        self.currentOperation = .restore
        self.progressFraction = 0.0
        self.progressText = NSLocalizedString("Calculating size…", comment: "")
        
        let appName = Bundle.main.appName ?? NSLocalizedString("App", comment: "")
        
        do {
            try await BackupEngine.shared.restoreBackup(skipNonCopyable: skipNonCopyable) { [weak self] copied, total in
                Task { @MainActor in
                    self?.updateProgress(copied: copied, total: total)
                }
            }
            self.process(.success(()), errorTitle: "")
        } catch {
            let title = String(format: NSLocalizedString("%@ could not be restored.", comment: ""), appName)
            self.process(.failure(error), errorTitle: title)
        }
    }
    
    private func process(_ result: Result<Void, Error>, errorTitle: String) {
        if case .failure(let error) = result {
            self.bootCheckError = error
        }
        NotificationCenter.default.post(
            name: AppDelegate.operationDidFinishNotification,
            object: nil,
            userInfo: [AppDelegate.operationResultKey: result]
        )
    }
}

@main
struct SideBackupApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    _ = appDelegate.open(url)
                }
        }
    }
}
