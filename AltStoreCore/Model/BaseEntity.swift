//
//  BaseEntity.swift
//  AltStore
//
//  Created by Magesh K on 28/01/25.
//  Copyright © 2025 SideStore. All rights reserved.
//

import CoreData

public class BaseEntity: NSManagedObject, Fetchable
{
    @nonobjc class func fetchRequest<T>() -> NSFetchRequest<T>
    {
        fatalError("method not implemented, subclass needs to provide an implementation")
    }

    internal override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?)
    {
        super.init(entity: entity, insertInto: context)
        
//        print("\(BaseEntity.self):\(type(of: self)): Inserting: \(entity.name ?? "nil") into context: \(String(describing: context))")
    }
}
