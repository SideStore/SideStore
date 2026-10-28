//
//  InstallAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 6/19/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UserNotifications
import UIKit
import Foundation
import Network
import CoreData
import SideSign

final class InstallAppOperation: BasePipelineOperation<InstallAppOperationContext, InstalledApp>, @unchecked Sendable {
    let storeApp: StoreApp?
    
    init(context: InstallAppOperationContext, app: any AppProtocol) throws {
        self.storeApp = app as? StoreApp
        try super.init(context: context)
        self.progress.totalUnitCount = 100
    }
    
    override func execute(parentProgress: Progress?) async throws -> InstalledApp {
        let startTime = CFAbsoluteTimeGetCurrent()
        debugLog("[InstallAppOperation] execute() started")
        defer {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            debugLog("[InstallAppOperation] execute() took: \(String(format: "%.3fs", elapsed))")
        }
        try await super.executePreconditionCheck(parentProgress: parentProgress)
        
        defer {
            self.removeRefreshedIPA()
        }
        
        guard
            let certificate = context.targetSigningCertificate,
            let resignedAppBundle = context.resignedAppBundle,
            let provisioningProfiles = context.provisioningProfiles
        else {
            throw OperationError.invalidParameters(
                "InstallAppOperation.execute: self.context.targetSigningCertificate or self.context.resignedAppBundle or self.context.provisioningProfiles is nil"
            )
        }

        #if !targetEnvironment(simulator)
        guard resignedAppBundle.provisioningProfile != nil else {
            throw OperationError.missingProvisioningProfile(reason: "Resigned app bundle '\(resignedAppBundle.bundleIdentifier)' is missing its embedded provisioning profile.")
        }
        #endif

        @Managed var appVersion = context.appVersion
        let storeBuildVersion = $appVersion.buildVersion
        
        let backgroundContext = self.context.dbBackgroundContext
        
        self.setProgress(10)
        let authTeam = try await AuthManager.shared.getAuthenticatedTeam()
        do {
            let installedApp = try await installApp(
                in: backgroundContext,
                certificate: certificate,
                resignedAppBundle: resignedAppBundle,
                provisioningProfiles: provisioningProfiles,
                storeBuildVersion: storeBuildVersion,
                authTeam: authTeam
            )
            self.context.installedApp = installedApp
            await CellularRefreshManager.shared.turnOnDataIfNeeded()
            return installedApp
        } catch {
            await CellularRefreshManager.shared.turnOnDataIfNeeded()
            throw error
        }
    }
    
    private func removeRefreshedIPA() {
        guard let fileURL = self.context.installedApp?.refreshedIPAURL else { return }
        
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                try FileManager.default.removeItem(at: fileURL)
                debugLog("[InstallAppOperation] Removed refreshed IPA")
            } catch {
                debugLog("[InstallAppOperation] Failed to remove refreshed .ipa: \(error)")
            }
        }
    }
    
    private func installApp(in backgroundContext: NSManagedObjectContext,
                            certificate: ALTCertificate,
                            resignedAppBundle: ALTApplication,
                            provisioningProfiles: [String: ALTProvisioningProfile],
                            storeBuildVersion: String?,
                            authTeam: ALTTeam) async throws -> InstalledApp
    {
        let (installedApp, isDifferentSideStore, bundleID, isSelfReinstall, isSideBackup) = try await backgroundContext.perform {
            let utis = resignedAppBundle.infoPlist[Bundle.Info.exportedUTIs] as? [[String: Any]]
            let isSideBackup = utis?.first?["UTTypeDescription"] as? String == "SideStore Backup App"
            
            if isSideBackup {
                let installedApp = try self.context.installedApp.flatMap { app in
                    backgroundContext.object(with: app.objectID) as? InstalledApp
                } ?? self.fetchOrCreateApp(
                    in: backgroundContext,
                    certificate: certificate,
                    resignedAppBundle: resignedAppBundle,
                    storeBuildVersion: storeBuildVersion,
                    authTeam: authTeam
                )
                return (installedApp, false, self.context.targetBundleIdentifier, false, true)
            }

            /* App */
            let installedApp = try self.fetchOrCreateApp(
                in: backgroundContext,
                certificate: certificate,
                resignedAppBundle: resignedAppBundle,
                storeBuildVersion: storeBuildVersion,
                authTeam: authTeam
            )
            
            let isDifferentSideStore = Self.isDifferentSideStoreContainer(installedApp, resignedAppBundle)
            if isDifferentSideStore {
                self.debugLog("""
                [WARN] Skipped inserting/updating into InstalledApp table for SideStore:
                    - Resigned Bundle ID: '\(resignedAppBundle.bundleIdentifier)'
                    - Active Container Bundle ID: '\(installedApp.resignedBundleIdentifier)'
                    Reason: A different bundle ID installs SideStore as a new app container which initializes its own database upon launch.
                            Hence we do not perist current change to prevent corruption of current sidestore's database entry.
                    
                """)
            } else {
                /* App Extensions */
                let installedExtensions = try self.fetchOrCreateExtensions(
                    for: resignedAppBundle,
                    installedApp: installedApp,
                    in: backgroundContext
                )
                installedApp.appExtensions = installedExtensions
                self.context.beginInstallationHandler?(installedApp)
                self.updateActiveAppsStatus(
                    for: installedApp,
                    provisioningProfiles: provisioningProfiles,
                    in: backgroundContext
                )
            }
            
            // Write staging info to local app Caches instead of Shared App Group to avoid container lockout
            let isSelfReinstall = !isDifferentSideStore &&
                                   installedApp.storeApp?.bundleIdentifier.range(of: Bundle.Info.appbundleIdentifier) != nil
            if isSelfReinstall {
                if let _ = provisioningProfiles[self.context.targetBundleIdentifier],
                   let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                {
                    let jsonURL = cachesURL.appendingPathComponent("StagedSelfReinstall.json")
                    
                    // Update refreshedDate inside the transient model context
                    installedApp.refreshedDate = Date()
                    
                    // Serialize the entire InstalledApp entity with all its composition relations
                    if let stagedData = installedApp.serialize(format: .json),
                       var dict = (try? JSONSerialization.jsonObject(with: stagedData, options: [])) as? [String: Any] {
                        dict["lastBundlePath"] = Bundle.main.bundlePath
                        
                        if let finalData = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) {
                            try? finalData.write(to: jsonURL)
                            self.debugLog("[InstallAppOperation] Wrote recursively serialized staged self-reinstall metadata to local Caches JSON: \(jsonURL.path)")
                        }
                    }
                }
            }
            
            return (installedApp, isDifferentSideStore, self.context.targetBundleIdentifier, isSelfReinstall, false)
        }
        
        self.setProgress(30)
        
        // Self-reinstall background suspension
        if isSelfReinstall {
            self.handleSelfReinstallation(for: installedApp)
        }
        
        // Phase 2: App installation
        if UserDefaults.standard.preferResignedIPA {
            try await installIPA(bundleID)
        } else {
            try await installAppBundle(bundleID, appName: resignedAppBundle.fileURL.lastPathComponent)
        }
        
        self.setProgress(90)
        
        // Phase 3: Post-install CoreData write — update refreshedDate
        if !isDifferentSideStore && !isSelfReinstall && !isSideBackup {
            await backgroundContext.perform {
                installedApp.refreshedDate = Date()
            }
        }
        
        self.setProgress(100)
        return installedApp
    }
    
    private static func isDifferentSideStoreContainer(_ installedApp: InstalledApp, _ resignedAppBundle: ALTApplication) -> Bool {
        return ((installedApp.bundleIdentifier == StoreApp.altstoreAppID) || resignedAppBundle.isAltStoreApp) &&
                (resignedAppBundle.bundleIdentifier != installedApp.resignedBundleIdentifier)
    }

    private func fetchOrCreateApp(in backgroundContext: NSManagedObjectContext,
                                  certificate: ALTCertificate,
                                  resignedAppBundle: ALTApplication,
                                  storeBuildVersion: String?,
                                  authTeam: ALTTeam) throws -> InstalledApp
    {
        guard let appBundleFingerprint = self.context.appBundleFingerprint else {
            throw OperationError.invalidParameters("InstallAppOperation: context.appBundleFingerprint is nil. CacheAppOperation must guarantee a fingerprint reference.")
        }
        
        let target = self.context.targetBundleIdentifier
        let predicate = NSPredicate(
            format: "(%K == %@) OR (%K == %@)",
            #keyPath(InstalledApp.customBundleIdentifier), target,
            #keyPath(InstalledApp.resignedBundleIdentifier), resignedAppBundle.bundleIdentifier
        )
        let customCertSerial = self.context.overrideSigningCertificate?.serialNumber
        let installedApp = try InstalledApp.first(
                                satisfying: predicate,
                                in: backgroundContext
                            ) ?? InstalledApp(
                                resignedAppBundle: resignedAppBundle,
                                originalBundleIdentifier: self.context.bundleIdentifier,
                                certificateSerialNumber: customCertSerial,
                                storeBuildVersion: storeBuildVersion,
                                context: backgroundContext
                            )
        if !Self.isDifferentSideStoreContainer(installedApp, resignedAppBundle) {
            installedApp.update(
                resignedAppBundle: resignedAppBundle,
                certificateSerialNumber: customCertSerial,
                storeBuildVersion: storeBuildVersion
            )
            installedApp.certificateStatus = self.context.targetCertStatus ?? installedApp.certificateStatus
            installedApp.customBundleIdentifier = context.customBundleIdentifier
            installedApp.useMainProfile = context.useMainProfile
            installedApp.appBundleFingerprint = appBundleFingerprint
            let teamPredicate = NSPredicate(format: "%K == %@", #keyPath(Team.identifier), authTeam.identifier)
            if let team = Team.first(satisfying: teamPredicate, in: backgroundContext) {
                installedApp.team = team
            }
            if let storeApp {
                let storeAppInContext = backgroundContext.object(with: storeApp.objectID) as? StoreApp
                installedApp.storeApp = storeAppInContext
                
                if let contextTrack = self.context.releaseTrack {
                    installedApp.releaseTrack = contextTrack
                } else if installedApp.releaseTrack == nil {
                    if let trackEntity = storeAppInContext?.latestSupportedVersion?.releaseTrack {
                        installedApp.releaseTrack = trackEntity
                    }
                }
            }
            // update alternate icon
            switch context.alternateIconMode {
                case .set(let alternateIconURL):
                    guard FileManager.default.fileExists(atPath: alternateIconURL.path) else { break }
                    installedApp.hasAlternateIcon = true
                    guard alternateIconURL != installedApp.alternateIconURL else { break }
                    do {
                        try FileManager.default.copyItem(
                            at: alternateIconURL,
                            to: installedApp.alternateIconURL,
                            shouldReplace: true
                        )
                        self.debugLog("[InstallAppOperation] Copied alternate icon at: \(alternateIconURL) to: \(installedApp.alternateIconURL)")
                    } catch {
                        self.debugLog("[InstallAppOperation] Failed to copy alternate icon: \(error)")
                    }
                case .remove:
                    try? FileManager.default.removeItem(at: installedApp.alternateIconURL)
                    installedApp.hasAlternateIcon = false
                case .preserve:
                    break
            }

            if let overrideProfile = self.context.overrideProvisioningProfile {
                ProfileManager.shared.assignProfile(uuid: overrideProfile.uuid, for: installedApp.bundleIdentifier)
                self.debugLog("[InstallAppOperation] Assigned profile '\(overrideProfile.name)' to installed app '\(installedApp.bundleIdentifier)'")
            }
        }

        return installedApp
    }

    private func fetchOrCreateExtensions(for resignedAppBundle: ALTApplication,
                                         installedApp: InstalledApp,
                                         in backgroundContext: NSManagedObjectContext) throws -> Set<InstalledExtension>
    {
        guard let targetAppBundle = self.context.targetAppBundle else {
            throw OperationError.invalidParameters("InstallAppOperation: targetAppBundle is missing in context.")
        }

        let originalExtensionsByFilename = Dictionary(
            targetAppBundle.appExtensions.map { ($0.fileURL.lastPathComponent, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var installedExtensions = Set<InstalledExtension>()
        
        for resignedAppExtensionBundle in resignedAppBundle.appExtensions {
            let filename = resignedAppExtensionBundle.fileURL.lastPathComponent
            guard let originalExtension = originalExtensionsByFilename[filename] else {
                throw OperationError.invalidParameters("InstallAppOperation: extension '\(filename)' not found in targetAppBundle.")
            }
            
            let targetParentBundleID = context.targetBundleIdentifier
            let resignedParentBundleID = resignedAppBundle.bundleIdentifier
            
            let originalAppExBundleID = originalExtension.bundleIdentifier
            let resignedBundleID = resignedAppExtensionBundle.bundleIdentifier
            var customAppExBundleID: String? = nil
            if context.customBundleIdentifier != nil {
                customAppExBundleID = resignedBundleID.replacingOccurrences(of: resignedParentBundleID, with: targetParentBundleID)
            }
            
            self.debugLog("""
            [InstallAppOperation] Extension Bundle Mapping:
              • targetParentBundleID   : \(targetParentBundleID)
              • resignedParentBundleID : \(resignedParentBundleID)
