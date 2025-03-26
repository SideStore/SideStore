//
//  Source17To17_1MigrationPolicy.swift
//  AltStore
//
//  Created by Magesh K on 15/03/25.
//  Copyright © 2025 SideStore. All rights reserved.
//

import CoreData

fileprivate extension NSManagedObject
{
    var sourceSourceURL: URL? {
        let sourceURL = self.value(forKey: #keyPath(Source.sourceURL)) as? URL
        return sourceURL
    }
    
    var sourceSourceId: String? {
        let sourceId = self.value(forKey: #keyPath(Source.identifier)) as? String
        return sourceId
    }
    
    var sourceApps: NSOrderedSet? {
        let apps = self.value(forKey: #keyPath(Source._apps)) as? NSOrderedSet
        return apps
    }
    
    var sourceNewsItems: NSOrderedSet? {
        let newsItems = self.value(forKey: #keyPath(Source._newsItems)) as? NSOrderedSet
        return newsItems
    }
}

fileprivate extension NSManagedObject
{
    func setSourceId(_ sourceID: String)
    {
        self.setValue(sourceID, forKey: #keyPath(Source.identifier))
    }

    func setGroupId(_ groupID: String)
    {
        self.setValue(groupID, forKey: #keyPath(Source.groupID))
    }

    func setSourceSourceUrl(_ sourceURL: URL)
    {
        self.setValue(sourceURL, forKey: #keyPath(Source.sourceURL))
    }
    
    func setSourceSourceID(_ sourceID: String)
    {
        self.setValue(sourceID, forKey: #keyPath(Source.identifier))
    }
    
    func setStoreAppSourceID(_ sourceID: String)
    {
        self.setValue(sourceID, forKey: #keyPath(StoreApp.sourceIdentifier))
    }
    
    func setNewsItemSourceID(_ sourceID: String)
    {
        self.setValue(sourceID, forKey: #keyPath(NewsItem.sourceIdentifier))
    }
    
    func setAppVersionSourceID(_ sourceID: String)
    {
        self.setValue(sourceID, forKey: #keyPath(AppVersion.sourceID))
    }
    
    func setAppPermissionSourceID(_ sourceID: String)
    {
        self.setValue(sourceID, forKey: #keyPath(AppPermission.sourceID))
    }
    
    func setAppScreenshotSourceID(_ sourceID: String)
    {
        self.setValue(sourceID, forKey: #keyPath(AppScreenshot.sourceID))
    }

    func setReleaseTracksSourceID(_ sourceID: String)
    {
        self.setValue(sourceID, forKey: #keyPath(ReleaseTrack._sourceID))
    }
}


fileprivate extension NSManagedObject
{
    var storeAppVersions: NSOrderedSet? {
        let versions = self.value(forKey: #keyPath(StoreApp._versions)) as? NSOrderedSet
        return versions
    }
    
    var storeAppPermissions: NSSet? {
        let permissions = self.value(forKey: #keyPath(StoreApp._permissions)) as? NSSet
        return permissions
    }
    
    var storeAppScreenshots: NSOrderedSet? {
        let screenshots = self.value(forKey: #keyPath(StoreApp._screenshots)) as? NSOrderedSet
        return screenshots
    }

    var storeAppReleaseTracks: NSOrderedSet? {
        let tracks = self.value(forKey: #keyPath(StoreApp._releaseTracks)) as? NSOrderedSet
        return tracks
    }
}

@objc(Source17To17_1MigrationPolicy)
class Source17To17_1MigrationPolicy: NSEntityMigrationPolicy
{
    override func createDestinationInstances(forSource sInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        // Let the default implementation create the basic destination AppPermission
        try super.createDestinationInstances(forSource: sInstance, in: mapping, manager: manager)
        
        // Get the destination Source instance that was created
        guard let dInstance = manager.destinationInstances(forEntityMappingName: mapping.name, sourceInstances: [sInstance]).first else {
            print("Failed to locate destination Source instance")
            return
        }
        
        // update new fields with initial values
        if let sourceID = sInstance.value(forKey: #keyPath(Source.identifier)) as? String {
            dInstance.setValue(sourceID, forKey: #keyPath(Source.groupID))
        }
        
        guard var sourceURL = dInstance.sourceSourceURL else {
            return
        }
                
        // sidestore official source has been moved to sidestore.io/apps-v2.json
        // if we don't switch, users will end up with 2 offical sources
        let normalizedSourceURL = try? sourceURL.normalized()
        if normalizedSourceURL == "apps.sidestore.io"                   // if using old source url (<0.5.9)
        {
            sourceURL = Source.altStoreSourceURL                        // switch to latest
            dInstance.setSourceSourceUrl(sourceURL)                     // and use it for current
        }

        var sourceID = try Source.sourceID(from: sourceURL)
        dInstance.setSourceId(sourceID)
        
        // for older versions migrating to current (their sourceID is their groupID)
        dInstance.setGroupId(sourceID)

        if sourceID == "apps.sidestore.io" {
            sourceID = Source.altStoreIdentifier
            dInstance.setSourceId(sourceID)
        }
    }
    
    override func createRelationships(forDestination dInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws
    {
        try super.createRelationships(forDestination: dInstance, in: mapping, manager: manager)
        
        guard let sourceID = dInstance.sourceSourceId else { return }
        
        for case let newsItem as NSManagedObject in dInstance.sourceNewsItems ?? []
        {
            newsItem.setNewsItemSourceID(sourceID)
        }

        for case let app as NSManagedObject in dInstance.sourceApps ?? []
        {
            app.setStoreAppSourceID(sourceID)
            
            for case let screenshot as NSManagedObject in app.storeAppScreenshots ?? []
            {
                screenshot.setAppScreenshotSourceID(sourceID)
            }
            
            for case let track as NSManagedObject in app.storeAppReleaseTracks ?? []
            {
//                print("Source_17_1MigrationPolicy: processing track \(track.value(forKey: "track")!)")
                track.setValue(sourceID, forKey: #keyPath(ReleaseTrack._sourceID))
                
                guard let releases = track.value(forKey: #keyPath(ReleaseTrack._releases)) as? NSOrderedSet else {
//                    print("Source_17_1MigrationPolicy: releases not found for track: \(track.value(forKey: "track")!)")
                    continue
                }
                
                for case let version as NSManagedObject in releases {
//                    print("Source_17_1MigrationPolicy: updating sourceID for version: \(version.value(forKey: "version")!)")
                    version.setValue(sourceID, forKey: #keyPath(AppVersion.sourceID))
                }
            }
        }
    }
}
