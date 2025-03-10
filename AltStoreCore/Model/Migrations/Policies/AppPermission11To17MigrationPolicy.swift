//
//  AppPermission11To17MigrationPolicy.swift
//  AltStore
//
//  Created by Magesh K on 11/03/25.
//  Copyright © 2025 SideStore. All rights reserved.
//

import CoreData

@objc(AppPermission11To17MigrationPolicy)
class AppPermission11To17MigrationPolicy: NSEntityMigrationPolicy {
    
    override func createDestinationInstances(forSource sInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        // Let the default implementation create the basic destination AppPermission
        try super.createDestinationInstances(forSource: sInstance, in: mapping, manager: manager)
        
        // Get the destination AppPermission instance that was created
        guard let destinationPermission = manager.destinationInstances(forEntityMappingName: mapping.name, sourceInstances: [sInstance]).first else {
            print("Failed to locate destination AppPdestinationAppermission instance")
            return
        }
        
        // Extract the type value from source
        if let type = sInstance.value(forKey: #keyPath(AppPermission.type)) as? String {
            // In the new model, "permission" is the actual permission string, which needs to be derived from the old "type"
            let permission = self.derivePermissionFromType(type)
            destinationPermission.setValue(permission, forKey: #keyPath(AppPermission._permission))
        }
        
        // set initial values copied from source as-is to satisfy unique constraints
        // (will be updated by StoreApp and Source migration policy in its createRelationship() method)
        if let storeApp = sInstance.value(forKey: #keyPath(AppPermission.app)) as? NSManagedObject{
            if let appBundle = storeApp.value(forKey: #keyPath(StoreApp.bundleIdentifier)) as? String{
                destinationPermission.setValue(appBundle, forKey: #keyPath(AppPermission.appBundleID))
            }

            if let sourceID = storeApp.value(forKey: #keyPath(StoreApp.sourceIdentifier)) as? String {
                destinationPermission.setValue(sourceID, forKey: #keyPath(AppPermission.sourceID))
            }
        }
    }
    
    // Helper method to derive permission string from type
    private func derivePermissionFromType(_ type: String) -> String {
        // Based on the code in the documents, we need to map the ALTAppPermissionType to permission strings
        switch type {
        case "photos": return "NSPhotosUsageDescription"
        case "camera": return "NSCameraUsageDescription"
        case "location": return "NSLocationUsageDescription"
        case "contacts": return "NSContactsUsageDescription"
        case "reminders": return "NSRemindersUsageDescription"
        case "music": return "NSAppleMusicUsageDescription"
        case "microphone": return "NSMicrophoneUsageDescription"
        case "speech-recognition": return "NSSpeechRecognitionUsageDescription"
        case "background-audio": return "NSBackgroundAudioUsageDescription"
        case "background-fetch": return "NSBackgroundFetchUsageDescription"
        case "bluetooth": return "NSBluetoothUsageDescription"
        case "network": return "NSNetworkUsageDescription"
        case "calendars": return "NSCalendarsUsageDescription"
        case "touchID": return "NSTouchIDUsageDescription"
        case "faceID": return "NSFaceIDUsageDescription"
        case "siri": return "NSSiriUsageDescription"
        case "motion": return "NSMotionUsageDescription"
        case "entitlement": return type // For entitlements, we might keep the raw value
        case "privacy": return type // For privacy permissions, we might keep the raw value
        default: return type // Default fallback
        }
    }
}
