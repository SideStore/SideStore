//
//  RemoveAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 5/12/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation
import AltStoreCore
import CoreData

@objc(RemoveAppOperation)
final class RemoveAppOperation: ResultOperation<InstalledApp>
{
    let context: InstallAppOperationContext
    
    init(context: InstallAppOperationContext)
    {
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
        
        guard let installedApp = self.context.installedApp else {
            return self.finish(.failure(OperationError.invalidParameters("RemoveAppOperation.main: self.context.installedApp is nil")))
        }
        
        debugLog("Removing app \(self.context.bundleIdentifier)...")
        
        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.remove(installedApp)
                self.finish(.success(result))
            } catch {
                self.finish(.failure(error))
            }
        }
    }
    
    private func remove(_ installedApp: InstalledApp) async throws -> InstalledApp {
        let resignedBundleIdentifier = await installedApp.managedObjectContext?.perform {
            self.resignedBundleIdentifier(for: installedApp)
        }
        guard let resignedBundleIdentifier else {
            throw OperationError.invalidParameters("RemoveAppOperation: installedApp.managedObjectContext is nil")
        }
        
        try removeApp(resignedBundleIdentifier)
        
        let backgroundContext = DatabaseManager.shared.persistentContainer.newBackgroundContext()
        return await backgroundContext.perform {
            self.markInactive(installedApp, in: backgroundContext)
        }
    }
    
    private func resignedBundleIdentifier(for installedApp: InstalledApp) -> String {
        installedApp.resignedBundleIdentifier
    }
    
    private func markInactive(_ installedApp: InstalledApp, in backgroundContext: NSManagedObjectContext) -> InstalledApp {
        self.progress.completedUnitCount += 1
        let installedApp = backgroundContext.object(with: installedApp.objectID) as! InstalledApp
        installedApp.isActive = false
        return installedApp
    }

    private func debugLog(_ text: String) {
        print(text)
    }

    private func verboseLog(_ text: String) {
        let isLoggingEnabled = OperationsLoggingControl.getFromDatabase(for: RemoveAppOperation.self)
        if isLoggingEnabled {
            print(text)
        }
    }
}

