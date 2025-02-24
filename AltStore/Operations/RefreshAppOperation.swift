//
//  RefreshAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 2/27/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation

import AltStoreCore
import AltSign
import Roxas
import minimuxer

@objc(RefreshAppOperation)
final class RefreshAppOperation: ResultOperation<InstalledApp>
{
    let context: AppOperationContext
    
    // Strong reference to managedObjectContext to keep it alive until we're finished.
    let managedObjectContext: NSManagedObjectContext
    
    init(context: AppOperationContext)
    {
        self.context = context
        self.managedObjectContext = DatabaseManager.shared.persistentContainer.newBackgroundContext()
        
        super.init()
    }
    
    override func main()
    {
        super.main()
        
        do
        {
            if let error = self.context.error {
                print("RefreshAppOperation.main: ERROR: self.context.app = \(self.context.app!); self.context.error is \(error)")
                return self.finish(.failure(error))
            }
            
            guard let profiles = self.context.provisioningProfiles else {
                return self.finish(.failure(OperationError.invalidParameters("RefreshAppOperation.main: self.context.provisioningProfiles is nil")))
            }
            
            guard let app = self.context.app else { return self.finish(.failure(OperationError(.appNotFound(name: nil)))) }

            for p in profiles {
                do {
                    let bytes = p.value.data.toRustByteSlice()
                    try install_provisioning_profile(bytes.forRust())
                } catch {
                    self.finish(.failure(MinimuxerError.ProfileInstall))
                }

                DatabaseManager.shared.persistentContainer.performBackgroundTask { (context) in
                    
                    self.progress.completedUnitCount += 1
                    
                    let predicate = NSPredicate(format: "%K == %@", #keyPath(InstalledApp.bundleIdentifier), app.bundleIdentifier)
                    self.managedObjectContext.perform {
                        guard let installedApp = InstalledApp.first(satisfying: predicate, in: self.managedObjectContext) else {
                            self.finish(.failure(OperationError(.appNotFound(name: app.name))))
                            return
                        }
                        installedApp.update(provisioningProfile: p.value)
                        for installedExtension in installedApp.appExtensions {
                            guard let provisioningProfile = profiles[installedExtension.bundleIdentifier] else { continue }
                            installedExtension.update(provisioningProfile: provisioningProfile)
                        }
                        self.finish(.success(installedApp))
                    }
                }
            }
        }
    }
}
