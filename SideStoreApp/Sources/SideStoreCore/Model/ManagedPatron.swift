//
//  ManagedPatron.swift
//  AltStoreCore
//
//  Created by Riley Testut on 4/18/22.
//  Copyright © 2022 Riley Testut. All rights reserved.
//

import CoreData

@objc(ManagedPatron)
public class ManagedPatron: NSManagedObject, Fetchable {
    @NSManaged public var name: String
    @NSManaged public var identifier: String

    override private init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?) {
        super.init(entity: entity, insertInto: context)
    }

    public init(patron: Patron, context: NSManagedObjectContext) {
        super.init(entity: ManagedPatron.entity(), insertInto: context)

        name = patron.name
        identifier = patron.identifier
    }
}

public extension ManagedPatron {
    @nonobjc class func fetchRequest() -> NSFetchRequest<ManagedPatron> {
        NSFetchRequest<ManagedPatron>(entityName: "Patron")
    }
}
