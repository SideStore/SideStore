//
//  LaunchViewController.swift
//  AltStore
//
//  Created by Riley Testut on 7/30/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit
import Roxas
import EmotionalDamage
import minimuxer
import WidgetKit

import AltStoreCore
import UniformTypeIdentifiers

let pairingFileName = "ALTPairingFile.mobiledevicepairing"

final class LaunchViewController: RSTLaunchViewController, UIDocumentPickerDelegate
{
    private var didFinishLaunching = false
    
    private var destinationViewController: UIViewController!
    
    override var launchConditions: [RSTLaunchCondition] {
        let isDatabaseStarted = RSTLaunchCondition(condition: { DatabaseManager.shared.isStarted }) { (completionHandler) in
            DatabaseManager.shared.start(completionHandler: completionHandler)
        }

        return [isDatabaseStarted]
    }
    
    override var childForStatusBarStyle: UIViewController? {
        return self.children.first
    }
    
    override var childForStatusBarHidden: UIViewController? {
        return self.children.first
    }
    
    override func viewDidLoad()
    {
        defer {
            // Create destinationViewController now so view controllers can register for receiving Notifications.
            self.destinationViewController = self.storyboard!.instantiateViewController(withIdentifier: "tabBarController") as! TabBarController
        }
        super.viewDidLoad()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(true)
        if #available(iOS 17, *), !UserDefaults.standard.sidejitenable {
            DispatchQueue.global().async {
                self.isSideJITServerDetected() { result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success():
                            let dialogMessage = UIAlertController(title: "SideJITServer Detected", message: "Would you like to enable SideJITServer", preferredStyle: .alert)
                            
                            // Create OK button with action handler
                            let ok = UIAlertAction(title: "OK", style: .default, handler: { (action) -> Void in
                                UserDefaults.standard.sidejitenable = true
                            })
                            
                            let cancel = UIAlertAction(title: "Cancel", style: .cancel)
                            //Add OK button to a dialog message
                            dialogMessage.addAction(ok)
                            dialogMessage.addAction(cancel)
                            
                            // Present Alert to
                            self.present(dialogMessage, animated: true, completion: nil)
                        case .failure(_):
                            print("Cannot find sideJITServer")
                        }
                    }
                }
            }
        }
        
        if #available(iOS 17, *), UserDefaults.standard.sidejitenable {
            DispatchQueue.global().async {
                self.askfornetwork()
            }
            print("SideJITServer Enabled")
        }
        
        
        
        #if !targetEnvironment(simulator)
        start_em_proxy(bind_addr: Consts.Proxy.serverURL)
        
        guard let pf = fetchPairingFile() else {
            displayError("Device pairing file not found.")
            return
        }
        start_minimuxer_threads(pf)
        #endif
    }
    
    func askfornetwork() {
        let address = UserDefaults.standard.textInputSideJITServerurl ?? ""
        
        var SJSURL = address
        
        if (UserDefaults.standard.textInputSideJITServerurl ?? "").isEmpty {
          SJSURL = "http://sidejitserver._http._tcp.local:8080"
        }
        
        // Create a network operation at launch to Refresh SideJITServer
        let url = URL(string: "\(SJSURL)/re/")!
        let task = URLSession.shared.dataTask(with: url) { (data, response, error) in
            print(data)
        }
        task.resume()
    }
    
    func isSideJITServerDetected(completion: @escaping (Result<Void, Error>) -> Void) {
        let address = UserDefaults.standard.textInputSideJITServerurl ?? ""
        
        var SJSURL = address
        
        if (UserDefaults.standard.textInputSideJITServerurl ?? "").isEmpty {
          SJSURL = "http://sidejitserver._http._tcp.local:8080"
        }
        
        // Create a network operation at launch to Refresh SideJITServer
        let url = URL(string: SJSURL)!
        let task = URLSession.shared.dataTask(with: url) { (data, response, error) in
            if let error = error {
                print("No SideJITServer on Network")
                completion(.failure(error))
                return
            }
            completion(.success(()))
        }
        task.resume()
        return
    }
    
    func fetchPairingFile() -> String? {
        let filename = "ALTPairingFile.mobiledevicepairing"
        let fm = FileManager.default
        let documentsPath = fm.documentsDirectory.appendingPathComponent("/\(filename)")
        if fm.fileExists(atPath: documentsPath.path), let contents = try? String(contentsOf: documentsPath), !contents.isEmpty {
            print("Loaded ALTPairingFile from \(documentsPath.path)")
            return contents
        } else if
            let appResourcePath = Bundle.main.url(forResource: "ALTPairingFile", withExtension: "mobiledevicepairing"),
            fm.fileExists(atPath: appResourcePath.path),
            let data = fm.contents(atPath: appResourcePath.path),
            let contents = String(data: data, encoding: .utf8),
            !contents.isEmpty,
            !UserDefaults.standard.isPairingReset {
            print("Loaded ALTPairingFile from \(appResourcePath.path)")
            return contents
        } else if let plistString = Bundle.main.object(forInfoDictionaryKey: "ALTPairingFile") as? String, !plistString.isEmpty, !plistString.contains("insert pairing file here"), !UserDefaults.standard.isPairingReset{
            print("Loaded ALTPairingFile from Info.plist")
            return plistString
        } else {
            // Show an alert explaining the pairing file
            // Create new Alert
            let dialogMessage = UIAlertController(title: "Pairing File", message: "Select the pairing file or select \"Help\" for help.", preferredStyle: .alert)
            
            // Create OK button with action handler
            let ok = UIAlertAction(title: "OK", style: .default, handler: { (action) -> Void in
                // Try to load it from a file picker
                var types = UTType.types(tag: "plist", tagClass: UTTagClass.filenameExtension, conformingTo: nil)
                types.append(contentsOf: UTType.types(tag: "mobiledevicepairing", tagClass: UTTagClass.filenameExtension, conformingTo: UTType.data))
                types.append(.xml)
                let documentPickerController = UIDocumentPickerViewController(forOpeningContentTypes: types)
                documentPickerController.shouldShowFileExtensions = true
                documentPickerController.delegate = self
                self.present(documentPickerController, animated: true, completion: nil)
                UserDefaults.standard.isPairingReset = false
             })
            
            //Add "help" button to take user to wiki
            let wikiOption = UIAlertAction(title: "Help", style: .default) { (action) in
                let wikiURL: String = "https://docs.sidestore.io/docs/getting-started/pairing-file"
                if let url = URL(string: wikiURL) {
                    UIApplication.shared.open(url)
                }
                sleep(2)
                exit(0)
            }
            
            //Add buttons to dialog message
            dialogMessage.addAction(wikiOption)
            dialogMessage.addAction(ok)

            // Present Alert to
            self.present(dialogMessage, animated: true, completion: nil)

            let dialogMessage2 = UIAlertController(title: "Analytics", message: "This app contains anonymous analytics for research and project development. By continuing to use this app, you are consenting to this data collection", preferredStyle: .alert)

            let ok2 = UIAlertAction(title: "OK", style: .default, handler: { (action) -> Void in})
            
            dialogMessage2.addAction(ok2)
            self.present(dialogMessage2, animated: true, completion: nil)

            return nil
        }
    }

    func displayError(_ msg: String) {
        print(msg)
        // Create a new alert
        let dialogMessage = UIAlertController(title: "Error launching SideStore", message: msg, preferredStyle: .alert)

        // Present alert to user
        self.present(dialogMessage, animated: true, completion: nil)
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let url = urls[0]
        let isSecuredURL = url.startAccessingSecurityScopedResource() == true

        do {
            // Read to a string
            let data1 = try Data(contentsOf: urls[0])
            let pairing_string = String(bytes: data1, encoding: .utf8)
            if pairing_string == nil {
                displayError("Unable to read pairing file")
            }
            
            // Save to a file for next launch
            let pairingFile = FileManager.default.documentsDirectory.appendingPathComponent("\(pairingFileName)")
            try pairing_string?.write(to: pairingFile, atomically: true, encoding: String.Encoding.utf8)
            
            // Start minimuxer now that we have a file
            start_minimuxer_threads(pairing_string!)
        } catch {
            displayError("Unable to read pairing file")
        }
        
        if (isSecuredURL) {
            url.stopAccessingSecurityScopedResource()
        }
        controller.dismiss(animated: true, completion: nil)
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        displayError("Choosing a pairing file was cancelled. Please re-open the app and try again.")
    }
    
    func start_minimuxer_threads(_ pairing_file: String) {
        target_minimuxer_address()
        let documentsDirectory = FileManager.default.documentsDirectory.absoluteString
        do {
            try start(pairing_file, documentsDirectory)
        } catch {
            try! FileManager.default.removeItem(at: FileManager.default.documentsDirectory.appendingPathComponent("\(pairingFileName)"))
            displayError("minimuxer failed to start, please restart SideStore. \((error as? LocalizedError)?.failureReason ?? "UNKNOWN ERROR!!!!!! REPORT TO GITHUB ISSUES!")")
        }
        if #available(iOS 17, *) {
            // TODO: iOS 17 and above have a new JIT implementation that is completely broken in SideStore :(
        }
        else {
            start_auto_mounter(documentsDirectory)
        }
    }
}

extension LaunchViewController
{
    override func handleLaunchError(_ error: Error)
    {
        do
        {
            throw error
        }
        catch let error as NSError
        {
            let title = error.userInfo[NSLocalizedFailureErrorKey] as? String ?? NSLocalizedString("Unable to Launch SideStore", comment: "")
            
            let errorDescription: String
            
            if #available(iOS 14.5, *)
            {
                let errorMessages = [error.debugDescription] + error.underlyingErrors.map { ($0 as NSError).debugDescription }
                errorDescription = errorMessages.joined(separator: "\n\n")
            }
            else
            {
                errorDescription = error.debugDescription
            }
            
            let alertController = UIAlertController(title: title, message: errorDescription, preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: NSLocalizedString("Retry", comment: ""), style: .default, handler: { (action) in
                self.handleLaunchConditions()
            }))
            self.present(alertController, animated: true, completion: nil)
        }
    }
    
    override func finishLaunching()
    {
        super.finishLaunching()
        
        guard !self.didFinishLaunching else { return }
        
        AppManager.shared.update()
        AppManager.shared.updatePatronsIfNeeded()
        PatreonAPI.shared.refreshPatreonAccount()
        
        AppManager.shared.updateAllSources { result in
            guard case .failure(let error) = result else { return }
            Logger.main.error("Failed to update sources on launch. \(error.localizedDescription, privacy: .public)")
        }
        
        self.updateKnownSources()
        
        WidgetCenter.shared.reloadAllTimelines()
        
        // Add view controller as child (rather than presenting modally)
        // so tint adjustment + card presentations works correctly.
        self.destinationViewController.view.frame = CGRect(x: 0, y: 0, width: self.view.bounds.width, height: self.view.bounds.height)
        self.destinationViewController.view.alpha = 0.0
        self.addChild(self.destinationViewController)
        self.view.addSubview(self.destinationViewController.view, pinningEdgesWith: .zero)
        self.destinationViewController.didMove(toParent: self)
        
        UIView.animate(withDuration: 0.2) {
            self.destinationViewController.view.alpha = 1.0
        }
        
        self.didFinishLaunching = true
    }
}

private extension LaunchViewController
{
    func updateKnownSources()
    {
        AppManager.shared.updateKnownSources { result in
            switch result
            {
            case .failure(let error): print("[ALTLog] Failed to update known sources:", error)
            case .success((_, let blockedSources)):
                DatabaseManager.shared.persistentContainer.performBackgroundTask { context in
                    let blockedSourceIDs = Set(blockedSources.lazy.map { $0.identifier })
                    let blockedSourceURLs = Set(blockedSources.lazy.compactMap { $0.sourceURL })
                    
                    let predicate = NSPredicate(format: "%K IN %@ OR %K IN %@",
                                                #keyPath(Source.identifier), blockedSourceIDs,
                                                #keyPath(Source.sourceURL), blockedSourceURLs)
                    
                    let sourceErrors = Source.all(satisfying: predicate, in: context).map { (source) in
                        let blockedSource = blockedSources.first { $0.identifier == source.identifier }
                        return SourceError.blocked(source, bundleIDs: blockedSource?.bundleIDs, existingSource: source)
                    }
                    
                    guard !sourceErrors.isEmpty else { return }
                                        
                    Task {
                        for error in sourceErrors
                        {
                            let title = String(format: NSLocalizedString("“%@” Blocked", comment: ""), error.$source.name)
                            let message = [error.localizedDescription, error.recoverySuggestion].compactMap { $0 }.joined(separator: "\n\n")
                            
                            await self.presentAlert(title: title, message: message)
                        }
                    }
                }
            }
        }
    }
}
