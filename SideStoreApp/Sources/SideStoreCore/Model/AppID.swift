//
//  AppID.swift
//  AltStore
//
//  Created by Riley Testut on 1/27/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import CoreData
import Foundation

import AltSign

@objc(AppID)
public class AppID: NSManagedObject, Fetchable {
    /* Properties */
    @NSManaged public var name: String
    @NSManaged public var identifier: String
    @NSManaged public var bundleIdentifier: String
    @NSManaged public var features: [ALTFeature: Any]
    @NSManaged public var expirationDate: Date?

    /* Relationships */
    @NSManaged public private(set) var team: Team?

    override private init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?) {
        super.init(entity: entity, insertInto: context)
    }

    public init(_ appID: ALTAppID, team: Team, context: NSManagedObjectContext) {
        super.init(entity: AppID.entity(), insertInto: context)

        name = appID.name
        identifier = appID.identifier
        bundleIdentifier = appID.bundleIdentifier
        features = appID.features
        expirationDate = appID.expirationDate

        self.team = team
    }
}

public extension AppID {
    @nonobjc class func fetchRequest() -> NSFetchRequest<AppID> {
        NSFetchRequest<AppID>(entityName: "AppID")
    }
}
