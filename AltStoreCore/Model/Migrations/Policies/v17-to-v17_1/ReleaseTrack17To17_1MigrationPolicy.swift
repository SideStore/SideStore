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
        try super.createDestinationInstances(forSource: sInstance, in: mapping, manager: manager)
    }
    
    
    override func createRelationships(
        forDestination dInstance: NSManagedObject,
        in mapping: NSEntityMapping,
        manager: NSMigrationManager
    ) throws {
        
        try super.createRelationships(forDestination: dInstance, in: mapping, manager: manager)
                
        // Retrieve the source storeApp from the source ReleaseTrack
        guard let storeApp = dInstance.value(forKey: #keyPath(ReleaseTrack.storeApp)) as? NSManagedObject else {
            print("Destination \(ReleaseTrack.description()) has no storeApp")
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
