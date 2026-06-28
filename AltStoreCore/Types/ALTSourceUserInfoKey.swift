//
//  ALTSourceUserInfoKey.swift
//  AltStoreCore
//
//  Created by Magesh K on 2026-06-28.
//

import Foundation

public struct ALTSourceUserInfoKey: RawRepresentable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
    
    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
    
    public init(stringLiteral value: String) {
        self.rawValue = value
    }
}

extension ALTSourceUserInfoKey {
    public static let patreonAccessToken: ALTSourceUserInfoKey = "patreonAccessToken"
    public static let skipPatreonDownloads: ALTSourceUserInfoKey = "skipPatreonDownloads"
}
