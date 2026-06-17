//
//  NSPredicate+Search.swift
//  AltStoreCore
//
//  Created by Magesh K on 6/17/26.
//

import Foundation

public extension NSPredicate {
    @objc(predicateForSearchingForText:inValuesForKeyPaths:)
    static func forSearching(forText searchText: String, inValuesForKeyPaths keyPaths: Set<String>) -> NSPredicate {
        if keyPaths.isEmpty {
            return NSPredicate(value: false)
        }
        
        if searchText.isEmpty {
            return NSPredicate(value: true)
        }
        
        let strippedString = searchText.trimmingCharacters(in: .whitespaces)
        let searchTerms = strippedString.components(separatedBy: .whitespacesAndNewlines)
        
        var subpredicates = [NSPredicate]()
        
        for searchTerm in searchTerms {
            var orPredicates = [NSPredicate]()
            
            for keyPath in keyPaths {
                let lhs = NSExpression(forKeyPath: keyPath)
                let rhs = NSExpression(forConstantValue: searchTerm)
                
                let predicate = NSComparisonPredicate(
                    leftExpression: lhs,
                    rightExpression: rhs,
                    modifier: .direct,
                    type: .contains,
                    options: [.caseInsensitive, .diacriticInsensitive]
                )
                
                orPredicates.append(predicate)
            }
            
            let compoundPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: orPredicates)
            subpredicates.append(compoundPredicate)
        }
        
        return NSCompoundPredicate(andPredicateWithSubpredicates: subpredicates)
    }
}
