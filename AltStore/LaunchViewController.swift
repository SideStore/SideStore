//
//  LaunchViewController.swift
//  AltStore
//
//  Created by Riley Testut on 7/30/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import EmotionalDamage
import minimuxer
import Roxas
import UIKit

import AltStoreCore
import UniformTypeIdentifiers

final class LaunchViewController: RSTLaunchViewController, UIDocumentPickerDelegate {
let pairingFileName = "ALTPairingFile.mobiledevicepairing"

final class LaunchViewController: RSTLaunchViewController, UIDocumentPickerDelegate
{
    private var didFinishLaunching = false
    
    private var destinationViewController: UIViewController!
    
    override var launchConditions: [RSTLaunchCondition] {
        let isDatabaseStarted = RSTLaunchCondition(condition: { DatabaseManager.shared.isStarted }) { completionHandler in
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
    
    override func viewDidLoad() {
        defer {
            // Create destinationViewController now so view controllers can register for receiving Notifications.
            self.destinationViewController = self.storyboard!.instantiateViewController(withIdentifier: "tabBarController") as! TabBarController
        }
        super.viewDidLoad()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(true)
        #if !targetEnvironment(simulator)
        start_em_proxy(bind_addr: Consts.Proxy.serverURL)

        guard let pf = fetchPairingFile() else {
            self.displayError("Device pairing file not found.")
            return
        }
        
        self.start_minimuxer_threads(pf)
        #endif
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
            !contents.isEmpty
        {
            print("Loaded ALTPairingFile from \(appResourcePath.path)")
            return contents
        } else if let plistString = Bundle.main.object(forInfoDictionaryKey: "ALTPairingFile") as? String, !plistString.isEmpty, !plistString.contains("insert pairing file here") {
            print("Loaded ALTPairingFile from Info.plist")
            return plistString
        } else {
            // Show an alert explaining the pairing file
            // Create new Alert
            let dialogMessage = UIAlertController(title: "Pairing File", message: "Select the pairing file for your device. For more information, go to https://wiki.sidestore.io/guides/install#pairing-process", preferredStyle: .alert)
            
            // Create OK button with action handler
            let ok = UIAlertAction(title: "OK", style: .default, handler: { _ in
                // Try to load it from a file picker
                var types = UTType.types(tag: "plist", tagClass: UTTagClass.filenameExtension, conformingTo: nil)
                types.append(contentsOf: UTType.types(tag: "mobiledevicepairing", tagClass: UTTagClass.filenameExtension, conformingTo: UTType.data))
                types.append(.xml)
                let documentPickerController = UIDocumentPickerViewController(forOpeningContentTypes: types)
//                documentPickerController.shouldShowFileExtensions = true
                documentPickerController.delegate = self
                self.present(documentPickerController, animated: true, completion: nil)
            })
            
            // Add OK button to a dialog message
            dialogMessage.addAction(ok)

            // Present Alert to
            self.present(dialogMessage, animated: true, completion: nil)

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
                self.displayError("Unable to read pairing file")
            }
            
            // Save to a file for next launch
            let pairingFile = FileManager.default.documentsDirectory.appendingPathComponent("\(pairingFileName)")
            try pairing_string?.write(to: pairingFile, atomically: true, encoding: String.Encoding.utf8)
            
            // Start minimuxer now that we have a file
            start_minimuxer_threads(pairing_string!)
        } catch {
            self.displayError("Unable to read pairing file")
        }
        
        if isSecuredURL {
            url.stopAccessingSecurityScopedResource()
        }
        controller.dismiss(animated: true, completion: nil)
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        self.displayError("Choosing a pairing file was cancelled. Please re-open the app and try again.")
    }
    
    func start_minimuxer_threads(_ pairing_file: String) {
        set_usbmuxd_socket()
        #if false // Retries
        var res = start_minimuxer(pairing_file: pairing_file)
        var attempts = 10
        while attempts != 0, res != 0 {
            print("start_minimuxer `res` != 0, retry #\(attempts)")
            res = start_minimuxer(pairing_file: pairing_file)
            attempts -= 1
        }
        #else
        let res = start_minimuxer(pairing_file: pairing_file)
        #endif
        if res != 0 {
            self.displayError("minimuxer failed to start. Incorrect arguments were passed.")
        target_minimuxer_address()
        let documentsDirectory = FileManager.default.documentsDirectory.absoluteString
        do {
            try start(pairing_file, documentsDirectory)
        } catch {
            try! FileManager.default.removeItem(at: FileManager.default.documentsDirectory.appendingPathComponent("\(pairingFileName)"))
            displayError("minimuxer failed to start, please restart SideStore. \((error as? LocalizedError)?.failureReason ?? "UNKNOWN ERROR!!!!!! REPORT TO GITHUB ISSUES!")")
        }
        start_auto_mounter(documentsDirectory)
    }
}

extension LaunchViewController {
    override func handleLaunchError(_ error: Error) {
        do {
            throw error
        } catch let error as NSError {
            let title = error.userInfo[NSLocalizedFailureErrorKey] as? String ?? NSLocalizedString("Unable to Launch SideStore", comment: "")
            
            let errorDescription: String
            
            if #available(iOS 14.5, *) {
                let errorMessages = [error.debugDescription] + error.underlyingErrors.map { ($0 as NSError).debugDescription }
                errorDescription = errorMessages.joined(separator: "\n\n")
            } else {
                errorDescription = error.debugDescription
            }
            
            let alertController = UIAlertController(title: title, message: errorDescription, preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: NSLocalizedString("Retry", comment: ""), style: .default, handler: { _ in
                self.handleLaunchConditions()
            }))
            self.present(alertController, animated: true, completion: nil)
        }
    }
    
    override func finishLaunching() {
        super.finishLaunching()
        
        guard !self.didFinishLaunching else { return }
        
        AppManager.shared.update()
        AppManager.shared.updatePatronsIfNeeded()
        PatreonAPI.shared.refreshPatreonAccount()
        
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
        
        if UserDefaults.standard.enableCowExploit, UserDefaults.standard.isCowExploitSupported {
            if let previous_exploit_time = UserDefaults.standard.object(forKey: "cowExploitRanBootTime") {
                let last_rantime = previous_exploit_time as! Date
                if last_rantime == bootTime() {
                    return print("exploit has ran this boot - \(last_rantime)")
                }
            }
            self.runExploit()
        }
        
        self.didFinishLaunching = true
    }
    
    func runExploit() {
        if UserDefaults.standard.enableCowExploit && UserDefaults.standard.isCowExploitSupported {
            patch3AppLimit { result in
                switch result {
                case .success:
                    UserDefaults.standard.set(bootTime(), forKey: "cowExploitRanBootTime")
                    print("patched sucessfully")
                case .failure(let err):
                    switch err {
                    case .NoFDA(let msg):
                        self.displayError("Failed to get full disk access: \(msg)")
                        return
                    case .FailedPatchd:
                        self.displayError("Failed to install patchd.")
                        return
                    }
                }
            }
        }
    }
}
