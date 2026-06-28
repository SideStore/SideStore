//
//  CacheManager.swift
//  AltStore
//
//  Created by Magesh K on 28/06/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import AltStoreCore

public final class CacheManager {
    public static let shared = CacheManager()
    
    private init() {}
    
    public func calculateCacheSize() -> Int64 {
        var totalSize: Int64 = 0
        let fileManager = FileManager.default
        
        // 1. Nuke cache size
        if let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let nukeCacheURL = cachesDirectory.appendingPathComponent("io.sidestore.Nuke")
            totalSize += getDirectorySize(at: nukeCacheURL)
        }
        
        // 2. Temporary directory size
        totalSize += getDirectorySize(at: fileManager.temporaryDirectory)
        
        // 3. Uninstalled app backup directories size
        if let backupsDirectory = fileManager.appBackupsDirectory,
           let fileURLs = try? fileManager.contentsOfDirectory(at: backupsDirectory, includingPropertiesForKeys: [.isDirectoryKey, .nameKey], options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles]) {
            
            // Get installed app bundle IDs
            let context = DatabaseManager.shared.viewContext
            let installedAppBundleIDs = Set(InstalledApp.all(in: context).map { $0.bundleIdentifier })
            
            for backupDirectory in fileURLs {
                if let resourceValues = try? backupDirectory.resourceValues(forKeys: [.isDirectoryKey, .nameKey]),
                   let isDirectory = resourceValues.isDirectory,
                   let bundleID = resourceValues.name {
                    if isDirectory && !installedAppBundleIDs.contains(bundleID) && !AppManager.shared.isActivelyManagingApp(withBundleID: bundleID) {
                        totalSize += getDirectorySize(at: backupDirectory)
                    }
                }
            }
        }
        
        return totalSize
    }
    
    public func formattedCacheSize() -> String {
        let size = calculateCacheSize()
        guard size > 0 else { return "0 KB" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
    
    public func formattedCacheSize(completion: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let size = self.calculateCacheSize()
            let result: String
            if size <= 0 {
                result = "0 KB"
            } else {
                let formatter = ByteCountFormatter()
                formatter.allowedUnits = [.useAll]
                formatter.countStyle = .file
                result = formatter.string(fromByteCount: size)
            }
            completion(result)
        }
    }
    
    private func getDirectorySize(at url: URL) -> Int64 {
        var size: Int64 = 0
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: url,
                                                     includingPropertiesForKeys: [.fileSizeKey],
                                                     options: []) else { return 0 }
        for case let fileURL as URL in enumerator {
            if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                size += Int64(fileSize)
            }
        }
        return size
    }
}
