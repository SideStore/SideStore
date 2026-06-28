//
//  ALTAppPermissions.swift
//  AltStoreCore
//
//  Created by Magesh K on 2026-06-28.
//

import Foundation

public struct ALTAppPermissionType: RawRepresentable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
    
    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
    
    public init(stringLiteral value: String) {
        self.rawValue = value
    }
}

extension ALTAppPermissionType {
    public static let unknown: ALTAppPermissionType = "unknown"
    public static let entitlement: ALTAppPermissionType = "entitlement"
    public static let privacy: ALTAppPermissionType = "privacy"
}

public struct ALTAppPrivacyPermission: RawRepresentable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
    
    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
    
    public init(stringLiteral value: String) {
        self.rawValue = value
    }
}

extension ALTAppPrivacyPermission {
    public static let appleMusic: ALTAppPrivacyPermission = "AppleMusic"
    public static let bluetooth: ALTAppPrivacyPermission = "BluetoothAlways"
    public static let calendars: ALTAppPrivacyPermission = "Calendars"
    public static let camera: ALTAppPrivacyPermission = "Camera"
    public static let faceID: ALTAppPrivacyPermission = "FaceID"
    public static let localNetwork: ALTAppPrivacyPermission = "LocalNetwork"
    public static let microphone: ALTAppPrivacyPermission = "Microphone"
    public static let photos: ALTAppPrivacyPermission = "PhotoLibrary"
}
