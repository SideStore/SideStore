//
//  StoreApp17To17_1MigrationPolicy.swift
//  AltStore
//
//  Created by Magesh K on 15/03/25.
//  Copyright © 2025 SideStore. All rights reserved.
//

import CoreData

fileprivate extension NSManagedObject
{
    var storeAppReleaseTracks: NSOrderedSet? {
        let tracks = self.value(forKey: #keyPath(StoreApp._releaseTracks)) as? NSOrderedSet
        return tracks
    }
}

@objc(StoreApp17To17_1MigrationPolicy)
class StoreApp17To17_1MigrationPolicy: NSEntityMigrationPolicy
{
    override func createDestinationInstances(forSource sInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        try super.createDestinationInstances(forSource: sInstance, in: mapping, manager: manager)
    }
    
    override func createRelationships(forDestination dInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws
    {
        try super.createRelationships(forDestination: dInstance, in: mapping, manager: manager)
                
        let appBundleID = dInstance.value(forKey: #keyPath(StoreApp.bundleIdentifier))

        for case let track as NSManagedObject in dInstance.storeAppReleaseTracks ?? []
        {
            track.setValue(appBundleID, forKey: #keyPath(ReleaseTrack._appBundleID))
            
            guard let releases = track.value(forKey: #keyPath(ReleaseTrack._releases)) as? NSOrderedSet else {
                continue
            }
            
            for case let version as NSManagedObject in releases {
                version.setValue(appBundleID, forKey: #keyPath(AppVersion.appBundleID))
            }
        }
                
        if let permissions = dInstance.value(forKey: #keyPath(StoreApp._permissions)) as? NSSet {
            for case let permission as NSManagedObject in permissions {
                permission.setValue(appBundleID, forKey: #keyPath(AppPermission.appBundleID))
            }
        }
        
        if let screenshots = dInstance.value(forKey: #keyPath(StoreApp._screenshots)) as? NSOrderedSet {
            for case let screenshot as NSManagedObject in screenshots {
                screenshot.setValue(appBundleID, forKey: #keyPath(AppScreenshot.appBundleID))
            }
        }
    }
}
