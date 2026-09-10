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
    
    private var didCleanUp = false
    
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
        
        defer{
            self.cleanUp()
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
            throw OperationError.invalidApp
        }
        #endif

        @Managed var appVersion = context.appVersion
        let storeBuildVersion = $appVersion.buildVersion
        
        let backgroundContext = self.context.dbBackgroundContext
        
        self.setProgress(10)
        do {
            let installedApp = try await installApp(
                in: backgroundContext,
                certificate: certificate,
                resignedAppBundle: resignedAppBundle,
                provisioningProfiles: provisioningProfiles,
                storeBuildVersion: storeBuildVersion
            )
            await CellularRefreshManager.shared.turnOnDataIfNeeded()
            return installedApp
        } catch {
            await CellularRefreshManager.shared.turnOnDataIfNeeded()
            throw error
        }
    }
    
    private func removeRefreshedIPA() {
        if let appBundle = context.targetAppBundle {
            let updatedApp = AnyApp(from: appBundle, bundleId: self.context.targetBundleIdentifier)
            let fileURL = InstalledApp.refreshedIPAURL(for: updatedApp)
            
            if FileManager.default.fileExists(atPath: fileURL.path) {
                do {
                    try FileManager.default.removeItem(at: fileURL)
                    debugLog("[InstallAppOperation] Removed refreshed IPA")
                } catch {
                    debugLog("[InstallAppOperation] Failed to remove refreshed .ipa: \(error)")
                }
            }
        }
    }
    
    private func installApp(in backgroundContext: NSManagedObjectContext,
                            certificate: ALTCertificate,
                            resignedAppBundle: ALTApplication,
                            provisioningProfiles: [String: ALTProvisioningProfile],
                            storeBuildVersion: String?) async throws -> InstalledApp
    {
        let (installedApp, isDifferentSideStore, bundleID, isSelfReinstall) = try await backgroundContext.perform {
            /* App */
            let installedApp = try self.fetchOrCreateApp(
                in: backgroundContext,
                certificate: certificate,
                resignedAppBundle: resignedAppBundle,
                storeBuildVersion: storeBuildVersion
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
            
            // This preserves our data in a serilized format that will be restored at boot onyl if installtion actually completed indicated by embedded provision uuid being different.
            let isSelfReinstall = !isDifferentSideStore &&
                                   installedApp.storeApp?.bundleIdentifier.range(of: Bundle.Info.appbundleIdentifier) != nil
            if isSelfReinstall {
                if let _ = provisioningProfiles[self.context.targetBundleIdentifier],
                   let appGroup = Bundle.main.altstoreAppGroup,
                   let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) 
                {
                    let jsonURL = containerURL.appendingPathComponent("StagedSelfReinstall.json")
                    
                    // Update refreshedDate inside the transient model context
                    installedApp.refreshedDate = Date()
                    
                    // Serialize the entire InstalledApp entity with all its composition relations
                    if let stagedData = installedApp.serialize(format: .json),
                       var dict = (try? JSONSerialization.jsonObject(with: stagedData, options: [])) as? [String: Any] {
                        dict["lastBundlePath"] = Bundle.main.bundlePath
                        
                        if let finalData = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) {
                            try? finalData.write(to: jsonURL)
                            self.debugLog("[InstallAppOperation] Wrote recursively serialized staged self-reinstall metadata to JSON: \(jsonURL.path)")
                        }
                    }
                }
            }
            
            return (installedApp, isDifferentSideStore, self.context.targetBundleIdentifier, isSelfReinstall)
        }
        
        self.setProgress(30)
        
        // Temporary directory and resigned .ipa no longer needed — delete now before AltStore quits.
        cleanUp()
        
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
        if !isDifferentSideStore && !isSelfReinstall {
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
                                  resignedAppBundle: ALTApplication, storeBuildVersion: String?) throws -> InstalledApp
    {
        let target = self.context.targetBundleIdentifier
        let predicate = NSPredicate(
            format: "(%K == %@) OR (%K == %@)",
            #keyPath(InstalledApp.customBundleIdentifier), target,
            #keyPath(InstalledApp.resignedBundleIdentifier), resignedAppBundle.bundleIdentifier
        )
        let installedApp = try InstalledApp.first(
                                satisfying: predicate,
                                in: backgroundContext
                            ) ?? InstalledApp(
                                resignedAppBundle: resignedAppBundle,
                                originalBundleIdentifier: self.context.bundleIdentifier,
                                certificateSerialNumber: certificate.serialNumber,
                                storeBuildVersion: storeBuildVersion,
                                context: backgroundContext
                            )
        if !Self.isDifferentSideStoreContainer(installedApp, resignedAppBundle) {
            installedApp.update(
                resignedAppBundle: resignedAppBundle,
                certificateSerialNumber: certificate.serialNumber,
                storeBuildVersion: storeBuildVersion
            )
            installedApp.certificateStatus = self.context.targetCertStatus ?? installedApp.certificateStatus
            installedApp.customBundleIdentifier = context.customBundleIdentifier
            installedApp.useMainProfile = context.useMainProfile
            if let team = DatabaseManager.shared.activeTeam(in: backgroundContext) {
                installedApp.team = team
            }
            if let storeApp {
                let storeAppInContext = backgroundContext.object(with: storeApp.objectID) as? StoreApp
                installedApp.storeApp = storeAppInContext
                
                if let contextTrack = self.context.releaseTrack {
                    // 1. If we downloaded a version with a known release track, overwrite the track record
                    installedApp.releaseTrack = contextTrack
                } else if installedApp.releaseTrack == nil {
                    // 2. Backward compatibility: if track was empty, initialize it with the store's active track
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
        
        if let bundle = Bundle(url: resignedAppBundle.fileURL),
            let directory = bundle.builtInPlugInsURL,
            let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsSubdirectoryDescendants])
        {
            for case let fileURL as URL in enumerator {
                guard let appExtensionBundle = Bundle(url: fileURL) else { continue }
                guard let resignedAppExtensionBundle = ALTApplication(fileURL: appExtensionBundle.bundleURL) else { continue }
                
                let filename = fileURL.lastPathComponent
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
                  • originalAppExBundleID  : \(originalAppExBundleID)
                  • customAppExBundleID    : \(customAppExBundleID ?? "nil")
                  • resignedAppExBundleID  : \(resignedBundleID)
                """)
                
                let installedExtension = try installedApp.appExtensions
                                                .first(where: { $0.resignedBundleIdentifier == resignedBundleID })
                                            ?? InstalledExtension(
                                                resignedAppExtensionBundle: resignedAppExtensionBundle,
                                                originalBundleIdentifier: originalAppExBundleID,
                                                context: backgroundContext
                                            )
                installedExtension.customBundleIdentifier = customAppExBundleID
                installedExtension.update(resignedAppExtensionBundle: resignedAppExtensionBundle)
                installedExtensions.insert(installedExtension)
            }
        }

        return installedExtensions
    }

    private func updateActiveAppsStatus(for installedApp: InstalledApp,
                                        provisioningProfiles: [String: ALTProvisioningProfile],
                                        in backgroundContext: NSManagedObjectContext
    ){
        if let sideloadedAppsLimit = UserDefaults.standard.activeAppsLimit,
               provisioningProfiles.contains(where: { $1.isFreeProvisioningProfile == true })
        {
            // When installing these new profiles, AltServer will remove all non-active profiles to ensure we remain under limit.
            let fetchRequest = InstalledApp.activeAppsFetchRequest()
            fetchRequest.includesPendingChanges = false
            
            // Only free-cert-signed apps count against the free limit
            var activeApps = InstalledApp.fetch(fetchRequest, in: backgroundContext)
                                         .filter { ($0.team?.type ?? .unknown) == .free }
            
            if !activeApps.contains(installedApp) {
                let activeAppsCount = activeApps.map { $0.requiredActiveSlots }.reduce(0, +)
                
                let availableActiveApps = max(sideloadedAppsLimit - activeAppsCount, 0)
                if installedApp.requiredActiveSlots <= availableActiveApps {
                    // This app has not been explicitly activated, but there are enough slots available,
                    // so implicitly activate it.
                    installedApp.isActive = true
                    activeApps.append(installedApp)
                } else {
                    installedApp.isActive = false
                }
            }
        } else {
            installedApp.isActive = true
        }
    }
        
    private func suspendToHomeScreen() async {
        let handler = self.context.handler.installAppHandler
        await handler.suspendToHomeScreen()
    }

    private func handleSelfReinstallation(for installedApp: InstalledApp) {
        // Reinstalling ourself will hang until we leave the app, so we need to exit it without force closing
        Task.detached {
            let bgTaskID = await MainActor.run {
                UIApplication.shared.beginBackgroundTask(withName: "SelfReinstall", expirationHandler: nil)
            }
            defer {
                if bgTaskID != .invalid {
                    Task { @MainActor in UIApplication.shared.endBackgroundTask(bgTaskID) }
                }
            }

            try? await Task.sleep(nanoseconds: AppConstants.Installation.selfInstallSuspendDelayNs)

            let handler = self.context.handler.installAppHandler
            guard await handler.isAppInForeground() else {
                self.debugLog("[InstallAppOperation] We are not in the foreground, let's not do anything")
                return
            }
            
            let delaySeconds = AppConstants.Installation.selfInstallSuspendDelayNs / 1_000_000_000
            self.debugLog("[InstallAppOperation] We are still installing after \(delaySeconds) seconds")
            
            await self.suspendToHomeScreen()

            // #if !os(tvOS)
            // let settings = await UNUserNotificationCenter.current().notificationSettings()
            // switch settings.authorizationStatus {
            //     case .authorized, .ephemeral, .provisional:
            //         self.verboseLog("[InstallAppOperation] Notifications are enabled")
            //
            //         let content = UNMutableNotificationContent()
            //         content.title = "Refreshing..."
            //         content.body = "SideStore will automatically move to the homescreen to finish refreshing!"
            //         let notification = UNNotificationRequest(identifier: Bundle.Info.appbundleIdentifier + ".FinishRefreshNotification", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false))
            //         try? await UNUserNotificationCenter.current().add(notification)
            //         
            //         await self.suspendToHomeScreen()
            //
            //     default:
            //         self.verboseLog("[InstallAppOperation] Notifications are not enabled")
            //
            //         await withTaskGroup(of: Void.self) { group in
            //             group.addTask { await handler.requestBackgroundSuspension() }
            //             group.addTask { try? await Task.sleep(nanoseconds: 5_000_000_000) }
            //             _ = await group.next()
            //             group.cancelAll()
            //         }
            //         await self.suspendToHomeScreen()
            //     }
            // #else
            // NotificationCenter.default.post(name: NSNotification.Name("TVTopShelfItemsDidChangeNotification"), object: nil)
            // await handler.requestBackgroundSuspension()
            // await self.suspendToHomeScreen()
            // #endif
        }
    }
    
    private func cleanUp() {
        guard !didCleanUp else { return }
        didCleanUp = true
        
        do {
            try FileManager.default.removeItem(at: context.temporaryDirectory)
        } catch {
            debugLog("[InstallAppOperation] Failed to remove temporary directory. \(error)")
        }
    }
}
