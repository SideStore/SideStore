//
//  CacheAppOperation.swift
//  SideStore
//
//  Created by Magesh K on 30/07/26.
//  Copyright © 2026 AltStore. All rights reserved.
//

import Foundation

final class CacheAppOperation: BasePipelineOperation<InstallAppOperationContext, URL?>, @unchecked Sendable {

    override func execute(parentProgress: Progress?) async throws -> URL? {
        let startTime = CFAbsoluteTimeGetCurrent()
        debugLog("[CacheAppOperation] execute() started")
        defer {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            debugLog("[CacheAppOperation] execute() took: \(String(format: "%.3fs", elapsed))")
        }
        try await super.executePreconditionCheck(parentProgress: parentProgress)
        self.setProgress(10)

        guard let appBundle = context.targetAppBundle else {
            debugLog("[CacheAppOperation] context.appBundle is nil")
            self.setProgress(100)
            return nil
        }

        self.setProgress(40)
        let targetFileURL = InstalledApp.fileURL(for: appBundle)
        
        self.setProgress(70)
        debugLog("[CacheAppOperation] Copying app bundle from \(appBundle.fileURL.path) to \(targetFileURL.path)")
        try FileManager.default.copyItem(at: appBundle.fileURL, to: targetFileURL, shouldReplace: true)
        
        self.setProgress(100)
        return targetFileURL
    }

    static func pruneUnusedCaches(activeBundleIDs: Set<String>, isActivelyManaging: (String) -> Bool) {
        do {
            let cachedAppDirectories = try FileManager.default.contentsOfDirectory(
                at: InstalledApp.appsDirectoryURL,
                includingPropertiesForKeys: [.isDirectoryKey, .nameKey],
                options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles]
            )
            for appDirectory in cachedAppDirectories {
                do {
                    let resourceValues = try appDirectory.resourceValues(forKeys: [.isDirectoryKey, .nameKey])
                    guard let isDirectory = resourceValues.isDirectory, let bundleID = resourceValues.name else { continue }
                    
                    if isDirectory && !activeBundleIDs.contains(bundleID) && !isActivelyManaging(bundleID) {
                        SideStore.debugLog("[CacheAppOperation] DELETING CACHED APP: \(bundleID)")
                        try FileManager.default.removeItem(at: appDirectory)
                    }
                } catch {
                    SideStore.debugLog("[CacheAppOperation] Failed to remove cached app directory: \(error)")
                }
            }
        } catch {
            SideStore.debugLog("[CacheAppOperation] Failed to remove cached apps: \(error)")
        }
    }
}
