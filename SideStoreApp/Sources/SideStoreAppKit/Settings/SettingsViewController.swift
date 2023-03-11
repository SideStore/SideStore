//
//  SettingsViewController.swift
//  AltStore
//
//  Created by Riley Testut on 8/31/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Intents
import IntentsUI
import MessageUI
import SafariServices
import UIKit

import SideStoreCore

private extension SettingsViewController {
    enum Section: Int, CaseIterable {
        case signIn
        case account
        case patreon
        case appRefresh
        case instructions
        case credits
        case debug
    }

    enum AppRefreshRow: Int, CaseIterable {
        case backgroundRefresh

        @available(iOS 14, *)
        case addToSiri

        static var allCases: [AppRefreshRow] {
            guard #available(iOS 14, *) else { return [.backgroundRefresh] }
            return [.backgroundRefresh, .addToSiri]
        }
    }

    enum CreditsRow: Int, CaseIterable {
        case developer
        case operations
        case designer
        case softwareLicenses
    }

    enum DebugRow: Int, CaseIterable {
        case sendFeedback
        case refreshAttempts
        case errorLog
        case resetPairingFile
        case advancedSettings
    }
}

final class SettingsViewController: UITableViewController {
    private var activeTeam: Team?

    private var prototypeHeaderFooterView: SettingsHeaderFooterView!

    private var debugGestureCounter = 0
    private weak var debugGestureTimer: Timer?

    @IBOutlet private var accountNameLabel: UILabel!
    @IBOutlet private var accountEmailLabel: UILabel!
    @IBOutlet private var accountTypeLabel: UILabel!

    @IBOutlet private var backgroundRefreshSwitch: UISwitch!

    @IBOutlet private var versionLabel: UILabel!

    override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)

        NotificationCenter.default.addObserver(self, selector: #selector(SettingsViewController.openPatreonSettings(_:)), name: SideStoreAppDelegate.openPatreonSettingsDeepLinkNotification, object: nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

		let nib = UINib(nibName: "SettingsHeaderFooterView", bundle: Bundle(for: SettingsHeaderFooterView.self))
        prototypeHeaderFooterView = nib.instantiate(withOwner: nil, options: nil)[0] as? SettingsHeaderFooterView

        tableView.register(nib, forHeaderFooterViewReuseIdentifier: "HeaderFooterView")

        let debugModeGestureRecognizer = UISwipeGestureRecognizer(target: self, action: #selector(SettingsViewController.handleDebugModeGesture(_:)))
        debugModeGestureRecognizer.delegate = self
        debugModeGestureRecognizer.direction = .up
        debugModeGestureRecognizer.numberOfTouchesRequired = 3
        tableView.addGestureRecognizer(debugModeGestureRecognizer)

        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            versionLabel.text = NSLocalizedString(String(format: "SideStore %@", version), comment: "SideStore Version")
        } else {
            versionLabel.text = NSLocalizedString("SideStore", comment: "")
        }

        tableView.contentInset.bottom = 20

        update()

        if #available(iOS 15, *), let appearance = tabBarController?.tabBar.standardAppearance {
            appearance.stackedLayoutAppearance.normal.badgeBackgroundColor = .altPrimary
            self.navigationController?.tabBarItem.scrollEdgeAppearance = appearance
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        update()
    }
}

private extension SettingsViewController {
    func update() {
        if let team = DatabaseManager.shared.activeTeam() {
            accountNameLabel.text = team.name
            accountEmailLabel.text = team.account.appleID
            accountTypeLabel.text = team.type.localizedDescription

            activeTeam = team
        } else {
            activeTeam = nil
        }

        backgroundRefreshSwitch.isOn = UserDefaults.standard.isBackgroundRefreshEnabled

        if isViewLoaded {
            tableView.reloadData()
        }
    }

    func prepare(_ settingsHeaderFooterView: SettingsHeaderFooterView, for section: Section, isHeader: Bool) {
        settingsHeaderFooterView.primaryLabel.isHidden = !isHeader
        settingsHeaderFooterView.secondaryLabel.isHidden = isHeader
        settingsHeaderFooterView.button.isHidden = true

        settingsHeaderFooterView.layoutMargins.bottom = isHeader ? 0 : 8

        switch section {
        case .signIn:
            if isHeader {
                settingsHeaderFooterView.primaryLabel.text = NSLocalizedString("ACCOUNT", comment: "")
            } else {
                settingsHeaderFooterView.secondaryLabel.text = NSLocalizedString("Sign in with your Apple ID to download apps from SideStore.", comment: "")
            }

        case .patreon:
            if isHeader {
                settingsHeaderFooterView.primaryLabel.text = NSLocalizedString("PATREON", comment: "")
            } else {
                settingsHeaderFooterView.secondaryLabel.text = NSLocalizedString("Support the SideStore Team by becoming a patron!", comment: "")
            }

        case .account:
            settingsHeaderFooterView.primaryLabel.text = NSLocalizedString("ACCOUNT", comment: "")

            settingsHeaderFooterView.button.setTitle(NSLocalizedString("SIGN OUT", comment: ""), for: .normal)
            settingsHeaderFooterView.button.addTarget(self, action: #selector(SettingsViewController.signOut(_:)), for: .primaryActionTriggered)
            settingsHeaderFooterView.button.isHidden = false

        case .appRefresh:
            if isHeader {
                settingsHeaderFooterView.primaryLabel.text = NSLocalizedString("REFRESHING APPS", comment: "")
            } else {
                settingsHeaderFooterView.secondaryLabel.text = NSLocalizedString("Enable Background Refresh to automatically refresh apps in the background when connected to Wi-Fi.", comment: "")
            }

        case .instructions:
            break

        case .credits:
            settingsHeaderFooterView.primaryLabel.text = NSLocalizedString("CREDITS", comment: "")

        case .debug:
            settingsHeaderFooterView.primaryLabel.text = NSLocalizedString("DEBUG", comment: "")
        }
    }

    func preferredHeight(for settingsHeaderFooterView: SettingsHeaderFooterView, in section: Section, isHeader: Bool) -> CGFloat {
        let widthConstraint = settingsHeaderFooterView.contentView.widthAnchor.constraint(equalToConstant: tableView.bounds.width)
        NSLayoutConstraint.activate([widthConstraint])
        defer { NSLayoutConstraint.deactivate([widthConstraint]) }

        prepare(settingsHeaderFooterView, for: section, isHeader: isHeader)

        let size = settingsHeaderFooterView.contentView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        return size.height
    }
}

private extension SettingsViewController {
    func signIn() {
        AppManager.shared.authenticate(presentingViewController: self) { result in
            DispatchQueue.main.async {
                switch result {
                case .failure(OperationError.cancelled):
                    // Ignore
                    break

                case let .failure(error):
                    let toastView = ToastView(error: error)
                    toastView.show(in: self)

                case .success: break
                }

                self.update()
            }
        }
    }

    @objc func signOut(_ sender: UIBarButtonItem) {
        func signOut() {
            DatabaseManager.shared.signOut { error in
                DispatchQueue.main.async {
                    if let error = error {
                        let toastView = ToastView(error: error)
                        toastView.show(in: self)
                    }

                    self.update()
                }
            }
        }

        let alertController = UIAlertController(title: NSLocalizedString("Are you sure you want to sign out?", comment: ""), message: NSLocalizedString("You will no longer be able to install or refresh apps once you sign out.", comment: ""), preferredStyle: .actionSheet)
        alertController.addAction(UIAlertAction(title: NSLocalizedString("Sign Out", comment: ""), style: .destructive) { _ in signOut() })
        alertController.addAction(.cancel)
        // Fix crash on iPad
        alertController.popoverPresentationController?.barButtonItem = sender
        present(alertController, animated: true, completion: nil)
    }

    @IBAction func toggleIsBackgroundRefreshEnabled(_ sender: UISwitch) {
        UserDefaults.standard.isBackgroundRefreshEnabled = sender.isOn
    }

    @available(iOS 14, *)
    @IBAction func addRefreshAppsShortcut() {
        guard let shortcut = INShortcut(intent: INInteraction.refreshAllApps().intent) else { return }

        let viewController = INUIAddVoiceShortcutViewController(shortcut: shortcut)
        viewController.delegate = self
        viewController.modalPresentationStyle = .formSheet
        present(viewController, animated: true, completion: nil)
    }

    @IBAction func handleDebugModeGesture(_: UISwipeGestureRecognizer) {
        debugGestureCounter += 1
        debugGestureTimer?.invalidate()

        if debugGestureCounter >= 3 {
            debugGestureCounter = 0

            UserDefaults.standard.isDebugModeEnabled.toggle()
            tableView.reloadData()
        } else {
            debugGestureTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
                self?.debugGestureCounter = 0
            }
        }
    }

    func openTwitter(username: String) {
        let twitterAppURL = URL(string: "twitter://user?screen_name=" + username)!
        UIApplication.shared.open(twitterAppURL, options: [:]) { success in
            if success {
                if let selectedIndexPath = self.tableView.indexPathForSelectedRow {
                    self.tableView.deselectRow(at: selectedIndexPath, animated: true)
                }
            } else {
                let safariURL = URL(string: "https://twitter.com/" + username)!

                let safariViewController = SFSafariViewController(url: safariURL)
                safariViewController.preferredControlTintColor = .altPrimary
                self.present(safariViewController, animated: true, completion: nil)
            }
        }
    }
}

private extension SettingsViewController {
    @objc func openPatreonSettings(_: Notification) {
        guard presentedViewController == nil else { return }

        UIView.performWithoutAnimation {
            self.navigationController?.popViewController(animated: false)
            self.performSegue(withIdentifier: "showPatreon", sender: nil)
        }
    }
}

extension SettingsViewController {
    override func numberOfSections(in tableView: UITableView) -> Int {
        var numberOfSections = super.numberOfSections(in: tableView)

        if !UserDefaults.standard.isDebugModeEnabled {
            numberOfSections -= 1
        }

        return numberOfSections
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let section = Section.allCases[section]
        switch section {
        case .signIn: return (activeTeam == nil) ? 1 : 0
        case .account: return (activeTeam == nil) ? 0 : 3
        case .appRefresh: return AppRefreshRow.allCases.count
        default: return super.tableView(tableView, numberOfRowsInSection: section.rawValue)
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = super.tableView(tableView, cellForRowAt: indexPath)

        if #available(iOS 14, *) {} else if let cell = cell as? InsetGroupTableViewCell,
                                            indexPath.section == Section.appRefresh.rawValue,
                                            indexPath.row == AppRefreshRow.backgroundRefresh.rawValue {
            // Only one row is visible pre-iOS 14.
            cell.style = .single
        }

        return cell
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let section = Section.allCases[section]
        switch section {
        case .signIn where activeTeam != nil: return nil
        case .account where activeTeam == nil: return nil
        case .signIn, .account, .patreon, .appRefresh, .credits, .debug:
            let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "HeaderFooterView") as! SettingsHeaderFooterView
            prepare(headerView, for: section, isHeader: true)
            return headerView

        case .instructions: return nil
        }
    }

    override func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        let section = Section.allCases[section]
        switch section {
        case .signIn where activeTeam != nil: return nil
        case .signIn, .patreon, .appRefresh:
            let footerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "HeaderFooterView") as! SettingsHeaderFooterView
            prepare(footerView, for: section, isHeader: false)
            return footerView

        case .account, .credits, .debug, .instructions: return nil
        }
    }

    override func tableView(_: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        let section = Section.allCases[section]
        switch section {
        case .signIn where activeTeam != nil: return 1.0
        case .account where activeTeam == nil: return 1.0
        case .signIn, .account, .patreon, .appRefresh, .credits, .debug:
            let height = preferredHeight(for: prototypeHeaderFooterView, in: section, isHeader: true)
            return height

        case .instructions: return 0.0
        }
    }

    override func tableView(_: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        let section = Section.allCases[section]
        switch section {
        case .signIn where activeTeam != nil: return 1.0
        case .account where activeTeam == nil: return 1.0
        case .signIn, .patreon, .appRefresh:
            let height = preferredHeight(for: prototypeHeaderFooterView, in: section, isHeader: false)
            return height

        case .account, .credits, .debug, .instructions: return 0.0
        }
    }
}

extension SettingsViewController {
    override func tableView(_: UITableView, didSelectRowAt indexPath: IndexPath) {
        let section = Section.allCases[indexPath.section]
        switch section {
        case .signIn: signIn()
        case .instructions: break
        case .appRefresh:
            let row = AppRefreshRow.allCases[indexPath.row]
            switch row {
            case .backgroundRefresh: break
            case .addToSiri:
                guard #available(iOS 14, *) else { return }
                addRefreshAppsShortcut()
            }

        case .credits:
            let row = CreditsRow.allCases[indexPath.row]
            switch row {
            case .developer: openTwitter(username: "sidestore_io")
            case .operations: openTwitter(username: "sidestore_io")
            case .designer: openTwitter(username: "lit_ritt")
            case .softwareLicenses: break
            }

        case .debug:
            let row = DebugRow.allCases[indexPath.row]
            switch row {
            case .sendFeedback:
                if MFMailComposeViewController.canSendMail() {
                    let mailViewController = MFMailComposeViewController()
                    mailViewController.mailComposeDelegate = self
                    mailViewController.setToRecipients(["support@sidestore.io"])

                    if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                        mailViewController.setSubject("SideStore Beta \(version) Feedback")
                    } else {
                        mailViewController.setSubject("SideStore Beta Feedback")
                    }

                    present(mailViewController, animated: true, completion: nil)
                } else {
                    let toastView = ToastView(text: NSLocalizedString("Cannot Send Mail", comment: ""), detailText: nil)
                    toastView.show(in: self)
                }
            case .resetPairingFile:
                let filename = "ALTPairingFile.mobiledevicepairing"
                let fm = FileManager.default
                let documentsPath = fm.documentsDirectory.appendingPathComponent("/\(filename)")
                let alertController = UIAlertController(
                    title: NSLocalizedString("Are you sure to reset the pairing file?", comment: ""),
                    message: NSLocalizedString("You can reset the pairing file when you cannot sideload apps or enable JIT. You need to restart SideStore.", comment: ""),
                    preferredStyle: UIAlertController.Style.actionSheet
                )

                alertController.addAction(UIAlertAction(title: NSLocalizedString("Delete and Reset", comment: ""), style: .destructive) { _ in
                    if fm.fileExists(atPath: documentsPath.path), let contents = try? String(contentsOf: documentsPath), !contents.isEmpty {
                        try? fm.removeItem(atPath: documentsPath.path)
                        NSLog("Pairing File Reseted")
                    }
                    self.tableView.deselectRow(at: indexPath, animated: true)
                    let dialogMessage = UIAlertController(title: NSLocalizedString("Pairing File Reseted", comment: ""), message: NSLocalizedString("Please restart SideStore", comment: ""), preferredStyle: .alert)
                    self.present(dialogMessage, animated: true, completion: nil)
                })
                alertController.addAction(.cancel)
                // Fix crash on iPad
                alertController.popoverPresentationController?.sourceView = tableView
                alertController.popoverPresentationController?.sourceRect = tableView.rectForRow(at: indexPath)
                present(alertController, animated: true)
                tableView.deselectRow(at: indexPath, animated: true)
            case .advancedSettings:
                // Create the URL that deep links to your app's custom settings.
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    // Ask the system to open that URL.
                    UIApplication.shared.open(url)
                } else {
                    ELOG("UIApplication.openSettingsURLString invalid")
                }
            case .refreshAttempts, .errorLog: break
            }

        default: break
        }
    }
}

extension SettingsViewController: MFMailComposeViewControllerDelegate {
    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith _: MFMailComposeResult, error: Error?) {
        if let error = error {
            let toastView = ToastView(error: error)
            toastView.show(in: self)
        }

        controller.dismiss(animated: true, completion: nil)
    }
}

extension SettingsViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer) -> Bool {
        true
    }
}

extension SettingsViewController: INUIAddVoiceShortcutViewControllerDelegate {
    func addVoiceShortcutViewController(_ controller: INUIAddVoiceShortcutViewController, didFinishWith _: INVoiceShortcut?, error: Error?) {
        if let indexPath = tableView.indexPathForSelectedRow {
            tableView.deselectRow(at: indexPath, animated: true)
        }

        controller.dismiss(animated: true, completion: nil)

        guard let error = error else { return }

        let toastView = ToastView(error: error)
        toastView.show(in: self)
    }

    func addVoiceShortcutViewControllerDidCancel(_ controller: INUIAddVoiceShortcutViewController) {
        if let indexPath = tableView.indexPathForSelectedRow {
            tableView.deselectRow(at: indexPath, animated: true)
        }

        controller.dismiss(animated: true, completion: nil)
    }
}
