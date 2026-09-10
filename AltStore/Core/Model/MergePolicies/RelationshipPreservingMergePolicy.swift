//
//  RelationshipPreservingMergePolicy.swift
//  AltStore
//
//  Created by Magesh K on 8/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import CoreData
import ObjectiveC

private var snapshotsKey: UInt8 = 0

public extension NSConstraintConflict {
    var allObjects: Set<NSManagedObject> {
        var allObjects = Set(self.conflictingObjects)
        if let databaseObject = self.databaseObject {
            allObjects.insert(databaseObject)
        }
        return allObjects
    }
    
    var snapshots: NSMapTable<NSManagedObject, NSDictionary> {
        if let snapshots = objc_getAssociatedObject(self, &snapshotsKey) as? NSMapTable<NSManagedObject, NSDictionary> {
            return snapshots
        }
        
        let snapshots = NSMapTable<NSManagedObject, NSDictionary>.strongToStrongObjects()
        
        for managedObject in self.allObjects {
            let snapshot = NSMutableDictionary()
            
            for property in managedObject.entity.properties {
                if property.isTransient || property is NSFetchedPropertyDescription {
                    continue
                }
                
                let value = managedObject.value(forKey: property.name)
                
                if let relationship = property as? NSRelationshipDescription, relationship.isToMany {
                    let relationshipObjects = NSMutableSet()
                    if let set = value as? NSSet {
                        for val in set {
                            relationshipObjects.add(val)
                        }
                    }
                    snapshot[property.name] = relationshipObjects
                } else {
                    snapshot[property.name] = value
                }
            }
            
            snapshots.setObject(snapshot, forKey: managedObject)
        }
        
        objc_setAssociatedObject(self, &snapshotsKey, snapshots, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        
        return snapshots
    }
    
    @discardableResult
    static func cacheSnapshots(for conflicts: [NSConstraintConflict]) -> NSMapTable<NSManagedObject, NSDictionary> {
        let snapshots = NSMapTable<NSManagedObject, NSDictionary>.strongToStrongObjects()
        
        for conflict in conflicts {
            let conflictSnapshots = conflict.snapshots
            let enumerator = conflictSnapshots.keyEnumerator()
            while let managedObject = enumerator.nextObject() as? NSManagedObject {
                if let snapshot = conflictSnapshots.object(forKey: managedObject) {
                    snapshots.setObject(snapshot, forKey: managedObject)
                }
            }
        }
        
        return snapshots
    }
}

open class RelationshipPreservingMergePolicy: NSMergePolicy {
    public override init(merge mergeType: NSMergePolicyType) {
        super.init(merge: mergeType)
    }
    
    public convenience init() {
        self.init(merge: .mergeByPropertyObjectTrumpMergePolicyType)
    }
    
    open override func resolve(constraintConflicts conflicts: [NSConstraintConflict]) throws {
        NSConstraintConflict.cacheSnapshots(for: conflicts)
        
        try super.resolve(constraintConflicts: conflicts)
        
        for conflict in conflicts {
            guard let databaseObject = conflict.databaseObject else {
                continue
            }
            
            let updatedObject = conflict.conflictingObjects.first
            
            let databaseSnapshot = conflict.snapshots.object(forKey: databaseObject) as? [String: Any]
            let updatedSnapshot = updatedObject.flatMap { conflict.snapshots.object(forKey: $0) } as? [String: Any]
            
            guard let updatedObj = updatedObject, let dbSnapshot = databaseSnapshot, let upSnapshot = updatedSnapshot else {
                continue
            }
            
            for (name, property) in databaseObject.entity.relationshipsByName {
                if property.isToMany {
                    continue
                }
                
                var relationshipObject: NSManagedObject? = nil
                
                let previousRelationshipObject = dbSnapshot[name] as? NSManagedObject
                let updatedRelationshipObject = upSnapshot[name] as? NSManagedObject
                
                if let previousRelationshipObject = previousRelationshipObject {
                    if updatedRelationshipObject == nil {
                        if updatedObj.changedValues()[name] == nil {
                            relationshipObject = previousRelationshipObject
                        } else {
                            relationshipObject = nil
                        }
                    } else {
                        if databaseObject.value(forKey: name) == nil {
                            relationshipObject = previousRelationshipObject
                        } else if updatedRelationshipObject?.managedObjectContext == nil {
                            relationshipObject = previousRelationshipObject
                        } else {
                            relationshipObject = updatedRelationshipObject
                        }
                    }
                } else {
                    if let updatedRelationshipObject = updatedRelationshipObject {
                        relationshipObject = updatedRelationshipObject
                    } else {
                        relationshipObject = nil
                    }
                }
                
                if databaseObject.value(forKey: name) as? NSManagedObject == relationshipObject {
                    continue
                }
                
                if let relObj = relationshipObject, relObj.managedObjectContext == nil {
                    continue
                }
                
                databaseObject.setValue(relationshipObject, forKey: name)
                
                if let inverseRelationship = property.inverseRelationship, !inverseRelationship.isToMany {
                    if let relObj = relationshipObject {
                        relObj.setValue(databaseObject, forKey: inverseRelationship.name)
                    } else {
                        previousRelationshipObject?.setValue(nil, forKey: inverseRelationship.name)
                        updatedRelationshipObject?.setValue(nil, forKey: inverseRelationship.name)
                    }
                }
            }
        }
    }
}
