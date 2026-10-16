//
//  UserDefaults+AltStore.swift
//  AltStore
//
//  Created by Magesh K on 6/17/26.
//  Copyright © 2019 SideStore. All rights reserved.
//

import Foundation
import Minimuxer
import MinimuxerCommon

public extension UserDefaults
{
    // Default track for beta updates when beta-updates are enabled
    static let defaultBetaUpdatesTrack: String = ReleaseTrackType.nightly.description


    @objc var firstLaunch: Date? {
        get { self.object(forKey: #function) as? Date }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var hasCompletedOnboarding: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var acctFileChecksum: String? {
        get { self.string(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var textServer: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var isSideJITServerEnabled: Bool {
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
    @objc var customAnisetteClientInfo: String? {
        get { self.string(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var customAnisetteUserAgent: String? {
        get { self.string(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var customAnisetteDeviceID: String? {
        get { self.string(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var customAnisetteLocalUserID: String? {
        get { self.string(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var customAnisetteLocale: String? {
        get { self.string(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var customAnisetteTimeZone: String? {
        get { self.string(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var customAnisetteXcodeVersion: String? {
        get { self.string(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var customAnisetteSerialNumber: String? {
        get { self.string(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var customAnisetteRoutingInfo: String? {
        get { self.string(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    
    @objc var isBackgroundRefreshEnabled: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var isBackgroundServiceEnabled: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    var backgroundServiceMode: BackgroundServiceMode {
        get {
            let mode = _backgroundServiceMode.flatMap { BackgroundServiceMode(rawValue: $0) } ?? .audio
            return mode
        }
        set {
            _backgroundServiceMode = newValue.rawValue
        }
    }
    @objc(backgroundServiceMode) private var _backgroundServiceMode: String? {
        get { self.string(forKey: "backgroundServiceMode") }
        set { self.set(newValue, forKey: "backgroundServiceMode") }
    }
    @objc var enableEMPforWireguard: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var minimuxerGatewayBackend: String {
        get { self.string(forKey: #function) ?? GatewayBackend.idevice.rawValue }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var remotePairingPortOverride: Int {
        get { self.integer(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var lastDiscoveredRemotePairingPort: Int {
        get { self.integer(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var isAutoRetryRemotePairingPortEnabled: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var isInstallConfirmationEnabled: Bool {
        get {
            guard self.object(forKey: #function) != nil else { return true }
            return self.bool(forKey: #function)
        }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var isClearCustomizationsOnUninstallEnabled: Bool {
        get {
            guard self.object(forKey: #function) != nil else { return true }
            return self.bool(forKey: #function)
        }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var isAutoLaunchAppAfterInstallEnabled: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var deviceProbeTimeoutOverride: Int {
        get { self.integer(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var skipNonCopyableBackupFiles: Bool {
        get {
            guard self.object(forKey: #function) != nil else { return true }
            return self.bool(forKey: #function)
        }
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
    @objc var isRotateLogsOnStartupEnabled: Bool {
        get {
            if self.object(forKey: #function) == nil {
                return true
            }
            return self.bool(forKey: #function)
        }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var freeAcctAppIdDeletion: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var isBetaUpdatesEnabled: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var customizeInfoPlist: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var preferSheetForInfoPlistCustomization: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var customizeEntitlements: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var preferSheetForEntitlementsCustomization: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var customizeAppId: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var customizeAppIcon: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var customizeProvisioningProfile: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var turnOffDataShortcutName: String {
        get { self.string(forKey: #function) ?? "TurnOffData" }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var turnOnDataShortcutName: String {
        get { self.string(forKey: #function) ?? "TurnOnData" }
        set { self.set(newValue, forKey: #function) }
    }
    
    var customizeAppExtensions: AppExtensionCustomization {
        get {
            let option = _customizeAppExtensions.flatMap { AppExtensionCustomization(rawValue: $0) } ?? .promptUser
            return option
        }
        set {
            _customizeAppExtensions = newValue.rawValue
        }
    }
    @objc(customizeAppExtensions) private var _customizeAppExtensions: String? {
        get { self.string(forKey: "customizeAppExtensions") }
        set { self.set(newValue, forKey: "customizeAppExtensions") }
    }
    var appImportSourceMode: AppImportSourceMode {
        get { _appImportSourceMode.flatMap { AppImportSourceMode(rawValue: $0) } ?? .prompt
        }
        set {
            _appImportSourceMode = newValue.rawValue
        }
    }
    @objc(appImportSourceMode) private var _appImportSourceMode: String? {
        get { self.string(forKey: "appImportSourceMode") }
        set { self.set(newValue, forKey: "appImportSourceMode") }
    }
    var autoFixAppGroupIDs: Bool {
        get {
            if self.object(forKey: "autoFixAppGroupIDs") != nil {
                return self._autoFixAppGroupIDs
            }
            return true
        }
        set { self._autoFixAppGroupIDs = newValue }
    }
    @objc(autoFixAppGroupIDs) private var _autoFixAppGroupIDs: Bool {
        get { self.bool(forKey: "autoFixAppGroupIDs") }
        set { self.set(newValue, forKey: "autoFixAppGroupIDs") }
    }
    @objc var preferResignedIPA: Bool {
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
    @objc var isAltSignVerboseLoggingEnabled: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var isSideStoreVerboseLoggingEnabled: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var isMinimuxerVerboseLoggingEnabled: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var isMinimuxerBackendHotswapEnabled: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var pairingFileEditSuppressedSHAs: [String: Bool] {
        get { (self.dictionary(forKey: #function) as? [String: Bool]) ?? [:] }
        set { self.set(newValue, forKey: #function) }
    }
    func isPairingFileEditSuppressed(forHash sha: String) -> Bool {
        pairingFileEditSuppressedSHAs[sha] ?? false
    }
    func setPairingFileEditSuppressed(_ suppressed: Bool, forHash sha: String) {
        var map = pairingFileEditSuppressedSHAs
        map[sha] = suppressed
        pairingFileEditSuppressedSHAs = map
    }

    var activePairingProtocol: PairingProtocol? {
        get { _activePairingProtocol.flatMap { PairingProtocol(rawValue: $0) } }
        set { _activePairingProtocol = newValue?.rawValue }
    }
    @objc(activePairingProtocol) private var _activePairingProtocol: String? {
        get { self.string(forKey: "activePairingProtocol") }
        set { self.set(newValue, forKey: "activePairingProtocol") }
    }

    var preferredPairingProtocol: PairingProtocol? {
        get { _preferredPairingProtocol.flatMap { PairingProtocol(rawValue: $0) } }
        set { _preferredPairingProtocol = newValue?.rawValue }
    }
    @objc(preferredPairingProtocol) private var _preferredPairingProtocol: String? {
        get { self.string(forKey: "preferredPairingProtocol") }
        set { self.set(newValue, forKey: "preferredPairingProtocol") }
    }
    @objc var keepSigningCertsAfterLogout: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var keepAnisetteDataAfterLogout: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var isDeviceRegistered: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var keepAnisetteHeadersAfterLogout: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var keepSideSignHeadersAfterLogout: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }

    @objc var isAnisetteOfflineMode: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var disableAnisetteRotation: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var useOnDeviceAnisette: Bool {
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
    
    @objc var patchedApps: [String]? {
        get { self.stringArray(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    
    @objc var defaultSourceIDs: [String]? {
        get { self.stringArray(forKey: "defaultSourceIDs") }
        set { self.set(newValue, forKey: "defaultSourceIDs") }
    }
    @objc var defaultServerURL: String? {
        get { self.string(forKey: "defaultServerURL") }
        set { self.set(newValue, forKey: "defaultServerURL") }
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
    @objc var isBundleIDVerificationEnabled: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var isiOSVersionVerificationEnabled: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var isAppVersionVerificationEnabled: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var isChecksumVerificationEnabled: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var isFileSizeVerificationEnabled: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var appVerificationDisabled: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var responseCachingDisabled: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var alwaysShowWireGuardConfig: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }
    @objc var acceptIPv6ConnectionConfig: Bool {
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
    
    @objc var isCellularRefreshEnabled: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
    }

    @objc var useLocalVPN: Bool {
        get { self.bool(forKey: #function) }
        set { self.set(newValue, forKey: #function) }
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
        
        let ios16 = OperatingSystemVersion(majorVersion: 16, minorVersion: 0, patchVersion: 0)
        let ios16_2 = OperatingSystemVersion(majorVersion: 16, minorVersion: 2, patchVersion: 0)
        let ios15_7_2 = OperatingSystemVersion(majorVersion: 15, minorVersion: 7, patchVersion: 2)
        
        // MacDirtyCow supports iOS 14.0 - 15.7.1 OR 16.0 - 16.1.2
        let isMacDirtyCowSupported =
        (ProcessInfo.processInfo.isOperatingSystemAtLeast(ios14) && !ProcessInfo.processInfo.isOperatingSystemAtLeast(ios15_7_2)) ||
        (ProcessInfo.processInfo.isOperatingSystemAtLeast(ios16) && !ProcessInfo.processInfo.isOperatingSystemAtLeast(ios16_2))
        
        let preferredAppSorting: AppSorting = .default
        
        let defaults = [
            // TODO: @mahee96: need to retire since irrelevant in ios 15+
            #keyPath(UserDefaults.isLegacyDeactivationSupported): isLegacyDeactivationSupported,
            #keyPath(UserDefaults.activeAppLimitIncludesExtensions): activeAppLimitIncludesExtensions,
            
            // still used on ios 15+
            #keyPath(UserDefaults.isAppLimitDisabled): false,
            #keyPath(UserDefaults.isCowExploitSupported): isMacDirtyCowSupported,
            #keyPath(UserDefaults._preferredAppSorting): preferredAppSorting.rawValue,

            // sidestore actively used
            #keyPath(UserDefaults.minimuxerGatewayBackend): GatewayBackend.idevice.rawValue,
            #keyPath(UserDefaults.keepSigningCertsAfterLogout): true,
            #keyPath(UserDefaults.keepAnisetteDataAfterLogout): true,
            #keyPath(UserDefaults.keepAnisetteHeadersAfterLogout): true,
            #keyPath(UserDefaults.keepSideSignHeadersAfterLogout): true,
            #keyPath(UserDefaults.isBackgroundRefreshEnabled): true,
            #keyPath(UserDefaults.isBackgroundServiceEnabled): true,
            #keyPath(UserDefaults.isBetaUpdatesEnabled): false,
            #keyPath(UserDefaults.permissionCheckingDisabled): true,
            #keyPath(UserDefaults.isBundleIDVerificationEnabled): true,
            #keyPath(UserDefaults.isiOSVersionVerificationEnabled): true,
            #keyPath(UserDefaults.isAppVersionVerificationEnabled): true,
            #keyPath(UserDefaults.isChecksumVerificationEnabled): true,
            #keyPath(UserDefaults.isFileSizeVerificationEnabled): false,
            #keyPath(UserDefaults.appVerificationDisabled): false,
            #keyPath(UserDefaults.isIdleTimeoutDisableEnabled): true,
            #keyPath(UserDefaults.betaUdpatesTrack): defaultBetaUpdatesTrack,
            #keyPath(UserDefaults.menuAnisetteList): AppConstants.Anisette.Servers.defaultSource,
            #keyPath(UserDefaults.menuAnisetteURL): AppConstants.Anisette.Servers.defaultServerURL,
            #keyPath(UserDefaults.isAnisetteOfflineMode): false,
            #keyPath(UserDefaults.disableAnisetteRotation): false,
            #keyPath(UserDefaults.useOnDeviceAnisette): true,
            #keyPath(UserDefaults.useLocalVPN): true,
            #keyPath(UserDefaults.acceptIPv6ConnectionConfig): false,
            #keyPath(UserDefaults.isAutoRetryRemotePairingPortEnabled): true,
            #keyPath(UserDefaults.enableEMPforWireguard): false,
            #keyPath(UserDefaults.skipNonCopyableBackupFiles): true,
            
            #keyPath(UserDefaults.responseCachingDisabled): false,
            #keyPath(UserDefaults.customizeInfoPlist): false,
            #keyPath(UserDefaults.preferSheetForInfoPlistCustomization): true,
            #keyPath(UserDefaults.customizeEntitlements): false,
            #keyPath(UserDefaults.preferSheetForEntitlementsCustomization): true,
            #keyPath(UserDefaults.customizeAppId): false,
            #keyPath(UserDefaults.customizeAppIcon): false,
            #keyPath(UserDefaults.customizeProvisioningProfile): false,
            #keyPath(UserDefaults._customizeAppExtensions): AppExtensionCustomization.promptUser.rawValue,
            #keyPath(UserDefaults._appImportSourceMode): AppImportSourceMode.prompt.rawValue,
            #keyPath(UserDefaults.isInstallConfirmationEnabled): true,
            #keyPath(UserDefaults.isClearCustomizationsOnUninstallEnabled): true,
            #keyPath(UserDefaults.isAutoLaunchAppAfterInstallEnabled): false,
            #keyPath(UserDefaults.preferResignedIPA): true,
            #keyPath(UserDefaults.isExportResignedAppEnabled): false,
            #keyPath(UserDefaults.isVerboseOperationsLoggingEnabled): false,
            #keyPath(UserDefaults.isSideStoreVerboseLoggingEnabled): false,
            #keyPath(UserDefaults.isAltSignVerboseLoggingEnabled): false,
            #keyPath(UserDefaults.isMinimuxerVerboseLoggingEnabled): false,
            #keyPath(UserDefaults.isMinimuxerBackendHotswapEnabled): false,
            #keyPath(UserDefaults.pairingFileEditSuppressedSHAs): [String: Bool](),
            #keyPath(UserDefaults.isRotateLogsOnStartupEnabled): true,
            #keyPath(UserDefaults.recreateDatabaseOnNextStart): false,
            #keyPath(UserDefaults.isCellularRefreshEnabled): false,
            #keyPath(UserDefaults.turnOffDataShortcutName): "TurnOffData",
            #keyPath(UserDefaults.turnOnDataShortcutName): "TurnOnData",
            #keyPath(UserDefaults.isPairingReset): true,
            #keyPath(UserDefaults.isDebugModeEnabled): false,
            #keyPath(UserDefaults.isDeviceRegistered): false,

        ] as [String: Any]

        // TODO: temporarily forcing this to be visible in nightlies, remove this in stable release later
        UserDefaults.standard.isDebugModeEnabled = true
        
        UserDefaults.standard.register(defaults: defaults)
        
        // MDC is unsupported and spareRestore is patched
        if !isMacDirtyCowSupported && ProcessInfo().sparseRestorePatched
        {
            // Disable isAppLimitDisabled if running iOS version that doesn't support MacDirtyCow.
            UserDefaults.standard.isAppLimitDisabled = false
        }
    }
    
    static func enableGlobalLogging() {
        let setAnySelector = #selector(UserDefaults.set(_:forKey:) as (UserDefaults) -> (Any?, String) -> Void)
        let setBoolSelector = #selector(UserDefaults.set(_:forKey:) as (UserDefaults) -> (Bool, String) -> Void)
        let setIntSelector = #selector(UserDefaults.set(_:forKey:) as (UserDefaults) -> (Int, String) -> Void)
        let removeSelector = #selector(UserDefaults.removeObject(forKey:))
        
        let swizzlePairs: [(Selector, Selector)] = [
            (setAnySelector, #selector(swizzled_setObject(_:forKey:))),
            (setBoolSelector, #selector(swizzled_setBool(_:forKey:))),
            (setIntSelector, #selector(swizzled_setInteger(_:forKey:))),
            (removeSelector, #selector(swizzled_removeObject(forKey:)))
        ]
        for (orig, swiz) in swizzlePairs {
            if let m1 = class_getInstanceMethod(UserDefaults.self, orig),
               let m2 = class_getInstanceMethod(UserDefaults.self, swiz) {
                method_exchangeImplementations(m1, m2)
            }
        }
    }
    
    static func dumpAllSettingsOnBoot() {
        debugLog("=== [UserDefaults] Standard Suite Dump ===")
        dumpDictionary(UserDefaults.standard.dictionaryRepresentation())
        
        if let appGroup = Bundle.main.altstoreAppGroup,
           let sharedDefaults = WidgetDataManager.sharedDefaults,
           sharedDefaults != UserDefaults.standard 
        {
            debugLog("=== [UserDefaults] Shared AppGroup Suite Dump (\(appGroup)) ===")
            dumpDictionary(sharedDefaults.dictionaryRepresentation())
        }
    }
    
    private static func dumpDictionary(_ dict: [String: Any]) {
        let filtered = dict.filter { key, _ in
            !key.hasPrefix("Apple") && !key.hasPrefix("NS") && !key.hasPrefix("PK")
        }
        
        if JSONSerialization.isValidJSONObject(filtered),
           let data = try? JSONSerialization.data(withJSONObject: filtered, options: [.prettyPrinted, .sortedKeys]),
           let jsonString = String(data: data, encoding: .utf8) {
            debugLog(jsonString)
        } else {
            debugLog("\(filtered)")
        }
    }
}

// diag logging hooks without changes to original source 
// this is to catch any and all userdefault writes
private extension UserDefaults {
    private func formatValueForLog(_ value: Any?) -> String {
        guard let value = value else { return "nil" }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
           let jsonString = String(data: data, encoding: .utf8) {
            return jsonString
        }
        return "\(value)"
    }

    @objc private func swizzled_setObject(_ value: Any?, forKey key: String) {
        debugLog("[UserDefaults] Key '\(key)' -> \(formatValueForLog(value))")
        self.swizzled_setObject(value, forKey: key)
    }

    @objc private func swizzled_setBool(_ value: Bool, forKey key: String) {
        debugLog("[UserDefaults] Key '\(key)' -> \(value)")
        self.swizzled_setBool(value, forKey: key)
    }

    @objc private func swizzled_setInteger(_ value: Int, forKey key: String) {
        debugLog("[UserDefaults] Key '\(key)' -> \(value)")
        self.swizzled_setInteger(value, forKey: key)
    }

    @objc private func swizzled_removeObject(forKey key: String) {
        debugLog("[UserDefaults] Removed Key '\(key)'")
        self.swizzled_removeObject(forKey: key)
    }
}
