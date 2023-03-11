//
//  Account.swift
//  AltStore
//
//  Created by Riley Testut on 6/5/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import CoreData
import Foundation

import AltSign

@objc(Account)
public class Account: NSManagedObject, Fetchable {
    public var localizedName: String {
        var components = PersonNameComponents()
        components.givenName = firstName
        components.familyName = lastName

        let name = PersonNameComponentsFormatter.localizedString(from: components, style: .default)
        return name
    }

    /* Properties */
    @NSManaged public var appleID: String
    @NSManaged public var identifier: String

    @NSManaged public var firstName: String
    @NSManaged public var lastName: String

    @NSManaged public var isActiveAccount: Bool

    /* Relationships */
    @NSManaged public var teams: Set<Team>

    override private init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?) {
        super.init(entity: entity, insertInto: context)
    }

    public init(_ account: ALTAccount, context: NSManagedObjectContext) {
        super.init(entity: Account.entity(), insertInto: context)

        update(account: account)
    }

    public func update(account: ALTAccount) {
        appleID = account.appleID
        identifier = account.identifier

        firstName = account.firstName
        lastName = account.lastName
    }
}

public extension Account {
    @nonobjc class func fetchRequest() -> NSFetchRequest<Account> {
        NSFetchRequest<Account>(entityName: "Account")
    }
}
