//
//  InstalledExtension.swift
//  AltStore
//
//  Created by Riley Testut on 1/7/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import CoreData
import Foundation

import AltSign

@objc(InstalledExtension)
public class InstalledExtension: NSManagedObject, InstalledAppProtocol {
    /* Properties */
    @NSManaged public var name: String
    @NSManaged public var bundleIdentifier: String
    @NSManaged public var resignedBundleIdentifier: String
    @NSManaged public var version: String

    @NSManaged public var refreshedDate: Date
    @NSManaged public var expirationDate: Date
    @NSManaged public var installedDate: Date

    /* Relationships */
    @NSManaged public var parentApp: InstalledApp?

    override private init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?) {
        super.init(entity: entity, insertInto: context)
    }

    public init(resignedAppExtension: ALTApplication, originalBundleIdentifier: String, context: NSManagedObjectContext) {
        super.init(entity: InstalledExtension.entity(), insertInto: context)

        bundleIdentifier = originalBundleIdentifier

        refreshedDate = Date()
        installedDate = Date()

        expirationDate = refreshedDate.addingTimeInterval(60 * 60 * 24 * 7) // Rough estimate until we get real values from provisioning profile.

        update(resignedAppExtension: resignedAppExtension)
    }

    public func update(resignedAppExtension: ALTApplication) {
        name = resignedAppExtension.name

        resignedBundleIdentifier = resignedAppExtension.bundleIdentifier
        version = resignedAppExtension.version

        if let provisioningProfile = resignedAppExtension.provisioningProfile {
            update(provisioningProfile: provisioningProfile)
        }
    }

    public func update(provisioningProfile: ALTProvisioningProfile) {
        refreshedDate = provisioningProfile.creationDate
        expirationDate = provisioningProfile.expirationDate
    }
}

public extension InstalledExtension {
    @nonobjc class func fetchRequest() -> NSFetchRequest<InstalledExtension> {
        NSFetchRequest<InstalledExtension>(entityName: "InstalledExtension")
    }
}
