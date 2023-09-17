//
//  DeactivateAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 3/4/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation

import AltStoreCore
import AltSign
import Roxas
import minimuxer

@objc(DeactivateAppOperation)
final class DeactivateAppOperation: ResultOperation<InstalledApp>
{
    let app: InstalledApp
    let context: OperationContext
    
    init(app: InstalledApp, context: OperationContext)
    {
        self.app = app
        self.context = context
        
        super.init()
    }
    
    override func main()
    {
        super.main()
        
        if let error = self.context.error { return self.finish(.failure(error)) }
        
        DatabaseManager.shared.persistentContainer.performBackgroundTask { (context) in
            let installedApp = context.object(with: self.app.objectID) as! InstalledApp
            let appExtensionProfiles = installedApp.appExtensions.map { $0.resignedBundleIdentifier }
            let allIdentifiers = [installedApp.resignedBundleIdentifier] + appExtensionProfiles
            
            for profile in allIdentifiers {
                var attempts = 5
                while (attempts > 0){
                    print("Remove Provisioning profile attempts left: \(attempts)")
                    do {
                        try remove_provisioning_profile(profile)
                        self.progress.completedUnitCount += 1
                        installedApp.isActive = false
                        self.finish(.success(installedApp))
                        break
                    } catch {
                        attempts -= 1
                        if (attempts <= 0){
                            self.finish(.failure(error))
                        }
                    }
                }
            }
        }
    }
}
