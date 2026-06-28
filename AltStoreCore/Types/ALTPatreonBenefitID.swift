//
//  ALTPatreonBenefitID.swift
//  AltStoreCore
//
//  Created by Magesh K on 2026-06-28.
//

import Foundation

public struct ALTPatreonBenefitID: RawRepresentable, Hashable, ExpressibleByStringLiteral {
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

extension ALTPatreonBenefitID {
    public static let betaAccess: ALTPatreonBenefitID = "1186336"
    public static let credits: ALTPatreonBenefitID = "1186340"
}
