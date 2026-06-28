//
//  UserDefaults+AltStore.swift
//  AltStore
//
//  Created by Magesh K on 6/17/26.
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
    
    // Default track for beta updates when beta-updates are enabled
    static let defaultBetaUpdatesTrack: String = ReleaseTracks.nightly.rawValue


    @objc var firstLaunch: Date? {
        get { self.object(forKey: #function) as? Date }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var requiresAppGroupMigration: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var textServer: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var sidejitenable: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var textInputSideJITServerurl: String? {
        get { self.string(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var textInputAnisetteURL: String? {
        get { self.string(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var customAnisetteURL: String? {
        get { self.string(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var menuAnisetteURL: String {
        get { self.string(forKey: #function) ?? "" }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var menuAnisetteList: String {
        get { self.string(forKey: #function) ?? "" }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var menuAnisetteServersList: [String] {
        get { self.stringArray(forKey: #function) ?? [] }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var preferredServerID: String? {
        get { self.string(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    
    @objc var isBackgroundRefreshEnabled: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var enableEMPforWireguard: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var isIdleTimeoutDisableEnabled: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var isAppLimitDisabled: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var isBetaUpdatesEnabled: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var customizeAppId: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var isExportResignedAppEnabled: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var isVerboseOperationsLoggingEnabled: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var isMinimuxerConsoleLoggingEnabled: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var isMinimuxerStatusCheckEnabled: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }

    @objc var recreateDatabaseOnNextStart: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var isPairingReset: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var isDebugModeEnabled: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var presentedLaunchReminderNotification: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    
    @objc var legacySideloadedApps: [String]? {
        get { self.stringArray(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    
    @objc var isLegacyDeactivationSupported: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var activeAppLimitIncludesExtensions: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    
    @objc var localServerSupportsRefreshing: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    
    @objc var patchedApps: [String]? {
        get { self.stringArray(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    
    @objc var trustedSourceIDs: [String]? {
        get { self.stringArray(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var trustedServerURL: String? {
        get { self.string(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    
    @objc var betaUdpatesTrack: String? {
        get { self.string(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    
    // Including "MacDirtyCow" in name triggers false positives with malware detectors 🤷‍♂️
    @objc var isCowExploitSupported: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    
    @objc var permissionCheckingDisabled: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var responseCachingDisabled: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
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
    
    @objc(preferredAppSorting) private var _preferredAppSorting: String? {
        get { self.string(forKey: "preferredAppSorting") }
        set { self.set(newValue, forKey: "preferredAppSorting") }
    }
    
    @nonobjc var activeAppsLimit: Int? {
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
    
    @objc(activeAppsLimit) private var _activeAppsLimit: NSNumber? {
        get { self.object(forKey: "activeAppsLimit") as? NSNumber }
        set { self.set(newValue, forKey: "activeAppsLimit") }
    }
    
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
        
        let permissionCheckingDisabled = false
        
        // Pre-iOS 15 doesn't support custom sorting, so default to sorting by name.
        // Otherwise, default to `default` sorting (a.k.a. "source order").
        let preferredAppSorting: AppSorting = if #available(iOS 15, *) { .default } else { .name }
        
        let defaults = [
            #keyPath(UserDefaults.isAppLimitDisabled): false,
            #keyPath(UserDefaults.isBetaUpdatesEnabled): false,
            #keyPath(UserDefaults.customizeAppId): false,
            #keyPath(UserDefaults.isExportResignedAppEnabled): false,
            #keyPath(UserDefaults.isDebugModeEnabled): false,
            #keyPath(UserDefaults.isVerboseOperationsLoggingEnabled): false,
            #keyPath(UserDefaults.isMinimuxerConsoleLoggingEnabled): false, // minimuxer logging is disabled by default for console loggin
            #keyPath(UserDefaults.isMinimuxerStatusCheckEnabled): true, // minimuxer status check is disabled by default to support LocalDevVPN based cellular refresh
            #keyPath(UserDefaults.recreateDatabaseOnNextStart): false,
            #keyPath(UserDefaults.isBackgroundRefreshEnabled): true,
            #keyPath(UserDefaults.enableEMPforWireguard): false,
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
