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
            throw OperationError.invalidOperationContext("SignInFlowHandler: Cannot prompt for credentials because presentingViewController is nil")
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
            throw OperationError.invalidOperationContext("SignInFlowHandler: Cannot prompt for 2FA verification code because presenting view controller is unavailable")
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
            return try await promptCodeEntry(
                title: NSLocalizedString("Please enter the 6-digit verification code that was sent to your Apple devices.", comment: ""),
                phoneNumbers: [],
                activePhoneID: "",
                currentDeliveryMode: nil,
                isTrustedDevice: true
            )

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
    private func showErrorRetryAlert(message: String) async throws -> Bool {
        return try await withCheckedThrowingContinuation { continuation in
            let alert = UIAlertController(
                title: NSLocalizedString("Verification Failed", comment: ""),
                message: message,
                preferredStyle: .alert
            )
            
            alert.addAction(UIAlertAction(title: NSLocalizedString("Retry", comment: ""), style: .default) { _ in
                continuation.resume(returning: true)
            })

            alert.addAction(UIAlertAction(title: systemLocalizedString("Cancel"), style: .cancel) { _ in
                continuation.resume(returning: false)
            })

            self.present(alert)
        }
    }

    @MainActor
    func accountRepair(url: URL, message: String) async -> AccountRepairDecision {
        guard self.isPresenterAvailable else {
            return .cancel
        }

        return await withCheckedContinuation { continuation in
            let appleAccountURL = AppConstants.URLs.appleAccount
            let baseMessage = message.isEmpty ? AppConstants.defaultAccountRepairMessage : message
            let displayMessage = """
                \(baseMessage)

                \(NSLocalizedString("Warning: Repeatedly skipping this without completing required verification or terms may lead to your account being restricted by Apple over time.", comment: ""))
                """

            let alert = UIAlertController(
                title: NSLocalizedString("Account Repair Required", comment: ""),
                message: displayMessage,
                preferredStyle: .alert
            )

            alert.addAction(UIAlertAction(title: NSLocalizedString("Open Developer Account", comment: ""), style: .default) { [weak self] _ in
                self?.activePresenter?.openWebURL(url)
                continuation.resume(returning: .cancel)
            })

            alert.addAction(UIAlertAction(title: NSLocalizedString("Open Apple Account", comment: ""), style: .default) { [weak self] _ in
                self?.activePresenter?.openWebURL(appleAccountURL)
                continuation.resume(returning: .cancel)
            })

            alert.addAction(UIAlertAction(title: NSLocalizedString("Skip & Continue", comment: ""), style: .default) { _ in
                continuation.resume(returning: .proceed)
            })

            alert.addAction(UIAlertAction(title: systemLocalizedString("Cancel"), style: .cancel) { _ in
                continuation.resume(returning: .cancel)
            })

            self.present(alert)
        }
    }

    @MainActor
    private func promptCodeEntry(title: String,
                                 phoneNumbers: [TrustedPhoneNumber],
                                 activePhoneID: String,
                                 currentDeliveryMode: TwoFactorDeliveryMode?,
                                 isTrustedDevice: Bool) async throws -> TwoFactorResponse
    {
        return try await withCheckedThrowingContinuation { continuation in
            let alertController = UIAlertController(title: title, message: nil, preferredStyle: .alert)
            var observer: NSObjectProtocol?
            alertController.addTextField { (textField) in
                textField.autocorrectionType = .no
                textField.autocapitalizationType = .none
                textField.keyboardType = .numberPad
                
                observer = NotificationCenter.default.addObserver(forName: UITextField.textDidChangeNotification, object: textField, queue: .main) { (notification) in
                    guard let textField = notification.object as? UITextField else { return }
                    alertController.actions.first?.isEnabled = (textField.text ?? "").count == 6
                }
            }
            
            let submitAction = UIAlertAction(title: NSLocalizedString("Continue", comment: ""), style: .default) { _ in
                if let observer = observer {
                    NotificationCenter.default.removeObserver(observer)
                }
                let textField = alertController.textFields?.first
                let code = textField?.text ?? ""
                continuation.resume(returning: .verificationCode(code))
            }
            submitAction.isEnabled = false
            alertController.addAction(submitAction)

            if isTrustedDevice {
                let otherMethodsAction = UIAlertAction(title: NSLocalizedString("Other Options…", comment: ""), style: .default) { [weak self] _ in
                    if let observer = observer {
                        NotificationCenter.default.removeObserver(observer)
                    }
                    guard let self = self else {
                        continuation.resume(returning: .cancel)
                        return
                    }
                    self.showDeliveryMethodDialog(preferredMode: .sms, phoneNumbers: phoneNumbers, activeID: activePhoneID, continuation: continuation)
                }
                alertController.addAction(otherMethodsAction)
            } else if let mode = currentDeliveryMode {
                let resendTitle = (mode == .sms)
                    ? NSLocalizedString("Resend SMS", comment: "")
                    : NSLocalizedString("Call Again", comment: "")
                let resendAction = UIAlertAction(title: resendTitle, style: .default) { _ in
                    if let observer = observer {
                        NotificationCenter.default.removeObserver(observer)
                    }
                    if case .voice = mode {
                        return continuation.resume(returning: .requestVoice(phoneID: activePhoneID))
                    }
                    if case .sms = mode {
                        return continuation.resume(returning: .requestSMS(phoneID: activePhoneID))
                    }
                }
                alertController.addAction(resendAction)

                let otherMethodsAction = UIAlertAction(title: NSLocalizedString("Other Options…", comment: ""), style: .default) { [weak self] _ in
                    if let observer = observer {
                        NotificationCenter.default.removeObserver(observer)
                    }
                    guard let self = self else {
                        continuation.resume(returning: .cancel)
                        return
                    }
                    self.showDeliveryMethodDialog(preferredMode: .trustedDevice, phoneNumbers: phoneNumbers, activeID: activePhoneID, continuation: continuation)
                }
                alertController.addAction(otherMethodsAction)

                if phoneNumbers.count > 1 {
                    let changeNumberAction = UIAlertAction(title: NSLocalizedString("Choose Different Number", comment: ""), style: .default) { [weak self] _ in
                        if let observer = observer {
                            NotificationCenter.default.removeObserver(observer)
                        }
                        guard let self = self else {
                            continuation.resume(returning: .cancel)
                            return
                        }
                        self.showPhoneNumberSelectionDialog(phoneNumbers: phoneNumbers, activeID: activePhoneID, mode: mode, continuation: continuation)
                    }
                    alertController.addAction(changeNumberAction)
                }
            }
            
            alertController.addAction(UIAlertAction(title: systemLocalizedString("Cancel"), style: .cancel) { _ in
                if let observer = observer {
                    NotificationCenter.default.removeObserver(observer)
                }
                continuation.resume(returning: .cancel)
            })
            
            self.present(alertController)
        }
    }

    @MainActor
    private func showDeliveryMethodDialog(preferredMode: TwoFactorDeliveryMode,
                                          phoneNumbers: [TrustedPhoneNumber],
                                          activeID: String,
                                          continuation: CheckedContinuation<TwoFactorResponse, Error>)
    {
        let alert = UIAlertController(
            title: NSLocalizedString("Verification Method", comment: ""),
            message: NSLocalizedString("How would you like to receive your verification code?", comment: ""),
            preferredStyle: .alert
        )

        let isAppleDefault = (preferredMode == .trustedDevice)
        let trustedDeviceTitle = isAppleDefault
            ? NSLocalizedString("Apple Devices (Recommended)", comment: "")
            : NSLocalizedString("Apple Devices", comment: "")
        let trustedDeviceAction = UIAlertAction(title: trustedDeviceTitle, style: .default) { _ in
            continuation.resume(returning: .requestTrustedDevice)
        }
        alert.addAction(trustedDeviceAction)

        let isSMSDefault = (preferredMode == .sms)
        let smsTitle = isSMSDefault
            ? NSLocalizedString("Text Message (SMS) (Recommended)", comment: "")
            : NSLocalizedString("Text Message (SMS)", comment: "")
        let smsAction = UIAlertAction(title: smsTitle, style: .default) { [weak self] _ in
            guard let self = self else {
                continuation.resume(returning: .cancel)
                return
            }
            if phoneNumbers.count > 1 {
                self.showPhoneNumberSelectionDialog(phoneNumbers: phoneNumbers, activeID: activeID, mode: .sms, continuation: continuation)
            } else {
                let targetID = phoneNumbers.first?.id ?? activeID
                continuation.resume(returning: .requestSMS(phoneID: targetID))
            }
        }
        alert.addAction(smsAction)

        let isVoiceDefault = (preferredMode == .voice)
        let voiceTitle = isVoiceDefault
            ? NSLocalizedString("Phone Call (Recommended)", comment: "")
            : NSLocalizedString("Phone Call", comment: "")
        let voiceAction = UIAlertAction(title: voiceTitle, style: .default) { [weak self] _ in
            guard let self = self else {
                continuation.resume(returning: .cancel)
                return
            }
            if phoneNumbers.count > 1 {
                self.showPhoneNumberSelectionDialog(phoneNumbers: phoneNumbers, activeID: activeID, mode: .voice, continuation: continuation)
            } else {
                let targetID = phoneNumbers.first?.id ?? activeID
                continuation.resume(returning: .requestVoice(phoneID: targetID))
            }
        }
        alert.addAction(voiceAction)

        alert.addAction(UIAlertAction(title: systemLocalizedString("Cancel"), style: .cancel) { _ in
            continuation.resume(returning: .cancel)
        })

        switch preferredMode {
        case .trustedDevice:
            alert.preferredAction = trustedDeviceAction
        case .sms:
            alert.preferredAction = smsAction
        case .voice:
            alert.preferredAction = voiceAction
        }

        self.present(alert)
    }

    @MainActor
    private func showPhoneNumberSelectionDialog(phoneNumbers: [TrustedPhoneNumber],
                                                 activeID: String,
                                                 mode: TwoFactorDeliveryMode,
                                                 continuation: CheckedContinuation<TwoFactorResponse, Error>)
    {
        let alert = UIAlertController(
            title: NSLocalizedString("Select Phone Number", comment: ""),
            message: NSLocalizedString("Choose a phone number to receive your verification code:", comment: ""),
            preferredStyle: .alert
        )

        for phone in phoneNumbers {
            let isCurrent = (phone.id == activeID)
            let buttonTitle = isCurrent ? "\(phone.number) (Current)" : phone.number
            let action = UIAlertAction(title: buttonTitle, style: .default) { _ in
                if case .voice = mode {
                    return continuation.resume(returning: .requestVoice(phoneID: phone.id))
                }
                if case .sms = mode {
                    return continuation.resume(returning: .requestSMS(phoneID: phone.id))
                }
            }
            alert.addAction(action)
        }

        alert.addAction(UIAlertAction(title: systemLocalizedString("Cancel"), style: .cancel) { _ in
            continuation.resume(returning: .cancel)
        })

        self.present(alert)
    }
    
    @MainActor
    func resolveRevocation(certificates: [ALTX509Certificate], teamType: ALTTeamType) async throws -> RevokeDecision {
        guard self.isPresenterAvailable else {
            throw OperationError.invalidOperationContext("SignInFlowHandler: Cannot resolve certificate revocation because presenting view controller is unavailable")
        }

        return try await withCheckedThrowingContinuation { continuation in
            let alertController = UIAlertController(
                title: NSLocalizedString("Revoke Certificates", comment: ""),
                message: NSLocalizedString("Select iOS Development certificate(s) to revoke:", comment: ""),
                preferredStyle: .alert
            )
            
            let revokeVC = RevokeCertificatesAlertViewController(certificates: certificates, teamType: teamType)
            alertController.setValue(revokeVC, forKey: "contentViewController")
            
            let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel) { _ in
                if teamType == .free {
                    let warningAlert = UIAlertController(
                        title: NSLocalizedString("Warning", comment: ""),
                        message: NSLocalizedString("SideStore cannot manage the existing certificate without owning its private key. The apps signed with the existing certificate will expire soon unless they are resigned and renewed explicitly by SideStore.", comment: ""),
                        preferredStyle: .alert
                    )
                    warningAlert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default) { _ in
                        warningAlert.dismiss(animated: true) {
                            continuation.resume(returning: .keepExisting)
                        }
                    })
                    self.present(warningAlert)
                } else {
                    continuation.resume(returning: .keepExisting)
                }
            }
            
            let isPaid = (teamType != .free && teamType != .unknown)
            let initialCount = revokeVC.getSelectedCertificates().count
            let initialTitle: String
            if isPaid {
                initialTitle = (initialCount == 0) ? "Continue Without Revoking" : "Revoke Selected (\(initialCount))"
            } else {
                initialTitle = "Revoke"
            }
            let actionStyle: UIAlertAction.Style = (isPaid && initialCount == 0) ? .default : .destructive
            let revokeAction = UIAlertAction(title: initialTitle, style: actionStyle) { _ in
                alertController.dismiss(animated: true) {
                    let selected = revokeVC.getSelectedCertificates()
                    continuation.resume(returning: .revokeSelected(selected))
                }
            }
            
            if isPaid {
                revokeAction.isEnabled = true
                revokeVC.onSelectionChanged = { selected in
                    if selected.isEmpty {
                        revokeAction.setValue(NSLocalizedString("Continue Without Revoking", comment: ""), forKey: "title")
                        revokeAction.setValue(nil, forKey: "titleTextColor")
                    } else {
                        revokeAction.setValue("Revoke Selected (\(selected.count))", forKey: "title")
                        revokeAction.setValue(UIColor.systemRed, forKey: "titleTextColor")
                    }
                }
            }
            
            alertController.addAction(cancelAction)
            alertController.addAction(revokeAction)
            
            self.present(alertController)
        }
    }
    
    @MainActor
    func resolveTeam(_ teams: [ALTTeam]) async throws -> ALTTeam {
        guard self.isPresenterAvailable else {
            throw OperationError.invalidOperationContext("SignInFlowHandler: Cannot resolve team selection because presenting view controller is unavailable")
        }

        return try await withCheckedThrowingContinuation { continuation in
            let storyboard = UIStoryboard(name: "Authentication", bundle: nil)
            let selectTeamViewController = storyboard.instantiateViewController(withIdentifier: "selectTeamViewController") as! SelectTeamViewController
            selectTeamViewController.teams = teams
            selectTeamViewController.completionHandler = { result in
                continuation.resume(with: result)
            }
            self.present(selectTeamViewController)
        }
    }
    
    @MainActor
    func resolvePostAuth() async {
        await withCheckedContinuation { continuation in
            var hasResumed = false
            let storyboard = UIStoryboard(name: "Authentication", bundle: nil)
            let instructionsViewController = storyboard.instantiateViewController(withIdentifier: "instructionsViewController") as! InstructionsViewController
            instructionsViewController.showsBottomButton = true
            instructionsViewController.completionHandler = {
                guard !hasResumed else {
                    debugLog("[SignInFlowHandler] resolvePostAuth completionHandler invoked more than once. Ignoring.")
                    return
                }
                hasResumed = true
                continuation.resume(returning: ())
            }
            self.present(instructionsViewController)
        }
    }
    
    @MainActor
    func resolveProvisioningError(_ error: Error) async -> ProvisioningErrorDecision {
        return await withCheckedContinuation { continuation in
            let alertController = UIAlertController(
                title: NSLocalizedString("Developer Portal Error", comment: ""),
                message: error.localizedDescription,
                preferredStyle: .alert
            )
            
            let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel) { _ in
                alertController.dismiss(animated: true) {
                    continuation.resume(returning: .cancel)
                }
            }
            
            let retryAction = UIAlertAction(title: NSLocalizedString("Retry", comment: ""), style: .default) { _ in
                alertController.dismiss(animated: true) {
                    continuation.resume(returning: .retry)
                }
            }
            
            alertController.addAction(cancelAction)
            alertController.addAction(retryAction)
            
            self.present(alertController)
        }
    }
    
    @MainActor
    func resolveResign(mismatchReason: CodeSignValidationReason, context: StandaloneOperationContext) async throws -> Bool {
        guard self.isPresenterAvailable else {
            throw OperationError.invalidOperationContext("SignInFlowHandler: Cannot resolve resign prompt because presenting view controller is unavailable")
        }

        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            let storyboard = UIStoryboard(name: "Authentication", bundle: nil)
            let resignViewController = storyboard.instantiateViewController(withIdentifier: "resignAltStoreViewController") as! ResignAltStoreViewController
            resignViewController.context = context
            resignViewController.mismatchReason = mismatchReason
            resignViewController.completionHandler = { result in
                guard !hasResumed else {
                    debugLog("[SignInFlowHandler] resolveResign completionHandler invoked more than once. Ignoring.")
                    return
                }
                hasResumed = true
                switch result {
                case .success:
                    continuation.resume(returning: true)
                case .failure:
                    continuation.resume(returning: false)
                }
            }
            self.present(resignViewController)
        }
    }
    
    @MainActor
    func complete() async {
        if self.navigationController.presentingViewController != nil {
            self.navigationController.dismiss(animated: true)
        }
    }
    
    @MainActor
    private func present(_ viewController: UIViewController) {
        let anchorVC = self.activePresenter
        if viewController is UIAlertController {
            anchorVC?.present(viewController, animated: true)
            return
        }
        
        if self.navigationController.presentingViewController != nil {
            if self.navigationController.viewControllers.contains(viewController) {
                // Already in stack
            } else {
                viewController.navigationItem.leftBarButtonItem = nil
                self.navigationController.pushViewController(viewController, animated: true)
            }
        } else {
            self.navigationController.setViewControllers([viewController], animated: false)
            anchorVC?.present(self.navigationController, animated: true)
        }
    }

    @MainActor
    func warnOutdatedAnisetteServer() async throws -> Bool {
        guard let presenter = self.activePresenter else {
            throw OperationError.invalidOperationContext("SignInFlowHandler: Cannot show outdated anisette warning because presenting view controller is unavailable")
        }
        
        return await withCheckedContinuation { continuation in
            let alert = UIAlertController(title: NSLocalizedString("WARNING: Outdated anisette server", comment: ""), message: NSLocalizedString("We've detected you are using an older anisette server. Using this server has a higher likelihood of locking your account and causing other issues. Are you sure you want to continue?", comment: ""), preferredStyle: UIAlertController.Style.alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("Continue", comment: ""), style: UIAlertAction.Style.destructive, handler: { action in
                continuation.resume(returning: true)
            }))
            alert.addAction(UIAlertAction(title: systemLocalizedString("Cancel"), style: UIAlertAction.Style.cancel, handler: { action in
                continuation.resume(returning: false)
            }))
            
            presenter.present(alert, animated: true)
        }
    }
}
