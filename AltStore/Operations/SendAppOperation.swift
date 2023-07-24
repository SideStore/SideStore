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
    
    override func main()
    {
        super.main()
        
        if let error = self.context.error
        {
            return self.finish(.failure(error))
        }
        
        guard let resignedApp = self.context.resignedApp else { return self.finish(.failure(OperationError.invalidParameters)) }
        
        // self.context.resignedApp.fileURL points to the app bundle, but we want the .ipa.
        let app = AnyApp(name: resignedApp.name, bundleIdentifier: self.context.bundleIdentifier, url: resignedApp.fileURL)
        let fileURL = InstalledApp.refreshedIPAURL(for: app)
        
        print("AFC App `fileURL`: \(fileURL.absoluteString)")
        
        if let data = NSData(contentsOf: fileURL) {
            var attempts = 10
            while (attempts != 0){
                print("Send app attempts left: \(attempts)")
                do {
                    let bytes = Data(data).toRustByteSlice()
                    try yeet_app_afc(app.bundleIdentifier, bytes.forRust())
                    self.progress.completedUnitCount += 1
                    self.finish(.success(()))
                    break
                } catch {
                    attempts -= 1
                    if (attempts == 0) {
                        self.finish(.failure(MinimuxerError.RwAfc))
                    }
                }
                self.progress.completedUnitCount += 1
                return self.finish(.success(()))
            }
        } else {
            print("IPA doesn't exist????")
            self.finish(.failure(OperationError.appNotFound))
        }
    }
}
