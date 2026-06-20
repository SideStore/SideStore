//
//  RSTRelationshipPreservingMergePolicy.swift
//  AltStoreCore
//
//  Created by Magesh K on 6/17/26.
//

import CoreData

@objc(RSTRelationshipPreservingMergePolicy)
open class RSTRelationshipPreservingMergePolicy: NSMergePolicy {
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
