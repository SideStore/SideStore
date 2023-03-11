//
//  RefreshAttempt.swift
//  AltStore
//
//  Created by Riley Testut on 7/31/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import CoreData

@objc(RefreshAttempt)
public class RefreshAttempt: NSManagedObject, Fetchable {
    @NSManaged public var identifier: String
    @NSManaged public var date: Date

    @NSManaged public var isSuccess: Bool
    @NSManaged public var errorDescription: String?

    override private init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?) {
        super.init(entity: entity, insertInto: context)
    }

    public init(identifier: String, result: Result<[String: Result<InstalledApp, Error>], Error>, context: NSManagedObjectContext) {
        super.init(entity: RefreshAttempt.entity(), insertInto: context)

        self.identifier = identifier
        date = Date()

        do {
            let results = try result.get()

            for (_, result) in results {
                guard case let .failure(error) = result else { continue }
                throw error
            }

            isSuccess = true
            errorDescription = nil
        } catch {
            isSuccess = false
            errorDescription = error.localizedDescription
        }
    }
}

public extension RefreshAttempt {
    @nonobjc class func fetchRequest() -> NSFetchRequest<RefreshAttempt> {
        NSFetchRequest<RefreshAttempt>(entityName: "RefreshAttempt")
    }
}
