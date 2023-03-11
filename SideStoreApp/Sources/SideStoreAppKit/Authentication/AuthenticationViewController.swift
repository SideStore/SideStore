//
//  AuthenticationViewController.swift
//  AltStore
//
//  Created by Riley Testut on 9/5/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

import AltSign

final class AuthenticationViewController: UIViewController {
    var authenticationHandler: ((String, String, @escaping (Result<(ALTAccount, ALTAppleAPISession), Error>) -> Void) -> Void)?
    var completionHandler: (((ALTAccount, ALTAppleAPISession, String)?) -> Void)?

    private weak var toastView: ToastView?

    @IBOutlet private var appleIDTextField: UITextField!
    @IBOutlet private var passwordTextField: UITextField!
    @IBOutlet private var signInButton: UIButton!

    @IBOutlet private var appleIDBackgroundView: UIView!
    @IBOutlet private var passwordBackgroundView: UIView!

    @IBOutlet private var scrollView: UIScrollView!
    @IBOutlet private var contentStackView: UIStackView!

    override func viewDidLoad() {
        super.viewDidLoad()

        signInButton.activityIndicatorView.style = .medium

        for view in [appleIDBackgroundView!, passwordBackgroundView!, signInButton!] {
            view.clipsToBounds = true
            view.layer.cornerRadius = 16
        }

        if UIScreen.main.isExtraCompactHeight {
            contentStackView.spacing = 20
        }

        NotificationCenter.default.addObserver(self, selector: #selector(AuthenticationViewController.textFieldDidChangeText(_:)), name: UITextField.textDidChangeNotification, object: appleIDTextField)
        NotificationCenter.default.addObserver(self, selector: #selector(AuthenticationViewController.textFieldDidChangeText(_:)), name: UITextField.textDidChangeNotification, object: passwordTextField)

        update()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        signInButton.isIndicatingActivity = false
        toastView?.dismiss()
    }
}

private extension AuthenticationViewController {
    func update() {
        if let _ = validate() {
            signInButton.isEnabled = true
            signInButton.alpha = 1.0
        } else {
            signInButton.isEnabled = false
            signInButton.alpha = 0.6
        }
    }

    func validate() -> (String, String)? {
        guard
            let emailAddress = appleIDTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines), !emailAddress.isEmpty,
            let password = passwordTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines), !password.isEmpty
        else { return nil }

        return (emailAddress, password)
    }
}

private extension AuthenticationViewController {
    @IBAction func authenticate() {
        guard let (emailAddress, password) = validate() else { return }

        appleIDTextField.resignFirstResponder()
        passwordTextField.resignFirstResponder()

        signInButton.isIndicatingActivity = true

        authenticationHandler?(emailAddress, password) { result in
            switch result {
            case .failure(ALTAppleAPIError.requiresTwoFactorAuthentication):
                // Ignore
                DispatchQueue.main.async {
                    self.signInButton.isIndicatingActivity = false
                }

            case let .failure(error as NSError):
                DispatchQueue.main.async {
                    let error = error.withLocalizedFailure(NSLocalizedString("Failed to Log In", comment: ""))

                    let toastView = ToastView(error: error)
                    toastView.textLabel.textColor = .altPink
                    toastView.detailTextLabel.textColor = .altPink
                    toastView.show(in: self)
                    self.toastView = toastView

                    self.signInButton.isIndicatingActivity = false
                }

            case let .success((account, session)):
                self.completionHandler?((account, session, password))
            }

            DispatchQueue.main.async {
                self.scrollView.setContentOffset(CGPoint(x: 0, y: -self.view.safeAreaInsets.top), animated: true)
            }
        }
    }

    @IBAction func cancel(_: UIBarButtonItem) {
        completionHandler?(nil)
    }
}

extension AuthenticationViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        switch textField {
        case appleIDTextField: passwordTextField.becomeFirstResponder()
        case passwordTextField: authenticate()
        default: break
        }

        update()

        return false
    }

    func textFieldDidBeginEditing(_: UITextField) {
        guard UIScreen.main.isExtraCompactHeight else { return }

        // Position all the controls within visible frame.
        var contentOffset = scrollView.contentOffset
        contentOffset.y = 44
        scrollView.setContentOffset(contentOffset, animated: true)
    }
}

extension AuthenticationViewController {
    @objc func textFieldDidChangeText(_: Notification) {
        update()
    }
}
