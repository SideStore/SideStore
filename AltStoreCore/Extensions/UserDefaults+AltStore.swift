//
//  UserDefaults+AltStore.swift
//  AltStore
//
//  Created by Riley Testut on 6/4/19.
//  Copyright © 2019 SideStore. All rights reserved.
//

import Foundation

public extension UserDefaults
{
    static let shared: UserDefaults = {
        guard let appGroup = Bundle.main.altstoreAppGroup else { return .standard }
        
        let sharedUserDefaults = UserDefaults(suiteName: appGroup)!
        return sharedUserDefaults
    }()
    
    @NSManaged var firstLaunch: Date?
    @NSManaged var requiresAppGroupMigration: Bool
    @NSManaged var textServer: Bool
    @NSManaged var sidejitenable: Bool
    @NSManaged var textInputSideJITServerurl: String?
    @NSManaged var textInputAnisetteURL: String?
    @NSManaged var customAnisetteURL: String?
    @NSManaged var menuAnisetteURL: String
    @NSManaged var menuAnisetteList: String
    @NSManaged var menuAnisetteServersList: [String]
    @NSManaged var preferredServerID: String?
    
    @NSManaged var isBackgroundRefreshEnabled: Bool
    @NSManaged var isIdleTimeoutDisableEnabled: Bool
    @NSManaged var isAppLimitDisabled: Bool
    @NSManaged var isBetaUpdatesEnabled: Bool
    @NSManaged var isExportResignedAppEnabled: Bool
    @NSManaged var isVerboseOperationsLoggingEnabled: Bool
    @NSManaged var isMinimuxerConsoleLoggingEnabled: Bool
    @NSManaged var isMinimuxerStatusCheckEnabled: Bool

    @NSManaged var recreateDatabaseOnNextStart: Bool
    @NSManaged var isPairingReset: Bool
    @NSManaged var isDebugModeEnabled: Bool
    @NSManaged var presentedLaunchReminderNotification: Bool
    
    @NSManaged var legacySideloadedApps: [String]?
    
    @NSManaged var isLegacyDeactivationSupported: Bool
    @NSManaged var activeAppLimitIncludesExtensions: Bool
    
    @NSManaged var localServerSupportsRefreshing: Bool
    
    @NSManaged var patchedApps: [String]?
    
    @NSManaged var patronsRefreshID: String?
    
    @NSManaged var trustedSourceIDs: [String]?
    @NSManaged var trustedServerURL: String?
    @NSManaged var skipPatreonDownloads: Bool
    
    @NSManaged var betaUdpatesTrack: String?

    @nonobjc var preferredAppSorting: AppSorting {
        get {
            let sorting = _preferredAppSorting.flatMap { AppSorting(rawValue: $0) } ?? .default
            return sorting
        }
        set {
            _preferredAppSorting = newValue.rawValue
        }
    }
    @NSManaged @objc(preferredAppSorting) private var _preferredAppSorting: String?
    
    @nonobjc
    var activeAppsLimit: Int? {
        get {
            return self._activeAppsLimit?.intValue
        }
        set {
            if let value = newValue
            {
                self._activeAppsLimit = NSNumber(value: value)
            }
            else
            {
                self._activeAppsLimit = nil
            }
        }
    }
    @NSManaged @objc(activeAppsLimit) private var _activeAppsLimit: NSNumber?
    
    // Including "MacDirtyCow" in name triggers false positives with malware detectors 🤷‍♂️
    @NSManaged var isCowExploitSupported: Bool
    
    @NSManaged var permissionCheckingDisabled: Bool
    @NSManaged var responseCachingDisabled: Bool
    
    // Default track for beta updates when beta-updates are enabled
    static let defaultBetaUpdatesTrack: String = ReleaseTracks.nightly.rawValue

    class func registerDefaults()
    {
        let ios13_5 = OperatingSystemVersion(majorVersion: 13, minorVersion: 5, patchVersion: 0)
        let isLegacyDeactivationSupported = !ProcessInfo.processInfo.isOperatingSystemAtLeast(ios13_5)
        let activeAppLimitIncludesExtensions = !ProcessInfo.processInfo.isOperatingSystemAtLeast(ios13_5)
        
        let ios14 = OperatingSystemVersion(majorVersion: 14, minorVersion: 0, patchVersion: 0)
        let localServerSupportsRefreshing = !ProcessInfo.processInfo.isOperatingSystemAtLeast(ios14)
        
        let ios16 = OperatingSystemVersion(majorVersion: 16, minorVersion: 0, patchVersion: 0)
        let ios16_2 = OperatingSystemVersion(majorVersion: 16, minorVersion: 2, patchVersion: 0)
        let ios15_7_2 = OperatingSystemVersion(majorVersion: 15, minorVersion: 7, patchVersion: 2)
        
        // MacDirtyCow supports iOS 14.0 - 15.7.1 OR 16.0 - 16.1.2
        let isMacDirtyCowSupported =
        (ProcessInfo.processInfo.isOperatingSystemAtLeast(ios14) && !ProcessInfo.processInfo.isOperatingSystemAtLeast(ios15_7_2)) ||
        (ProcessInfo.processInfo.isOperatingSystemAtLeast(ios16) && !ProcessInfo.processInfo.isOperatingSystemAtLeast(ios16_2))
        
        // TODO: @mahee96: why should the permissions checking be any different, for now, it shouldn't so commented debug mode code
//        #if DEBUG
//        let permissionCheckingDisabled = true
//        #else
        let permissionCheckingDisabled = false
//        #endif
        
        // Pre-iOS 15 doesn't support custom sorting, so default to sorting by name.
        // Otherwise, default to `default` sorting (a.k.a. "source order").
        let preferredAppSorting: AppSorting = if #available(iOS 15, *) { .default } else { .name }
        
        let defaults = [
            #keyPath(UserDefaults.isAppLimitDisabled): false,
            #keyPath(UserDefaults.isBetaUpdatesEnabled): false,
            #keyPath(UserDefaults.isExportResignedAppEnabled): false,
            #keyPath(UserDefaults.isDebugModeEnabled): false,
            #keyPath(UserDefaults.isVerboseOperationsLoggingEnabled): false,
            #keyPath(UserDefaults.isMinimuxerConsoleLoggingEnabled): false, // minimuxer logging is disabled by default for console loggin
            #keyPath(UserDefaults.isMinimuxerStatusCheckEnabled): false, // minimuxer status check is disabled by default to support stosVPN based cellular refresh
            #keyPath(UserDefaults.recreateDatabaseOnNextStart): false, 
            #keyPath(UserDefaults.isBackgroundRefreshEnabled): true,
            #keyPath(UserDefaults.isIdleTimeoutDisableEnabled): true,
            #keyPath(UserDefaults.isPairingReset): true,
            #keyPath(UserDefaults.isLegacyDeactivationSupported): isLegacyDeactivationSupported,
            #keyPath(UserDefaults.activeAppLimitIncludesExtensions): activeAppLimitIncludesExtensions,
            #keyPath(UserDefaults.localServerSupportsRefreshing): localServerSupportsRefreshing,
            #keyPath(UserDefaults.requiresAppGroupMigration): true,
            #keyPath(UserDefaults.menuAnisetteList): "https://servers.sidestore.io/servers.json",
            #keyPath(UserDefaults.menuAnisetteURL): "https://ani.sidestore.io",
            #keyPath(UserDefaults.isCowExploitSupported): isMacDirtyCowSupported,
            #keyPath(UserDefaults.permissionCheckingDisabled): permissionCheckingDisabled,
            #keyPath(UserDefaults._preferredAppSorting): preferredAppSorting.rawValue,
            #keyPath(UserDefaults.betaUdpatesTrack): defaultBetaUpdatesTrack,
        ] as [String: Any]
        
        UserDefaults.standard.register(defaults: defaults)
        UserDefaults.shared.register(defaults: defaults)
        
        // MDC is unsupported and spareRestore is patched
        if !isMacDirtyCowSupported && ProcessInfo().sparseRestorePatched
        {
            // Disable isAppLimitDisabled if running iOS version that doesn't support MacDirtyCow.
            UserDefaults.standard.isAppLimitDisabled = false
        }
        
        #if !BETA
        UserDefaults.standard.responseCachingDisabled = false
        #endif
    }
}
