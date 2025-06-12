//
//  SettingsViewController.swift
//  AltStore
//
//  Created by Riley Testut on 8/31/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit
import SwiftUI
import SafariServices
import MessageUI
import Intents
import IntentsUI

import SemanticVersion

import AltStoreCore
import CAltSign
import UniformTypeIdentifiers

extension SettingsViewController
{
    fileprivate enum Section: Int, CaseIterable
    {
        case signIn
        case account
        case patreon
        case display
        case appRefresh
        case instructions
        case techyThings
        case credits
        case advancedSettings
        case signing
        // diagnostics section, will be enabled on release builds only on swipe down with 3 fingers 3 times
        case diagnostics
        // case macDirtyCow
    }
    
    fileprivate enum AppRefreshRow: Int, CaseIterable
    {
        case backgroundRefresh
        case noIdleTimeout        
        case addToSiri
        case disableAppLimit
        
        static var allCases: [AppRefreshRow] {
            var c: [AppRefreshRow] = [.backgroundRefresh, .noIdleTimeout, .addToSiri]

            // conditional entries go at the last to preserve ordering
            if UserDefaults.standard.isCowExploitSupported || !ProcessInfo().sparseRestorePatched
            {
                c.append(.disableAppLimit)
            }
            return c
        }
    }
    
    fileprivate enum CreditsRow: Int, CaseIterable
    {
        case developer
        case operations
        case designer
        case softwareLicenses
    }
    
    fileprivate enum TechyThingsRow: Int, CaseIterable
    {
        case errorLog
        case clearCache
    }
    
    fileprivate enum AdvancedSettingsRow: Int, CaseIterable
    {
        case sendFeedback
        case refreshAttempts
        case refreshSideJITServer
        case resetPairingFile
        case anisetteServers
        case betaUpdates
        case betaTrack
//        case hiddenSettings
    }
    
    fileprivate enum SigningSettingsRow: Int, CaseIterable {
        case importCert
        case exportCert
    }

    fileprivate enum DiagnosticsRow: Int, CaseIterable
    {
        case responseCaching
        case exportResignedApp
        case verboseOperationsLogging
        case exportDatabase
        case deleteDatabase
        case operationsLoggingControl
        case recreateDatabase
        case minimuxerConsoleLogging
    }
}

final class SettingsViewController: UITableViewController
{
    private var activeTeam: Team?
    
    private var prototypeHeaderFooterView: SettingsHeaderFooterView!
    
    // Add outlet
    @IBOutlet private var betaTrackLabel: UILabel!
    @IBOutlet private var betaTrackPopupButton: UIButton!

    private var debugGestureCounter = 0
    private weak var debugGestureTimer: Timer?
    
    @IBOutlet private var accountNameLabel: UILabel!
    @IBOutlet private var accountEmailLabel: UILabel!
    @IBOutlet private var accountTypeLabel: UILabel!
    
    @IBOutlet private var backgroundRefreshSwitch: UISwitch!
    @IBOutlet private var noIdleTimeoutSwitch: UISwitch!
    @IBOutlet private var disableAppLimitSwitch: UISwitch!
    @IBOutlet private var betaUpdatesSwitch: UISwitch!
    @IBOutlet private var exportResignedAppsSwitch: UISwitch!
    @IBOutlet private var verboseOperationsLoggingSwitch: UISwitch!
    @IBOutlet private var minimuxerConsoleLoggingSwitch: UISwitch!
    
//    @IBOutlet private var refreshSideJITServer: UILabel!
    @IBOutlet private var disableResponseCachingSwitch: UISwitch!
    
    @IBOutlet private var mastodonButton: UIButton!
    @IBOutlet private var threadsButton: UIButton!
    @IBOutlet private var twitterButton: UIButton!
    @IBOutlet private var githubButton: UIButton!
    
    @IBOutlet private var versionLabel: UILabel!
    
    @IBOutlet private var recreateDatabaseSwitch: UISwitch!
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    
    private static var exportDBInProgress = false
    private static var deleteDBInProgress = false
    
    required init?(coder aDecoder: NSCoder)
    {
        super.init(coder: aDecoder)
        
        NotificationCenter.default.addObserver(self, selector: #selector(SettingsViewController.openPatreonSettings(_:)), name: AppDelegate.openPatreonSettingsDeepLinkNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(SettingsViewController.openErrorLog(_:)), name: ToastView.openErrorLogNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(SettingsViewController.openExportCertificateConfirm(_:)), name: AppDelegate.exportCertificateNotification, object: nil)
    }
    
    
    private func handleReleaseChannelSelection(_ channel: String) {
        // Update your model/preferences
        UserDefaults.standard.betaUdpatesTrack = channel
        updateReleaseChannelButtonTitle()
    }
    
    private func updateReleaseChannelButtonTitle() {
        let channel = UserDefaults.standard.betaUdpatesTrack ?? UserDefaults.defaultBetaUpdatesTrack
        betaTrackPopupButton.setTitle(channel, for: .normal)
    }
    
    private func configureReleaseChannelButton() {
        let currentTrack = UserDefaults.standard.betaUdpatesTrack
        
        // get all tracks as string available except .stable and .unknown
        var trackOptions: [String] = ReleaseTracks.betaTracks.map {$0.rawValue}

        if let currentTrack{
            // prepend currently selected beta track from the user defaults
            trackOptions = [currentTrack] + trackOptions.filter { $0 != currentTrack }
        }
    
        // Create menu items with proper styling
        let items = trackOptions.map{ channel in
            UIAction(title: channel, handler: { [weak self] _ in
                self?.handleReleaseChannelSelection(channel)
            })
        }
        
        // Create menu with proper styling
        let menu = UIMenu(title: "",
                         options: [.singleSelection, .displayInline], // Add displayInline
                         children: items
        )
        betaTrackPopupButton.menu = menu

        // Set initial state
        updateReleaseChannelButtonTitle()
    }


    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        let nib = UINib(nibName: "SettingsHeaderFooterView", bundle: nil)
        self.prototypeHeaderFooterView = nib.instantiate(withOwner: nil, options: nil)[0] as? SettingsHeaderFooterView
        
        self.tableView.register(nib, forHeaderFooterViewReuseIdentifier: "HeaderFooterView")
        
        let debugModeGestureRecognizer = UISwipeGestureRecognizer(target: self, action: #selector(SettingsViewController.handleDebugModeGesture(_:)))
        debugModeGestureRecognizer.delegate = self
        debugModeGestureRecognizer.direction = .up
        debugModeGestureRecognizer.numberOfTouchesRequired = 3
        self.tableView.addGestureRecognizer(debugModeGestureRecognizer)
        
        // set the version label to show in settings screen
        self.versionLabel.text = getVersionLabel()
        
        self.versionLabel.numberOfLines = 0
        self.versionLabel.lineBreakMode = .byWordWrapping
        self.versionLabel.setNeedsUpdateConstraints()
        
        self.tableView.contentInset.bottom = 40
        
        self.update()
        
        if #available(iOS 15, *)
        {
            if let appearance = self.tabBarController?.tabBar.standardAppearance
            {
                appearance.stackedLayoutAppearance.normal.badgeBackgroundColor = .altPrimary
                self.navigationController?.tabBarItem.scrollEdgeAppearance = appearance
            }
            
            // We can only configure the contentMode for a button's background image from Interface Builder.
            // This works, but it means buttons don't visually highlight because there's no foreground image.
            // As a workaround, we manually set the foreground image + contentMode here.
            for button in [self.mastodonButton!, self.threadsButton!, self.twitterButton!, self.githubButton!]
            {
                // Get the assigned image from Interface Builder.
                let image = button.configuration?.background.image
                
                button.configuration = nil
                button.setImage(image, for: .normal)
                button.imageView?.contentMode = .scaleAspectFit
            }
        }
        
        configureReleaseChannelButton()
    }
    
    override func viewWillAppear(_ animated: Bool)
    {
        super.viewWillAppear(animated)
        
        // show nav bar if not shown already
        self.navigationController?.setNavigationBarHidden(false, animated: animated)
        
        self.update()
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "anisetteServers" {
            let controller = segue.destination
            
            // disable bottom tab bar since 'back' button is already available
//            controller.hidesBottomBarWhenPushed = true
            
            self.show(controller, sender: nil)
        } else {
            super.prepare(for: segue, sender: sender)
        }
    }

}


private extension SettingsViewController
{
    
    private func getVersionLabel() -> String {
        let buildInfo = BuildInfo()
        
        func getXcodeVersion() -> String {
            var xcodeVersion =  buildInfo.xcode.map { version in
                "Xcode \(version)" + (buildInfo.xcode_revision.map { revision in " - \(revision)" } ?? "")       // Ex: "0.6.0 - Xcode 16.2 - 21ac1ef"
            } ?? ""

            if let pairing = Bundle.main.object(forInfoDictionaryKey: "ALTPairingFile") as? String,
                pairing != "<insert pairing file here>"{
                xcodeVersion += " - true"
            }
            return xcodeVersion
        }

        
        var versionLabel: String = ""
        let installedApp = InstalledApp.fetchAltStore(in: DatabaseManager.shared.viewContext)
        // first check if there is installed app entity, if so, get version info from that
        if let installedApp
        {
            var localizedVersion = installedApp.version
            // Only show build version for non stable builds.
            localizedVersion += buildInfo.project_version.map{ version in
                version.isEmpty  ? "" : " (\(version))"
            } ?? installedApp.localizedVersion
        
            versionLabel = NSLocalizedString(String(format: "Version %@", localizedVersion), comment: "SideStore Version")
        }
        else if let version = buildInfo.marketing_version
        {
            versionLabel = NSLocalizedString(String(format: "Version %@", version), comment: "SideStore Version")
        }
        else
        {
            var version = "SideStore\t"
            version += "\n\(Bundle.Info.appbundleIdentifier)"
            versionLabel = NSLocalizedString(version, comment: "SideStore Version")
        }
        
        // add xcode build version for local builds
        if let installedApp,
           SemanticVersion(installedApp.version)?.preRelease == "local"
        {
            versionLabel += "\n\(getXcodeVersion())"
        }
        
        return versionLabel
    }
    
    
    func update()
    {
        if let team = DatabaseManager.shared.activeTeam()
        {
            self.accountNameLabel.text = team.name
            self.accountEmailLabel.text = team.account.appleID
            self.accountTypeLabel.text = team.type.localizedDescription
            
            self.activeTeam = team
        }
        else
        {
            self.activeTeam = nil
        }
        
        // AppRefreshRow
        self.backgroundRefreshSwitch.isOn = UserDefaults.standard.isBackgroundRefreshEnabled
        self.noIdleTimeoutSwitch.isOn = UserDefaults.standard.isIdleTimeoutDisableEnabled
        self.disableAppLimitSwitch.isOn = UserDefaults.standard.isAppLimitDisabled

        // AdvancedSettingsRow
        self.betaUpdatesSwitch.isOn = UserDefaults.standard.isBetaUpdatesEnabled
        self.betaTrackLabel.isEnabled = UserDefaults.standard.isBetaUpdatesEnabled
        self.betaTrackPopupButton.isEnabled = UserDefaults.standard.isBetaUpdatesEnabled

        // DiagnosticsRow
        self.disableResponseCachingSwitch.isOn = UserDefaults.standard.responseCachingDisabled
        self.exportResignedAppsSwitch.isOn = UserDefaults.standard.isExportResignedAppEnabled
        self.verboseOperationsLoggingSwitch.isOn = UserDefaults.standard.isVerboseOperationsLoggingEnabled
        self.minimuxerConsoleLoggingSwitch.isOn = UserDefaults.standard.isMinimuxerConsoleLoggingEnabled

        self.recreateDatabaseSwitch.isOn = UserDefaults.standard.recreateDatabaseOnNextStart

        if self.isViewLoaded
        {
            self.tableView.reloadData()
        }
    }
    
    func prepare(_ settingsHeaderFooterView: SettingsHeaderFooterView, for section: Section, isHeader: Bool)
    {
        settingsHeaderFooterView.primaryLabel.isHidden = !isHeader
        settingsHeaderFooterView.secondaryLabel.isHidden = isHeader
        settingsHeaderFooterView.button.isHidden = true
        
        settingsHeaderFooterView.layoutMargins.bottom = isHeader ? 0 : 8
        
        switch section
        {
        case .signIn:
            if isHeader
            {
                settingsHeaderFooterView.primaryLabel.text = NSLocalizedString("ACCOUNT", comment: "")
            }
            else
            {
                settingsHeaderFooterView.secondaryLabel.text = NSLocalizedString("Sign in with your Apple ID to download apps from SideStore.", comment: "")
            }
            
        case .patreon:
            if isHeader
            {
                settingsHeaderFooterView.primaryLabel.text = NSLocalizedString("SUPPORT US", comment: "")
            }
            else
            {
                settingsHeaderFooterView.secondaryLabel.text = NSLocalizedString("Support the SideStore Team by following our socials or becoming a patron!", comment: "")
            }

        case .account:
            settingsHeaderFooterView.primaryLabel.text = NSLocalizedString("ACCOUNT", comment: "")
            
            settingsHeaderFooterView.button.setTitle(NSLocalizedString("SIGN OUT", comment: ""), for: .normal)
            settingsHeaderFooterView.button.addTarget(self, action: #selector(SettingsViewController.signOut(_:)), for: .primaryActionTriggered)
            settingsHeaderFooterView.button.isHidden = false
            
        case .appRefresh:
            if isHeader
            {
                settingsHeaderFooterView.primaryLabel.text = NSLocalizedString("REFRESHING APPS", comment: "")
            }
            else
            {
                settingsHeaderFooterView.secondaryLabel.text = NSLocalizedString("Enable Background Refresh to automatically refresh apps in the background when connected to Wi-Fi. \n\nEnable Disable Idle Timeout to allow SideStore to keep your device awake during a refresh or install of any apps.", comment: "")
            }
            
        case .display:
            if isHeader
            {
                settingsHeaderFooterView.primaryLabel.text = NSLocalizedString("DISPLAY", comment: "")
            }
            else
            {
                settingsHeaderFooterView.secondaryLabel.text = NSLocalizedString("Personalize your SideStore experience by choosing an alternate app icon.", comment: "")
            }
            
            
        case .instructions:
            break
            
        case .techyThings:
            if isHeader
            {
                settingsHeaderFooterView.primaryLabel.text = NSLocalizedString("TECHY THINGS", comment: "")
            }
            else
            {
                settingsHeaderFooterView.secondaryLabel.text = NSLocalizedString("Free up disk space by removing non-essential data, such as temporary files and backups for uninstalled apps.", comment: "")
            }
            
        case .credits:
            settingsHeaderFooterView.primaryLabel.text = NSLocalizedString("CREDITS", comment: "")
            
        case .advancedSettings:
            settingsHeaderFooterView.primaryLabel.text = NSLocalizedString("ADVANCED SETTINGS", comment: "")
            
        case .signing:
            // FIXME: Why "Enable Background Refresh ..." appear here if secondaryLabel is not specified???
            if isHeader
            {
                settingsHeaderFooterView.primaryLabel.text = NSLocalizedString("SIGNING", comment: "")
            }
            else
            {
                settingsHeaderFooterView.secondaryLabel.text = NSLocalizedString("", comment: "")
            }

            
        case .diagnostics:
            settingsHeaderFooterView.primaryLabel.text = NSLocalizedString("DIAGNOSTICS", comment: "")
            
        // case .macDirtyCow:
        //     if isHeader
        //     {
        //         settingsHeaderFooterView.primaryLabel.text = NSLocalizedString("MACDIRTYCOW", comment: "")
        //     }
        //     else
        //     {
        //         settingsHeaderFooterView.secondaryLabel.text = NSLocalizedString("If you've removed the 3-sideloaded app limit via the MacDirtyCow exploit, disable this setting to sideload more than 3 apps at a time.", comment: "")
        //     }
            
        }
    }
    
    func preferredHeight(for settingsHeaderFooterView: SettingsHeaderFooterView, in section: Section, isHeader: Bool) -> CGFloat
    {
        let widthConstraint = settingsHeaderFooterView.contentView.widthAnchor.constraint(equalToConstant: tableView.bounds.width)
        NSLayoutConstraint.activate([widthConstraint])
        defer { NSLayoutConstraint.deactivate([widthConstraint]) }
        
        self.prepare(settingsHeaderFooterView, for: section, isHeader: isHeader)
        
        let size = settingsHeaderFooterView.contentView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        return size.height
    }
    
    func isSectionHidden(_ section: Section) -> Bool
    {
        switch section
        {
        // case .macDirtyCow:
        //     let isHidden = !(UserDefaults.standard.isCowExploitSupported && UserDefaults.standard.isDebugModeEnabled)
        //     return isHidden
            
        default: return false
        }
    }
}

private extension SettingsViewController
{
    func signIn()
    {
        AppManager.shared.authenticate(presentingViewController: self) { (result) in
            DispatchQueue.main.async {
                switch result
                {
                case .failure(OperationError.cancelled):
                    // Ignore
                    break
                    
                case .failure(let error):
                    let toastView = ToastView(error: error)
                    toastView.show(in: self)
                    
                case .success: break
                }
                
                self.update()
            }
        }
    }
    
    @objc func signOut(_ sender: UIBarButtonItem)
    {
        func signOut()
        {
            DatabaseManager.shared.signOut { (error) in
                DispatchQueue.main.async {
                    if let error = error
                    {
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
        //Fix crash on iPad
        alertController.popoverPresentationController?.barButtonItem = sender
        self.present(alertController, animated: true, completion: nil)
    }
    
    @IBAction func toggleDisableAppLimit(_ sender: UISwitch) {
        if UserDefaults.standard.isCowExploitSupported || !ProcessInfo().sparseRestorePatched {
            // accept state change only when valid
            UserDefaults.standard.isAppLimitDisabled = sender.isOn
            
            // TODO: Here we force reload the activeAppsLimit after detecting change in isAppLimitDisabled
            //       Why do we need to do this, once identified if this is intentional and working as expected, remove this todo
            if UserDefaults.standard.activeAppsLimit != nil
            {
                UserDefaults.standard.activeAppsLimit = InstalledApp.freeAccountActiveAppsLimit
            }
        }
    }
    
    @IBAction func toggleResignedAppExport(_ sender: UISwitch) {
        // update it in database
        UserDefaults.standard.isExportResignedAppEnabled = sender.isOn
    }

    @IBAction func toggleVerboseOperationsLogging(_ sender: UISwitch) {
        // update it in database
        UserDefaults.standard.isVerboseOperationsLoggingEnabled = sender.isOn
    }

    @IBAction func toggleMinimuxerConsoleLogging(_ sender: UISwitch) {
        // update it in database
        UserDefaults.standard.isMinimuxerConsoleLoggingEnabled = sender.isOn
    }

    @IBAction func toggleMinimuxerStatusCheck(_ sender: UISwitch) {
        // update it in database
        UserDefaults.standard.isMinimuxerStatusCheckEnabled = sender.isOn
    }

    @IBAction func toggleRecreateDatabaseSwitch(_ sender: UISwitch) {
        // Update the setting in UserDefaults
        UserDefaults.standard.recreateDatabaseOnNextStart = sender.isOn

        guard sender.isOn else { return }
        
        DispatchQueue.global().async {
            for time in (1...3).reversed() {
                DispatchQueue.main.async {
                    guard UserDefaults.standard.recreateDatabaseOnNextStart else {
                        return
                    }
                    let toast = ToastView(text: "Database Delete Scheduled on Next Launch", detailText: "App is closing in \(time) seconds...")
                    toast.tintColor = .altPrimary
                    toast.preferredDuration = 1
                    toast.show(in: self)
                }
                sleep(1) // Background sleep
            }

            DispatchQueue.main.async {
                guard UserDefaults.standard.recreateDatabaseOnNextStart else {
                    return
                }
                exit(0)
            }
        }
    }

    
    @IBAction func toggleEnableBetaUpdates(_ sender: UISwitch) {
        betaTrackLabel.isEnabled = sender.isOn
        betaTrackPopupButton.isEnabled = sender.isOn
        // update it in database
        UserDefaults.standard.isBetaUpdatesEnabled = sender.isOn
    }
    
    @IBAction func toggleIsBackgroundRefreshEnabled(_ sender: UISwitch)
    {
        UserDefaults.standard.isBackgroundRefreshEnabled = sender.isOn
    }
    
    @IBAction func toggleNoIdleTimeoutEnabled(_ sender: UISwitch)
    {
        UserDefaults.standard.isIdleTimeoutDisableEnabled = sender.isOn
    }
    
    @IBAction func toggleDisableResponseCaching(_ sender: UISwitch)
    {
        UserDefaults.standard.responseCachingDisabled = sender.isOn
    }
    
    func addRefreshAppsShortcut()
    {
        guard let shortcut = INShortcut(intent: INInteraction.refreshAllApps().intent) else { return }
        
        let viewController = INUIAddVoiceShortcutViewController(shortcut: shortcut)
        viewController.delegate = self
        viewController.modalPresentationStyle = .formSheet
        self.present(viewController, animated: true, completion: nil)
    }
    
    func clearCache()
    {
        let alertController = UIAlertController(title: NSLocalizedString("Are you sure you want to clear SideStore's cache?", comment: ""),
                                                message: NSLocalizedString("This will remove all temporary files as well as backups for uninstalled apps.", comment: ""),
                                                preferredStyle: .actionSheet)
        alertController.addAction(UIAlertAction(title: UIAlertAction.cancel.title, style: UIAlertAction.cancel.style) { [weak self] _ in
            self?.tableView.indexPathForSelectedRow.map { self?.tableView.deselectRow(at: $0, animated: true) }
        })
        alertController.addAction(UIAlertAction(title: NSLocalizedString("Clear Cache", comment: ""), style: .destructive) { [weak self] _ in
            AppManager.shared.clearAppCache { result in
                DispatchQueue.main.async {
                    self?.tableView.indexPathForSelectedRow.map { self?.tableView.deselectRow(at: $0, animated: true) }
                    
                    switch result
                    {
                    case .success: break
                    case .failure(let error):
                        let alertController = UIAlertController(title: NSLocalizedString("Unable to Clear Cache", comment: ""), message: error.localizedDescription, preferredStyle: .alert)
                        alertController.addAction(.ok)
                        self?.present(alertController, animated: true)
                    }
                }
            }
        })
        
        if let popoverController = alertController.popoverPresentationController {
            popoverController.sourceView = self.view
            popoverController.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 0, height: 0)
        }
        
        self.present(alertController, animated: true)
    }
    
    @IBAction func handleDebugModeGesture(_ gestureRecognizer: UISwipeGestureRecognizer)
    {
        self.debugGestureCounter += 1
        self.debugGestureTimer?.invalidate()
        
        if self.debugGestureCounter >= 3
        {
            self.debugGestureCounter = 0
            
            UserDefaults.standard.isDebugModeEnabled.toggle()
            self.tableView.reloadData()
        }
        else
        {
            self.debugGestureTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] (timer) in
                self?.debugGestureCounter = 0
            }
        }
    }
    
    func openTwitter(username: String)
    {
        let twitterAppURL = URL(string: "twitter://user?screen_name=" + username)!
        UIApplication.shared.open(twitterAppURL, options: [:]) { (success) in
            if success
            {
                if let selectedIndexPath = self.tableView.indexPathForSelectedRow
                {
                    self.tableView.deselectRow(at: selectedIndexPath, animated: true)
                }
            }
            else
            {
                let safariURL = URL(string: "https://twitter.com/" + username)!
                
                let safariViewController = SFSafariViewController(url: safariURL)
                safariViewController.preferredControlTintColor = .altPrimary
                self.present(safariViewController, animated: true, completion: nil)
            }
        }
    }
    
    func openMastodon(username: String)
    {
        // Rely on universal links to open app.
        
        let components = username.split(separator: "@")
        guard components.count == 2 else { return }
        
        let server = String(components[1])
        let username = "@" + String(components[0])
        
        guard let serverURL = URL(string: "https://" + server) else { return }
        
        let mastodonURL = serverURL.appendingPathComponent(username)
        UIApplication.shared.open(mastodonURL, options: [:])
    }
    
    func openThreads(username: String)
    {
        // Rely on universal links to open app.
        
        let safariURL = URL(string: "https://www.threads.net/@" + username)!
        UIApplication.shared.open(safariURL, options: [:])
    }
    
    @IBAction func followAltStoreMastodon()
    {
        self.openMastodon(username: "@sidestoreio@fosstodon.org")
    }
    
    @IBAction func followAltStoreThreads()
    {
        self.openThreads(username: "sidestore.io")
    }
    
    @IBAction func followAltStoreTwitter()
    {
        self.openTwitter(username: "sidestoreio")
    }
    
    @IBAction func followAltStoreGitHub()
    {
        let safariURL = URL(string: "https://github.com/SideStore")!
        UIApplication.shared.open(safariURL, options: [:])
    }
}

private extension SettingsViewController
{
    @objc func openPatreonSettings(_ notification: Notification)
    {
        guard self.presentedViewController == nil else { return }
                
        UIView.performWithoutAnimation {
            self.navigationController?.popViewController(animated: false)
            self.performSegue(withIdentifier: "showPatreon", sender: nil)
        }
    }

    @objc func openErrorLog(_: Notification) {
        guard self.presentedViewController == nil else { return }

        self.navigationController?.popViewController(animated: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.performSegue(withIdentifier: "showErrorLog", sender: nil)
        }
    }
    
    @objc func openExportCertificateConfirm(_ notification: Notification)
    {
        func export()
        {
            guard let template = notification.userInfo?[AppDelegate.exportCertificateCallbackTemplateKey] as? String,
                  template.contains("$(BASE64_CERT)") else {
                let toastView = ToastView(text: NSLocalizedString("No $(BASE64_CERT) placeholder found", comment: ""), detailText: nil)
                toastView.show(in: self)
                return
            }
            guard let data = Keychain.shared.signingCertificate,
            let password = Keychain.shared.signingCertificatePassword else {
                let toastView = ToastView(text: NSLocalizedString("Failed to find certificate or password", comment: ""), detailText: nil)
                toastView.show(in: self)
                return
            }
            let base64encodedCert = data.base64EncodedString()
            var allowedQueryParamAndKey = NSCharacterSet.urlQueryAllowed
            allowedQueryParamAndKey.remove(charactersIn: ";/?:@&=+$, ")
            guard let encodedCert = base64encodedCert.addingPercentEncoding(withAllowedCharacters: allowedQueryParamAndKey) else {
                let toastView = ToastView(text: NSLocalizedString("Failed to encode certificate!", comment: ""), detailText: nil)
                toastView.show(in: self)
                return
            }
            var urlStr = template.replacingOccurrences(of: "$(BASE64_CERT)", with: encodedCert, options: .literal, range: nil)
            urlStr = urlStr.replacingOccurrences(of: "$(PASSWORD)", with: password, options: .literal, range: nil)
            
            print(urlStr)
            guard let callbackUrl = URL(string: urlStr) else {
                let toastView = ToastView(text: NSLocalizedString("Failed to initialize callback URL!", comment: ""), detailText: nil)
                toastView.show(in: self)
                return
            }
            UIApplication.shared.open(callbackUrl)
        }
        
        let alertController = UIAlertController(title: NSLocalizedString("Export Certificate", comment: ""), message: NSLocalizedString("Do you want to export your certificate to an external app? That app will be able to sign apps using your certificate.", comment: ""), preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: NSLocalizedString("Export", comment: ""), style: .default) { _ in export() })
        alertController.addAction(.cancel)
        self.present(alertController, animated: true, completion: nil)
    }
}

extension SettingsViewController
{
    override func numberOfSections(in tableView: UITableView) -> Int
    {
        var numberOfSections = super.numberOfSections(in: tableView)
        
        if !UserDefaults.standard.isDebugModeEnabled
        {
            numberOfSections -= 1
        }
        
        return numberOfSections
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int
    {
        let section = Section.allCases[section]
        switch section
        {
        case _ where isSectionHidden(section): return 0
        case .signIn: return (self.activeTeam == nil) ? 1 : 0
        case .account: return (self.activeTeam == nil) ? 0 : 3
        case .appRefresh: return AppRefreshRow.allCases.count
        default: return super.tableView(tableView, numberOfRowsInSection: section.rawValue)
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell
    {
        let cell = super.tableView(tableView, cellForRowAt: indexPath)
        
        if #available(iOS 14, *) {}
        else if let cell = cell as? InsetGroupTableViewCell,
                indexPath.section == Section.appRefresh.rawValue,
                indexPath.row == AppRefreshRow.backgroundRefresh.rawValue
        {
            // Only one row is visible pre-iOS 14.
            cell.style = .single
        }
        
        if AppRefreshRow.AllCases().count == 1
        {
            if let cell = cell as? InsetGroupTableViewCell,
               indexPath.section == Section.appRefresh.rawValue,
               indexPath.row == AppRefreshRow.backgroundRefresh.rawValue
            {
                cell.style = .single
            }
        }
        
        if let cell = cell as? InsetGroupTableViewCell,
               indexPath.section == Section.appRefresh.rawValue,
               indexPath.row == AppRefreshRow.allCases.count-1      // last row
        {
            cell.setValue(3, forKey: "style")
        }
        
        
        return cell
    }
    
    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView?
    {
        let section = Section.allCases[section]
        switch section
        {
        case _ where isSectionHidden(section): return nil
        case .signIn where self.activeTeam != nil: return nil
        case .account where self.activeTeam == nil: return nil
        case .signIn, .account, .patreon, .display, .appRefresh, .techyThings, .credits, .advancedSettings, .signing ,.diagnostics /* ,.macDirtyCow */:
            let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "HeaderFooterView") as! SettingsHeaderFooterView
            self.prepare(headerView, for: section, isHeader: true)
            return headerView
            
        case .instructions: return nil
        }
    }
    
    override func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView?
    {
        let section = Section.allCases[section]
        switch section
        {
        case _ where isSectionHidden(section): return nil
        case .signIn where self.activeTeam != nil: return nil
        // case .signIn, .patreon, .display, .appRefresh, .techyThings, .macDirtyCow:
        case .signIn, .patreon, .display, .appRefresh, .techyThings, .signing:
            let footerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "HeaderFooterView") as! SettingsHeaderFooterView
            self.prepare(footerView, for: section, isHeader: false)
            return footerView
            
        case .account, .credits, .advancedSettings, .instructions, .diagnostics: return nil
        }
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat
    {
        let section = Section.allCases[section]
        switch section
        {
        case _ where isSectionHidden(section): return 1.0
        case .signIn where self.activeTeam != nil: return 1.0
        case .account where self.activeTeam == nil: return 1.0
        // case .signIn, .account, .patreon, .display, .appRefresh, .techyThings, .credits, .macDirtyCow, .advanced:
        case .signIn, .account, .patreon, .display, .appRefresh, .techyThings, .credits, .advancedSettings, .signing, .diagnostics:
            let height = self.preferredHeight(for: self.prototypeHeaderFooterView, in: section, isHeader: true)
            return height
            
        case .instructions: return 0.0
        }
    }
    
    override func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat
    {
        let section = Section.allCases[section]
        switch section
        {
        case _ where isSectionHidden(section): return 1.0
        case .signIn where self.activeTeam != nil: return 1.0
        case .account where self.activeTeam == nil: return 1.0            
        // case .signIn, .patreon, .display, .appRefresh, .techyThings, .macDirtyCow:
        case .signIn, .patreon, .display, .appRefresh, .techyThings, .signing, .diagnostics:
            let height = self.preferredHeight(for: self.prototypeHeaderFooterView, in: section, isHeader: false)
            return height
            
        case .account, .credits, .advancedSettings, .instructions: return 0.0
        }
    }
}

extension SettingsViewController
{
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath)
    {
        let section = Section.allCases[indexPath.section]
        switch section
        {
        case .signIn: self.signIn()
        case .appRefresh:
            let row = AppRefreshRow.allCases[indexPath.row]
            switch row
            {
            case .backgroundRefresh: break
            case .noIdleTimeout: break
            case .disableAppLimit: break
            case .addToSiri:
//                guard #available(iOS 14, *) else { return }   // our min deployment is iOS 15 now :) so commented out
                self.addRefreshAppsShortcut()
            }
            
        case .techyThings:
            let row = TechyThingsRow.allCases[indexPath.row]
            switch row
            {
            case .errorLog: break
            case .clearCache: self.clearCache()
            }
            
        case .credits:
            let row = CreditsRow.allCases[indexPath.row]
            switch row
            {
            case .developer: self.openTwitter(username: "sidestoreio")
            case .operations: self.openTwitter(username: "sidestoreio")
            case .designer: self.openTwitter(username: "lit_ritt")
            case .softwareLicenses: break
            }
            
            if let selectedIndexPath = self.tableView.indexPathForSelectedRow
            {
                self.tableView.deselectRow(at: selectedIndexPath, animated: true)
            }
            
        case .advancedSettings:
            let row = AdvancedSettingsRow.allCases[indexPath.row]
            switch row
            {
            case .sendFeedback:
                let alertController = UIAlertController(title: "Send Feedback", message: "Choose a method to send feedback:", preferredStyle: .actionSheet)
                
                // Option 1: GitHub
                alertController.addAction(UIAlertAction(title: "GitHub", style: .default) { _ in
                    if let githubURL = URL(string: "https://github.com/SideStore/SideStore/issues") {
                        let safariViewController = SFSafariViewController(url: githubURL)
                        safariViewController.preferredControlTintColor = .altPrimary
                        self.present(safariViewController, animated: true, completion: nil)
                    }
                })
                
                // Option 2: Discord
                alertController.addAction(UIAlertAction(title: "Discord", style: .default) { _ in
                    if let discordURL = URL(string: "https://discord.gg/sidestore-949183273383395328") {
                        let safariViewController = SFSafariViewController(url: discordURL)
                        safariViewController.preferredControlTintColor = .altPrimary
                        self.present(safariViewController, animated: true, completion: nil)
                    }
                })
                
                // Option 3: Mail
                alertController.addAction(UIAlertAction(title: "Send Email", style: .default) { _ in
                    if MFMailComposeViewController.canSendMail() {
                        let mailViewController = MFMailComposeViewController()
                        mailViewController.mailComposeDelegate = self
                        mailViewController.setToRecipients(["support@sidestore.io"])

                        // TODO: MARKETING_VERSION is going to be set anyways so this needs to be fixed for beta
                        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                            mailViewController.setSubject("SideStore Beta \(version) Feedback")
                        } else {
                            mailViewController.setSubject("SideStore Beta Feedback")
                        }

                       self.present(mailViewController, animated: true, completion: nil)
                    } else {
                      let toastView = ToastView(text: NSLocalizedString("Cannot Send Mail", comment: ""), detailText: nil)
                      toastView.show(in: self)
                    }
                })
                
                // Cancel action
                alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
                
                // For iPad: Set the source view if presenting on iPad to avoid crashes
                if let popoverController = alertController.popoverPresentationController {
                    popoverController.sourceView = self.view
                    popoverController.sourceRect = self.view.bounds
                }
                
                // Present the action sheet
                self.present(alertController, animated: true, completion: nil)
                
            case .refreshSideJITServer:
                if #available(iOS 17, *) {
                
                   let alertController = UIAlertController(
                      title: NSLocalizedString("SideJITServer", comment: ""),
                      message: NSLocalizedString("Settings for SideJITServer", comment: ""),
                      preferredStyle: UIAlertController.Style.actionSheet)
                    
                    
                    if UserDefaults.standard.sidejitenable {
                        alertController.addAction(UIAlertAction(title: NSLocalizedString("Disable", comment: ""), style: .default){ _ in
                            UserDefaults.standard.sidejitenable = false
                        })
                    } else {
                        alertController.addAction(UIAlertAction(title: NSLocalizedString("Enable", comment: ""), style: .default){ _ in
                            UserDefaults.standard.sidejitenable = true
                        })
                    }
                    
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("Server Address", comment: ""), style: .default){ _ in
                        let alertController1 = UIAlertController(title: "SideJITServer Address", message: "Please Enter the SideJITServer Address Below. (this is not needed if SideJITServer has already been detected)", preferredStyle: .alert)
                        

                        alertController1.addTextField { textField in
                            textField.placeholder = "SideJITServer Address"
                        }
                        
                        
                        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
                        alertController1.addAction(cancelAction)
                        

                        let okAction = UIAlertAction(title: "OK", style: .default) { _ in
                            if let text = alertController1.textFields?.first?.text {
                                UserDefaults.standard.textInputSideJITServerurl = text
                            }
                        }
                        
                        alertController1.addAction(okAction)
                        
                        // Present the alert controller
                        self.present(alertController1, animated: true)
                    })
                    

                   alertController.addAction(UIAlertAction(title: NSLocalizedString("Refresh", comment: ""), style: .destructive){ _ in
                      if UserDefaults.standard.sidejitenable {
                         var SJSURL = ""
                          if (UserDefaults.standard.textInputSideJITServerurl ?? "").isEmpty {
                            SJSURL = "http://sidejitserver._http._tcp.local:8080"
                         } else {
                            SJSURL = UserDefaults.standard.textInputSideJITServerurl ?? ""
                         }
                        
                          
                         let url = URL(string: SJSURL + "/re/")!

                         let task = URLSession.shared.dataTask(with: url) { (data, response, error) in
                            if let error = error {
                               print("Error: \(error)")
                            } else {
                               // Do nothing with data or response
                            }
                         }

                         task.resume()
                      }
                   })
                    

                   let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
                   alertController.addAction(cancelAction)
                   //Fix crash on iPad
                   alertController.popoverPresentationController?.sourceView = self.tableView
                   alertController.popoverPresentationController?.sourceRect = self.tableView.rectForRow(at: indexPath)
                   self.present(alertController, animated: true)
                   self.tableView.deselectRow(at: indexPath, animated: true)
                } else {
                   let alertController = UIAlertController(
                      title: NSLocalizedString("You are not on iOS 17+ This will not work", comment: ""),
                      message: NSLocalizedString("This is meant for 'SideJITServer' and it only works on iOS 17+ ", comment: ""),
                      preferredStyle: UIAlertController.Style.actionSheet)

                   alertController.addAction(.cancel)
                   //Fix crash on iPad
                   alertController.popoverPresentationController?.sourceView = self.tableView
                   alertController.popoverPresentationController?.sourceRect = self.tableView.rectForRow(at: indexPath)
                   self.present(alertController, animated: true)
                   self.tableView.deselectRow(at: indexPath, animated: true)
                }
                
            case .resetPairingFile:
                
                let filename = "ALTPairingFile.mobiledevicepairing"
                
                let fm = FileManager.default
                
                let documentsPath = fm.documentsDirectory.appendingPathComponent("/\(filename)")
                let alertController = UIAlertController(
                    title: NSLocalizedString("Are you sure to reset the pairing file?", comment: ""),
                    message: NSLocalizedString("You can reset the pairing file when you cannot sideload apps or enable JIT. You need to restart SideStore.", comment: ""),
                    preferredStyle: UIAlertController.Style.actionSheet)
                
                alertController.addAction(UIAlertAction(title: NSLocalizedString("Delete and Reset", comment: ""), style: .destructive){ _ in
                    if fm.fileExists(atPath: documentsPath.path), let contents = try? String(contentsOf: documentsPath), !contents.isEmpty {
                        UserDefaults.standard.isPairingReset = true
                        try? fm.removeItem(atPath: documentsPath.path)
                        NSLog("Pairing File Reseted")
                    }
                    self.tableView.deselectRow(at: indexPath, animated: true)
                    let dialogMessage = UIAlertController(title: NSLocalizedString("Pairing File Reset", comment: ""), message: NSLocalizedString("Please restart SideStore", comment: ""), preferredStyle: .alert)
                    self.present(dialogMessage, animated: true, completion: nil)
                })
                alertController.addAction(.cancel)
                //Fix crash on iPad
                alertController.popoverPresentationController?.sourceView = self.tableView
                alertController.popoverPresentationController?.sourceRect = self.tableView.rectForRow(at: indexPath)
                self.present(alertController, animated: true)
                self.tableView.deselectRow(at: indexPath, animated: true)
                
            case .anisetteServers:
                
                func handleRefreshResult(_ result: Result<Void, any Error>) {
                    var message = "Servers list refreshed"
                    var details: String? = nil
                    var duration: TimeInterval = 2.0
                                        
                    switch result {
                        case .success:
                            // No additional action needed, default message is sufficient
                            break
                        case .failure(let error):
                            message  = "Failed to refresh servers list"
                            details  = String(describing: error)
                            duration = 4.0
                    }
                    
                    let toast = ToastView(text: message, detailText: details)
                    toast.preferredDuration = duration
                    toast.show(in: self)
                }
                
                // Instantiate SwiftUI View inside UIHostingController
                let anisetteServersView = AnisetteServersView(selected: UserDefaults.standard.menuAnisetteURL, errorCallback: {
                    ToastView(text: "Cleared adi.pb!", detailText: "You will need to log back into Apple ID in SideStore.")
                        .show(in: self)
                }, refreshCallback: {result in
                    handleRefreshResult(result)
                })
                
                let anisetteServersController = UIHostingController(rootView: anisetteServersView)

                self.prepare(for: UIStoryboardSegue(identifier: "anisetteServers", source: self, destination: anisetteServersController), sender: nil)
                
//            case .hiddenSettings:
//                // Create the URL that deep links to your app's custom settings.
//                if let url = URL(string: UIApplication.openSettingsURLString) {
//                    // Ask the system to open that URL.
//                    UIApplication.shared.open(url)
//                } else {
//                    ELOG("UIApplication.openSettingsURLString invalid")
//                }
            case .refreshAttempts, .betaUpdates, .betaTrack: break

            }
        case .signing:
            let row = SigningSettingsRow.allCases[indexPath.row]
            switch row {
            case .importCert:
                Task {
                    let certUrl = await withUnsafeContinuation { c in
                        let importVc = UIDocumentPickerViewController(forOpeningContentTypes: [UTType(filenameExtension: "p12")!], asCopy: false)
                        ImportExport.documentPickerHandler = DocumentPickerHandler { url in
                            c.resume(returning: url)
                        }
                        importVc.delegate = ImportExport.documentPickerHandler

                        self.present(importVc, animated: true)
                        
                    }
                    guard let certUrl else {
                        return
                    }
                    
                    let password = await withUnsafeContinuation { (c: UnsafeContinuation<String?,Never>) in
                        let alertController = UIAlertController(title: NSLocalizedString("Please enter the password for the certificate.", comment: ""), message: nil, preferredStyle: .alert)
                        
                        alertController.addTextField { (textField) in
                            textField.autocorrectionType = .no
                            textField.autocapitalizationType = .none
                        }
                        
                        let submitAction = UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default) { (action) in
                            let textField = alertController.textFields?.first
                            
                            let code = textField?.text ?? ""
                            c.resume(returning: code)
                        }
                        alertController.addAction(submitAction)
                        alertController.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel) { (action) in
                            c.resume(returning: nil)
                        })
                        
                        self.present(alertController, animated: true)
                    }
                    
                    guard let password else {
                        return
                    }
                    let _ = certUrl.startAccessingSecurityScopedResource()
                    defer {
                        certUrl.stopAccessingSecurityScopedResource()
                    }
                    let certData : Data
                    do {
                        certData = try Data(contentsOf: certUrl)
                    } catch {
                        let toastView = ToastView(text: NSLocalizedString("Failed to import certificate!", comment: ""), detailText: error.localizedDescription)
                        toastView.show(in: self)
                        return
                    }
                    
                    guard let altCert = ALTCertificate(p12Data: certData, password: password) else {
                        let toastView = ToastView(text: NSLocalizedString("Failed to import certificate!", comment: ""), detailText: "Failed to create ALTCertificate. Check if the password is correct.")
                        toastView.show(in: self)
                        return
                    }
                    
                    Keychain.shared.signingCertificate = altCert.encryptedP12Data(withPassword: "")!
                    let toastView = ToastView(text: NSLocalizedString("Certificate imported successfully!", comment: ""), detailText: nil)
                    toastView.show(in: self)
                }

                break
            case .exportCert:
                Task {
                    guard let certData = Keychain.shared.signingCertificate else {
                        let toastView = ToastView(text: NSLocalizedString("Failed to export certificate!", comment: ""), detailText: "Certificate not found.")
                        toastView.show(in: self)
                        return
                    }
                    
                    let password = await withUnsafeContinuation { (c: UnsafeContinuation<String?,Never>) in
                        let alertController = UIAlertController(title: NSLocalizedString("Please enter the password for the certificate.", comment: ""), message: nil, preferredStyle: .alert)
                        
                        alertController.addTextField { (textField) in
                            textField.autocorrectionType = .no
                            textField.autocapitalizationType = .none
                        }
                        
                        let submitAction = UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default) { (action) in
                            let textField = alertController.textFields?.first
                            
                            let code = textField?.text ?? ""
                            c.resume(returning: code)
                        }
                        alertController.addAction(submitAction)
                        alertController.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel) { (action) in
                            c.resume(returning: nil)
                        })
                        
                        self.present(alertController, animated: true)
                    }
                    
                    guard let password else {
                        return
                    }
                    
                    guard let altCert = ALTCertificate(p12Data: certData, password: nil) else {
                        let toastView = ToastView(text: NSLocalizedString("Failed to export certificate!", comment: ""), detailText: "Failed to create ALTCertificate. Check if the password is correct.")
                        toastView.show(in: self)
                        return
                    }
                    
                    guard let newCertData = altCert.encryptedP12Data(withPassword: password) else {
                        let toastView = ToastView(text: NSLocalizedString("Failed to export certificate!", comment: ""), detailText: "Failed to encrypt  ALTCertificate.")
                        toastView.show(in: self)
                        return
                    }
                    
                    let newCertTmpPath = FileManager.default.temporaryDirectory.appendingPathComponent("SideStoreSigningCertificate.p12")
                    do {
                        try newCertData.write(to: newCertTmpPath)
                    } catch {
                        let toastView = ToastView(text: NSLocalizedString("Failed to export certificate!", comment: ""), detailText: error.localizedDescription)
                        toastView.show(in: self)
                        return
                    }
                    let exportVC = UIDocumentPickerViewController(forExporting: [newCertTmpPath], asCopy: false)
                    self.present(exportVC, animated: true)
                }
                break
            }
            
        case .diagnostics:
            let row = DiagnosticsRow.allCases[indexPath.row]
            switch row {
                
            case .deleteDatabase:
                if !Self.deleteDBInProgress {
                    Self.deleteDBInProgress = true
                    
                    _ = DatabaseManager.deleteDatabase()
                    
                    exit(0) // exit app immediately to prevent db usage and crashes
                }
                
            case .exportDatabase:
                // do not accept simulatenous export requests
                if !Self.exportDBInProgress {
                    Self.exportDBInProgress = true
                    Task{
                        var toastView: ToastView?
                        do{
                            let exportedURL = try await CoreDataHelper.exportCoreDataStore()
                            print("exportSqliteDB: ExportedURL: \(exportedURL)")
                            toastView = ToastView(text: "Export Successful", detailText: nil)
                        }catch{
                            print("exportSqliteDB: \(error)")
                            toastView = ToastView(error: error)
                        }
                        
                        // show toast to user about the result
                        DispatchQueue.main.async {
                            toastView?.show(in: self)
                        }
                        
                        // update that work has finished
                        Self.exportDBInProgress = false
                    }
                }
                
            case .operationsLoggingControl:
                
                // Instantiate SwiftUI View inside UIHostingController
                let operationsLoggingControlView = OperationsLoggingControlView()
                let operationsLoggingController = UIHostingController(rootView: operationsLoggingControlView)
                let segue = UIStoryboardSegue(identifier: "operationsLoggingControl", source: self, destination: operationsLoggingController)
                self.present(segue.destination, animated: true, completion: nil)
                
            case .responseCaching, .exportResignedApp, .verboseOperationsLogging, .minimuxerConsoleLogging, .recreateDatabase : break
            }
            
            
        // case .account, .patreon, .display, .instructions, .macDirtyCow: break
        case .account, .patreon, .display, .instructions: break
        }
        
        
        // deselect the row before returning (so that it doesn't look like stuck selected)
        tableView.deselectRow(at: indexPath, animated: true)
    }
}

extension SettingsViewController: MFMailComposeViewControllerDelegate
{
    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?)
    {
        if let error = error
        {
            let toastView = ToastView(error: error)
            toastView.show(in: self)
        }
        
        controller.dismiss(animated: true, completion: nil)
    }
}

extension SettingsViewController: UIGestureRecognizerDelegate
{
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool
    {
        return true
    }
}

extension SettingsViewController: INUIAddVoiceShortcutViewControllerDelegate
{
    func addVoiceShortcutViewController(_ controller: INUIAddVoiceShortcutViewController, didFinishWith voiceShortcut: INVoiceShortcut?, error: Error?)
    {
        if let indexPath = self.tableView.indexPathForSelectedRow
        {
            self.tableView.deselectRow(at: indexPath, animated: true)
        }
        
        controller.dismiss(animated: true, completion: nil)
        
        guard let error = error else { return }
        
        let toastView = ToastView(error: error)
        toastView.show(in: self)
    }
    
    func addVoiceShortcutViewControllerDidCancel(_ controller: INUIAddVoiceShortcutViewController)
    {
        if let indexPath = self.tableView.indexPathForSelectedRow
        {
            self.tableView.deselectRow(at: indexPath, animated: true)
        }
        
        controller.dismiss(animated: true, completion: nil)
    }
}
