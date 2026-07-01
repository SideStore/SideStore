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
import CoreData

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
        
        if let error = self.context.error
        {
            self.finish(.failure(error))
            return
        }
        
        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.deactivate()
                self.finish(.success(result))
            } catch {
                self.finish(.failure(error))
            }
        }
    }
    
    private func deactivate() async throws -> InstalledApp {
        let backgroundContext = DatabaseManager.shared.persistentContainer.newBackgroundContext()
        return try await backgroundContext.perform {
            try self.performDeactivate(in: backgroundContext)
        }
    }
    
    private func performDeactivate(in backgroundContext: NSManagedObjectContext) throws -> InstalledApp {
        let installedApp = backgroundContext.object(with: self.app.objectID) as! InstalledApp
        let appExtensionProfiles = installedApp.appExtensions.map { $0.resignedBundleIdentifier }
        let allIdentifiers = [installedApp.resignedBundleIdentifier] + appExtensionProfiles
        
        for profile in allIdentifiers {
            do {
                try removeProvisioningProfile(profile)
                self.progress.completedUnitCount += 1
                installedApp.isActive = false
                return installedApp
            } catch {
                throw error
            }
        }
        throw OperationError.invalidParameters("DeactivateAppOperation: no profiles found to remove")
    }
    
    private func debugLog(_ text: String) {
        print(text)
    }
    
    private func verboseLog(_ text: String) {
        let isLoggingEnabled = OperationsLoggingControl.getFromDatabase(for: DeactivateAppOperation.self)
        if isLoggingEnabled {
            print(text)
        }
    }
}

