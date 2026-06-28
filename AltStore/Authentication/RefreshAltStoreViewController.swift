//
//  RefreshAltStoreViewController.swift
//  AltStore
//
//  Created by Riley Testut on 10/26/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit
import AltStoreCore
import AltSign

final class RefreshAltStoreViewController: UIViewController
{
    var context: AuthenticatedOperationContext!
    var mismatchReason: SigningCertificateMismatchReason?
    
    var completionHandler: ((Result<Void, Error>) -> Void)?
    
    @IBOutlet private var placeholderView: RSTPlaceholderView!
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.placeholderView.textLabel.isHidden = true
        
        self.placeholderView.detailTextLabel.textAlignment = .left
        self.placeholderView.detailTextLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        
        let reason = self.mismatchReason ?? (self.context?.team?.type == .free ? .freeAccountLimitRevoked : .revoked)
        let reasonText: String
        
        switch reason {
            case .expired:
                reasonText = NSLocalizedString("The signing certificate used to install SideStore has expired.", comment: "")
            case .revoked:
                reasonText = NSLocalizedString("The signing certificate used to install SideStore was revoked on the Apple Developer portal.", comment: "")
            case .freeAccountLimitRevoked:
                reasonText = NSLocalizedString("Free developer accounts are limited to 1 active signing certificate. Since the private key for your existing certificate was not found on this device, SideStore had to create a new certificate, which automatically revoked the old one.", comment: "")
            case .differentAccount:
                reasonText = NSLocalizedString("The logged-in Apple ID account has changed.", comment: "")
            case .differentTeam:
                reasonText = NSLocalizedString("The active developer team has changed.", comment: "")
            case .privateKeyLost:
                reasonText = NSLocalizedString("The private key for the active signing certificate is missing from this device's keychain.", comment: "")
            case .externalSigner:
                reasonText = NSLocalizedString("SideStore was installed by a different signing tool (like Xcode or AltStore).", comment: "")
            case .corruptProfile:
                reasonText = NSLocalizedString("The provisioning profile for SideStore is corrupt or missing.", comment: "")
        }
        
        let header = NSLocalizedString("Signing certificate mismatch detected.", comment: "")
        let paragraph1 = NSLocalizedString("To ensure you can continue using SideStore, the app must be reinstalled now using the new certificate. Otherwise, you will be unable to refresh or open SideStore once the old certificate expires.", comment: "")
        let paragraph2 = NSLocalizedString("This reinstallation registers the new signature with the OS and will terminate SideStore. You can reopen SideStore immediately once reinstallation is completed.", comment: "")
        
        let fullText = "\(header)\n\n\(paragraph1)\n\n\(paragraph2)\n\nReason: \(reasonText)"
        let attributedString = NSMutableAttributedString(string: fullText)
        
        if let reasonRange = fullText.range(of: "Reason:") {
            let nsRange = NSRange(reasonRange, in: fullText)
            let baseFont = self.placeholderView.detailTextLabel.font ?? UIFont.systemFont(ofSize: 14)
            if let boldFontDescriptor = baseFont.fontDescriptor.withSymbolicTraits(.traitBold) {
                let boldFont = UIFont(descriptor: boldFontDescriptor, size: baseFont.pointSize)
                attributedString.addAttribute(.font, value: boldFont, range: nsRange)
            }
            attributedString.addAttribute(.foregroundColor, value: UIColor.white, range: nsRange)
        }
        
        self.placeholderView.detailTextLabel.attributedText = attributedString
    }
}

private extension RefreshAltStoreViewController
{
    @IBAction func refreshAltStore(_ sender: PillButton)
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
            let group = AppManager.shared.install(altStore, presentingViewController: self, context: self.context) { (result) in
                switch result
                {
                case .success: self.completionHandler?(.success(()))
                case .failure(let error as NSError):
                    DispatchQueue.main.async {
                        sender.progress = nil
                        sender.isIndicatingActivity = false
                        
                        let alertController = UIAlertController(title: NSLocalizedString("Failed to Refresh SideStore", comment: ""), message: error.localizedFailureReason ?? error.localizedDescription, preferredStyle: .alert)
                        alertController.addAction(UIAlertAction(title: NSLocalizedString("Try Again", comment: ""), style: .default, handler: { (action) in
                            refresh()
                        }))
                        alertController.addAction(UIAlertAction(title: NSLocalizedString("Refresh Later", comment: ""), style: .cancel, handler: { (action) in
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
