//
//  AppreleaseTrack.swift
//  AltStore
//
//  Created by Magesh K on 19/01/25.
//  Copyright © 2025 SideStore. All rights reserved.
//

import CoreData

// created for 0.6.0
@objc(ReleaseTrack)
public class ReleaseTrack: BaseEntity, Decodable
{
    // attributes
    @NSManaged @objc(track) public private(set) var _track: String?
    @NSManaged @objc(appBundleID) public private(set) var _appBundleID: String?
    @NSManaged @objc(sourceID) public private(set) var _sourceID: String?

    // RelationShips
    @NSManaged @objc(releases) public private(set) var _releases: NSOrderedSet?
    @NSManaged public private(set) var storeApp: StoreApp?
    
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case track
        case releases
    }
    
    public var track: String? {
        return _track?.isEmpty == false ? _track : nil
    }
    
    public var releases:[AppVersion]? {
        return _releases?.array as? [AppVersion]
    }
        
    // Required initializer for Core Data (context saves)
    private override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?) {
        super.init(entity: entity, insertInto: context)
    }

    public required init(from decoder: Decoder) throws{
        guard let context = decoder.managedObjectContext else {
            preconditionFailure("Decoder must have non-nil NSManagedObjectContext.")
        }
        
        // Must initialize with context in order for child context saves to work correctly.
        super.init(entity: ReleaseTrack.entity(), insertInto: context)
        
        do
        {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            self._track = try container.decode(String.self, forKey: .track)
            
            let releases = try container.decode([AppVersion].self, forKey: .releases)
            guard releases.count > 0 else
            {
                throw DecodingError.dataCorruptedError(forKey: .releases, in: container, debugDescription: "At least one version is required in key: releases")
            }
            self._releases = NSOrderedSet(array: releases)
        }
        catch
        {
            if let context = self.managedObjectContext
            {
                context.delete(self)
            }
            throw error
        }
    }
}

public extension ReleaseTrack{
    
    /// Warning:
    /// - Special handling required for deleted objects:
    ///   - CoreData sets all properties to nil during deletion
    ///   - This triggers KVO and could cause "mutating removed object" errors
    ///   - We guard against this by checking deletion state before updates
    ///
    internal func updateVersions(for storeApp: StoreApp?) {
        guard let storeApp = storeApp else { return }
        
            releases?.forEach { version in
                // never mutate objects that are being deleted or is already deleted
                guard let context = version.managedObjectContext,
                      !version.isDeleted, !context.deletedObjects.contains(version) else
                {
                    return
                }
                
                // update it into the appVersion
                _ = version.mutateForData(channel: track, appBundleID: storeApp.bundleIdentifier, sourceID: storeApp.sourceIdentifier)
            }
    }
    
    /// Defer updates to fields that require storeApp inverse relationship to be set, which is not available in init(),
    /// by observing changes to the prop and update the data later
    ///
    /// NOTE: We use KVO here only coz, ReleaseTrack already has an inverse relationship to StoreAppV2
    ///       So coredata will actually set the storeApp but only issue is that it happens after init() is complete
    ///       hence we are using KVO so that one doesn't need to manually set the value via a setter method
    ///
    /// However this caused an issue when an object is marked deleted during merge policy conflict resolution, all its props are set to nil by coredata.
    /// this causes this KVO observer to be triggered and mutating the deleted entity causing a "coredata error: Mutating removed object"
    /// which is now handled by checking if context.deletedObjects doesn't contain it and version.isDeleted is not true yet
    /// 
    override func didChangeValue(forKey key: String) {
        super.didChangeValue(forKey: key)
        if key == NSExpression(forKeyPath: #keyPath(ReleaseTrack.storeApp)).keyPath
        {
            updateVersions(for: storeApp)
            
            // update unique constraint attribs
            self._appBundleID = storeApp?.bundleIdentifier
            self._sourceID = storeApp?.sourceIdentifier
        }
    }
}
