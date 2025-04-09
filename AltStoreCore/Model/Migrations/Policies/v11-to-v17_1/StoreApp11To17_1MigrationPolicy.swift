//
//  StoreApp11To17_1MigrationPolicy.swift
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

@objc(StoreApp11To17_1MigrationPolicy)
class StoreApp11To17_1MigrationPolicy: StoreApp11To17MigrationPolicy
{
    override func createDestinationInstances(forSource sInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        try super.createDestinationInstances(forSource: sInstance, in: mapping, manager: manager)
    }
    
    override func createRelationships(forDestination dInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws
    {
        try super.createRelationships(forDestination: dInstance, in: mapping, manager: manager)
                
        let appBundleID = dInstance.value(forKey: #keyPath(StoreApp.bundleIdentifier))
        let sourceID = dInstance.value(forKey: #keyPath(StoreApp.sourceIdentifier))

        for case let track as NSManagedObject in dInstance.storeAppReleaseTracks ?? []
        {
            track.setValue(appBundleID, forKey: #keyPath(ReleaseTrack._appBundleID))
            track.setValue(sourceID, forKey: #keyPath(ReleaseTrack._sourceID))
            
            guard let releases = track.value(forKey: #keyPath(ReleaseTrack._releases)) as? NSOrderedSet else {
                continue
            }
            
            for case let version as NSManagedObject in releases {
                version.setValue(appBundleID, forKey: #keyPath(AppVersion.appBundleID))
                version.setValue(sourceID, forKey: #keyPath(AppVersion.sourceID))
            }
        }
                
        if let permissions = dInstance.value(forKey: #keyPath(StoreApp._permissions)) as? NSSet {
            for case let permission as NSManagedObject in permissions {
                permission.setValue(appBundleID, forKey: #keyPath(AppPermission.appBundleID))
                permission.setValue(sourceID, forKey: #keyPath(AppPermission.sourceID))
            }
        }
        
        if let screenshots = dInstance.value(forKey: #keyPath(StoreApp._screenshots)) as? NSOrderedSet {
            for case let screenshot as NSManagedObject in screenshots {
                screenshot.setValue(appBundleID, forKey: #keyPath(AppScreenshot.appBundleID))
                screenshot.setValue(sourceID, forKey: #keyPath(AppScreenshot.sourceID))
            }
        }
    }
}
