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
    
    var firstLaunch: Date? {
        get { self.object(forKey: "firstLaunch") as? Date }
        set { self.set(newValue, forKey: "firstLaunch") }
    }
    var requiresAppGroupMigration: Bool {
        get { self.bool(forKey: "requiresAppGroupMigration") }
        set { self.set(newValue, forKey: "requiresAppGroupMigration") }
    }
    var textServer: Bool {
        get { self.bool(forKey: "textServer") }
        set { self.set(newValue, forKey: "textServer") }
    }
    var sidejitenable: Bool {
        get { self.bool(forKey: "sidejitenable") }
        set { self.set(newValue, forKey: "sidejitenable") }
    }
    var textInputSideJITServerurl: String? {
        get { self.string(forKey: "textInputSideJITServerurl") }
        set { self.set(newValue, forKey: "textInputSideJITServerurl") }
    }
    var textInputAnisetteURL: String? {
        get { self.string(forKey: "textInputAnisetteURL") }
        set { self.set(newValue, forKey: "textInputAnisetteURL") }
    }
    var customAnisetteURL: String? {
        get { self.string(forKey: "customAnisetteURL") }
        set { self.set(newValue, forKey: "customAnisetteURL") }
    }
    var menuAnisetteURL: String {
        get { self.string(forKey: "menuAnisetteURL") ?? "" }
        set { self.set(newValue, forKey: "menuAnisetteURL") }
    }
    var menuAnisetteList: String {
        get { self.string(forKey: "menuAnisetteList") ?? "" }
        set { self.set(newValue, forKey: "menuAnisetteList") }
    }
    var menuAnisetteServersList: [String] {
        get { self.stringArray(forKey: "menuAnisetteServersList") ?? [] }
        set { self.set(newValue, forKey: "menuAnisetteServersList") }
    }
    var preferredServerID: String? {
        get { self.string(forKey: "preferredServerID") }
        set { self.set(newValue, forKey: "preferredServerID") }
    }
    
    var isBackgroundRefreshEnabled: Bool {
        get { self.bool(forKey: "isBackgroundRefreshEnabled") }
        set { self.set(newValue, forKey: "isBackgroundRefreshEnabled") }
    }
    var enableEMPforWireguard: Bool {
        get { self.bool(forKey: "enableEMPforWireguard") }
        set { self.set(newValue, forKey: "enableEMPforWireguard") }
    }
    var isIdleTimeoutDisableEnabled: Bool {
        get { self.bool(forKey: "isIdleTimeoutDisableEnabled") }
        set { self.set(newValue, forKey: "isIdleTimeoutDisableEnabled") }
    }
    var isAppLimitDisabled: Bool {
        get { self.bool(forKey: "isAppLimitDisabled") }
        set { self.set(newValue, forKey: "isAppLimitDisabled") }
    }
    var isBetaUpdatesEnabled: Bool {
        get { self.bool(forKey: "isBetaUpdatesEnabled") }
        set { self.set(newValue, forKey: "isBetaUpdatesEnabled") }
    }
    var customizeAppId: Bool {
        get { self.bool(forKey: "customizeAppId") }
        set { self.set(newValue, forKey: "customizeAppId") }
    }
    var isExportResignedAppEnabled: Bool {
        get { self.bool(forKey: "isExportResignedAppEnabled") }
        set { self.set(newValue, forKey: "isExportResignedAppEnabled") }
    }
    var isVerboseOperationsLoggingEnabled: Bool {
        get { self.bool(forKey: "isVerboseOperationsLoggingEnabled") }
        set { self.set(newValue, forKey: "isVerboseOperationsLoggingEnabled") }
    }
    var isMinimuxerConsoleLoggingEnabled: Bool {
        get { self.bool(forKey: "isMinimuxerConsoleLoggingEnabled") }
        set { self.set(newValue, forKey: "isMinimuxerConsoleLoggingEnabled") }
    }
    var isMinimuxerStatusCheckEnabled: Bool {
        get { self.bool(forKey: "isMinimuxerStatusCheckEnabled") }
        set { self.set(newValue, forKey: "isMinimuxerStatusCheckEnabled") }
    }

    var recreateDatabaseOnNextStart: Bool {
        get { self.bool(forKey: "recreateDatabaseOnNextStart") }
        set { self.set(newValue, forKey: "recreateDatabaseOnNextStart") }
    }
    var isPairingReset: Bool {
        get { self.bool(forKey: "isPairingReset") }
        set { self.set(newValue, forKey: "isPairingReset") }
    }
    var isDebugModeEnabled: Bool {
        get { self.bool(forKey: "isDebugModeEnabled") }
        set { self.set(newValue, forKey: "isDebugModeEnabled") }
    }
    var presentedLaunchReminderNotification: Bool {
        get { self.bool(forKey: "presentedLaunchReminderNotification") }
        set { self.set(newValue, forKey: "presentedLaunchReminderNotification") }
    }
    
    var legacySideloadedApps: [String]? {
        get { self.stringArray(forKey: "legacySideloadedApps") }
        set { self.set(newValue, forKey: "legacySideloadedApps") }
    }
    
    var isLegacyDeactivationSupported: Bool {
        get { self.bool(forKey: "isLegacyDeactivationSupported") }
        set { self.set(newValue, forKey: "isLegacyDeactivationSupported") }
    }
    var activeAppLimitIncludesExtensions: Bool {
        get { self.bool(forKey: "activeAppLimitIncludesExtensions") }
        set { self.set(newValue, forKey: "activeAppLimitIncludesExtensions") }
    }
    
    var localServerSupportsRefreshing: Bool {
        get { self.bool(forKey: "localServerSupportsRefreshing") }
        set { self.set(newValue, forKey: "localServerSupportsRefreshing") }
    }
    
    var patchedApps: [String]? {
        get { self.stringArray(forKey: "patchedApps") }
        set { self.set(newValue, forKey: "patchedApps") }
    }
    
    var trustedSourceIDs: [String]? {
        get { self.stringArray(forKey: "trustedSourceIDs") }
        set { self.set(newValue, forKey: "trustedSourceIDs") }
    }
    var trustedServerURL: String? {
        get { self.string(forKey: "trustedServerURL") }
        set { self.set(newValue, forKey: "trustedServerURL") }
    }
    
    var betaUdpatesTrack: String? {
        get { self.string(forKey: "betaUdpatesTrack") }
        set { self.set(newValue, forKey: "betaUdpatesTrack") }
    }

    @nonobjc var preferredAppSorting: AppSorting {
        get {
            let sorting = _preferredAppSorting.flatMap { AppSorting(rawValue: $0) } ?? .default
            return sorting
        }
        set {
            _preferredAppSorting = newValue.rawValue
        }
    }
    
    private var _preferredAppSorting: String? {
        get { self.string(forKey: "preferredAppSorting") }
        set { self.set(newValue, forKey: "preferredAppSorting") }
    }
    
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
    
    private var _activeAppsLimit: NSNumber? {
        get { self.object(forKey: "activeAppsLimit") as? NSNumber }
        set { self.set(newValue, forKey: "activeAppsLimit") }
    }
    
    // Including "MacDirtyCow" in name triggers false positives with malware detectors 🤷‍♂️
    var isCowExploitSupported: Bool {
        get { self.bool(forKey: "isCowExploitSupported") }
        set { self.set(newValue, forKey: "isCowExploitSupported") }
    }
    
    var permissionCheckingDisabled: Bool {
        get { self.bool(forKey: "permissionCheckingDisabled") }
        set { self.set(newValue, forKey: "permissionCheckingDisabled") }
    }
    var responseCachingDisabled: Bool {
        get { self.bool(forKey: "responseCachingDisabled") }
        set { self.set(newValue, forKey: "responseCachingDisabled") }
    }
    
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
            "isAppLimitDisabled": false,
            "isBetaUpdatesEnabled": false,
            "customizeAppId": false,
            "isExportResignedAppEnabled": false,
            "isDebugModeEnabled": false,
            "isVerboseOperationsLoggingEnabled": false,
            "isMinimuxerConsoleLoggingEnabled": false, // minimuxer logging is disabled by default for console loggin
            "isMinimuxerStatusCheckEnabled": false, // minimuxer status check is disabled by default to support LocalDevVPN based cellular refresh
            "recreateDatabaseOnNextStart": false, 
            "isBackgroundRefreshEnabled": true,
            "enableEMPforWireguard": false,
            "isIdleTimeoutDisableEnabled": true,
            "isPairingReset": true,
            "isLegacyDeactivationSupported": isLegacyDeactivationSupported,
            "activeAppLimitIncludesExtensions": activeAppLimitIncludesExtensions,
            "localServerSupportsRefreshing": localServerSupportsRefreshing,
            "requiresAppGroupMigration": true,
            "menuAnisetteList": "https://servers.sidestore.io/servers.json",
            "menuAnisetteURL": "https://ani.sidestore.io",
            "isCowExploitSupported": isMacDirtyCowSupported,
            "permissionCheckingDisabled": permissionCheckingDisabled,
            "preferredAppSorting": preferredAppSorting.rawValue,
            "betaUdpatesTrack": defaultBetaUpdatesTrack,
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
