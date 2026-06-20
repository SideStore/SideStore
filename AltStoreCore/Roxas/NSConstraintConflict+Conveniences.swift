//
//  NSConstraintConflict+Conveniences.swift
//  AltStoreCore
//
//  Created by Magesh K on 6/17/26.
//

import CoreData
import ObjectiveC

private var snapshotsKey: UInt8 = 0

public extension NSConstraintConflict {
    @objc var allObjects: Set<NSManagedObject> {
        var allObjects = Set(self.conflictingObjects)
        if let databaseObject = self.databaseObject {
            allObjects.insert(databaseObject)
        }
        return allObjects
    }
    
    @objc var snapshots: NSMapTable<NSManagedObject, NSDictionary> {
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
    
    @objc(cacheSnapshotsForConflicts:)
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
