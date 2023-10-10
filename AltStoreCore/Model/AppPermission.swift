//
//  AppPermission.swift
//  AltStore
//
//  Created by Riley Testut on 7/23/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import CoreData
import UIKit

import AltSign
public extension ALTAppPermissionType
{
    var localizedShortName: String? {
        switch self
        {
        case .photos: return NSLocalizedString("Photos", comment: "")
        case .backgroundAudio: return NSLocalizedString("Audio (BG)", comment: "")
        case .backgroundFetch: return NSLocalizedString("Fetch (BG)", comment: "")
        default: return nil
        }
    }
    
    var localizedName: String? {
        switch self
        {
        case .photos: return NSLocalizedString("Photos", comment: "")
        case .camera: return NSLocalizedString("Camera", comment: "")
        case .location: return NSLocalizedString("Location", comment: "")
        case .contacts: return NSLocalizedString("Contacts", comment: "")
        case .reminders: return NSLocalizedString("Reminders", comment: "")
        case .appleMusic: return NSLocalizedString("Apple Music", comment: "")
        case .microphone: return NSLocalizedString("Microphone", comment: "")
        case .speechRecognition: return NSLocalizedString("Speech Recognition", comment: "")
        case .backgroundAudio: return NSLocalizedString("Background Audio", comment: "")
        case .backgroundFetch: return NSLocalizedString("Background Fetch", comment: "")
        case .bluetooth: return NSLocalizedString("Bluetooth", comment: "")
        case .network: return NSLocalizedString("Network", comment: "")
        case .calendars: return NSLocalizedString("Calendars", comment: "")
        case .touchID: return NSLocalizedString("Touch ID", comment: "")
        case .faceID: return NSLocalizedString("Face ID", comment: "")
        case .siri: return NSLocalizedString("Siri", comment: "")
        case .motion: return NSLocalizedString("Motion", comment: "")
        default: return nil
        }
    }
    
    var icon: UIImage? {
        switch self
        {
        case .photos: return UIImage(systemName: "photo.on.rectangle.angled")
        case .camera: return UIImage(systemName: "camera.fill")
        case .location: return UIImage(systemName: "location.fill")
        case .contacts: return UIImage(systemName: "person.2.fill")
        case .reminders: return UIImage(systemName: "checklist")
        case .appleMusic: return UIImage(systemName: "music.note")
        case .microphone: return UIImage(systemName: "mic.fill")
        case .speechRecognition: return UIImage(systemName: "waveform.and.mic")
        case .backgroundAudio: return UIImage(systemName: "speaker.fill")
        case .backgroundFetch: return UIImage(systemName: "square.and.arrow.down")
        case .bluetooth: return UIImage(systemName: "wave.3.right")
        case .network: return UIImage(systemName: "network")
        case .calendars: return UIImage(systemName: "calendar")
        case .touchID: return UIImage(systemName: "touchid")
        case .faceID: return UIImage(systemName: "faceid")
        case .siri: return UIImage(systemName: "mic.and.signal.meter.fill")
        case .motion: return UIImage(systemName: "figure.walk.motion")
        default:
            return nil
        }
    }
}

@objc(AppPermission) @dynamicMemberLookup
public class AppPermission: NSManagedObject, Fetchable
{
    /* Properties */
    @NSManaged public var type: ALTAppPermissionType
    
    // usageDescription must be non-optional for backwards compatibility,
    // so we store non-optional value and provide public accessor with optional return type.
    @nonobjc public var usageDescription: String? {
        get { _usageDescription.isEmpty ? nil : _usageDescription }
        set { _usageDescription = newValue ?? "" }
    }
    @NSManaged @objc(usageDescription) private var _usageDescription: String
    
    @nonobjc public var permission: any ALTAppPermission {
        switch self.type
        {
        case .entitlement: return ALTEntitlement(rawValue: self._permission)
        case .privacy: return ALTAppPrivacyPermission(rawValue: self._permission)
        default: return UnknownAppPermission(rawValue: self._permission)
        }
    }
    @NSManaged @objc(permission) private var _permission: String
    
    // Set by StoreApp.
    @NSManaged public var appBundleID: String
    @NSManaged public var sourceID: String
    
    /* Relationships */
    @NSManaged public internal(set) var app: StoreApp?
    
    private override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?)
    {
        super.init(entity: entity, insertInto: context)
    }
    
    convenience init(permission: String, usageDescription: String?, type: ALTAppPermissionType, context: NSManagedObjectContext)
    {
        self.init(entity: AppPermission.entity(), insertInto: context)
        
        self._permission = permission
        self.usageDescription = usageDescription
        self.type = type
    }
}

public extension AppPermission
{
    @nonobjc class func fetchRequest() -> NSFetchRequest<AppPermission>
    {
        return NSFetchRequest<AppPermission>(entityName: "AppPermission")
    }
}

// @dynamicMemberLookup
public extension AppPermission
{
    // Convenience for accessing .permission properties.
    subscript<T>(dynamicMember keyPath: KeyPath<any ALTAppPermission, T>) -> T {
        get {
            return self.permission[keyPath: keyPath]
        }
    }
}

private struct AnyDecodable: Decodable
{
    init(from decoder: Decoder) throws 
    {
    }
}

internal struct AppPermissions: Decodable
{
    var entitlements: [AppPermission] = []
    var privacy: [AppPermission] = []
    
    private enum CodingKeys: String, CodingKey, Decodable
    {
        case entitlements
        case privacy
        
        // Legacy
        case name
        case usageDescription
    }
    
    init(from decoder: Decoder) throws
    {
        guard let context = decoder.managedObjectContext else { preconditionFailure("Decoder must have non-nil NSManagedObjectContext.") }
        
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.entitlements = try self.parseEntitlements(from: container, into: context)
        self.privacy = try self.parsePrivacyPermissions(from: container, into: context)
    }
    
    private func parseEntitlements(from container: KeyedDecodingContainer<CodingKeys>, into context: NSManagedObjectContext) throws -> [AppPermission]
    {
        guard container.contains(.entitlements) else { return [] }
        
        do
        {
            do
            {
                // Legacy
                // Must parse as [String: String], NOT [CodingKeys: String], to avoid incorrect DecodingError.typeMismatch error.
                let rawEntitlements = try container.decode([[String: String]].self, forKey: .entitlements)
                
                let entitlements = try rawEntitlements.compactMap { (dictionary) -> AppPermission? in
                    guard let name = dictionary[CodingKeys.name.rawValue] else {
                        let context = DecodingError.Context(codingPath: container.codingPath, debugDescription: "Legacy entitlements must have `name` key.")
                        throw DecodingError.keyNotFound(CodingKeys.name, context)
                    }
                    
                    let entitlement = AppPermission(permission: name, usageDescription: nil, type: .entitlement, context: context)
                    return entitlement
                }
                
                return entitlements
            }
            catch DecodingError.typeMismatch
            {
                // Detailed
                // AnyDecodable ensures we're forward-compatible with any values we may later require for entitlement permissions.
                let rawEntitlements = try container.decode([String: AnyDecodable?].self, forKey: .entitlements)
                
                let entitlements = rawEntitlements.map { AppPermission(permission: $0.key, usageDescription: nil, type: .entitlement, context: context) }
                return entitlements
            }
        }
        catch DecodingError.typeMismatch
        {
            // Default
            let rawEntitlements = try container.decode([String].self, forKey: .entitlements)
            
            let entitlements = rawEntitlements.map { AppPermission(permission: $0, usageDescription: nil, type: .entitlement, context: context) }
            return entitlements
        }
    }
    
    private func parsePrivacyPermissions(from container: KeyedDecodingContainer<CodingKeys>, into context: NSManagedObjectContext) throws -> [AppPermission]
    {
        guard container.contains(.privacy) else { return [] }
        
        do
        {
            // Legacy
            // Must parse as [String: String], NOT [CodingKeys: String], to avoid incorrect DecodingError.typeMismatch error.
            let rawPermissions = try container.decode([[String: String]].self, forKey: .privacy)
            
            let permissions = try rawPermissions.compactMap { (dictionary) -> AppPermission? in
                guard let name = dictionary[CodingKeys.name.rawValue] else {
                    let context = DecodingError.Context(codingPath: container.codingPath, debugDescription: "Legacy privacy permissions must have `name` key.")
                    throw DecodingError.keyNotFound(CodingKeys.name, context)
                }
                
                let usageDescription = dictionary[CodingKeys.usageDescription.rawValue]
                
                let convertedName = "NS" + name + "UsageDescription" // Convert legacy privacy permissions to their NS[Privacy]UsageDescription equivalent.
                let permission = AppPermission(permission: convertedName, usageDescription: usageDescription, type: .privacy, context: context)
                return permission
            }
            
            return permissions
        }
        catch DecodingError.typeMismatch
        {
            // Default
            let rawPermissions = try container.decode([String: String?].self, forKey: .privacy)
            
            let permissions = rawPermissions.map { AppPermission(permission: $0, usageDescription: $1, type: .privacy, context: context) }
            return permissions
        }
    }
}
