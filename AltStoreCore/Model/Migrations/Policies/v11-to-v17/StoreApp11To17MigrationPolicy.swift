//
//  StoreApp11To17MigrationPolicy.swift
//  AltStore
//
//  Created by Magesh K on 25/02/25.
//  Copyright © 2025 SideStore. All rights reserved.
//


import CoreData

@objc(StoreApp11To17MigrationPolicy)
class StoreApp11To17MigrationPolicy: NSEntityMigrationPolicy {
    
    let defaultChannel = "stable"

    
//    override func createDestinationInstances(forSource sInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
//        // First, let the default implementation create the basic destination StoreApp
//        try super.createDestinationInstances(forSource: sInstance, in: mapping, manager: manager)
//        
//        // Get the destination StoreApp instance that was created
//        guard let destinationStoreApp = manager.destinationInstances(forEntityMappingName: mapping.name, sourceInstances: [sInstance]).first else {
//            print("Failed to locate destination StoreApp instance")
//            return
//        }
//        
//        // Get the source versions array
//        guard let sourceVersions = sInstance.value(forKey: #keyPath(StoreApp._versions)) as? NSOrderedSet else {
//            print("Source has no versions")
//            return
//        }
//        
//        
//        // Create a new ReleaseTrack entity
//        let context = destinationStoreApp.managedObjectContext!
//        let releaseTrack = NSEntityDescription.insertNewObject(forEntityName: ReleaseTrack.entity().name!, into: context)
//        releaseTrack.setValue(defaultChannel, forKey: #keyPath(ReleaseTrack._track))
//        
//        // Connect the releaseTrack to the destination StoreApp
//        releaseTrack.setValue(destinationStoreApp, forKey: #keyPath(ReleaseTrack.storeApp))
//        
//        // Add it to the releaseTracks of the destination StoreApp
//        let releaseTracks = NSMutableOrderedSet()
//        releaseTracks.add(releaseTrack)
//        destinationStoreApp.setValue(releaseTracks, forKey: #keyPath(StoreApp._releaseTracks))
//        
//        // Find the entity mapping for AppVersion
//        let appVersionMappingName = findEntityMappingName(for: AppVersion.entity().name!, in: manager)
//        
//        // Now for each source version, find its corresponding migrated version and add to the releaseTrack
//        let versions = NSMutableOrderedSet()
//        for sourceVersion in sourceVersions.array {
//            guard let sourceVersion = sourceVersion as? NSManagedObject else { continue }
//            
//            let destinationVersions = manager.destinationInstances(forEntityMappingName: appVersionMappingName, sourceInstances: [sourceVersion])
//            if let destinationVersion = destinationVersions.first {
//                
//                // update channel info
//                if let appVersion = destinationVersion as? AppVersion {
//                    _ = appVersion.mutateForData(channel: defaultChannel)
//                }
//                
//                versions.add(destinationVersion)
//                
//                // Connect in the other direction too
//                destinationVersion.setValue(releaseTrack, forKey: #keyPath(AppVersion.releaseTrack))
//            }
//        }
//        
//        // Set the releases relationship on the releaseTrack
//        releaseTrack.setValue(versions, forKey: #keyPath(ReleaseTrack._releases))
//    }
    
    
    // Helper function to find the entity mapping name for a given entity
    private func findEntityMappingName(for entityName: String, in manager: NSMigrationManager) -> String {
        let mappingModel = manager.mappingModel
        
        for entityMapping in mappingModel.entityMappings {
            if entityMapping.sourceEntityName == entityName {
                return entityMapping.name
            }
        }
        
        // If not found, return a default (you might want to handle this differently)
        print("Warning: Could not find mapping for entity: \(entityName)")
        return "\(entityName)To\(entityName)"
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
        
        // Retrieve the source versions from the source StoreApp
        guard let sourceVersions = sInstance.value(forKey: #keyPath(StoreApp._versions)) as? NSOrderedSet else {
            print("Source store app has no versions")
            return
        }
        
        // Create a new ReleaseTrack entity
        let context = dInstance.managedObjectContext!
        let releaseTrack = NSEntityDescription.insertNewObject(forEntityName: ReleaseTrack.entity().name ?? ReleaseTrack.description(), into: context)
        releaseTrack.setValue(defaultChannel, forKey: #keyPath(ReleaseTrack._track))

        // Connect the releaseTrack to the destination StoreApp
        releaseTrack.setValue(dInstance, forKey: #keyPath(ReleaseTrack.storeApp))


        // Find the mapping name for AppVersion (make sure this exactly matches your mapping model)
        let appVersionMappingName = findEntityMappingName(for: AppVersion.entity().name ?? AppVersion.description(), in: manager)
        
        // Create a mutable ordered set for the destination AppVersion objects
        let destinationVersionsSet = NSMutableOrderedSet()
        for sourceVersion in sourceVersions.array {
            guard let sourceVersion = sourceVersion as? NSManagedObject else { continue }
            
            // Retrieve the corresponding destination AppVersion instance
            let destVersions = manager.destinationInstances(forEntityMappingName: appVersionMappingName, sourceInstances: [sourceVersion])
            if let destVersion = destVersions.first {
                // update channel info
                destinationVersionsSet.add(destVersion)
                
                // Optionally update properties or establish the inverse relationship
                destVersion.setValue(releaseTrack, forKey: #keyPath(AppVersion.releaseTrack))
                destVersion.setValue(defaultChannel, forKey: #keyPath(AppVersion._channel))
                destVersion.setValue("", forKey: #keyPath(AppVersion._buildVersion))
            } else {
                print("Destination AppVersion not found for source version: \(sourceVersion)")
            }
        }
        
        // Finally, link the destination AppVersion objects to the ReleaseTrack's relationship
        releaseTrack.setValue(destinationVersionsSet, forKey: #keyPath(ReleaseTrack._releases))
        
        // clear the versions field
//        dInstance.setValue(NSOrderedSet(), forKey: #keyPath(StoreApp._versions))
        dInstance.setValue(nil, forKey: #keyPath(StoreApp._versions))
    }
}

