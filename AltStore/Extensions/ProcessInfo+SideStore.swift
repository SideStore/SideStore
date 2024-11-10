//
//  ProcessInfo+SideStore.swift
//  SideStore
//
//  Created by ny on 10/23/24.
//  Copyright © 2024 SideStore. All rights reserved.
//

import Foundation

fileprivate struct BuildVersion: Comparable {
    let prefix: String
    let numericPart: Int
    let suffix: Character?
    
    init?(_ buildString: String) {
        // Initialize indices
        var index = buildString.startIndex
        
        // Extract prefix (letters before the numeric part)
        while index < buildString.endIndex, !buildString[index].isNumber {
            index = buildString.index(after: index)
        }
        guard index > buildString.startIndex else { return nil }
        self.prefix = String(buildString[buildString.startIndex..<index])
        
        // Extract numeric part
        let startOfNumeric = index
        while index < buildString.endIndex, buildString[index].isNumber {
            index = buildString.index(after: index)
        }
        guard let numericValue = Int(buildString[startOfNumeric..<index]) else { return nil }
        self.numericPart = numericValue
        
        // Extract suffix (if any)
        if index < buildString.endIndex {
            self.suffix = buildString[index]
        } else {
            self.suffix = nil
        }
    }
    
    // Implement Comparable protocol
    static func < (lhs: BuildVersion, rhs: BuildVersion) -> Bool {
        // Compare prefixes
        if lhs.prefix != rhs.prefix {
            return lhs.prefix < rhs.prefix
        }
        // Compare numeric parts
        if lhs.numericPart != rhs.numericPart {
            return lhs.numericPart < rhs.numericPart
        }
        // Compare suffixes
        switch (lhs.suffix, rhs.suffix) {
        case let (l?, r?):
            return l < r
        case (nil, _?):
            return true // nil is considered less than any character
        case (_?, nil):
            return false
        default:
            return false // Both are nil and equal
        }
    }
    
    static func == (lhs: BuildVersion, rhs: BuildVersion) -> Bool {
        return lhs.prefix == rhs.prefix &&
        lhs.numericPart == rhs.numericPart &&
        lhs.suffix == rhs.suffix
    }
}

extension ProcessInfo {
    var shortVersion: String {
        operatingSystemVersionString
            .replacingOccurrences(of: "Version ", with: "")
            .replacingOccurrences(of: "Build ", with: "")
    }
    
    var operatingSystemBuild: String {
        if let start = shortVersion.range(of: "(")?.upperBound,
           let end = shortVersion.range(of: ")")?.lowerBound {
            shortVersion[start..<end].replacingOccurrences(of: "Build ", with: "")
        } else { "???" }
    }
    
    var sparseRestorePatched: Bool {
        if operatingSystemVersion < OperatingSystemVersion(majorVersion: 18, minorVersion: 1, patchVersion: 0) { false }
        else if operatingSystemVersion > OperatingSystemVersion(majorVersion: 18, minorVersion: 1, patchVersion: 1) { true }
        else if operatingSystemVersion >= OperatingSystemVersion(majorVersion: 18, minorVersion: 1, patchVersion: 0),
                let currentBuild = BuildVersion(operatingSystemBuild),
                let targetBuild  = BuildVersion("22B5054e") {
            currentBuild >= targetBuild
        } else { false }
    }
}
