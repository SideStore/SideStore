//
//  OperationsLoggingControl.swift
//  AltStore
//
//  Created by Magesh K on 14/01/25.
//  Copyright © 2025 SideStore. All rights reserved.
//

import Foundation

class OperationsLoggingControl {

    func updateDatabase(for operation: Operation.Type, value: Bool) {
        Self.updateDatabase(for: operation, value: value)
    }
   
    private static func updateDatabase(for operation: Operation.Type, value: Bool) {
        // This method should handle the database update logic based on the operation and value
        let key = Self.getKey(operation)
        print("Updating database for key: \(key), value: \(value)")
        UserDefaults.standard.set(value, forKey: key)
    }
    
    private static func stripGenericTypeName(from string: String) -> String {
        // ex: 1. "EnableJITOperation<DummyConformance>"
        // ex: 1. "EnableJITOperation<DummyConformance<SomeMoreType>>"
        // will become EnableJITOperation without the generics type info
        if let range = string.range(of: "<") {
            return String(string[..<range.lowerBound])
        }
        return string
    }
    
    private static func getKey(_ operation: Operation.Type) -> String {
        let processedOperation = Self.stripGenericTypeName(from: "\(operation)")
        return "\(processedOperation)LoggingEnabled"
    }
    
    func getFromDatabase(for operation: Operation.Type)  -> Bool{
        return Self.getFromDatabase(for: operation)
    }

    static func getUpdatedFromDatabase(for operation: Operation.Type, defaultVal: Bool)  -> Bool{
        let key = Self.getKey(operation)
        let valueInDb = UserDefaults.standard.value(forKey: key) as? Bool
        if valueInDb == nil {
            // put the value if not already present
            updateDatabase(for: operation, value: defaultVal)
        }
        return valueInDb ?? defaultVal
    }

    public static func getFromDatabase(for operation: Operation.Type) -> Bool {
        let key = Self.getKey(operation)
        return UserDefaults.standard.bool(forKey: key)
    }
}
