//
//  InstallAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 6/19/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//
import Foundation
import Network

import AltSign
import SideStoreCore
import RoxasUIKit
import MiniMuxer
import minimuxer
import os.log

@objc(InstallAppOperation)
final class InstallAppOperation: ResultOperation<InstalledApp> {
    let context: InstallAppOperationContext

    private var didCleanUp = false

    init(context: InstallAppOperationContext) {
        self.context = context

        super.init()

        progress.totalUnitCount = 100
    }

    override func main() {
        super.main()

        if let error = context.error {
            finish(.failure(error))
            return
        }

        guard
            let certificate = context.certificate,
            let resignedApp = context.resignedApp
        else { return finish(.failure(OperationError.invalidParameters)) }

        let backgroundContext = DatabaseManager.shared.persistentContainer.newBackgroundContext()
        backgroundContext.perform {
            /* App */
            let installedApp: InstalledApp

            // Fetch + update rather than insert + resolve merge conflicts to prevent potential context-level conflicts.
            if let app = InstalledApp.first(satisfying: NSPredicate(format: "%K == %@", #keyPath(InstalledApp.bundleIdentifier), self.context.bundleIdentifier), in: backgroundContext) {
                installedApp = app
            } else {
                installedApp = InstalledApp(resignedApp: resignedApp, originalBundleIdentifier: self.context.bundleIdentifier, certificateSerialNumber: certificate.serialNumber, context: backgroundContext)
            }

            installedApp.update(resignedApp: resignedApp, certificateSerialNumber: certificate.serialNumber)
            installedApp.needsResign = false

            if let team = DatabaseManager.shared.activeTeam(in: backgroundContext) {
                installedApp.team = team
            }

            /* App Extensions */
            var installedExtensions = Set<InstalledExtension>()

            if
                let bundle = Bundle(url: resignedApp.fileURL),
                let directory = bundle.builtInPlugInsURL,
                let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil, options: [.skipsSubdirectoryDescendants])
            {
                for case let fileURL as URL in enumerator {
                    guard let appExtensionBundle = Bundle(url: fileURL) else { continue }
                    guard let appExtension = ALTApplication(fileURL: appExtensionBundle.bundleURL) else { continue }

                    let parentBundleID = self.context.bundleIdentifier
                    let resignedParentBundleID = resignedApp.bundleIdentifier

                    let resignedBundleID = appExtension.bundleIdentifier
                    let originalBundleID = resignedBundleID.replacingOccurrences(of: resignedParentBundleID, with: parentBundleID)

                    print("`parentBundleID`: \(parentBundleID)")
                    print("`resignedParentBundleID`: \(resignedParentBundleID)")
                    print("`resignedBundleID`: \(resignedBundleID)")
                    print("`originalBundleID`: \(originalBundleID)")

                    let installedExtension: InstalledExtension

                    if let appExtension = installedApp.appExtensions.first(where: { $0.bundleIdentifier == originalBundleID }) {
                        installedExtension = appExtension
                    } else {
                        installedExtension = InstalledExtension(resignedAppExtension: appExtension, originalBundleIdentifier: originalBundleID, context: backgroundContext)
                    }

                    installedExtension.update(resignedAppExtension: appExtension)

                    installedExtensions.insert(installedExtension)
                }
            }

            installedApp.appExtensions = installedExtensions

            self.context.beginInstallationHandler?(installedApp)

            // Temporary directory and resigned .ipa no longer needed, so delete them now to ensure AltStore doesn't quit before we get the chance to.
            self.cleanUp()

            var activeProfiles: Set<String>?
            if let sideloadedAppsLimit = UserDefaults.standard.activeAppsLimit {
                // When installing these new profiles, AltServer will remove all non-active profiles to ensure we remain under limit.

                let fetchRequest = InstalledApp.activeAppsFetchRequest()
                fetchRequest.includesPendingChanges = false

                var activeApps = InstalledApp.fetch(fetchRequest, in: backgroundContext)
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

                activeProfiles = Set(activeApps.flatMap { installedApp -> [String] in
                    let appExtensionProfiles = installedApp.appExtensions.map { $0.resignedBundleIdentifier }
                    return [installedApp.resignedBundleIdentifier] + appExtensionProfiles
                })
            }

            let ns_bundle = NSString(string: installedApp.bundleIdentifier)
            let ns_bundle_ptr = UnsafeMutablePointer<CChar>(mutating: ns_bundle.utf8String)

            let res = minimuxer_install_ipa(ns_bundle_ptr)
            if res == 0 {
                installedApp.refreshedDate = Date()
                self.finish(.success(installedApp))

            } else {
                self.finish(.failure(minimuxer_to_operation(code: res)))
            }
        }
    }

    override func finish(_ result: Result<InstalledApp, Error>) {
        cleanUp()

        // Only remove refreshed IPA when finished.
        if let app = context.app {
            let fileURL = InstalledApp.refreshedIPAURL(for: app)

            do {
                try FileManager.default.removeItem(at: fileURL)
            } catch {
                os_log("Failed to remove refreshed .ipa: %@", type: .error , error.localizedDescription)
            }
        }

        super.finish(result)
    }
}

private extension InstallAppOperation {
    func cleanUp() {
        guard !didCleanUp else { return }
        didCleanUp = true

        do {
            try FileManager.default.removeItem(at: context.temporaryDirectory)
        } catch {
            os_log("Failed to remove temporary directory. %@", type: .error , error.localizedDescription)
        }
    }
}
