//
//  PatreonAccount.swift
//  AltStore
//
//  Created by Riley Testut on 8/20/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import CoreData

@objc(PatreonAccount)
public class PatreonAccount: NSManagedObject, Fetchable
{
    @NSManaged public var identifier: String
    
    @NSManaged public var name: String
    @NSManaged public var firstName: String?
    
    // Use `isPatron` for backwards compatibility.
    @NSManaged @objc(isPatron) public var isAltStorePatron: Bool
    
    /* Relationships */
    @nonobjc public var pledges: Set<Pledge> { _pledges as! Set<Pledge> }
    @NSManaged @objc(pledges) internal var _pledges: NSSet
    
    private override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?)
    {
        super.init(entity: entity, insertInto: context)
    }
    
    init(account: PatreonAPI.UserAccount, context: NSManagedObjectContext)
    {
        super.init(entity: PatreonAccount.entity(), insertInto: context)
        
        self.identifier = account.identifier
        self.name = account.name
        self.firstName = account.firstName
        
//        if let patronResponse = response.included?.first
//        {
//            let patron = Patron(response: patronResponse)
//            self.isPatron = (patron.status == .active)
//        }
//        else
//        {
//            self.isPatron = false
//        }
//        self.isPatron = true
        self.isAltStorePatron = true
    }
}

public extension PatreonAccount
{
    @nonobjc class func fetchRequest() -> NSFetchRequest<PatreonAccount>
    {
        return NSFetchRequest<PatreonAccount>(entityName: "PatreonAccount")
    }
}

