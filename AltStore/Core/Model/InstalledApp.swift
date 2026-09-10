//
//  InstalledApp.swift
//  AltStore
//
//  Created by Riley Testut on 5/20/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import CoreData

import SideSign
@preconcurrency import UIKit
import SemanticVersion

public enum CertificateStatus: Equatable, Sendable {
    case valid(isCrossSigned: Bool)
    case revoked
    case expired
}

extension InstalledApp
{
    public static var freeAccountActiveAppsLimit: Int {
        if UserDefaults.standard.isAppLimitDisabled
        {
            // MacDirtyCow exploit allows users to remove 3-app limit, so return 10 to match App ID limit per-week.
            // Don't return nil because that implies there is no limit, which isn't quite true due to App ID limit.
            return 10
        }
        else
        {
            // Free developer accounts are limited to only 3 active sideloaded apps at a time as of iOS 13.3.1.
            return 3
        }
    }
}

public protocol InstalledAppProtocol: Fetchable
{
    var name: String { get }
    var bundleIdentifier: String { get }
    var resignedBundleIdentifier: String { get }
    var customBundleIdentifier: String? { get }
    var version: String { get }
    
    var refreshedDate: Date { get }
    var expirationDate: Date { get }
    var installedDate: Date { get }
}

@objc(InstalledApp)
public class InstalledApp: BaseEntity, InstalledAppProtocol
{
    /* Properties */
    @NSManaged public var name: String
    @NSManaged public var bundleIdentifier: String
    @NSManaged public var resignedBundleIdentifier: String
    @NSManaged public var customBundleIdentifier: String?
    @NSManaged public var version: String
    @NSManaged public var buildVersion: String
    
    @NSManaged public var refreshedDate: Date
    @NSManaged public var expirationDate: Date
    @NSManaged public var installedDate: Date
    
    @NSManaged public var isActive: Bool
    @NSManaged public var hasAlternateIcon: Bool
    
    @NSManaged public var useMainProfile: Bool
    
    @NSManaged public var certificateSerialNumber: String?
    @NSManaged public var storeBuildVersion: String?
    @NSManaged public var certificateStatusRaw: String?
    
    public var certificateStatus: CertificateStatus {
        get {
            guard let raw = self.certificateStatusRaw else { return .valid(isCrossSigned: false) }
            switch raw {
            case "valid":
                return .valid(isCrossSigned: false)
            case "validCrossSigned":
                return .valid(isCrossSigned: true)
            case "revoked":
                return .revoked
            case "expired":
                return .expired
            default:
                return .valid(isCrossSigned: false)
            }
        }
        set {
            switch newValue {
            case .valid(let isCrossSigned):
                self.certificateStatusRaw = isCrossSigned ? "validCrossSigned" : "valid"
            case .revoked:
                self.certificateStatusRaw = "revoked"
            case .expired:
                self.certificateStatusRaw = "expired"
            }
        }
    }

    
    /* Transient */
    @NSManaged public var isRefreshing: Bool
    
    /* Relationships */
    @NSManaged public var storeApp: StoreApp?
    @NSManaged public var team: Team?
    @NSManaged public var releaseTrack: ReleaseTrack?
    @NSManaged public var appExtensions: Set<InstalledExtension>
    
    @NSManaged public private(set) var loggedErrors: NSSet /* Set<LoggedError> */ // Use NSSet to avoid eagerly fetching values.
    
    public var isSideloaded: Bool {
        return self.storeApp == nil
    }
    
    @objc public var hasUpdate: Bool {
        // Basic validation
        guard isActive,
              let storeApp = self.storeApp,
              let latestVersion = storeApp.latestSupportedVersion else
        {
            return false
        }
        
        // Check pledge requirements
        guard !storeApp.isPledgeRequired || storeApp.isPledged else
        {
            return false
        }
        
        // Get current semantic versions
        let currentSemVer = SemanticVersion(self.version)
        let latestSemVer = SemanticVersion(latestVersion.version)
        
        // If semantic versions can't be parsed, fall back to string comparison
        if currentSemVer == nil || latestSemVer == nil {
            return !matches(latestVersion)
        }
        let currentVer = SemanticVersion("\(currentSemVer!.major).\(currentSemVer!.minor).\(currentSemVer!.patch)")
        let latestVer  = SemanticVersion("\(latestSemVer!.major).\(latestSemVer!.minor).\(latestSemVer!.patch)")
        
        // Compare by major.minor.patch
        if latestVer! > currentVer! {
            return true
        }
        
        // Check beta updates if enabled
        if UserDefaults.standard.isBetaUpdatesEnabled,
           ReleaseTrackType.betaTracks.contains(latestVersion.channel),
           latestVer == currentVer,         // major.minor.patch are matching
           // now compare by preRelease and build to break the tie
           // TODO: since multiple tracks can be independent, when a different version is available on selected track than installed
           //       we accept it, now ex: if the setup is consistent for upstream merge lets say from alpha to nightly and alpha can never fall behind nightly,
           //       then the preRelease+build combo will always be incremental and our below not-equals check will still work.
           (latestSemVer!.build != currentSemVer!.build) || (latestSemVer!.preRelease != currentSemVer!.preRelease)
        {
            return true
        }
        
        // else include everything as-is when doing lexicographic comparison
        // NOTE: stable x.y.z is always > x.y.z-abcd+1234
        return latestSemVer! > currentSemVer!
    }

    
    public var appIDCount: Int {
        return 1 + self.appExtensions.count
    }
    
    public var requiredActiveSlots: Int {
        let requiredActiveSlots = UserDefaults.standard.activeAppLimitIncludesExtensions ? self.appIDCount : 1
        return requiredActiveSlots
    }
    
    private override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?)
    {
        super.init(entity: entity, insertInto: context)
    }
    
    public init(resignedAppBundle: ALTApplication, originalBundleIdentifier: String, certificateSerialNumber: String?, storeBuildVersion: String?, context: NSManagedObjectContext) throws
    {
        super.init(entity: InstalledApp.entity(), insertInto: context)
        
        self.bundleIdentifier = originalBundleIdentifier
        
        debugLog("InstalledApp `self.bundleIdentifier`: \(self.bundleIdentifier)")
        
        self.refreshedDate = Date()
        self.installedDate = Date()
        
        #if targetEnvironment(simulator)
        self.expirationDate = self.refreshedDate.addingTimeInterval(60 * 60 * 24 * 7)
        #else
        guard let expirationDate = resignedAppBundle.provisioningProfile?.expirationDate else {
            throw ALTError.invalidApp(reason: "The app is missing a valid provisioning profile.")
        }
        self.expirationDate = expirationDate
        #endif
        
        // In practice this update() is redundant because we always call update() again after init from callers,
        // but better to have an init that is guaranteed to successfully initialize an object
        // than one that has a hidden assumption a second method will be called.
        self.update(resignedAppBundle: resignedAppBundle, certificateSerialNumber: certificateSerialNumber, storeBuildVersion: storeBuildVersion)
    }
}

public extension InstalledApp
{
    var localizedVersion: String {
        guard let storeBuildVersion else { return self.version }
        
        let localizedVersion = "\(self.version) (\(storeBuildVersion))"
        return localizedVersion
    }
    
    func update(resignedAppBundle: ALTApplication, certificateSerialNumber: String?, storeBuildVersion: String?)
    {
        self.name = resignedAppBundle.name
        
        self.resignedBundleIdentifier = resignedAppBundle.bundleIdentifier
        self.version = resignedAppBundle.version
        
        self.buildVersion = resignedAppBundle.buildVersion
        self.storeBuildVersion = storeBuildVersion
        
        self.certificateSerialNumber = certificateSerialNumber
        
        if let provisioningProfile = resignedAppBundle.provisioningProfile
        {
            self.update(provisioningProfile: provisioningProfile)
        }
    }
    
    func update(provisioningProfile: ALTProvisioningProfile)
    {
        self.refreshedDate = provisioningProfile.creationDate
        self.expirationDate = provisioningProfile.expirationDate
    }
    
    func loadIcon() async throws -> UIImage?
    {
        if self.bundleIdentifier == StoreApp.altstoreAppID,
           let iconName = UIApplication.alt_shared?.value(forKey: "alternateIconName") as? String
        {
            // Use alternate app icon for AltStore, if one was chosen.
            let imageName = iconName.replacingOccurrences(of: "Icon", with: "")
            let image = UIImage(named: imageName) ?? UIImage(named: iconName)
            return image
        }
        
        let hasAlternateIcon = self.hasAlternateIcon
        let alternateIconURL = self.alternateIconURL
        let fileURL = self.fileURL
        
        return try await Task.detached(priority: .userInitiated) {
            if hasAlternateIcon,
               case let data = try Data(contentsOf: alternateIconURL),
               let icon = UIImage(data: data)
            {
                return icon
            }
            
            let appBundle = ALTApplication(fileURL: fileURL)
            return appBundle?.icon
        }.value
    }

    func matches(_ appVersion: AppVersion) -> Bool 
    {
        let matchesAppVersion = (self.version == appVersion.version && self.storeBuildVersion == appVersion.buildVersion)
        return matchesAppVersion
    }
}

public extension InstalledApp
{
    @nonobjc class func fetchRequest() -> NSFetchRequest<InstalledApp>
    {
        return NSFetchRequest<InstalledApp>(entityName: "InstalledApp")
    }
    
    class func supportedUpdatesFetchRequest() -> NSFetchRequest<InstalledApp> 
    {
        let fetchRequest = InstalledApp.fetchRequest() as NSFetchRequest<InstalledApp>
        
        fetchRequest.predicate = NSPredicate(format: "%K == YES", #keyPath(InstalledApp.hasUpdate))
        
        return fetchRequest
    }
    
    class func activeAppsFetchRequest() -> NSFetchRequest<InstalledApp>
    {
        let fetchRequest = InstalledApp.fetchRequest() as NSFetchRequest<InstalledApp>
        fetchRequest.predicate = NSPredicate(format: "%K == YES", #keyPath(InstalledApp.isActive))
        debugLog("Active Apps Fetch Request: \(String(describing: fetchRequest.predicate))")
        return fetchRequest
    }
    
    class func fetchAltStore(in context: NSManagedObjectContext) -> InstalledApp?
    {
        let predicate = NSPredicate(format: "%K == %@", #keyPath(InstalledApp.bundleIdentifier), StoreApp.altstoreAppID)
        debugLog("Fetch 'AltStore' Predicate: \(String(describing: predicate))")
        let altStore = InstalledApp.first(satisfying: predicate, in: context)
        return altStore
    }
    
    class func fetchActiveApps(in context: NSManagedObjectContext) -> [InstalledApp]
    {
        let activeApps = InstalledApp.fetch(InstalledApp.activeAppsFetchRequest(), in: context)
        return activeApps
    }
    
    class func fetchAppsForRefreshingAll(in context: NSManagedObjectContext) -> [InstalledApp]
    {
        let predicate = NSPredicate(format: "(%K == YES AND %K != %@) AND (%K == nil OR %K == NO OR %K == YES)",
                                    #keyPath(InstalledApp.isActive),
                                    #keyPath(InstalledApp.bundleIdentifier), StoreApp.altstoreAppID,
                                    #keyPath(InstalledApp.storeApp),
                                    #keyPath(InstalledApp.storeApp.isPledgeRequired),
                                    #keyPath(InstalledApp.storeApp.isPledged))
        
        var installedApps = InstalledApp.all(satisfying: predicate,
                                             sortedBy: [NSSortDescriptor(keyPath: \InstalledApp.expirationDate, ascending: true)],
                                             in: context)
        
        if let altStoreApp = InstalledApp.fetchAltStore(in: context)
        {
            // Refresh AltStore last since it causes app to quit.
            
            if let storeApp = altStoreApp.storeApp
            {
                if !storeApp.isPledgeRequired || storeApp.isPledged
                {
                    // Only add AltStore if it's the public version OR if it's the beta and we're pledged to it.
                    installedApps.append(altStoreApp)
                }
            }
            else
            {
                // No associated storeApp, so add it just to be safe.
                installedApps.append(altStoreApp)
            }
        }
        
        return installedApps
    }
    
    class func fetchAppsForBackgroundRefresh(in context: NSManagedObjectContext) -> [InstalledApp]
    {
        // Date 6 hours before now.
        let date = Date().addingTimeInterval(-1 * 6 * 60 * 60)
        
        let predicate = NSPredicate(format: "(%K == YES) AND (%K < %@) AND (%K != %@) AND (%K == nil OR %K == NO OR %K == YES)",
                                    #keyPath(InstalledApp.isActive),
                                    #keyPath(InstalledApp.refreshedDate), date as NSDate,
                                    #keyPath(InstalledApp.bundleIdentifier), StoreApp.altstoreAppID,
                                    #keyPath(InstalledApp.storeApp),
                                    #keyPath(InstalledApp.storeApp.isPledgeRequired),
                                    #keyPath(InstalledApp.storeApp.isPledged)
        )
        
        var installedApps = InstalledApp.all(satisfying: predicate,
                                             sortedBy: [NSSortDescriptor(keyPath: \InstalledApp.expirationDate, ascending: true)],
                                             in: context)
        
        if let altStoreApp = InstalledApp.fetchAltStore(in: context), altStoreApp.refreshedDate < date
        {
            if let storeApp = altStoreApp.storeApp
            {
                if !storeApp.isPledgeRequired || storeApp.isPledged
                {
                    // Only add AltStore if it's the public version OR if it's the beta and we're pledged to it.
                    installedApps.append(altStoreApp)
                }
            }
            else
            {
                // No associated storeApp, so add it just to be safe.
                installedApps.append(altStoreApp)
            }
        }
        
        return installedApps
    }
}

public extension InstalledApp
{
    // TODO: @mahee96: Do NOT hardcode app's url scheme prefixes as in here
    //       Need to get it dynamically from the Info.plist of other means
    var openAppURL: URL {
        return InstalledApp.openAppURL(resignedBundleIdentifier: self.resignedBundleIdentifier)
    }
    
    // TODO: @mahee96: Do NOT hardcode app's url scheme prefixes as in here
    //       Need to get it dynamically from the Info.plist of other means
    class func openAppURL(resignedBundleIdentifier: String) -> URL
    {
        let openAppURL = URL(string: "sidestore-" + resignedBundleIdentifier + "://")!
        return openAppURL
    }
    
    class func openAppURL(for app: InstalledAppProtocol) -> URL
    {
        return self.openAppURL(resignedBundleIdentifier: app.resignedBundleIdentifier)
    }
    
    class func openAppURL(for app: AppProtocol) -> URL
    {
        let identifier = (app as? InstalledAppProtocol)?.resignedBundleIdentifier ?? app.bundleIdentifier
        return self.openAppURL(resignedBundleIdentifier: identifier)
    }
}

public extension InstalledApp
{
    class var appsDirectoryURL: URL {
        let baseDirectory = FileManager.default.altstoreSharedDirectory ?? FileManager.default.applicationSupportDirectory
        let appsDirectoryURL = baseDirectory.appendingPathComponent("Apps")
        
        do { try FileManager.default.createDirectory(at: appsDirectoryURL, withIntermediateDirectories: true, attributes: nil) }
        catch { debugLog("Creating App Directory Error: \(error)") }
        return appsDirectoryURL
    }
    
    class var legacyAppsDirectoryURL: URL {
        let baseDirectory = FileManager.default.applicationSupportDirectory
        let appsDirectoryURL = baseDirectory.appendingPathComponent("Apps")
        return appsDirectoryURL
    }
    
    class func fileURL(for app: AppProtocol) -> URL
    {
        let appURL = self.directoryURL(for: app).appendingPathComponent("App.app")
        return appURL
    }
    
    class func refreshedIPAURL(for app: AppProtocol) -> URL
    {
        let ipaURL = self.directoryURL(for: app).appendingPathComponent("Refreshed.ipa")
        debugLog("[InstalledApp] 'ipaURL': \(ipaURL.absoluteString)")
        return ipaURL
    }
    
    class func directoryURL(for app: AppProtocol) -> URL
    {
        let directoryURL = InstalledApp.appsDirectoryURL.appendingPathComponent(app.bundleIdentifier)
        
        do { try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil) }
        catch { debugLog("\(error)") }
        
        return directoryURL
    }
    
    class func installedAppUTI(forBundleIdentifier bundleIdentifier: String) -> String
    {
        let installedAppUTI = "io.sidestore.Installed." + bundleIdentifier
        return installedAppUTI
    }
    
    class func installedBackupAppUTI(forBundleIdentifier bundleIdentifier: String) -> String
    {
        let installedBackupAppUTI = InstalledApp.installedAppUTI(forBundleIdentifier: bundleIdentifier) + ".backup"
        return installedBackupAppUTI
    }
    
    class func alternateIconURL(forBundleIdentifier bundleIdentifier: String) -> URL
    {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let iconsDirectory = appSupport.appendingPathComponent("AppIcons", isDirectory: true)
        try? FileManager.default.createDirectory(at: iconsDirectory, withIntermediateDirectories: true, attributes: nil)
        return iconsDirectory.appendingPathComponent("\(bundleIdentifier).png")
    }
    
    class func alternateIconURL(for app: InstalledAppProtocol) -> URL
    {
        let bundleID = app.customBundleIdentifier ?? app.resignedBundleIdentifier
        return self.alternateIconURL(forBundleIdentifier: bundleID)
    }
    
    var directoryURL: URL {
        return InstalledApp.directoryURL(for: self)
    }
    
    var fileURL: URL {
        return InstalledApp.fileURL(for: self)
    }
    
    var refreshedIPAURL: URL {
        return InstalledApp.refreshedIPAURL(for: self)
    }
    
    var installedAppUTI: String {
        return InstalledApp.installedAppUTI(forBundleIdentifier: self.resignedBundleIdentifier)
    }
    
    var installedBackupAppUTI: String {
        return InstalledApp.installedBackupAppUTI(forBundleIdentifier: self.resignedBundleIdentifier)
    }
    
    var alternateIconURL: URL {
        return InstalledApp.alternateIconURL(for: self)
    }
}
