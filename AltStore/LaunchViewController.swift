//
//  LaunchViewController.swift
//  AltStore
//
//  Created by Riley Testut on 7/30/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

@preconcurrency import UIKit

import SideSign
import UniformTypeIdentifiers
import CryptoKit

final class LaunchViewController: UIViewController {
    private var didFinishLaunching = false
    private var retries = 0
    private var maxRetries = 3
    private var splashView: SplashView!
    private var destinationViewController: TabBarController?
    private var startTime: Date!

    override func viewDidLoad() {
        super.viewDidLoad()
        debugLog("[LaunchViewController] viewDidLoad()")
        splashView = SplashView(frame: view.bounds, appName: "SideStore")
        destinationViewController = storyboard!.instantiateViewController(withIdentifier: "tabBarController") as? TabBarController
        view.addSubview(splashView)
    }

    override func viewDidAppear(_ animated: Bool) {
        debugLog("LaunchViewController.viewDidAppear() invoked")
        super.viewDidAppear(animated)
        guard !didFinishLaunching else { return }
        startTime = Date()
        splashView.updateStatus(NSLocalizedString("Starting…", comment: ""))
        
        // spin off the startup sequence concurrently
        Task.detached { [weak self] in
            await self?.runLaunchSequence()
        }
        Task.detached { [weak self] in
            await self?.doPostLaunch()
        }
    }

    private nonisolated func runLaunchSequence() async {
        guard await retries < maxRetries else { return }
        await MainActor.run{
            retries += 1
        }
        do {
            try await DatabaseManager.shared.start()
            await self.finishLaunching()
        } catch {
            await self.handleLaunchError(error, retryCallback: self.runLaunchSequence)
        }
    }

    private nonisolated func doPostLaunch() async {
        #if !targetEnvironment(simulator)
        await detectAndImportAccountFile()
        #endif
    }

    @MainActor
    func displayError(_ msg: String) {
        debugLog("[SideStore] \(msg)")
        let alert = UIAlertController(title: "Error launching SideStore", message: msg, preferredStyle: .alert)
        self.present(alert, animated: true)
    }
    
    func detectAndImportAccountFile() {
        let accountFileURL = FileManager.default.documentsDirectory.appendingPathComponent(AppConstants.accountConfigurationFileName)
        guard FileManager.default.fileExists(atPath: accountFileURL.path) else { return }
        guard let data = try? Data(contentsOf: accountFileURL) else { return }
        
        let checksum = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
        guard checksum != UserDefaults.standard.acctFileChecksum else {
            debugLog("[LaunchViewController] Skipping import for \(accountFileURL.lastPathComponent): checksum unchanged.")
            return
        }

        let alert = ImportAccountAlertController.make(data: data, checksum: checksum, presentingViewController: self)
        self.present(alert, animated: true)
    }

    @MainActor
    func handleLaunchError(_ error: Error, retryCallback: (() async -> Void)? = nil) {
        do { throw error } catch let error as NSError {
            let title = error.userInfo[NSLocalizedFailureErrorKey] as? String ?? NSLocalizedString("Unable to Launch SideStore", comment: "")
            let desc = ([error.debugDescription] + error.underlyingErrors.map { ($0 as NSError).debugDescription }).joined(separator: "\n\n")
            let alert = UIAlertController(title: title, message: desc, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("Retry", comment: ""), style: .default) { _ in
                Task { await retryCallback?() }
            })
            present(alert, animated: true)
        }
    }

    @MainActor
    func finishLaunching() async {
        guard !didFinishLaunching else { return }
        didFinishLaunching = true
        
        splashView.updateStatus(NSLocalizedString("Loading apps…", comment: ""))
        await AppManager.shared.reconcileInstalledApps()
        splashView.updateStatus(NSLocalizedString("Updating sources…", comment: ""))
        AppManager.shared.updateAllSources { result in
            guard case .failure(let error) = result else { return }
            debugLog("Failed to update sources on launch. \(error.localizedDescription)")
            
            
            let errorDesc = ErrorProcessing(.fullError).getDescription(error: error as NSError)
            debugLog("Failed to update sources on launch. \(errorDesc)")
            
            let toastView = ToastView(text: NSLocalizedString("Some sources were unable to load", comment: ""), detailText: nil)
            toastView.addTarget(self.destinationViewController, action: #selector(TabBarController.presentSources), for: .touchUpInside)
            toastView.show(in: self.destinationViewController!.selectedViewController ?? self.destinationViewController!)
        }
        updateKnownSources()
        splashView.updateStatus(NSLocalizedString("Almost there…", comment: ""))
        didFinishLaunching = true
        
        let destinationVC = destinationViewController!
        
        let elapsed = abs(startTime.timeIntervalSinceNow)
        let remaining = elapsed >= 1 ? 0 : 1 - elapsed
        try? await Task.sleep(nanoseconds: UInt64(remaining * 500_000_000))
        
        destinationVC.loadViewIfNeeded()
        addChild(destinationVC)
        destinationVC.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(destinationVC.view)
        destinationVC.didMove(toParent: self)
        
        // Pin edges BEFORE animation
        NSLayoutConstraint.activate([
            destinationVC.view.topAnchor.constraint(equalTo: view.topAnchor),
            destinationVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            destinationVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            destinationVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        // Set initial alpha for fade-in
        destinationVC.view.alpha = 0

        UIView.transition(with: view, duration: 0.3, options: .transitionCrossDissolve) { [self] in
            self.splashView.alpha = 0
            destinationVC.view.alpha = 1
        } completion: { [self] _ in
            debugLog("[LaunchViewController] Transition complete — exiting LaunchViewController, handing off to TabBarController")
            self.splashView.removeFromSuperview()
            self.destinationViewController = destinationVC
            
            Task.detached { @MainActor [weak self] in
                guard let self = self else { return }
                if AppBootManager.shared.needsPairingPrompt {
                    await AppBootManager.shared.promptForPairing(on: self)
                }
                
                if AppBootManager.shared.needsSideJITPrompt {
                    SideJITManager.shared.presentJITPrompt(presentingVC: self)
                }
            }
        }
    }

    func updateKnownSources() {
        AppManager.shared.updateKnownSources { result in
            switch result {
            case .failure(let error): debugLog("[SideStore] Failed to update known sources: \(error)")
            case .success((_, let blockedSources)):
                DatabaseManager.shared.persistentContainer.performBackgroundTask { context in
                    let blockedSourceIDs = Set(blockedSources.lazy.map { $0.identifier })
                    let blockedSourceURLs = Set(blockedSources.lazy.compactMap { $0.sourceURL })
                    let predicate = NSPredicate(format: "%K IN %@ OR %K IN %@", #keyPath(Source.identifier), blockedSourceIDs, #keyPath(Source.sourceURL), blockedSourceURLs)
                    let sourceErrors = Source.all(satisfying: predicate, in: context).map { source in
                        let blocked = blockedSources.first { $0.identifier == source.identifier }
                        return SourceError.blocked(source, bundleIDs: blocked?.bundleIDs, existingSource: source)
                    }
                    guard !sourceErrors.isEmpty else { return }
                    Task {
                        for error in sourceErrors {
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
