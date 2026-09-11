//
//  ImportAccountAlertController.swift
//  SideStore
//
//  Created by Magesh K on 8/10/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

@preconcurrency import UIKit
import Foundation

class ImportAccountAlertViewController: UIViewController {
    let passwordTextField = PaddedSecureTextField()

    override func viewDidLoad() {
        super.viewDidLoad()

        passwordTextField.isSecureTextEntry = true
        passwordTextField.placeholder = NSLocalizedString("File Password", comment: "")
        passwordTextField.borderStyle = .none
        #if !os(tvOS)
        passwordTextField.backgroundColor = .tertiarySystemFill
        #else
        passwordTextField.backgroundColor = UIColor.white.withAlphaComponent(0.15)
        #endif
        passwordTextField.layer.cornerRadius = 14
        passwordTextField.layer.masksToBounds = true
        passwordTextField.font = .systemFont(ofSize: 16)
        passwordTextField.autocapitalizationType = .none
        passwordTextField.autocorrectionType = .no

        passwordTextField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(passwordTextField)

        NSLayoutConstraint.activate([
            passwordTextField.heightAnchor.constraint(equalToConstant: 44),
            passwordTextField.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            passwordTextField.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
            passwordTextField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            passwordTextField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)
        ])
    }

    override var preferredContentSize: CGSize {
        get {
            return CGSize(width: 270, height: 60)
        }
        set {
            super.preferredContentSize = newValue
        }
    }
}

class ImportAccountAlertController: UIAlertController {
    
    static func make(
        data: Data,
        checksum: String,
        presentingViewController: UIViewController
    ) -> UIAlertController {
        let alert = UIAlertController(
            title: NSLocalizedString("Import Account", comment: ""),
            message: NSLocalizedString("An account configuration file was found. Enter password to import.", comment: ""),
            preferredStyle: .alert
        )
        let alertVC = ImportAccountAlertViewController()
        alert.setValue(alertVC, forKey: "contentViewController")
        
        let importAction = UIAlertAction(title: NSLocalizedString("Import", comment: ""), style: .default) { [weak presentingViewController, weak alertVC] _ in
            guard let presentingVC = presentingViewController,
                  let password = alertVC?.passwordTextField.text,
                  !password.isEmpty else { return }
            do {
                let account = try ImportExport.importAccount(data, filePassword: password)
                UserDefaults.standard.acctFileChecksum = checksum
                let toastView = ToastView(
                    text: String(format: NSLocalizedString("Successfully imported '%@'!", comment: ""), account.email),
                    detailText: NSLocalizedString("SideStore should be fully operational!", comment: "")
                )
                toastView.show(in: presentingVC)
            } catch {
                debugLog("[ImportAccountAlertController] Failed to import account configuration: \(error)")
                let toastView = ToastView(
                    text: NSLocalizedString("Failed to import account configuration!", comment: ""),
                    detailText: error.localizedDescription
                )
                toastView.show(in: presentingVC)
            }
        }
        
        let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel)
        alert.addAction(importAction)
        alert.addAction(cancelAction)
        
        return alert
    }
}
