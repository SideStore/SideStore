//
//  ReleaseTrack17To17_1MigrationPolicy.swift
//  AltStore
//
//  Created by Magesh K on 15/03/25.
//  Copyright © 2025 SideStore. All rights reserved.
//

import CoreData

@objc(ReleaseTrack17To17_1MigrationPolicy)
class ReleaseTrack17To17_1MigrationPolicy: NSEntityMigrationPolicy {
    
    override func createDestinationInstances(forSource sInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        // Let the default implementation create the basic destination AppPermission
        try super.createDestinationInstances(forSource: sInstance, in: mapping, manager: manager)
        
        // Get the destination AppPermission instance that was created
        guard let destinationPermission = manager.destinationInstances(forEntityMappingName: mapping.name, sourceInstances: [sInstance]).first else {
            print("Failed to locate destination ReleaseTrack instance")
            return
        }
        
        if let track = sInstance.value(forKey: #keyPath(ReleaseTrack._track)) as? String {
            destinationPermission.setValue(track, forKey: #keyPath(ReleaseTrack._track))
        }
        
        // set initial values migrated from source as-is
        if let storeApp = sInstance.value(forKey: #keyPath(ReleaseTrack.storeApp)) as? NSManagedObject{
            if let appBundle = storeApp.value(forKey: #keyPath(StoreApp.bundleIdentifier)) as? String{
                destinationPermission.setValue(appBundle, forKey: #keyPath(ReleaseTrack._appBundleID))
            }

            if let sourceID = storeApp.value(forKey: #keyPath(StoreApp.sourceIdentifier)) as? String {
                destinationPermission.setValue(sourceID, forKey: #keyPath(ReleaseTrack._sourceID))
            }
        }
    }
    
    
    override func createRelationships(
        forDestination dInstance: NSManagedObject,
        in mapping: NSEntityMapping,
        manager: NSMigrationManager
    ) throws {
        // Retrieve the corresponding source instance for the destination StoreApp
        let sourceInstances = manager.sourceInstances(forEntityMappingName: mapping.name, destinationInstances: [dInstance])
        guard let sInstance = sourceInstances.first else {
            print("No source instance found for destination: \(dInstance)")
            return
        }
        
        // Retrieve the source storeApp from the source ReleaseTrack
        guard let storeApp = sInstance.value(forKey: #keyPath(ReleaseTrack.storeApp)) as? NSManagedObject else {
            print("Source \(ReleaseTrack.description()) has no storeApp")
            return
        }
        
        // set initial values copied from source as-is to satisfy unique constraints
        // (will be updated by StoreApp and Source migration policy in its createRelationship() method)
        if let appBundle = storeApp.value(forKey: #keyPath(StoreApp.bundleIdentifier)) as? String{
            dInstance.setValue(appBundle, forKey: #keyPath(ReleaseTrack._appBundleID))
        }

        if let sourceID = storeApp.value(forKey: #keyPath(StoreApp.sourceIdentifier)) as? String {
            dInstance.setValue(sourceID, forKey: #keyPath(ReleaseTrack._sourceID))
        }
    }
    
}
