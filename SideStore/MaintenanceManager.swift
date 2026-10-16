//
//  MaintenanceManager.swift
//  SideStore
//
//  Created by Magesh K on 22/08/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import CoreData
import SideSign

public final class MaintenanceManager {
    public static let shared = MaintenanceManager()

    // Increment this counter whenever you want to trigger another maintenance pass in future updates
    public static let currentMaintenanceCounter = 7

    public static let maintenanceCounterFileName = ".maintenance_counter"

    private var maintenanceCounterFileURL: URL? {
        FileManager.default.altstoreSharedDirectory?.appendingPathComponent(Self.maintenanceCounterFileName)
    }

    private var completedCounter: Int {
        get {
            guard let url = maintenanceCounterFileURL,
                  let str = try? String(contentsOf: url, encoding: .utf8),
                  let val = Int(str.trimmingCharacters(in: .whitespacesAndNewlines)) else { return 0 }
            return val
        }
        set {
            guard let url = maintenanceCounterFileURL else { return }
            try? "\(newValue)".write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private init() {}

    public func performDatabaseMigrationIfNeeded() async {
        let current = completedCounter
        guard current < Self.currentMaintenanceCounter else { return }

        for pass in (current + 1)...Self.currentMaintenanceCounter {
            switch pass {
            case 4:
                await migrateDatabaseFiles()
            default:
                break
            }
        }
    }

    public func performMaintenanceIfNeeded() async {
        let current = completedCounter
        guard current < Self.currentMaintenanceCounter else { return }

        for pass in (current + 1)...Self.currentMaintenanceCounter {
            debugLog("[MaintenanceManager] Running maintenance pass \(pass)...")
            switch pass {
            case 1:
                Keychain.shared.clearAll()
                await AuthManager.shared.signOut(keepCertificate: false, keepAnisetteData: false)
            case 2:
                AnisetteDataManager.shared.clearCache()
                await AuthManager.shared.signOut(keepCertificate: true, keepAnisetteData: false)
            case 3:
                UserDefaults.standard.tunnelOverridePeerIp = nil
            case 4:
                await migrateLegacyCachedAppBundles()
            case 5:
                await migrateLegacyCachedSigningCertificates()
            case 6:
                AnisetteConfigManager.shared.resetToDefaults()
                SideSignConfigManager.shared.resetToDefaults()
            case 7:
                await migratePairingFiles()
            default:
                break
            }
        }

        completedCounter = Self.currentMaintenanceCounter
        debugLog("[MaintenanceManager] Maintenance up to counter \(Self.currentMaintenanceCounter) complete.")
    }

}

private extension MaintenanceManager {
    func migrateDatabaseFiles() async {
        let fileManager = FileManager.default
        let dbDir = PersistentContainer.defaultDirectoryURL()

        let extensions = ["", "-wal", "-shm"]
        let legacyName = AppConstants.Database.legacyFileName
        let targetName = AppConstants.Database.fileName

        let legacyTargetURL = dbDir.appendingPathComponent(legacyName)
        let newTargetURL = dbDir.appendingPathComponent(targetName)

        if fileManager.fileExists(atPath: legacyTargetURL.path) && !fileManager.fileExists(atPath: newTargetURL.path) {
            for ext in extensions {
                let src = dbDir.appendingPathComponent("\(legacyName)\(ext)")
                let dst = dbDir.appendingPathComponent("\(targetName)\(ext)")
                if fileManager.fileExists(atPath: src.path) {
                    do {
                        try fileManager.moveItem(at: src, to: dst)
                        debugLog("[MaintenanceManager] Migrated database file '\(src.lastPathComponent)' -> '\(dst.lastPathComponent)'")
                    } catch {
                        debugLog("[MaintenanceManager] Failed to move database file '\(src.lastPathComponent)': \(error)")
                    }
                }
            }
        }
    }

    // added in v0.7.0
    func migrateLegacyCachedAppBundles() async {
        let context = DatabaseManager.shared.viewContext
        await context.perform {
            let fetchRequest: NSFetchRequest<InstalledApp> = InstalledApp.fetchRequest()
            let installedApps = (try? context.fetch(fetchRequest)) ?? []
            let appsByBundleID = Dictionary(installedApps.map { ($0.resignedBundleIdentifier, $0) }, uniquingKeysWith: { first, _ in first })

            var didMutate = false
            let appsDir = InstalledApp.appsDirectoryURL
            guard let subdirectories = try? FileManager.default.contentsOfDirectory(
                at: appsDir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                return
            }

            for directory in subdirectories {
                guard directory.lastPathComponent != "Payloads" else { continue }
                let legacyAppURL = directory.appendingPathComponent("App.app")
                guard FileManager.default.fileExists(atPath: legacyAppURL.path) else { continue }

                guard let signature = AppBundleFingerprint.compute(for: legacyAppURL) else {
                    debugLog("[MaintenanceManager] Failed to compute fingerprint for legacy app at '\(legacyAppURL.path)'")
                    continue
                }

                let targetFileURL = InstalledApp.payloadURL(forSignature: signature)
                let targetParentDir = targetFileURL.deletingLastPathComponent()

                do {
                    if !FileManager.default.fileExists(atPath: targetFileURL.path) {
                        try FileManager.default.createDirectory(at: targetParentDir, withIntermediateDirectories: true, attributes: nil)
                        try FileManager.default.moveItem(at: legacyAppURL, to: targetFileURL)
                    } else {
                        try FileManager.default.removeItem(at: legacyAppURL)
                    }

                    let bundleID = directory.lastPathComponent
                    if let app = appsByBundleID[bundleID] {
                        app.appBundleFingerprint = signature
                        didMutate = true
                    }
                    debugLog("[MaintenanceManager] Migrated legacy app bundle '\(bundleID)' to payload '\(signature)'.")
                } catch {
                    debugLog("[MaintenanceManager] Failed to move legacy app bundle at '\(legacyAppURL.path)': \(error)")
                }
            }

            if didMutate {
                try? context.save()
            }
        }
    }

    func migrateLegacyCachedSigningCertificates() async {
        let context = DatabaseManager.shared.viewContext
        await context.perform {
            let fetchRequest: NSFetchRequest<InstalledApp> = InstalledApp.fetchRequest()
            guard let installedApps = try? context.fetch(fetchRequest) else { return }
            let fileManager = FileManager.default
            let appsDir = InstalledApp.appsDirectoryURL

            for app in installedApps {
                guard app.bundleIdentifier != app.resignedBundleIdentifier else { continue }

                let legacyCertURL = appsDir.appendingPathComponent(app.bundleIdentifier).appendingPathComponent("signing_certificate.der")
                let targetCertURL = app.signingCertificateURL

                guard fileManager.fileExists(atPath: legacyCertURL.path) else { continue }

                do {
                    if !fileManager.fileExists(atPath: targetCertURL.path) {
                        let targetDir = targetCertURL.deletingLastPathComponent()
                        try fileManager.createDirectory(at: targetDir, withIntermediateDirectories: true, attributes: nil)
                        try fileManager.moveItem(at: legacyCertURL, to: targetCertURL)
                    } else {
                        try fileManager.removeItem(at: legacyCertURL)
                    }
                    debugLog("[MaintenanceManager] Migrated signing cert for '\(app.bundleIdentifier)' -> '\(app.resignedBundleIdentifier)'")
                } catch {
                    debugLog("[MaintenanceManager] Failed to migrate signing cert from '\(legacyCertURL.path)': \(error)")
                }
            }
        }
    }

    func migratePairingFiles() async {
        let fileManager = FileManager.default
        let lockdownURL = fileManager.documentsDirectory.appendingPathComponent(AppConstants.Pairing.lockdownPairingFileName)
        let remoteURL = fileManager.documentsDirectory.appendingPathComponent(AppConstants.Pairing.remotePairingFileName)

        let legacyURL = fileManager.documentsDirectory.appendingPathComponent(AppConstants.Pairing.legacyPairingFileName)
        guard fileManager.fileExists(atPath: legacyURL.path),
              let content = try? String(contentsOf: legacyURL), !content.isEmpty else 
        { 
            return 
        }

        let remoteRP = try? PairingFileManager.shared.parse(content: content, preferred: .rppairing)
        let lockdown = try? PairingFileManager.shared.parse(content: content, preferred: .lockdown)
        if remoteRP != nil && !fileManager.fileExists(atPath: remoteURL.path) {
            try? content.write(to: remoteURL, atomically: true, encoding: .utf8)
            debugLog("[MaintenanceManager] Migrated remote pairing file to '\(remoteURL.path)'.")
        }
        if lockdown != nil && !fileManager.fileExists(atPath: lockdownURL.path) {
            try? content.write(to: lockdownURL, atomically: true, encoding: .utf8)
            debugLog("[MaintenanceManager] Migrated lockdown pairing file to '\(lockdownURL.path)'.")
        }

        try? fileManager.removeItem(at: legacyURL)
        debugLog("[MaintenanceManager] Removed legacy pairing file '\(legacyURL.path)'.")
    }
}
