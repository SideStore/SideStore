//
//  Managed.swift
//  AltStore
//
//  Created by Riley Testut on 10/5/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import CoreData
import Foundation

@propertyWrapper @dynamicMemberLookup
struct Managed<ManagedObject: NSManagedObject> {
    var wrappedValue: ManagedObject {
        didSet {
            self.managedObjectContext = self.wrappedValue.managedObjectContext
        }
    }

    private var managedObjectContext: NSManagedObjectContext?

    var projectedValue: Managed<ManagedObject> {
        self
    }

    init(wrappedValue: ManagedObject) {
        self.wrappedValue = wrappedValue
        self.managedObjectContext = wrappedValue.managedObjectContext
    }

    subscript<T>(dynamicMember keyPath: KeyPath<ManagedObject, T>) -> T {
        var result: T!

        if let context = managedObjectContext {
            context.performAndWait {
                result = self.wrappedValue[keyPath: keyPath]
            }
        } else {
            result = self.wrappedValue[keyPath: keyPath]
        }

        return result
    }
}
