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
import SwiftUI

final class LaunchViewController: UIViewController {
    private var didFinishLaunching = false
    private var retries = 0
    private var maxRetries = 3
    private var splashViewModel = SplashViewModel()
    private var destinationViewController: TabBarController?

    override func viewDidLoad() {
        super.viewDidLoad()
        debugLog("[LaunchViewController] viewDidLoad()")
        destinationViewController = storyboard!.instantiateViewController(withIdentifier: "tabBarController") as? TabBarController

        #if !os(tvOS)
            if !UserDefaults.standard.hasCompletedOnboarding {
                let hostingController = UIHostingController(rootView: OnboardingView { [weak self] in
                    Task { @MainActor in
                        self?.transitionToMainInterface()
                    }
                })
                embed(child: hostingController)
                return
            }
        #endif

        view.backgroundColor = .black
        let splashHosting = UIHostingController(rootView: SplashView(viewModel: splashViewModel) { [weak self] in
            self?.transitionToMainInterface()
        })
        splashHosting.view.backgroundColor = .black
        embed(child: splashHosting)
    }

    @MainActor
    private func embed(child: UIViewController) {
        child.loadViewIfNeeded()
        addChild(child)
        child.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(child.view)
        child.didMove(toParent: self)

        NSLayoutConstraint.activate([
            child.view.topAnchor.constraint(equalTo: view.topAnchor),
            child.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            child.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            child.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        debugLog("LaunchViewController.viewDidAppear() invoked")
        super.viewDidAppear(animated)
        guard !didFinishLaunching else { return }
        
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
        let (title, message, extraActions) = self.parseLaunchErrorDetails(error, retryCallback: retryCallback)

        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        extraActions.forEach { alert.addAction($0) }
        alert.addAction(UIAlertAction(title: NSLocalizedString("Retry", comment: ""), style: .default) { _ in
            Task { await retryCallback?() }
        })
        present(alert, animated: true)
    }

    @MainActor
    private func parseLaunchErrorDetails(_ error: Error, retryCallback: (() async -> Void)?) -> (title: String, message: String, extraActions: [UIAlertAction]) {
        if let dbError = error as? DatabaseError {
            switch dbError {
            case .databaseDowngradeDetected(let reason):
                let resetAction = UIAlertAction(title: NSLocalizedString("Reset Database", comment: ""), style: .destructive) { [weak self] _ in
                    DatabaseManager.recreateDatabase()
                    Task {
                        await MainActor.run { self?.retries = 0 }
                        await retryCallback?()
                    }
                }
                return (
                    title: dbError.errorDescription ?? NSLocalizedString("Database Downgrade Detected", comment: ""),
                    message: reason,
                    extraActions: [resetAction]
                )
            case .missingAppGroup(let reason), .migrationFailed(let reason):
                return (
                    title: dbError.errorDescription ?? NSLocalizedString("Database Error", comment: ""),
                    message: reason,
                    extraActions: []
                )
            }
        }

        let nsError = error as NSError
        let title = nsError.userInfo[NSLocalizedFailureErrorKey] as? String ?? NSLocalizedString("Unable to Launch SideStore", comment: "")
        let desc = ([nsError.debugDescription] + nsError.underlyingErrors.map { ($0 as NSError).debugDescription }).joined(separator: "\n\n")
        return (title: title, message: desc, extraActions: [])
    }

    @MainActor
    func finishLaunching() async {
        guard !didFinishLaunching else { return }

        #if !os(tvOS)
            if !UserDefaults.standard.hasCompletedOnboarding {
                await AppManager.shared.reconcileInstalledApps()
                AppManager.shared.updateAllSources { _ in }
                updateKnownSources()
                didFinishLaunching = true
                return
            }
        #endif

        didFinishLaunching = true
        
        await AppManager.shared.reconcileInstalledApps()
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

        splashViewModel.isReadyToExit = true
    }

    @MainActor
    private func transitionToMainInterface() {
        let destinationVC = destinationViewController!

        embed(child: destinationVC)

        // Set initial alpha for fade-in
        destinationVC.view.alpha = 0

        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0.2 : 0.5, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut]) { [self] in
            for child in self.children where child !== destinationVC {
                child.view.alpha = 0
            }

            destinationVC.view.alpha = 1
        } completion: { [self] _ in
            debugLog("[LaunchViewController] Transition complete - exiting LaunchViewController, handing off to TabBarController")
            for child in self.children where child !== destinationVC {
                child.willMove(toParent: nil)
                child.view.removeFromSuperview()
                child.removeFromParent()
            }
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
