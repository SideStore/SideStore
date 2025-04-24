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
import minimuxer

@objc(SendAppOperation)
final class SendAppOperation: ResultOperation<()>
{
    let context: InstallAppOperationContext
    
    private let dispatchQueue = DispatchQueue(label: "com.sidestore.SendAppOperation")
    
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
        print("AFC App `fileURL`: \(fileURL.absoluteString)")

        // Wait for Shortcut to Finish Before Proceeding
        UIApplication.shared.open(shortcutURLoff, options: [:]) { _ in
            print("Shortcut finished execution. Proceeding with file transfer.")

            DispatchQueue.global().async {
                self.processFile(at: fileURL, for: app.bundleIdentifier)
            }
        }
    }

    private func processFile(at fileURL: URL, for bundleIdentifier: String) {
        guard let data = NSData(contentsOf: fileURL) else {
            print("IPA doesn't exist????")
            return self.finish(.failure(OperationError(.appNotFound(name: bundleIdentifier))))
        }

        do {
            let bytes = Data(data).toRustByteSlice()
            try yeet_app_afc(bundleIdentifier, bytes.forRust())
            self.progress.completedUnitCount += 1
            self.finish(.success(()))
        } catch {
            self.finish(.failure(MinimuxerError.RwAfc))
            self.progress.completedUnitCount += 1
            self.finish(.success(()))
        }
    }
}
