//
//  InstallAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 6/19/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UserNotifications
import Foundation
import Network
import CoreData
@preconcurrency import AltSign

let shortcutURLonDelay = URL(string: "shortcuts://run-shortcut?name=TurnOnDataDelay")!

final class InstallAppOperation: BasePipelineOperation<InstallAppOperationContext, InstalledApp>, @unchecked Sendable {
    private static let selfInstallSuspendDelayNs: UInt64 = 2_000_000_000

    let storeApp: StoreApp?
    var backgroundContext: NSManagedObjectContext?
    
    private var didCleanUp = false
    
    init(context: InstallAppOperationContext, app: any AppProtocol) throws {
        self.storeApp = app as? StoreApp
        try super.init(context: context)
        self.progress.totalUnitCount = 100
    }
    
    override func execute(parentProgress: Progress?) async throws -> InstalledApp {
        debugLog("[InstallAppOperation] execute() started")
        defer {
            debugLog("[InstallAppOperation] execute() completed")
            self.cleanUp()
            self.removeRefreshedIPA()
        }
        try await super.executePreconditionCheck(parentProgress: parentProgress)
        
        guard
            let certificate = context.overrideCertificate ?? context.authenticatedContext.signingCertificate,
            let resignedAppBundle = context.resignedAppBundle,
            let provisioningProfiles = context.provisioningProfiles
        else {
            throw OperationError.invalidParameters(
                "InstallAppOperation.execute: self.context.authenticatedContext.signingCertificate or self.context.resignedAppBundle or self.context.provisioningProfiles is nil"
            )
        }

        #if !targetEnvironment(simulator)
        guard resignedAppBundle.provisioningProfile != nil else {
            throw OperationError.invalidApp
        }
        #endif

        @Managed var appVersion = context.appVersion
        let storeBuildVersion = $appVersion.buildVersion
        
        guard let backgroundContext = self.context.dbBackgroundContext else {
            throw OperationError.invalidParameters("InstallAppOperation: context.dbBackgroundContext is nil")
        }
        self.backgroundContext = backgroundContext
        
        self.setProgress(10)
        let installedApp = try await installApp(
            in: backgroundContext,
            certificate: certificate,
            resignedAppBundle: resignedAppBundle,
            provisioningProfiles: provisioningProfiles,
            storeBuildVersion: storeBuildVersion
        )
        
        return installedApp
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
                
                // Remove stale "PlugIns" (Extensions) from currently installed App
                self.removeStaleAppExtensions(for: installedApp)
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
                if let newProfile = provisioningProfiles[installedApp.bundleIdentifier],
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
            
            return (installedApp, isDifferentSideStore, installedApp.bundleIdentifier, isSelfReinstall)
        }
        
        self.setProgress(30)
        
        // Temporary directory and resigned .ipa no longer needed — delete now before AltStore quits.
        cleanUp()
        
        // Self-reinstall background suspension
        if isSelfReinstall {
            self.handleSelfReinstallation(for: installedApp)
        }
        
        // Phase 2: IPA installation
        try await installIPA(bundleID)
        
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
        let installedApp = try InstalledApp.first(
                                satisfying: NSPredicate(format: "%K == %@", #keyPath(InstalledApp.bundleIdentifier), context.bundleIdentifier),
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
        var installedExtensions = Set<InstalledExtension>()
        
        for appExtension in resignedAppBundle.appExtensions {
            let parentBundleID = context.bundleIdentifier
            let resignedParentBundleID = resignedAppBundle.bundleIdentifier

            let resignedBundleID = appExtension.bundleIdentifier
            let appExBundleID = resignedBundleID.replacingOccurrences(of: resignedParentBundleID, with: parentBundleID)

            self.debugLog("""
            [InstallAppOperation] Extension Bundle Mapping:
              • parentBundleID         : \(parentBundleID)
              • resignedParentBundleID : \(resignedParentBundleID)
              • appExBundleID          : \(appExBundleID)
              • resignedAppExBundleID  : \(resignedBundleID)
            """)

            let installedExtension = try installedApp.appExtensions
                                            .first(where: { $0.bundleIdentifier == appExBundleID })
                                        ?? InstalledExtension(
                                            resignedAppExtensionBundle: appExtension,
                                            originalBundleIdentifier: appExBundleID,
                                            context: backgroundContext
                                        )
            installedExtension.update(resignedAppExtensionBundle: appExtension)
            installedExtensions.insert(installedExtension)
        }

        return installedExtensions
    }

    private func removeStaleAppExtensions(for installedApp: InstalledApp) {
        if let installedAppExns = ALTApplication(fileURL: installedApp.fileURL)?.appExtensions {
            let currentAppExns = Set(installedApp.appExtensions).map{ $0.bundleIdentifier }
            let staleAppExns = installedAppExns.filter{ !currentAppExns.contains($0.bundleIdentifier) }
            
            for staleAppExn in staleAppExns {
                do {
                    try FileManager.default.removeItem(at: staleAppExn.fileURL)
                    self.debugLog("[InstallAppOperation] removed stale app-extension: \(staleAppExn.fileURL)")
                } catch {
                    self.debugLog("[InstallAppOperation] remove appExtensions Error: \(error)")
                }
            }
        }
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
        
    private func suspendToHomeScreen() {
        let handler = self.context.handler.installAppHandler
        handler.suspendToHomeScreen(shouldTurnOffData: self.context.shouldTurnOffData)
    }

    private func handleSelfReinstallation(for installedApp: InstalledApp) {
        // Reinstalling ourself will hang until we leave the app, so we need to exit it without force closing
        Task.detached {
            try? await Task.sleep(nanoseconds: Self.selfInstallSuspendDelayNs)

            let handler = self.context.handler.installAppHandler
            guard handler.isAppInForeground else {
                self.debugLog("[InstallAppOperation] We are not in the foreground, let's not do anything")
                return
            }
                
            let delaySeconds = Self.selfInstallSuspendDelayNs / 1_000_000_000
            self.debugLog("[InstallAppOperation] We are still installing after \(delaySeconds) seconds")
            
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            switch settings.authorizationStatus {
                case .authorized, .ephemeral, .provisional:
                    self.verboseLog("[InstallAppOperation] Notifications are enabled")

                    let content = UNMutableNotificationContent()
                    content.title = "Refreshing..."
                    content.body = "SideStore will automatically move to the homescreen to finish refreshing!"
                    let notification = UNNotificationRequest(identifier: Bundle.Info.appbundleIdentifier + ".FinishRefreshNotification", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false))
                    try await UNUserNotificationCenter.current().add(notification)
                    
                    self.suspendToHomeScreen()

                default:
                    self.verboseLog("[InstallAppOperation] Notifications are not enabled")

                    handler.requestBackgroundSuspension {
                        self.suspendToHomeScreen()
                    }
                }
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
