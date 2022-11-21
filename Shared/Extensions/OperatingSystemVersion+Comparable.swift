//
//  OperatingSystemVersion+Comparable.swift
//  AltStoreCore
//
//  Created by nythepegasus on 5/9/24.
//

import Foundation

extension OperatingSystemVersion: Comparable {
    public static func ==(lhs: OperatingSystemVersion, rhs: OperatingSystemVersion) -> Bool {
        return lhs.majorVersion == rhs.majorVersion && lhs.minorVersion == rhs.minorVersion && lhs.patchVersion == rhs.patchVersion
    }
    
    public static func <(lhs: OperatingSystemVersion, rhs: OperatingSystemVersion) -> Bool {
        return lhs.stringValue.compare(rhs.stringValue, options: .numeric) == .orderedAscending
    }
}
