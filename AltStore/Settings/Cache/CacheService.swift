//
//  CacheService.swift
//  AltStore
//
//  Created by Magesh K on 2026-06-29.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import AltStoreCore

struct CacheService {
    static let shared = CacheService()
    
    private init() {}
    
    var internalAppsDirectory: URL {
        return InstalledApp.appsDirectoryURL
    }
    
    var resignedAppsDirectory: URL {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsURL.appendingPathComponent("ResignedApps")
    }
    
    func fetchInternalApps() -> [URL] {
        let fileManager = FileManager.default
        guard let urls = try? fileManager.contentsOfDirectory(at: internalAppsDirectory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        return urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false }
    }
    
    func fetchResignedApps() -> [URL] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: resignedAppsDirectory.path) else {
            return []
        }
        guard let urls = try? fileManager.contentsOfDirectory(at: resignedAppsDirectory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        return urls
    }
    
    func calculateSize(of url: URL) -> Int64 {
        let fileManager = FileManager.default
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        
        if !isDir.boolValue {
            return (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        }
        
        var totalSize: Int64 = 0
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: []) else { return 0 }
        for case let fileURL as URL in enumerator {
            if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalSize += Int64(fileSize)
            }
        }
        return totalSize
    }
    
    func delete(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
}
