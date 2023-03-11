//
//  StoreApp.swift
//  AltStore
//
//  Created by Riley Testut on 5/20/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import CoreData
import Foundation
import class UIKit.UIColor

import Roxas

public extension StoreApp {
	#if SWIFT_PACKAGE
		#if ALPHA
			static let altstoreAppID = Bundle.Info.appbundleIdentifier
		#elseif BETA
			static let altstoreAppID = Bundle.Info.appbundleIdentifier
		#else
			static let altstoreAppID = Bundle.Info.appbundleIdentifier
		#endif
	#else
		#if ALPHA
			static let altstoreAppID = Bundle.Info.appbundleIdentifier
		#elseif BETA
			static let altstoreAppID = Bundle.Info.appbundleIdentifier
		#else
			static let altstoreAppID = Bundle.Info.appbundleIdentifier
		#endif
	#endif
    static let dolphinAppID = "me.oatmealdome.dolphinios-njb"
}

@objc
public enum Platform: UInt, Codable {
    case ios
    case tvos
    case macos
}

@objc
public final class PlatformURL: NSManagedObject, Decodable {
    /* Properties */
    @NSManaged public private(set) var platform: Platform
    @NSManaged public private(set) var downloadURL: URL

    private enum CodingKeys: String, CodingKey {
        case platform
        case downloadURL
    }

    public init(from decoder: Decoder) throws {
        guard let context = decoder.managedObjectContext else { preconditionFailure("Decoder must have non-nil NSManagedObjectContext.") }

        // Must initialize with context in order for child context saves to work correctly.
        super.init(entity: PlatformURL.entity(), insertInto: context)

        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            platform = try container.decode(Platform.self, forKey: .platform)
            downloadURL = try container.decode(URL.self, forKey: .downloadURL)
        } catch {
            if let context = managedObjectContext {
                context.delete(self)
            }

            throw error
        }
    }
}

extension PlatformURL: Comparable {
    public static func < (lhs: PlatformURL, rhs: PlatformURL) -> Bool {
        lhs.platform.rawValue < rhs.platform.rawValue
    }

    public static func > (lhs: PlatformURL, rhs: PlatformURL) -> Bool {
        lhs.platform.rawValue > rhs.platform.rawValue
    }

    public static func <= (lhs: PlatformURL, rhs: PlatformURL) -> Bool {
        lhs.platform.rawValue <= rhs.platform.rawValue
    }

    public static func >= (lhs: PlatformURL, rhs: PlatformURL) -> Bool {
        lhs.platform.rawValue >= rhs.platform.rawValue
    }
}

public typealias PlatformURLs = [PlatformURL]

@objc(StoreApp)
public class StoreApp: NSManagedObject, Decodable, Fetchable {
    /* Properties */
    @NSManaged public private(set) var name: String
    @NSManaged public private(set) var bundleIdentifier: String
    @NSManaged public private(set) var subtitle: String?

    @NSManaged public private(set) var developerName: String
    @NSManaged public private(set) var localizedDescription: String
    @NSManaged @objc(size) internal var _size: Int32

    @NSManaged public private(set) var iconURL: URL
    @NSManaged public private(set) var screenshotURLs: [URL]

    @NSManaged @objc(version) internal var _version: String
    @NSManaged @objc(versionDate) internal var _versionDate: Date
    @NSManaged @objc(versionDescription) internal var _versionDescription: String?

    @NSManaged @objc(downloadURL) internal var _downloadURL: URL
    @NSManaged public private(set) var platformURLs: PlatformURLs?

    @NSManaged public private(set) var tintColor: UIColor?
    @NSManaged public private(set) var isBeta: Bool

    @objc public internal(set) var sourceIdentifier: String? {
        get {
            willAccessValue(forKey: #keyPath(sourceIdentifier))
            defer { self.didAccessValue(forKey: #keyPath(sourceIdentifier)) }

            let sourceIdentifier = primitiveSourceIdentifier
            return sourceIdentifier
        }
        set {
            willChangeValue(forKey: #keyPath(sourceIdentifier))
            primitiveSourceIdentifier = newValue
            didChangeValue(forKey: #keyPath(sourceIdentifier))

            for version in versions {
                version.sourceID = newValue
            }
        }
    }

    @NSManaged private var primitiveSourceIdentifier: String?

    @NSManaged public var sortIndex: Int32

    /* Relationships */
    @NSManaged public var installedApp: InstalledApp?
    @NSManaged public var newsItems: Set<NewsItem>

    @NSManaged @objc(source) public var _source: Source?
    @NSManaged @objc(permissions) public var _permissions: NSOrderedSet

    @NSManaged public private(set) var latestVersion: AppVersion?
    @NSManaged @objc(versions) public private(set) var _versions: NSOrderedSet

    @NSManaged public private(set) var loggedErrors: NSSet /* Set<LoggedError> */ // Use NSSet to avoid eagerly fetching values.

    @nonobjc public var source: Source? {
        set {
            _source = newValue
            sourceIdentifier = newValue?.identifier
        }
        get {
            _source
        }
    }

    @nonobjc public var permissions: [AppPermission] {
        _permissions.array as! [AppPermission]
    }

    @nonobjc public var versions: [AppVersion] {
        _versions.array as! [AppVersion]
    }

    @nonobjc public var size: Int64? {
        guard let version = latestVersion else { return nil }
        return version.size
    }

    @nonobjc public var version: String? {
        guard let version = latestVersion else { return nil }
        return version.version
    }

    @nonobjc public var versionDescription: String? {
        guard let version = latestVersion else { return nil }
        return version.localizedDescription
    }

    @nonobjc public var versionDate: Date? {
        guard let version = latestVersion else { return nil }
        return version.date
    }

    @nonobjc public var downloadURL: URL? {
        guard let version = self.latestVersion else { return nil }
        return version.downloadURL
    }

    override private init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?) {
        super.init(entity: entity, insertInto: context)
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case bundleIdentifier
        case developerName
        case localizedDescription
        case version
        case versionDescription
        case versionDate
        case iconURL
        case screenshotURLs
        case downloadURL
        case platformURLs
        case tintColor
        case subtitle
        case permissions
        case size
        case isBeta = "beta"
        case versions
    }

    public required init(from decoder: Decoder) throws {
        guard let context = decoder.managedObjectContext else { preconditionFailure("Decoder must have non-nil NSManagedObjectContext.") }

        // Must initialize with context in order for child context saves to work correctly.
        super.init(entity: StoreApp.entity(), insertInto: context)

        do {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            bundleIdentifier = try container.decode(String.self, forKey: .bundleIdentifier)
            developerName = try container.decode(String.self, forKey: .developerName)
            localizedDescription = try container.decode(String.self, forKey: .localizedDescription)

            subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)

            iconURL = try container.decode(URL.self, forKey: .iconURL)
            screenshotURLs = try container.decodeIfPresent([URL].self, forKey: .screenshotURLs) ?? []

            let downloadURL = try container.decodeIfPresent(URL.self, forKey: .downloadURL)
            let platformURLs = try container.decodeIfPresent(PlatformURLs.self.self, forKey: .platformURLs)
            if let platformURLs = platformURLs {
                self.platformURLs = platformURLs
                // Backwards compatibility, use the fiirst (iOS will be first since sorted that way)
                if let first = platformURLs.sorted().first {
                    _downloadURL = first.downloadURL
                } else {
                    throw DecodingError.dataCorruptedError(forKey: .platformURLs, in: container, debugDescription: "platformURLs has no entries")
                }

            } else if let downloadURL = downloadURL {
                _downloadURL = downloadURL
            } else {
                throw DecodingError.dataCorruptedError(forKey: .downloadURL, in: container, debugDescription: "E downloadURL:String or downloadURLs:[[Platform:URL]] key required.")
            }

            if let tintColorHex = try container.decodeIfPresent(String.self, forKey: .tintColor) {
                guard let tintColor = UIColor(hexString: tintColorHex) else {
                    throw DecodingError.dataCorruptedError(forKey: .tintColor, in: container, debugDescription: "Hex code is invalid.")
                }

                self.tintColor = tintColor
            }

            isBeta = try container.decodeIfPresent(Bool.self, forKey: .isBeta) ?? false

            let permissions = try container.decodeIfPresent([AppPermission].self, forKey: .permissions) ?? []
            _permissions = NSOrderedSet(array: permissions)

            if let versions = try container.decodeIfPresent([AppVersion].self, forKey: .versions) {
                // TODO: Throw error if there isn't at least one version.

                for version in versions {
                    version.appBundleID = bundleIdentifier
                }

                setVersions(versions)
            } else {
                let version = try container.decode(String.self, forKey: .version)
                let versionDate = try container.decode(Date.self, forKey: .versionDate)
                let versionDescription = try container.decodeIfPresent(String.self, forKey: .versionDescription)

                let downloadURL = try container.decode(URL.self, forKey: .downloadURL)
                let size = try container.decode(Int32.self, forKey: .size)

                let appVersion = AppVersion.makeAppVersion(version: version,
                                                           date: versionDate,
                                                           localizedDescription: versionDescription,
                                                           downloadURL: downloadURL,
                                                           size: Int64(size),
                                                           appBundleID: bundleIdentifier,
                                                           in: context)
                setVersions([appVersion])
            }
        } catch {
            if let context = managedObjectContext {
                context.delete(self)
            }

            throw error
        }
    }
}

private extension StoreApp {
    func setVersions(_ versions: [AppVersion]) {
        guard let latestVersion = versions.first else { preconditionFailure("StoreApp must have at least one AppVersion.") }

        self.latestVersion = latestVersion
        _versions = NSOrderedSet(array: versions)

        // Preserve backwards compatibility by assigning legacy property values.
        _version = latestVersion.version
        _versionDate = latestVersion.date
        _versionDescription = latestVersion.localizedDescription
        _downloadURL = latestVersion.downloadURL
        _size = Int32(latestVersion.size)
    }
}

public extension StoreApp {
    @nonobjc class func fetchRequest() -> NSFetchRequest<StoreApp> {
        NSFetchRequest<StoreApp>(entityName: "StoreApp")
    }

    class func makeAltStoreApp(in context: NSManagedObjectContext) -> StoreApp {
        let app = StoreApp(context: context)
        app.name = "SideStore"
        app.bundleIdentifier = StoreApp.altstoreAppID
        app.developerName = "Side Team"
        app.localizedDescription = "SideStore is an alternative App Store."
        app.iconURL = URL(string: "https://user-images.githubusercontent.com/705880/63392210-540c5980-c37b-11e9-968c-8742fc68ab2e.png")!
        app.screenshotURLs = []
        app.sourceIdentifier = Source.altStoreIdentifier

        let appVersion = AppVersion.makeAppVersion(version: "0.3.0",
                                                   date: Date(),
                                                   downloadURL: URL(string: "http://rileytestut.com")!,
                                                   size: 0,
                                                   appBundleID: app.bundleIdentifier,
                                                   sourceID: Source.altStoreIdentifier,
                                                   in: context)
        app.setVersions([appVersion])

        print("makeAltStoreApp StoreApp: \(String(describing: app))")

        #if BETA
            app.isBeta = true
        #endif

        return app
    }
}
