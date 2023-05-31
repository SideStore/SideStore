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
import AltStoreCore
import Roxas
import minimuxer

@objc(InstallAppOperation)
final class InstallAppOperation: ResultOperation<InstalledApp>
{
    let context: InstallAppOperationContext
    
    private var didCleanUp = false
    
    init(context: InstallAppOperationContext)
    {
        self.context = context
        
        super.init()
        
        self.progress.totalUnitCount = 100
    }
    
    override func main()
    {
        super.main()
        
        if let error = self.context.error
        {
            self.finish(.failure(error))
            return
        }
        
        guard
            let certificate = self.context.certificate,
            let resignedApp = self.context.resignedApp
        else { return self.finish(.failure(OperationError.invalidParameters)) }
        
        let backgroundContext = DatabaseManager.shared.persistentContainer.newBackgroundContext()
        backgroundContext.perform
        {
            /* App */
            let installedApp: InstalledApp
            
            // Fetch + update rather than insert + resolve merge conflicts to prevent potential context-level conflicts.
            if let app = InstalledApp.first(satisfying: NSPredicate(format: "%K == %@", #keyPath(InstalledApp.bundleIdentifier), self.context.bundleIdentifier), in: backgroundContext)
            {
                installedApp = app
            }
            else
            {
                installedApp = InstalledApp(resignedApp: resignedApp, originalBundleIdentifier: self.context.bundleIdentifier, certificateSerialNumber: certificate.serialNumber, context: backgroundContext)
            }
            
            installedApp.update(resignedApp: resignedApp, certificateSerialNumber: certificate.serialNumber)
            installedApp.needsResign = false
            
            if let team = DatabaseManager.shared.activeTeam(in: backgroundContext)
            {
                installedApp.team = team
            }
            
            /* App Extensions */
            var installedExtensions = Set<InstalledExtension>()
            
            if
                let bundle = Bundle(url: resignedApp.fileURL),
                let directory = bundle.builtInPlugInsURL,
                let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil, options: [.skipsSubdirectoryDescendants])
            {
                for case let fileURL as URL in enumerator
                {
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
                    
                    if let appExtension = installedApp.appExtensions.first(where: { $0.bundleIdentifier == originalBundleID })
                    {
                        installedExtension = appExtension
                    }
                    else
                    {
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
            if let sideloadedAppsLimit = UserDefaults.standard.activeAppsLimit
            {
                // When installing these new profiles, AltServer will remove all non-active profiles to ensure we remain under limit.
                
                let fetchRequest = InstalledApp.activeAppsFetchRequest()
                fetchRequest.includesPendingChanges = false
                
                var activeApps = InstalledApp.fetch(fetchRequest, in: backgroundContext)
                if !activeApps.contains(installedApp)
                {
                    let activeAppsCount = activeApps.map { $0.requiredActiveSlots }.reduce(0, +)
                    
                    let availableActiveApps = max(sideloadedAppsLimit - activeAppsCount, 0)
                    if installedApp.requiredActiveSlots <= availableActiveApps
                    {
                        // This app has not been explicitly activated, but there are enough slots available,
                        // so implicitly activate it.
                        installedApp.isActive = true
                        activeApps.append(installedApp)
                    }
                    else
                    {
                        installedApp.isActive = false
                    }
                }
                
                activeProfiles = Set(activeApps.flatMap
                { installedApp -> [String] in
                    let appExtensionProfiles = installedApp.appExtensions.map { $0.resignedBundleIdentifier }
                    return [installedApp.resignedBundleIdentifier] + appExtensionProfiles
                })
            }
            
            var installing = true
            if installedApp.storeApp?.bundleIdentifier == Bundle.Info.appbundleIdentifier {
                // Reinstalling ourself will hang until we leave the app, so we need to exit it without force closing
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    if UIApplication.shared.applicationState != .active {
                        print("We are not in the foreground, let's not do anything")
                        return
                    }
                    if !installing {
                        print("Installing finished")
                        return
                    }
                    print("We are still installing after 3 seconds")
                    
                    UNUserNotificationCenter.current().getNotificationSettings { settings in
                        switch (settings.authorizationStatus) {
                        case .authorized, .ephemeral, .provisional:
                            print("Notifications are enabled")
                            
                            let content = UNMutableNotificationContent()
                            content.title = "Refreshing..."
                            content.body = "To finish refreshing, SideStore must be moved to the background, which it does by opening Safari. Please reopen SideStore after it is done refreshing!"
                            let notification = UNNotificationRequest(identifier: Bundle.Info.appbundleIdentifier + ".FinishRefreshNotification", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false))
                            UNUserNotificationCenter.current().add(notification)
                            
                            DispatchQueue.main.async { UIApplication.shared.open(URL(string: "x-web-search://")!) }
                            
                            break
                        default:
                            print("Notifications are not enabled")
                            
                            let alert = UIAlertController(title: "Finish Refresh", message: "To finish refreshing, SideStore must be moved to the background. To do this, you can either go to the Home Screen or open Safari by pressing Continue. Please reopen SideStore after doing this.", preferredStyle: .alert)
                            alert.addAction(UIAlertAction(title: NSLocalizedString("Continue", comment: ""), style: .default, handler: { _ in
                                print("Opening Safari")
                                DispatchQueue.main.async { UIApplication.shared.open(URL(string: "x-web-search://")!) }
                            }))
                            
                            DispatchQueue.main.async {
                                let keyWindow = UIApplication.shared.windows.filter { $0.isKeyWindow }.first
                                if var topController = keyWindow?.rootViewController {
                                    while let presentedViewController = topController.presentedViewController {
                                        topController = presentedViewController
                                    }
                                    topController.present(alert, animated: true)
                                } else {
                                    print("No key window? Let's just open Safari")
                                    UIApplication.shared.open(URL(string: "x-web-search://")!)
                                }
                            }
                            
                            break
                        }
                    }
                }
            }
            
            let res = minimuxer_install_ipa(ns_bundle_ptr)
            if res == 0
            {
                installedApp.refreshedDate = Date()
                self.finish(.success(installedApp))
            }
            else if res == -15
            {
                // try again
                if UserDefaults.standard.enableCowExploit && UserDefaults.standard.isCowExploitSupported
                {
                    patch3AppLimit
                    { result in
                        switch result
                        {
                        case .success:
                            UserDefaults.standard.set(bootTime(), forKey: "cowExploitRanBootTime")
                            print("patched sucessfully")
                        case .failure(let err):
                            switch err
                            {
                            case .NoFDA:
                                self.finish(.failure(OperationError.cowExploitNoFDA))
                                return
                            case .FailedPatchd:
                                self.finish(.failure(OperationError.cowExploitFailedPatchd))
                                return
                            }
                        }
                    }
                    
                    let res_try_again = minimuxer_install_ipa(ns_bundle_ptr)
                    if res_try_again == 0
                    {
                        installedApp.refreshedDate = Date()
                        self.finish(.success(installedApp))
                    }
                    else
                    {
                        self.finish(.failure(minimuxer_to_operation(code: res_try_again)))
                    }
                }
            }
            else
            {
                self.finish(.failure(minimuxer_to_operation(code: res)))
            do {
                try install_ipa(installedApp.bundleIdentifier)
                installing = false
            } catch {
                installing = false
                return self.finish(.failure(error))
            }
            
            installedApp.refreshedDate = Date()
            self.finish(.success(installedApp))
        }
    }
    
    override func finish(_ result: Result<InstalledApp, Error>)
    {
        self.cleanUp()
        
        // Only remove refreshed IPA when finished.
        if let app = self.context.app
        {
            let fileURL = InstalledApp.refreshedIPAURL(for: app)
            
            do
            {
                try FileManager.default.removeItem(at: fileURL)
                print("Removed refreshed IPA")
            }
            catch
            {
                print("Failed to remove refreshed .ipa: \(error)")
            }
        }
        
        super.finish(result)
    }
}

private extension InstallAppOperation
{
    func cleanUp()
    {
        guard !self.didCleanUp else { return }
        self.didCleanUp = true
        
        do
        {
            try FileManager.default.removeItem(at: self.context.temporaryDirectory)
        }
        catch
        {
            print("Failed to remove temporary directory.", error)
        }
    }
}
