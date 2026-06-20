//
//  Bundle+AltStore.swift
//  AltStore
//
//  Created by Riley Testut on 5/30/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation

public extension Bundle
{
    struct Info
    {
        public static let deviceID = "ALTDeviceID"
        public static let serverID = "ALTServerID"
        public static let certificateID = "ALTCertificateID"
        public static let appGroups = "ALTAppGroups"
        public static let altBundleID = "ALTBundleIdentifier"

        public static let orgbundleIdentifier =  "com.SideStore"
        public static let appbundleIdentifier =  orgbundleIdentifier + ".SideStore"
        public static let devicePairingString = "ALTPairingFile"
        public static let urlTypes = "CFBundleURLTypes"
        public static let exportedUTIs = "UTExportedTypeDeclarations"
        public static let backgroundModes = "UIBackgroundModes"
        
        public static let untetherURL = "ALTFugu14UntetherURL"
        public static let untetherRequired = "ALTFugu14UntetherRequired"
        public static let untetherMinimumiOSVersion = "ALTFugu14UntetherMinimumVersion"
        public static let untetherMaximumiOSVersion = "ALTFugu14UntetherMaximumVersion"
    }
}

public extension Bundle
{
    var infoPlistURL: URL {
        let infoPlistURL = self.bundleURL.appendingPathComponent("Info.plist")
        return infoPlistURL
    }
    
    var provisioningProfileURL: URL {
        let provisioningProfileURL = self.bundleURL.appendingPathComponent("embedded.mobileprovision")
        return provisioningProfileURL
    }
    
    var certificateURL: URL {
        let certificateURL = self.bundleURL.appendingPathComponent("ALTCertificate.p12")
        return certificateURL
    }
    
    var altstorePlistURL: URL {
        let altstorePlistURL = self.bundleURL.appendingPathComponent("AltStore.plist")
        return altstorePlistURL
    }
}

public extension Bundle
{
    static var baseAltStoreAppGroupID = "group." + Bundle.Info.appbundleIdentifier

    var appGroups: [String] {
        if let groups = self.infoDictionary?[Bundle.Info.appGroups] as? [String], !groups.isEmpty {
            return groups
        }
        
        // On iOS 27, self.infoDictionary can come back empty/stale in the widget
        // extension process (observed as a timing issue during widget rendering).
        // Fall back to reading Info.plist directly off disk, which still returns
        // the correct per-build (Debug team-suffixed or Release) app group value
        // rather than guessing at a hardcoded literal.
        if let groups = self.completeInfoDictionary?[Bundle.Info.appGroups] as? [String] {
            return groups
        }
        
        return []
    }
    
    var altstoreAppGroup: String? {        
        let appGroup = self.appGroups.first { $0.contains(Bundle.baseAltStoreAppGroupID) }
        return appGroup
    }
    
    var completeInfoDictionary: [String : Any]? {
        let infoPlistURL = self.infoPlistURL
        return NSDictionary(contentsOf: infoPlistURL) as? [String : Any]
    }
}
