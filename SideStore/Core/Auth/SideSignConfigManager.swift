//
//  SideSignConfigManager.swift
//  SideStore
//
//  Created by Magesh K on 11/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import SideSign

public actor SideSignConfigManager {
    public static let shared = SideSignConfigManager()
    
    private nonisolated var configFileURL: URL {
        let libraryDirectory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        return libraryDirectory.appendingPathComponent("sidesign-config.json")
    }
    
    public func loadConfig() -> SideSignHeaders {
        if let data = try? Data(contentsOf: configFileURL),
           let config = try? Foundation.JSONDecoder().decode(SideSignHeaders.self, from: data) {
            DeveloperPortal.shared.customHeaders = config
            return config
        }
        let defaultConfig = SideSignHeaders()
        DeveloperPortal.shared.customHeaders = defaultConfig
        return defaultConfig
    }
    
    public nonisolated func applyConfigToDeveloperPortal() {
        if let data = try? Data(contentsOf: configFileURL),
           let config = try? Foundation.JSONDecoder().decode(SideSignHeaders.self, from: data) {
            DeveloperPortal.shared.customHeaders = config
        } else {
            DeveloperPortal.shared.customHeaders = SideSignHeaders()
        }
    }
    
    public func saveConfig(_ config: SideSignHeaders) {
        let encoder = Foundation.JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if let data = try? encoder.encode(config) {
            try? data.write(to: configFileURL, options: .atomic)
        }
        DeveloperPortal.shared.customHeaders = config
    }
    
    public func importFromFile(url: URL) throws -> SideSignHeaders {
        let data = try Data(contentsOf: url)
        let config = try Foundation.JSONDecoder().decode(SideSignHeaders.self, from: data)
        saveConfig(config)
        return config
    }
    
    public func exportConfigData() -> Data? {
        let config = loadConfig()
        let encoder = Foundation.JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try? encoder.encode(config)
    }
    
    @discardableResult
    public nonisolated func resetToDefaults() -> SideSignHeaders {
        deleteConfigFile()
        let defaultConfig = SideSignHeaders()
        DeveloperPortal.shared.customHeaders = defaultConfig
        return defaultConfig
    }
    
    public nonisolated func deleteConfigFile() {
        try? FileManager.default.removeItem(at: configFileURL)
    }
    
    public nonisolated func hasConfigFile() -> Bool {
        return FileManager.default.fileExists(atPath: configFileURL.path)
    }
}
