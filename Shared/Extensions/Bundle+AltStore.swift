//
//  Bundle+AltStore.swift
//  AltStore
//
//  Created by Riley Testut on 5/30/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation

// @livecontainer
private extension Bundle {
    @objc dynamic static let activeBundle: Bundle = Bundle.main
    @objc dynamic static let storeAppBundleIdentifier = "com.SideStore.SideStore"
    @objc dynamic static let appbundleIdentifier = "com.SideStore.SideStore"
}

public extension Bundle
{
    struct Info
    {
        public static let activeBundle: Bundle = Bundle.activeBundle
        public static let activeBundleURL: URL = activeBundle.bundleURL
        public static let activeBundleVersion: String = {
            let info = activeBundle.infoDictionary
            let version = (info?["CFBundleShortVersionString"] as? String) ?? "?.?.?"
            let build = (info?["CFBundleVersion"] as? String).map { " (\($0))" } ?? "(????)"
            return NSLocalizedString(String(format: "Version %@%@", version, build), comment: "SideStore Version")
        }()
        public static let activeBundleIdentifier: String = activeBundle.bundleIdentifier!
        public static let storeAppBundleIdentifier = Bundle.storeAppBundleIdentifier
        public static let appbundleIdentifier = Bundle.appbundleIdentifier
 
        public static let deviceID = "ALTDeviceID"
        public static let serverID = "ALTServerID"
        public static let certificateID = "ALTCertificateID"
        public static let appGroups = "ALTAppGroups"
        public static let altBundleID = "ALTBundleIdentifier"
     
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
    // @livecontainer
    @objc dynamic static let baseAltStoreAppGroupID = "group." + Bundle.Info.appbundleIdentifier

    var appGroups: [String] {
        return self.infoDictionary?[Bundle.Info.appGroups] as? [String] ?? []
    }
    
    // @livecontainer
    @objc dynamic var altstoreAppGroup: String? {
        let appGroup = self.appGroups.first { $0.contains(Bundle.baseAltStoreAppGroupID) }
        return appGroup
    }
    
    var completeInfoDictionary: [String : Any]? {
        let infoPlistURL = self.infoPlistURL
        return NSDictionary(contentsOf: infoPlistURL) as? [String : Any]
    }
}

public extension String {
    var isAltStoreAppID: Bool {
        let activeID   = Bundle.Info.activeBundleIdentifier
        let altstoreID = Bundle.Info.appbundleIdentifier
        
        let matchesActiveBundle   = !activeID.isEmpty && self.contains(activeID)
        let matchesAltStoreBundle = !altstoreID.isEmpty && self.contains(altstoreID)
        
        return matchesActiveBundle || matchesAltStoreBundle
    }
}
