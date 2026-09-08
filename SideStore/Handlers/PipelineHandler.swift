//
//  PipelineHandler.swift
//  SideStore
//
//  Created by Magesh K on 8/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import UIKit
import SideSign

final class PipelineHandler: PipelineExecutionHandler, 
                             PreflightChecksHandler, 
                             EntitlementsReviewHandler, 
                             ExtensionRemovalHandler, 
                             UnsupportedVersionHandler, 
                             InstallAppHandler, 
                             UserCustomizationHandler,
                             Sendable
{
    var preflightChecksHandler: PreflightChecksHandler { self }
    var entitlementsReviewHandler: EntitlementsReviewHandler { self }
    var extensionRemovalHandler: ExtensionRemovalHandler { self }
    var unsupportedVersionHandler: UnsupportedVersionHandler { self }
    var installAppHandler: InstallAppHandler { self }
    var userCustomizationHandler: UserCustomizationHandler { self }
    
    let isResignActive: Bool
    private let presenterProvider: PresenterProvider?
    
    init(
        isResignActive: Bool = false,
        presenterProvider: PresenterProvider? = nil
    ) {
        self.isResignActive = isResignActive
        self.presenterProvider = presenterProvider
    }

    @MainActor
    private var isPresenterAvailable: Bool {
        return self.activePresenter != nil
    }

    @MainActor
    private var activePresenter: UIViewController? {
        return self.presenterProvider?()
    }
    
    @MainActor
    func resolveBundleIDMismatch(targetID: String, activeEffectiveID: String) async -> Bool {
        guard let presenter = self.activePresenter else {
            return false
        }
        
        let title = NSLocalizedString("Bundle ID Mismatch", comment: "")
        let message = String(format: NSLocalizedString("The app you are installing has a bundle ID (%@) that does not match the active app (%@). Would you like to proceed?", comment: ""), targetID, activeEffectiveID)
        
        return await withCheckedContinuation { continuation in
            let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: UIAlertAction.cancel.title, style: UIAlertAction.cancel.style) { _ in
                continuation.resume(returning: false)
            })
            alertController.addAction(UIAlertAction(title: NSLocalizedString("Proceed", comment: ""), style: .default) { _ in
                continuation.resume(returning: true)
            })
            presenter.present(alertController, animated: true)
        }
    }
    
    @MainActor
    func reviewPermissions(_ permissions: [ALTEntitlement], for app: AppProtocol, mode: PermissionReviewMode) async throws {
        guard let presenter = self.activePresenter else {
            throw OperationError.invalidOperationContext("PipelineHandler: Cannot review permissions because presenting view controller is unavailable")
        }
        let reviewPermissionsViewController = ReviewPermissionsViewController(app: app, permissions: permissions, mode: mode)
        let navigationController = UINavigationController(rootViewController: reviewPermissionsViewController)
        
        defer {
            navigationController.dismiss(animated: true)
        }
        
        try await withCheckedThrowingContinuation { continuation in
            reviewPermissionsViewController.completionHandler = { result in
                continuation.resume(with: result)
            }
            
            presenter.present(navigationController, animated: true)
        }
    }
    
    @MainActor
    func selectAppExtensionsToRemove(
        appBundle: ALTApplication,
        localAppExtensions: [ALTApplication],
        excessExtensions: Set<ALTApplication>
    ) async throws -> ExtensionRemovalDecision {
        guard let presenter = self.activePresenter else {
            return .keepAll(useMainProfile: false)
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let firstSentence: String
            if UserDefaults.standard.activeAppLimitIncludesExtensions {
                firstSentence = NSLocalizedString("Non-developer Apple IDs are limited to 3 active apps and app extensions.", comment: "")
            } else {
                firstSentence = NSLocalizedString("Non-developer Apple IDs are limited to creating 10 App IDs per week.", comment: "")
            }
            
            let message = firstSentence + " " + String(format: NSLocalizedString("Would you like to remove this app's extensions so they don't count towards your limit? There are %d Extensions", comment: ""), appBundle.appExtensions.count)
            
            let alertController = UIAlertController(title: NSLocalizedString("App Contains Extensions", comment: ""), message: message, preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: UIAlertAction.cancel.title, style: UIAlertAction.cancel.style, handler: { _ in
                continuation.resume(throwing: OperationError.cancelled)
            }))
            alertController.addAction(UIAlertAction(title: NSLocalizedString("Keep App Extensions (Use Main Profile)", comment: ""), style: .default) { _ in
                continuation.resume(returning: .keepAll(useMainProfile: true))
            })
            alertController.addAction(UIAlertAction(title: NSLocalizedString("Keep App Extensions (Register App ID for Each Extension)", comment: ""), style: .default) { _ in
                continuation.resume(returning: .keepAll(useMainProfile: false))
            })
            alertController.addAction(UIAlertAction(title: NSLocalizedString("Remove App Extensions", comment: ""), style: .destructive) { _ in
                continuation.resume(returning: .removeAll)
            })
            
            alertController.addAction(UIAlertAction(title: NSLocalizedString("Choose App Extensions", comment: ""), style: .default) { _ in
                let popoverContentController = AppExtensionViewHostingController(extensions: appBundle.appExtensions) { selection in
                    continuation.resume(returning: .removeSelected(Set(selection)))
                }
                
                let suiview = popoverContentController.view!
                suiview.translatesAutoresizingMaskIntoConstraints = false
                #if !os(tvOS)
                popoverContentController.modalPresentationStyle = .popover
                
                if let popoverPresentationController = popoverContentController.popoverPresentationController {
                    popoverPresentationController.sourceView = presenter.view
                    popoverPresentationController.sourceRect = CGRect(x: 50, y: 50, width: 4, height: 4)
                    popoverPresentationController.delegate = popoverContentController
                    presenter.present(popoverContentController, animated: true)
                } else {
                    continuation.resume(throwing: OperationError.invalidParameters("RemoveAppExtensionsOperation: popoverContentController.popoverPresentationController is nil"))
                }
                #else
                popoverContentController.modalPresentationStyle = .blurOverFullScreen
                presenter.present(popoverContentController, animated: true)
                #endif
            })
            
            presenter.present(alertController, animated: true) {
                if presenter.presentedViewController == nil && !alertController.isViewLoaded {
                    let errMsg = "RemoveAppExtensionsOperation: unable to present dialog, view context not available." +
                                 "\nDid you move to different screen or background after starting the operation?"
                    continuation.resume(throwing: OperationError.invalidOperationContext(errMsg))
                }
            }
        }
    }
    
    @MainActor
    func resolveUnsupportediOSVersion(errorDescription: String, appName: String, compatibleVersion: String) async throws -> Bool {
        guard let presenter = self.activePresenter else {
            return false
        }
        
        let title = NSLocalizedString("Unsupported iOS Version", comment: "")
        let message = errorDescription + "\n\n" + NSLocalizedString("Would you like to download the last version compatible with this device instead?", comment: "")
        
        return await withCheckedContinuation { continuation in
            let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: UIAlertAction.cancel.title, style: UIAlertAction.cancel.style) { _ in
                continuation.resume(returning: false)
            })
            alertController.addAction(UIAlertAction(title: String(format: NSLocalizedString("Download %@ %@", comment: ""), appName, compatibleVersion), style: .default) { _ in
                continuation.resume(returning: true)
            })
            presenter.present(alertController, animated: true)
        }
    }
    
    func requestBackgroundSuspension() async {
        await withCheckedContinuation { continuation in
            Task { @MainActor in
                let alert = UIAlertController(
                    title: "Finish Refresh",
                    message: """
                    To finish refreshing, SideStore must be moved to the background. To do this, you can either go to the Home Screen manually or by hitting Continue. Please reopen SideStore after doing this.
                    """,
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: NSLocalizedString("Continue", comment: ""), style: .default, handler: { _ in
                    continuation.resume()
                }))
                
                let presenter = self.activePresenter
                                ?? UIApplication.shared.connectedScenes
                                    .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                                    .first?.rootViewController
                                    
                if var topVC = presenter {
                    while let presented = topVC.presentedViewController {
                        topVC = presented
                    }
                    topVC.present(alert, animated: true)
                } else {
                    continuation.resume()
                }
            }
        }
    }
    
    func suspendToHomeScreen() async {
        await CellularRefreshManager.shared.turnOnDataIfNeeded()
        await MainActor.run {
            _ = UIApplication.shared.perform(#selector(NSXPCConnection.suspend))
        }
    }
    
    func isAppInForeground() async -> Bool {
        await MainActor.run {
            UIApplication.shared.applicationState == .active
        }
    }
    
    @MainActor
    func resolveBundleIDOverride(initialBundleID: String) async throws -> (customID: String, appendTeamID: Bool)? {
        guard let presenter = self.activePresenter else {
            return (initialBundleID, true)
        }
        
        let titleText = NSLocalizedString("AppID Customization", comment: "")
        let messageText = NSLocalizedString("Customize the AppID if required and press 'Confirm' to proceed.", comment: "")
        
        let alert = UIAlertController(
            title: titleText,
            message: messageText,
            preferredStyle: .alert
        )
        
        alert.addTextField { textField in
            textField.text = initialBundleID
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
            textField.clearButtonMode = .whileEditing
        }
        
        alert.addTextField { textField in
            textField.isUserInteractionEnabled = false
        }
        
        let checkboxView = AppendTeamIDCheckboxView(isChecked: true)
        checkboxView.translatesAutoresizingMaskIntoConstraints = false
        
        _ = alert.view
        if let tf1 = alert.textFields?.first, let tf1View = tf1.superview {
            tf1View.layer.cornerRadius = 20
            tf1View.layer.cornerCurve = .continuous
            tf1View.layer.maskedCorners = [
                .layerMinXMinYCorner,
                .layerMaxXMinYCorner,
                .layerMinXMaxYCorner,
                .layerMaxXMaxYCorner
            ]
            tf1View.layer.masksToBounds = true
            tf1View.clipsToBounds = true
            
            // Clear outer table grouping container so it doesn't draw flat bottom edges
            tf1View.superview?.backgroundColor = .clear
            tf1View.superview?.layer.borderWidth = 0
            tf1View.superview?.layer.borderColor = UIColor.clear.cgColor
        }
        
        if (alert.textFields?.count ?? 0) >= 2,
           let tf1 = alert.textFields?.first,
           let tf2 = alert.textFields?[1],
           let container = tf2.superview {
            tf2.isHidden = true
            container.backgroundColor = .clear
            container.layer.borderWidth = 0
            container.layer.borderColor = UIColor.clear.cgColor
            
            for subview in container.subviews where subview !== checkboxView && subview !== tf2 {
                subview.isHidden = true
                subview.alpha = 0
            }
            
            container.addSubview(checkboxView)
            NSLayoutConstraint.activate([
                checkboxView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
                checkboxView.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -16),
                checkboxView.centerYAnchor.constraint(equalTo: container.centerYAnchor)
            ])
        }
        
        return await withCheckedContinuation { continuation in
            let okAction = UIAlertAction(title: NSLocalizedString("Confirm", comment: ""), style: .default) { _ in
                let text = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines)
                let customID = (text?.isEmpty == false) ? text! : initialBundleID
                let appendTeamID = checkboxView.isChecked
                continuation.resume(returning: (customID, appendTeamID))
            }
            
            let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel) { _ in
                continuation.resume(returning: nil)
            }
            alert.addAction(cancelAction)
            alert.addAction(okAction)
            presenter.present(alert, animated: true)
        }
    }


    @MainActor
    func resolveAppGroupMismatch(originalGroup: String, correctedGroup: String) async throws -> AppGroupResolution {
        guard let presenter = self.activePresenter else {
            return .correctAndProceed(correctedGroup)
        }
        
        let title = NSLocalizedString("App Group Discrepancy", comment: "")
        let message = String(format: NSLocalizedString("The app group '%@' does not match the app's bundle ID casing. Would you like to correct it to '%@'?", comment: ""), originalGroup, correctedGroup)
        
        return await withCheckedContinuation { continuation in
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            
            alert.addAction(UIAlertAction(title: NSLocalizedString("Correct & Proceed", comment: ""), style: .default) { _ in
                continuation.resume(returning: .correctAndProceed(correctedGroup))
            })
            
            alert.addAction(UIAlertAction(title: NSLocalizedString("Keep Original", comment: ""), style: .destructive) { _ in
                continuation.resume(returning: .keepOriginal(originalGroup))
            })
            
            alert.addAction(UIAlertAction(title: UIAlertAction.cancel.title, style: .cancel) { _ in
                continuation.resume(returning: .keepOriginal(originalGroup))
            })
            
            presenter.present(alert, animated: true)
        }
    }
}
