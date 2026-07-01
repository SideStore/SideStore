//
//  SendAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 6/7/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//
import Foundation
import Network
import AltStoreCore
import Minimuxer

@objc(SendAppOperation)
final class SendAppOperation: ResultOperation<()>
{
    let context: InstallAppOperationContext
    
    init(context: InstallAppOperationContext)
    {
        self.context = context
        
        super.init()
        
        self.progress.totalUnitCount = 1
    }
    
    override func main() {
        super.main()

        if let error = self.context.error {
            return self.finish(.failure(error))
        }

        guard let resignedApp = self.context.resignedApp else {
            return self.finish(.failure(OperationError.invalidParameters("SendAppOperation.main: self.resignedApp is nil")))
        }

        let shortcutURLoff = URL(string: "shortcuts://run-shortcut?name=TurnOffData")!

        let app = AnyApp(name: resignedApp.name, bundleIdentifier: self.context.bundleIdentifier, url: resignedApp.fileURL, storeApp: nil)
        let fileURL = InstalledApp.refreshedIPAURL(for: app)
        verboseLog("AFC App `fileURL`: \(fileURL.absoluteString)")

        // only when minimuxer is not ready and below 26.4 should we turn off data
        if #available(iOS 26.4, *) {
            context.shouldTurnOffData = false
        } else if minimuxerStatus != .ready {
            context.shouldTurnOffData = true
        } else {
            context.shouldTurnOffData = false
        }

        Task { [weak self] in
            guard let self else { return }
            if self.context.shouldTurnOffData {
                // Wait for Shortcut to Finish Before Proceeding
                await withCheckedContinuation { continuation in
                    UIApplication.shared.open(shortcutURLoff, options: [:]) { _ in
                        self.debugLog("Shortcut finished execution. Proceeding with file transfer.")
                        continuation.resume()
                    }
                }
            }
            do {
                try await self.processFile(at: fileURL, for: app.bundleIdentifier)
                self.finish(.success(()))
            } catch {
                self.finish(.failure(error))
            }
        }
    }

    private func processFile(at fileURL: URL, for bundleIdentifier: String) async throws {
        guard let data = NSData(contentsOf: fileURL) else {
            debugLog("IPA doesn't exist????")
            throw OperationError(.appNotFound(name: bundleIdentifier))
        }
        let bytes = Data(data)
        try yeetAppAFC(bundleIdentifier, bytes)
        self.progress.completedUnitCount += 1
    }

    private func debugLog(_ text: String)
    {
        print(text)
    }

    private func verboseLog(_ text: String)
    {
        let isLoggingEnabled = OperationsLoggingControl.getFromDatabase(for: SendAppOperation.self)
        if isLoggingEnabled {
            print(text)
        }
    }
}
