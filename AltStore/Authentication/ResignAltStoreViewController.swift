//
//  ResignAltStoreViewController.swift
//  AltStore
//
//  Created by Riley Testut on 10/26/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

@preconcurrency import UIKit
import SideSign

final class ResignAltStoreViewController: UIViewController
{
    var context: StandaloneOperationContext!
    var mismatchReason: CodeSignValidationReason?
    
    var completionHandler: ((Result<Void, Error>) -> Void)?
    
    @IBOutlet private var placeholderView: PlaceholderView!
    @IBOutlet private var reinstallButton: PillButton!
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.placeholderView.textLabel.isHidden = true
        
        self.placeholderView.detailTextLabel.textAlignment = .left
        self.placeholderView.detailTextLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        
        let reason = self.mismatchReason ?? (AuthManager.shared.team?.type == .free ? .freeAccountLimitRevoked : .revoked)
        debugLog("[ResignAltStoreViewController] Displaying Resign SideStore Now screen (mismatchReason: \(reason)).")
        let reasonText: String
        
        switch reason {
            case .expired:
                reasonText = NSLocalizedString("The signing certificate used to install SideStore has expired.", comment: "")
            case .revoked:
                reasonText = NSLocalizedString("The signing certificate used to install SideStore was revoked on the Apple Developer portal.", comment: "")
            case .freeAccountLimitRevoked:
                reasonText = NSLocalizedString("Free developer accounts are limited to 1 active signing certificate. Since the private key for the active certificate was not found on this device, SideStore will create a new certificate. This will automatically revoke the active certificate, which may disable installations on other devices or made by Xcode.", comment: "")
            case .differentAccount:
                reasonText = NSLocalizedString("The logged-in Apple ID account has changed.", comment: "")
            case .differentTeam:
                reasonText = NSLocalizedString("The active developer team has changed.", comment: "")
            case .privateKeyLost:
                reasonText = NSLocalizedString("The private key for the active signing certificate is missing from this device's keychain.", comment: "")
            case .externalSigner:
                reasonText = NSLocalizedString("SideStore was installed by a different signing tool (like Xcode or AltStore).", comment: "")
            case .missingProfile:
                reasonText = NSLocalizedString("The provisioning profile for SideStore is missing or invalid.", comment: "")
            case .missingCertificate:
                reasonText = NSLocalizedString("The signing certificate could not be extracted from SideStore's binary.", comment: "")
        }
        
        let isRevocationExpected = (reason == .privateKeyLost || reason == .freeAccountLimitRevoked)
        let buttonTitle = isRevocationExpected ?
            NSLocalizedString("Revoke and Resign Now", comment: "") :
            NSLocalizedString("Resign Now", comment: "")
        self.reinstallButton.setTitle(buttonTitle, for: .normal)
        self.reinstallButton.fontSize = 15
        
        let header = NSLocalizedString("Signing certificate mismatch detected.", comment: "")
        let paragraph1 = NSLocalizedString("To ensure you can continue using SideStore, \nthe app must be reinstalled now using the new certificate. Otherwise, you will be unable to refresh or open SideStore once the old certificate expires.", comment: "")
        let paragraph2 = NSLocalizedString("This reinstallation registers the new signature with the OS and will terminate SideStore. You can reopen SideStore immediately once reinstallation is completed.", comment: "")
        
        let fullText = "\(header)\n\n\(paragraph1)\n\n\(paragraph2)"
        let attributedString = NSMutableAttributedString(string: fullText)
        
        if let headerRange = fullText.range(of: header) {
            let nsRange = NSRange(headerRange, in: fullText)
            attributedString.addAttribute(.foregroundColor, value: UIColor.white, range: nsRange)
        }
        
        self.placeholderView.detailTextLabel.attributedText = attributedString
        
        // Separator Line
        let separator = UIView()
        separator.backgroundColor = UIColor.white.withAlphaComponent(0.2)
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
        
        // Reason Bold Prefix
        let reasonLabel = UILabel()
        reasonLabel.text = NSLocalizedString("Reason:", comment: "")
        reasonLabel.textColor = .white
        reasonLabel.font = UIFont.boldSystemFont(ofSize: 14)
        reasonLabel.setContentHuggingPriority(.required, for: .horizontal)
        
        // Reason Description
        let reasonTextLabel = UILabel()
        reasonTextLabel.text = reasonText
        reasonTextLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        reasonTextLabel.font = UIFont.systemFont(ofSize: 14)
        reasonTextLabel.numberOfLines = 0
        
        // Horizontal Container for key-value layout
        let reasonContainer = UIStackView(arrangedSubviews: [reasonLabel, reasonTextLabel])
        reasonContainer.axis = .horizontal
        reasonContainer.alignment = .top
        reasonContainer.spacing = 8
        
        // Add to standard Stack View hierarchy
        self.placeholderView.stackView.addArrangedSubview(separator)
        self.placeholderView.stackView.addArrangedSubview(reasonContainer)
        
        // Pin edges to match the width of the stack view
        separator.leadingAnchor.constraint(equalTo: self.placeholderView.stackView.leadingAnchor).isActive = true
        separator.trailingAnchor.constraint(equalTo: self.placeholderView.stackView.trailingAnchor).isActive = true
        
        reasonContainer.leadingAnchor.constraint(equalTo: self.placeholderView.stackView.leadingAnchor).isActive = true
        reasonContainer.trailingAnchor.constraint(equalTo: self.placeholderView.stackView.trailingAnchor).isActive = true
        
        self.placeholderView.stackView.setCustomSpacing(20, after: self.placeholderView.detailTextLabel)
        self.placeholderView.stackView.setCustomSpacing(15, after: separator)
    }
}

private extension ResignAltStoreViewController
{
    @IBAction func resignAltStore(_ sender: PillButton)
    {
        guard let altStore = InstalledApp.fetchAltStore(in: DatabaseManager.shared.viewContext) else { return }
                
        func refresh()
        {
            sender.isIndicatingActivity = true
            
            if let progress = AppManager.shared.installationProgress(for: altStore)
            {
                // Cancel pending AltStore installation so we can start a new one.
                progress.cancel()
            }
                        
            // Install, _not_ refresh, to ensure we are installing with a non-revoked certificate.
            let group = AppManager.shared.install(.app(altStore), presentingViewController: self, context: self.context) { (result) in
                switch result
                {
                case .success: self.completionHandler?(.success(()))
                case .failure(let error as NSError):
                    DispatchQueue.main.async {
                        sender.progress = nil
                        sender.isIndicatingActivity = false
                        
                        if error is CancellationError || (error.domain == NSCocoaErrorDomain && error.code == NSUserCancelledError) {
                            debugLog("[ResignAltStoreViewController] Operation cancelled. Auto-dismissing Resign SideStore Now screen.")
                            self.context?.error = OperationError.cancelled
                            self.completionHandler?(.failure(OperationError.cancelled))
                            self.dismiss(animated: true, completion: nil)
                            return
                        }
                        
                        let alertController = UIAlertController(title: NSLocalizedString("Failed to Resign SideStore", comment: ""), message: error.localizedFailureReason ?? error.localizedDescription, preferredStyle: .alert)
                        alertController.addAction(UIAlertAction(title: NSLocalizedString("Try Again", comment: ""), style: .default, handler: { (action) in
                            refresh()
                        }))
                        alertController.addAction(UIAlertAction(title: NSLocalizedString("Resign Later", comment: ""), style: .cancel, handler: { (action) in
                            self.completionHandler?(.failure(error))
                        }))
                        
                        self.present(alertController, animated: true, completion: nil)
                    }
                }
            }
            
            sender.progress = group.progress
        }
        
        refresh()
    }
    
    @IBAction func cancel(_ sender: UIButton)
    {
        self.completionHandler?(.failure(OperationError.cancelled))
    }
}
