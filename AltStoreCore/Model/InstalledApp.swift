//
//  InstalledApp.swift
//  AltStore
//
//  Created by Riley Testut on 5/20/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import CoreData

import AltSign
import SemanticVersion

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
    @NSManaged public var version: String
    @NSManaged public var buildVersion: String
    
    @NSManaged public var refreshedDate: Date
    @NSManaged public var expirationDate: Date
    @NSManaged public var installedDate: Date
    
    @NSManaged public var isActive: Bool
    @NSManaged public var needsResign: Bool
    @NSManaged public var hasAlternateIcon: Bool
    
    @NSManaged public var certificateSerialNumber: String?
    @NSManaged public var storeBuildVersion: String?
    
    /* Transient */
    @NSManaged public var isRefreshing: Bool
    
    /* Relationships */
    @NSManaged public var storeApp: StoreApp?
    @NSManaged public var team: Team?
    @NSManaged public var appExtensions: Set<InstalledExtension>
    
    @NSManaged public private(set) var loggedErrors: NSSet /* Set<LoggedError> */ // Use NSSet to avoid eagerly fetching values.
    
    public var isSideloaded: Bool {
        return self.storeApp == nil
    }
    
    
    // TODO: integrate the following into the hasUpdate such that altstore sources also work with SideStore, ex: pledge check etc for updates
    /*
     
     
     
     
//        let predicateFormat = [
//            // isActive && storeApp != nil && latestSupportedVersion != nil
//            "%K == YES AND %K != nil AND %K != nil",
//
//            "AND",
//
//            // latestSupportedVersion.version != installedApp.version || latestSupportedVersion.buildVersion != installedApp.storeBuildVersion
//            //
//            // We have to also check !(latestSupportedVersion.buildVersion == '' && installedApp.storeBuildVersion == nil)
//            // because latestSupportedVersion.buildVersion stores an empty string for nil, while installedApp.storeBuildVersion uses NULL.
//            "(%K != %K OR (%K != %K AND NOT (%K == '' AND %K == nil)))",
//
//            "AND",
//
//            // !isPledgeRequired || isPledged
//            "(%K == NO OR %K == YES)"
//        ].joined(separator: " ")
//
//        fetchRequest.predicate = NSPredicate(format: predicateFormat,
//                                             #keyPath(InstalledApp.isActive), #keyPath(InstalledApp.storeApp), #keyPath(InstalledApp.storeApp.latestSupportedVersion),
//                                             #keyPath(InstalledApp.storeApp.latestSupportedVersion.version), #keyPath(InstalledApp.version),
//                                             #keyPath(InstalledApp.storeApp.latestSupportedVersion._buildVersion), #keyPath(InstalledApp.storeBuildVersion),
//                                             #keyPath(InstalledApp.storeApp.latestSupportedVersion._buildVersion), #keyPath(InstalledApp.storeBuildVersion),
//                                             #keyPath(InstalledApp.storeApp.isPledgeRequired), #keyPath(InstalledApp.storeApp.isPledged))
//
     

    */
    
    
    
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
           ReleaseTracks.betaTracks.contains(latestVersion.channel),
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
    
    public init(resignedApp: ALTApplication, originalBundleIdentifier: String, certificateSerialNumber: String?, storeBuildVersion: String?, context: NSManagedObjectContext)
    {
        super.init(entity: InstalledApp.entity(), insertInto: context)
        
        self.bundleIdentifier = originalBundleIdentifier
        
        print("InstalledApp `self.bundleIdentifier`: \(self.bundleIdentifier)")
        
        self.refreshedDate = Date()
        self.installedDate = Date()
        
        self.expirationDate = self.refreshedDate.addingTimeInterval(60 * 60 * 24 * 7) // Rough estimate until we get real values from provisioning profile.
        
        // In practice this update() is redundant because we always call update() again after init from callers,
        // but better to have an init that is guaranteed to successfully initialize an object
        // than one that has a hidden assumption a second method will be called.
        self.update(resignedApp: resignedApp, certificateSerialNumber: certificateSerialNumber, storeBuildVersion: storeBuildVersion)
    }
}

public extension InstalledApp
{
    var localizedVersion: String {
        guard let storeBuildVersion else { return self.version }
        
        let localizedVersion = "\(self.version) (\(storeBuildVersion))"
        return localizedVersion
    }
    
    func update(resignedApp: ALTApplication, certificateSerialNumber: String?, storeBuildVersion: String?)
    {
        self.name = resignedApp.name
        
        self.resignedBundleIdentifier = resignedApp.bundleIdentifier
        self.version = resignedApp.version
        
        self.buildVersion = resignedApp.buildVersion
        self.storeBuildVersion = storeBuildVersion
        
        self.certificateSerialNumber = certificateSerialNumber
        
        if let provisioningProfile = resignedApp.provisioningProfile
        {
            self.update(provisioningProfile: provisioningProfile)
        }
    }
    
    func update(provisioningProfile: ALTProvisioningProfile)
    {
        self.refreshedDate = provisioningProfile.creationDate
        self.expirationDate = provisioningProfile.expirationDate
    }
    
    func loadIcon(completion: @escaping (Result<UIImage?, Error>) -> Void)
    {
        // TODO: @mahee96: Fix this later (reason: alternateIcon is not available for appEx)
//        if self.bundleIdentifier == StoreApp.altstoreAppID,
//           let iconName = UIApplication.alt_shared?.alternateIconName
//        {
//            // Use alternate app icon for AltStore, if one is chosen.
//            
//            let image = UIImage(named: iconName)
//            completion(.success(image))
//            
//            return
//        }
        
        let hasAlternateIcon = self.hasAlternateIcon
        let alternateIconURL = self.alternateIconURL
        let fileURL = self.fileURL
        
        DispatchQueue.global().async {
            do
            {
                if hasAlternateIcon,
                   case let data = try Data(contentsOf: alternateIconURL),
                   let icon = UIImage(data: data)
                {
                    return completion(.success(icon))
                }
                
                let application = ALTApplication(fileURL: fileURL)
                completion(.success(application?.icon))
            }
            catch
            {
                completion(.failure(error))
            }
        }
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
        print("Active Apps Fetch Request: \(String(describing: fetchRequest.predicate))")
        return fetchRequest
    }
    
    class func fetchAltStore(in context: NSManagedObjectContext) -> InstalledApp?
    {
        let predicate = NSPredicate(format: "%K == %@", #keyPath(InstalledApp.bundleIdentifier), StoreApp.altstoreAppID)
        print("Fetch 'AltStore' Predicate: \(String(describing: predicate))")
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
        let openAppURL = URL(string: "sidestore-" + self.bundleIdentifier + "://")!
        return openAppURL
    }
    
    // TODO: @mahee96: Do NOT hardcode app's url scheme prefixes as in here
    //       Need to get it dynamically from the Info.plist of other means
    class func openAppURL(for app: AppProtocol) -> URL
    {
        let openAppURL = URL(string: "sidestore-" + app.bundleIdentifier + "://")!
        return openAppURL
    }
    
    // var isUpdateAvailable: Bool {
    //     guard let storeApp = self.storeApp, let latestVersion = storeApp.latestSupportedVersion else { return false }
    //     guard !storeApp.isPledgeRequired || storeApp.isPledged else { return false }
        
    //     let isUpdateAvailable = !self.matches(latestVersion)
    //     return isUpdateAvailable
    // }
}

public extension InstalledApp
{
    class var appsDirectoryURL: URL {
        let baseDirectory = FileManager.default.altstoreSharedDirectory ?? FileManager.default.applicationSupportDirectory
        let appsDirectoryURL = baseDirectory.appendingPathComponent("Apps")
        
        do { try FileManager.default.createDirectory(at: appsDirectoryURL, withIntermediateDirectories: true, attributes: nil) }
        catch { print("Creating App Directory Error: \(error)") }
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
        print("`ipaURL`: \(ipaURL.absoluteString)")
        return ipaURL
    }
    
    class func directoryURL(for app: AppProtocol) -> URL
    {
        let directoryURL = InstalledApp.appsDirectoryURL.appendingPathComponent(app.bundleIdentifier)
        
        do { try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil) }
        catch { print(error) }
        
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
    
    class func alternateIconURL(for app: AppProtocol) -> URL
    {
        let installedBackupAppUTI = self.directoryURL(for: app).appendingPathComponent("AltIcon.png")
        return installedBackupAppUTI
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
