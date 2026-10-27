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
    
    var appBundleFingerprint: String? { get }
    var signingCertificateURL: URL { get }
    var directoryURL: URL { get }
    var fileURL: URL { get }
    var refreshedIPAURL: URL { get }
    var alternateIconURL: URL { get }

    var customProvisioningProfileURL: URL? { get }
    var customInfoPlistURL: URL? { get }
    var customEntitlementsURL: URL? { get }
    var customProvisioningProfile: ALTProvisioningProfile? { get }
    var customEntitlements: [String: any Sendable]? { get }
}

public extension InstalledAppProtocol {
    var appBundleFingerprint: String? { nil }
    
    var directoryURL: URL {
        return InstalledApp.appsDirectoryURL.appendingPathComponent(self.resignedBundleIdentifier)
    }
    
    var fileURL: URL {
        if let signature = self.appBundleFingerprint {
            let payloadURL = InstalledApp.payloadURL(forSignature: signature)
            if FileManager.default.fileExists(atPath: payloadURL.path) {
                return payloadURL
            }
        }
        return self.directoryURL.appendingPathComponent("App.app")
    }
    
    var refreshedIPAURL: URL {
        return self.directoryURL.appendingPathComponent("Refreshed.ipa")
    }
    
    var alternateIconURL: URL {
        let bundleID = self.customBundleIdentifier ?? self.resignedBundleIdentifier
        let appSupport = FileManager.default.applicationSupportDirectory
        return appSupport.appendingPathComponent("AppIcons", isDirectory: true).appendingPathComponent("\(bundleID).png")
    }
    
    var signingCertificateURL: URL {
        return self.directoryURL.appendingPathComponent("signing_certificate.der")
    }

    var customProvisioningProfileURL: URL? {
        let fileURL = self.directoryURL.appendingPathComponent("ProvisioningProfiles").appendingPathComponent("\(self.resignedBundleIdentifier).mobileprovision")
        return FileManager.default.fileExists(atPath: fileURL.path) ? fileURL : nil
    }

    var customInfoPlistURL: URL? {
        let fileURL = self.directoryURL.appendingPathComponent("Info.plist").appendingPathComponent("\(self.resignedBundleIdentifier).plist")
        return FileManager.default.fileExists(atPath: fileURL.path) ? fileURL : nil
    }

    var customEntitlementsURL: URL? {
        let fileURL = self.directoryURL.appendingPathComponent("Entitlements").appendingPathComponent("\(self.resignedBundleIdentifier).plist")
        return FileManager.default.fileExists(atPath: fileURL.path) ? fileURL : nil
    }

    var customProvisioningProfile: ALTProvisioningProfile? {
        guard let url = self.customProvisioningProfileURL else { return nil }
        return try? ALTProvisioningProfile(url: url)
    }

    var customEntitlements: [String: any Sendable]? {
        guard let url = self.customEntitlementsURL,
              let parser = try? InfoPlistParser(plistURL: url)
        else { return nil }
        return parser.rawDictionary
    }
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
    @NSManaged public var appBundleFingerprint: String?
    
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
    
    @NSManaged public private(set) var loggedErrors: NSSet
    
    public var isSideloaded: Bool {
        return self.storeApp == nil
    }
    
    @objc public var hasUpdate: Bool {
        guard isActive,
              let storeApp = self.storeApp,
              let latestVersion = storeApp.latestSupportedVersion else
        {
            return false
        }
        
        guard !storeApp.isPledgeRequired || storeApp.isPledged else
        {
            return false
        }
        
        let currentSemVer = SemanticVersion(self.version)
        let latestSemVer = SemanticVersion(latestVersion.version)
        
        if currentSemVer == nil || latestSemVer == nil {
            return !matches(latestVersion)
        }
        let currentVer = SemanticVersion("\(currentSemVer!.major).\(currentSemVer!.minor).\(currentSemVer!.patch)")
        let latestVer  = SemanticVersion("\(latestSemVer!.major).\(latestSemVer!.minor).\(latestSemVer!.patch)")
        
        if latestVer! > currentVer! {
            return true
        }
        
        if UserDefaults.standard.isBetaUpdatesEnabled,
           ReleaseTrackType.betaTracks.contains(latestVersion.channel),
           latestVer == currentVer,
           (latestSemVer!.build != currentSemVer!.build) || (latestSemVer!.preRelease != currentSemVer!.preRelease)
        {
            return true
        }
        
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
        return fetchRequest
    }
    
    class func fetchAltStore(in context: NSManagedObjectContext) -> InstalledApp?
    {
        let predicate = NSPredicate(format: "%K == %@", #keyPath(InstalledApp.bundleIdentifier), StoreApp.altstoreAppID)
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
            if let storeApp = altStoreApp.storeApp
            {
                if !storeApp.isPledgeRequired || storeApp.isPledged
                {
                    installedApps.append(altStoreApp)
                }
            }
            else
            {
                installedApps.append(altStoreApp)
            }
        }
        
        return installedApps
    }
    
    class func fetchAppsForBackgroundRefresh(in context: NSManagedObjectContext) -> [InstalledApp]
    {
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
                    installedApps.append(altStoreApp)
                }
            }
            else
            {
                installedApps.append(altStoreApp)
            }
        }
        
        return installedApps
    }
}

public extension InstalledApp
{
    var openAppURL: URL {
        return InstalledApp.openAppURL(targetBundleIdentifier: self.resignedBundleIdentifier)
    }
    
    class func openAppURL(targetBundleIdentifier: String) -> URL {
        return URL(string: "sidestore-" + targetBundleIdentifier + "://")!
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
    
    class func payloadDirectoryURL(forSignature signature: String) -> URL {
        return InstalledApp.appsDirectoryURL.appendingPathComponent("Payloads").appendingPathComponent(signature)
    }

    class func payloadURL(forSignature signature: String) -> URL {
        return self.payloadDirectoryURL(forSignature: signature).appendingPathComponent("App.app")
    }

    class func installedAppUTI(forBundleIdentifier bundleIdentifier: String) -> String {
        return "io.sidestore.Installed." + bundleIdentifier
    }
    
    public var installedAppUTI: String {
        return InstalledApp.installedAppUTI(forBundleIdentifier: self.resignedBundleIdentifier)
    }
    
    public var installedBackupAppUTI: String {
        return self.installedAppUTI + ".backup"
    }
}
