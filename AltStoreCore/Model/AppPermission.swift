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
public class AppPermission: NSManagedObject, Decodable, Fetchable
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
    
    private enum CodingKeys: String, CodingKey
    {
        case name
        case usageDescription
    }
    
    public required init(from decoder: Decoder) throws
    {
        guard let context = decoder.managedObjectContext else { preconditionFailure("Decoder must have non-nil NSManagedObjectContext.") }
        
        super.init(entity: AppPermission.entity(), insertInto: context)
        
        do
        {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            self._permission = try container.decode(String.self, forKey: .name)
            self.usageDescription = try container.decodeIfPresent(String.self, forKey: .usageDescription)
            
            // Will be updated from StoreApp.
            self.type = .unknown
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
