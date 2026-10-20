//
//  SignInFlowHandler.swift
//  SideStore
//
//  Created by Magesh K on 8/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import UIKit
import SideSign

class SignInFlowHandler: AnyObject, SignInHandler, AnisetteServerHandler {
    
    private weak var presentingViewController: UIViewController?
    private weak var presentedAuthVC: AuthenticationViewController?
    
    private var credentialsContinuation: CheckedContinuation<(String, String), Error>?
    private var activeAuthCompletionHandler: ((Result<(ALTAccount, ALTAppleAPISession), Error>) -> Void)?
    var showsDoItLater: Bool = false
    
    private lazy var navigationController: UINavigationController = {
        let storyboard = UIStoryboard(name: "Authentication", bundle: nil)
        let navigationController = storyboard.instantiateViewController(withIdentifier: "navigationController") as! UINavigationController
        navigationController.isModalInPresentation = true
        return navigationController
    }()
    
    init(presentingViewController: UIViewController?) {
        self.presentingViewController = presentingViewController
    }

    private var isPresenterAvailable: Bool {
        return self.presentingViewController != nil || self.navigationController.presentingViewController != nil
    }

    private var activePresenter: UIViewController? {
        if self.navigationController.presentingViewController != nil {
            return self.navigationController
        }
        return self.presentingViewController?.presentedViewController ?? self.presentingViewController
    }
    
    @MainActor
    func credentials() async throws -> (String, String) {
        guard let presentingViewController = self.presentingViewController else {
            throw OperationError.invalidParameters("SignInFlowHandler: Cannot prompt for credentials because presentingViewController is nil")
        }
        
        if let _ = self.presentedAuthVC {
            return try await withCheckedThrowingContinuation { continuation in
                self.credentialsContinuation = continuation
            }
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            self.credentialsContinuation = continuation
            
            let storyboard = UIStoryboard(name: "Authentication", bundle: nil)
            let authVC = storyboard.instantiateViewController(withIdentifier: "authenticationViewController") as! AuthenticationViewController
            self.presentedAuthVC = authVC
            
            authVC.authenticationHandler = { [weak self] (appleID, password, completionHandler) in
                guard let self = self else { return }
                self.activeAuthCompletionHandler = completionHandler
                if let credsContinuation = self.credentialsContinuation {
                    self.credentialsContinuation = nil
                    credsContinuation.resume(returning: (appleID, password))
                }
            }
            
            authVC.completionHandler = { [weak self] (result) in
                guard let self = self else { return }
                if result == nil {
                    // Cancelled
                    if let credsContinuation = self.credentialsContinuation {
                        self.credentialsContinuation = nil
                        credsContinuation.resume(throwing: OperationError.cancelled)
                    }
                    self.presentedAuthVC = nil
                    
                    if self.navigationController.presentingViewController != nil {
                        self.navigationController.dismiss(animated: true)
                    }
                } else {
                    // Success (dismissed)
                    self.presentedAuthVC = nil
                }
            }
            
            self.navigationController.view.tintColor = .altInvertedPrimary
            self.navigationController.setViewControllers([authVC], animated: false)
            presentingViewController.present(self.navigationController, animated: true)
        }
    }
    
    @MainActor
    func handleSignInResult(_ result: Result<(ALTAccount, ALTAppleAPISession), Error>) async {
        if let completionHandler = self.activeAuthCompletionHandler {
            self.activeAuthCompletionHandler = nil
            switch result {
            case .success((let account, let session)):
                completionHandler(.success((account, session)))
            case .failure(let error):
                completionHandler(.failure(error))
            }
        }
    }
    
    @MainActor
    func verificationCode(for request: TwoFactorRequest) async throws -> TwoFactorResponse {
        guard self.isPresenterAvailable else {
            throw OperationError.invalidParameters("SignInFlowHandler: Cannot prompt for 2FA verification code because presenting view controller is unavailable")
        }

        let errorMessage: String? = request.error

        if let errorMessage, !errorMessage.isEmpty {
            let shouldRetry = try await showErrorRetryAlert(message: errorMessage)
            guard shouldRetry else {
                return .cancel
            }
        }

        switch request {
        case .selectDeliveryMethod(let preferredMode, let phoneNumbers):
            return try await withCheckedThrowingContinuation { continuation in
                self.showDeliveryMethodDialog(
                    preferredMode: preferredMode,
                    phoneNumbers: phoneNumbers,
                    activeID: phoneNumbers.first?.id ?? "",
                    continuation: continuation
                )
            }

        case .trustedDevice:
            // Fallback directly to our manual popup if native prompt hangs
            return try await promptManualOverrideCode()

        case .sms(let phoneNumbers, let activeID, _):
            let activePhone = phoneNumbers.first(where: { $0.id == activeID })
            let title: String
            if let activePhone, !activePhone.number.isEmpty {
                title = String(format: NSLocalizedString("Please enter the 6-digit verification code sent via SMS to %@.", comment: ""), activePhone.number)
            } else {
                title = NSLocalizedString("Please enter the 6-digit verification code sent via SMS to your phone.", comment: "")
            }
            return try await promptCodeEntry(
                title: title,
                phoneNumbers: phoneNumbers,
                activePhoneID: activeID,
                currentDeliveryMode: .sms,
                isTrustedDevice: false
            )

        case .voice(let phoneNumbers, let activeID, _):
            let activePhone = phoneNumbers.first(where: { $0.id == activeID })
            let title: String
            if let activePhone, !activePhone.number.isEmpty {
                title = String(format: NSLocalizedString("Please enter the 6-digit verification code sent via phone call to %@.", comment: ""), activePhone.number)
            } else {
                title = NSLocalizedString("Please enter the 6-digit verification code sent via phone call.", comment: "")
            }
            return try await promptCodeEntry(
                title: title,
                phoneNumbers: phoneNumbers,
                activePhoneID: activeID,
                currentDeliveryMode: .voice,
                isTrustedDevice: false
            )
        }
    }

    @MainActor
    private func promptManualOverrideCode() async throws -> TwoFactorResponse {
        return try await withCheckedThrowingContinuation { continuation in
            let alertController = UIAlertController(
                title: NSLocalizedString("Manual 2FA Required", comment: ""),
                message: NSLocalizedString("Enter the 6-digit code from your trusted device or iOS Settings > Apple Account:", comment: ""),
                preferredStyle: .alert
            )
            
            alertController.addTextField { textField in
                textField.autocorrectionType = .no
                textField.autocapitalizationType = .none
                textField.keyboardType = .numberPad
                textField.textContentType = .oneTimeCode
            }
            
            let submitAction = UIAlertAction(title: NSLocalizedString("Submit", comment: ""), style: .default) { _ in
                let textField = alertController.textFields?.first
                let code = textField?.text ?? ""
                if code.count == 6 {
                    continuation.resume(returning: .verificationCode(code))
                } else {
                    continuation.resume(returning: .cancel)
                }
            }
            submitAction.isEnabled
