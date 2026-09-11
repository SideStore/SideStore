//
//  ExportResignedIpaOperation.swift
//  SideStore
//
//  Created by Magesh K on 30/07/26.
//  Copyright © 2026 AltStore. All rights reserved.
//

import Foundation
import SideSign

final class ExportResignedIpaOperation: BasePipelineOperation<InstallAppOperationContext, URL?>, @unchecked Sendable {

    override func execute(parentProgress: Progress?) async throws -> URL? {
        let startTime = CFAbsoluteTimeGetCurrent()
        debugLog("[ExportResignedIpaOperation] execute() started")
        defer {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            debugLog("[ExportResignedIpaOperation] execute() took: \(String(format: "%.3fs", elapsed))")
        }
        try await super.executePreconditionCheck(parentProgress: parentProgress)
        self.setProgress(10)

        guard UserDefaults.standard.isExportResignedAppEnabled else {
            self.setProgress(100)
            return context.ipaURL
        }

        guard let resignedAppBundle = self.context.resignedAppBundle else {
            throw OperationError.invalidParameters("ExportResignedIpaOperation: context.resignedAppBundle is nil")
        }

        guard let sourceURL = self.context.ipaURL else {
            debugLog("[ExportResignedIpaOperation] context.ipaURL is nil, skipping export")
            self.setProgress(100)
            return nil
        }

        let documentsURL = FileManager.default.documentsDirectory
        let resignedAppsURL = documentsURL.appendingPathComponent("ResignedApps")
        self.setProgress(30)
        do {
            if !FileManager.default.fileExists(atPath: resignedAppsURL.path) {
                try FileManager.default.createDirectory(at: resignedAppsURL, withIntermediateDirectories: true, attributes: nil)
            }
        } catch {
            debugLog("Failed to create ResignedApps folder: \(error)")
            throw error
        }

        let utis = Bundle(url: resignedAppBundle.fileURL)?.infoDictionary?[Bundle.Info.exportedUTIs] as? [[String: Any]]
        let isSideBackup = utis?.first?["UTTypeDescription"] as? String == "SideStore Backup App"
        let destPath = isSideBackup ? resignedAppBundle.name + "-sidebackup" : resignedAppBundle.name
        let destinationURL = resignedAppsURL.appendingPathComponent(destPath + ".ipa")
        self.setProgress(60)
        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
        } catch {
            debugLog("Failed to delete existing file at destination: \(error)")
            throw error
        }
        self.setProgress(80)
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            debugLog("File copied to: \(destinationURL.path)")
        } catch {
            debugLog("Failed to copy file to destination: \(error)")
            throw error
        }
        self.setProgress(100)
        return destinationURL
    }
}
