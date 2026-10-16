//
//  SceneDelegate.swift
//  AltStore
//
//  Created by Riley Testut on 7/6/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

@preconcurrency import UIKit


final class SceneDelegate: UIResponder, UIWindowSceneDelegate
{
    var window: UIWindow?

    // Holds an imported .ipa URL when the scene isn't active yet (cold launch),
    // so the import notification can be posted once the scene becomes active.
    private var pendingImportIPAURL: URL?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions)
    {
        debugLog("[SceneDelegate] scene(willConnectTo:) invoked")
        // Use this method to optionally configure and attach the UIWindow `window` to the provided UIWindowScene `scene`.
        // If using a storyboard, the `window` property will automatically be initialized and attached to the scene.
        // This delegate does not imply the connecting scene or session are new (see `application:configurationForConnectingSceneSession` instead).
        guard let _ = (scene as? UIWindowScene) else { return }
        
        if let context = connectionOptions.urlContexts.first
        {
            self.open(context)
        }
    }

    func sceneWillEnterForeground(_ scene: UIScene)
    {
        // Called as the scene transitions from the foreground to the background.
        // Use this method to undo the changes made on entering the background.
        
        // applicationWillEnterForeground is _not_ called when launching app,
        // whereas sceneWillEnterForeground _is_ called when launching.
        // As a result, DatabaseManager might not be started yet, so just return if it isn't
        // (since all these methods are called separately during app startup).
        guard DatabaseManager.shared.isStarted else { return }
        
        Task {
            await AppManager.shared.reconcileInstalledApps()
            await WidgetDataManager.publishCurrentInstalledAppsIfNeeded(in: DatabaseManager.shared.viewContext)
        }
    }

    func sceneDidBecomeActive(_ scene: UIScene)
    {
        debugLog("[SceneDelegate] sceneDidBecomeActive() invoked")
        defer {
            // dump sidebackup logs if any
            Task.detached { await AppDelegate.dumpSideBackupLogsIfNeeded() }
        }
        
        if DatabaseManager.shared.isStarted {
            Task {
                await WidgetDataManager.publishCurrentInstalledAppsIfNeeded(in: DatabaseManager.shared.viewContext)
            }
        }
        
        // Flush any .ipa import that arrived before the scene was active (cold launch).
        guard let url = self.pendingImportIPAURL else { return }
        self.pendingImportIPAURL = nil
        NotificationCenter.default.post(name: AppDelegate.importAppDeepLinkNotification, object: nil, userInfo: [AppDelegate.importAppDeepLinkURLKey: url])
    }

    func sceneDidEnterBackground(_ scene: UIScene)
    {
        // Called as the scene transitions from the foreground to the background.
        // Use this method to save data, release shared resources, and store enough scene-specific state information
        // to restore the scene back to its current state.
        
        guard UIApplication.shared.applicationState == .background else { return }
        
        // Make sure to update AppDelegate.applicationDidEnterBackground() as well.

        guard let oneMonthAgo = Calendar.current.date(byAdding: .month, value: -1, to: Date()) else { return }
        
        let midnightOneMonthAgo = Calendar.current.startOfDay(for: oneMonthAgo)
        Task.detached(priority: .background) {
            do
            {
                try await DatabaseManager.shared.purgeLoggedErrors(before: midnightOneMonthAgo)
            }
            catch
            {
                debugLog("[SideStore] Failed to purge logged errors before \(midnightOneMonthAgo). \(error)")
            }
        }
        
    }
    
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>)
    {
        guard let context = URLContexts.first else { return }
        debugLog("[SceneDelegate] scene(_:openURLContexts:) called with URL: \(context.url)")
        self.open(context)
    }
}

private extension SceneDelegate
{
    func open(_ context: UIOpenURLContext)
    {
        debugLog("[SceneDelegate] open(_:) called with URL: \(context.url)")
        if context.url.isFileURL
        {
            guard context.url.pathExtension.lowercased() == "ipa" else { return }

            // Copy the shared .ipa out of its security-scoped location into a
            // temporary directory we own, so it stays readable while signing.
            if !context.url.startAccessingSecurityScopedResource() {
                debugLog("[SideStore] Failed to access security-scoped resource for imported IPA")
                return
            }
            defer { context.url.stopAccessingSecurityScopedResource() }

            let temporaryDirectory = FileManager.default.uniqueTemporaryURL()
            do {
                try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true, attributes: nil)
            } catch {
                debugLog("[SideStore] Failed to create temp directory for imported IPA: \(error)")
                return
            }

            let ipa = temporaryDirectory.appendingPathComponent(context.url.lastPathComponent)

            do {
                try FileManager.default.copyItem(at: context.url, to: ipa)
            } catch {
                debugLog("[SideStore] Failed to copy imported IPA: \(error)")
                return
            }

            if UIApplication.shared.applicationState == .active {
                NotificationCenter.default.post(name: AppDelegate.importAppDeepLinkNotification, object: nil, userInfo: [AppDelegate.importAppDeepLinkURLKey: ipa])
            } else {
                // Defer until the scene is active (cold launch) — see sceneDidBecomeActive.
                self.pendingImportIPAURL = ipa
            }
        }
        else
        {
            URLHandler.shared.handle(context.url)
        }
    }
}


func exportPairingFile(_ urlname: String) {
    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
       let window = windowScene.windows.first, let viewcontroller = window.rootViewController {
        let fm = FileManager.default
        let documentsPath = fm.documentsDirectory.appendingPathComponent("ALTPairingFile.mobiledevicepairing")
        
        
        guard let data = try? Data(contentsOf: documentsPath) else {
            let toastView = ToastView(text: NSLocalizedString("Failed to find Pairing File!", comment: ""), detailText: nil)
            toastView.show(in: viewcontroller)
            return
        }
        
        let base64encodedCert = data.base64EncodedString()
        var allowedQueryParamAndKey = NSCharacterSet.urlQueryAllowed
        allowedQueryParamAndKey.remove(charactersIn: ";/?:@&=+$, ")
        guard let encodedCert = base64encodedCert.addingPercentEncoding(withAllowedCharacters: allowedQueryParamAndKey) else {
            let toastView = ToastView(text: NSLocalizedString("Failed to encode pairingFile!", comment: ""), detailText: nil)
            toastView.show(in: viewcontroller)
            return
        }
        
        let urlStr = "\(urlname)://pairingFile?data=$(BASE64_PAIRING)"
        let finished = urlStr.replacingOccurrences(of: "$(BASE64_PAIRING)", with: encodedCert, options: .literal, range: nil)
        
        debugLog(finished)
        guard let callbackUrl = URL(string: finished) else {
            let toastView = ToastView(text: NSLocalizedString("Failed to initialize callback URL!", comment: ""), detailText: nil)
            toastView.show(in: viewcontroller)
            return
        }
        UIApplication.shared.open(callbackUrl)
    }
}
