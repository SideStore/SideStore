//
//  KnownSource.swift
//  AltStore
//
//  Created by Riley Testut on 5/16/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import Foundation

public struct KnownSource: Decodable
{
    public var identifier: String
    public var sourceURL: URL?
    public var bundleIDs: [String]?
}

private extension KnownSource
{
    var dictionaryRepresentation: [String: Any] {
        let dictionary: [String: Any?] = [
            KnownSource.CodingKeys.identifier.stringValue: identifier,
            KnownSource.CodingKeys.sourceURL.stringValue: self.sourceURL?.absoluteString,
            KnownSource.CodingKeys.bundleIDs.stringValue: self.bundleIDs
        ]
        
        return dictionary.compactMapValues { $0 }
    }
    
    init?(dictionary: [String: Any])
    {
        guard let identifier = dictionary[CodingKeys.identifier.stringValue] as? String else { return nil }
        self.identifier = identifier
        
        if let sourceURLString = dictionary[CodingKeys.sourceURL.stringValue] as? String
        {
            self.sourceURL = URL(string: sourceURLString)
        }
        
        let bundleIDs = dictionary[CodingKeys.bundleIDs.stringValue] as? [String]
        self.bundleIDs = bundleIDs
    }
}

public extension UserDefaults
{
    // Cache recommended sources just in case we need to check whether source is recommended or not.
    @nonobjc var recommendedSources: [KnownSource]? {
        get {
            guard let sources = _recommendedSources?.compactMap({ KnownSource(dictionary: $0) }) else { return nil }
            return sources
        }
        set {
            _recommendedSources = newValue?.map { $0.dictionaryRepresentation }
        }
    }
    private var _recommendedSources: [[String: Any]]? {
        get { self.array(forKey: "recommendedSources") as? [[String: Any]] }
        set { self.set(newValue, forKey: "recommendedSources") }
    }
    
    @nonobjc var blockedSources: [KnownSource]? {
        get {
            guard let sources = _blockedSources?.compactMap({ KnownSource(dictionary: $0) }) else { return nil }
            return sources
        }
        set {
            _blockedSources = newValue?.map { $0.dictionaryRepresentation }
        }
    }
    private var _blockedSources: [[String: Any]]? {
        get { self.array(forKey: "blockedSources") as? [[String: Any]] }
        set { self.set(newValue, forKey: "blockedSources") }
    }
}
