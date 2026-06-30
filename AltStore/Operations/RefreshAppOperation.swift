//
//  RefreshAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 2/27/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation
import CoreData
import AltStoreCore
import AltSign
import Minimuxer

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
                debugLog("RefreshAppOperation.main: ERROR: self.context.app = \(self.context.app!); self.context.error is \(error)")
                return self.finish(.failure(error))
            }
            
            guard let profiles = self.context.provisioningProfiles else {
                return self.finish(.failure(OperationError.invalidParameters("RefreshAppOperation.main: self.context.provisioningProfiles is nil")))
            }
            
            guard let app = self.context.app else { return self.finish(.failure(OperationError(.appNotFound(name: nil)))) }
            
            Task { [weak self] in
                guard let self else { return }
                do {
                    let installed = try await self.refresh(app: app, profiles: profiles)
                    self.finish(.success(installed))
                } catch {
                    self.finish(.failure(error))
                }
            }
        }
    }
    
    private func refresh(app: ALTApplication, profiles: [String: ALTProvisioningProfile]) async throws -> InstalledApp {
        for p in profiles {
            do {
                try installProvisioningProfiles(p.value.data)
            } catch {
                throw MinimuxerError.ProfileInstall
            }
        }
        
        return try await self.managedObjectContext.perform {
            try self.updateInstalledApp(for: app, profiles: profiles)
        }
    }
    
    private func updateInstalledApp(for app: ALTApplication, profiles: [String: ALTProvisioningProfile]) throws -> InstalledApp {
        self.progress.completedUnitCount += 1
        
        let predicate = NSPredicate(format: "%K == %@", #keyPath(InstalledApp.bundleIdentifier), app.bundleIdentifier)
        guard let installedApp = InstalledApp.first(satisfying: predicate, in: self.managedObjectContext) else {
            throw OperationError(.appNotFound(name: app.name))
        }
        installedApp.update(provisioningProfile: profiles.values.first!)
        for installedExtension in installedApp.appExtensions {
            guard let provisioningProfile = profiles[installedExtension.bundleIdentifier] else { continue }
            installedExtension.update(provisioningProfile: provisioningProfile)
        }
        return installedApp
    }
    
    private func debugLog(_ text: String) {
        print(text)
    }

    private func verboseLog(_ text: String) {
        let isLoggingEnabled = OperationsLoggingControl.getFromDatabase(for: RefreshAppOperation.self)
        if isLoggingEnabled {
            print(text)
        }
    }
}
