//
//  SettingsViewController.swift
//  AltStore
//
//  Created by Riley Testut on 8/31/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

@preconcurrency import UIKit
import SwiftUI
#if !os(tvOS)
import MessageUI
#endif
import Intents
#if !os(tvOS)
import IntentsUI
#endif

import SemanticVersion
import SideSign
import UniformTypeIdentifiers

extension SettingsViewController
{
    private enum Section: Int, CaseIterable
    {
        case signIn
        case account
        case patreon
        case display
        case appRefresh
        case instructions
        case techyThings
        case credits
        case betaTesting
        case advancedSettings
        case diagnostics    // diagnostics section, will be enabled on release builds only on swipe down with 3 fingers 3 times
        // case macDirtyCow
    }
    
    private enum AppRefreshRow: Int, CaseIterable
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
    
    private enum CreditsRow: Int, CaseIterable
    {
        case developer
        case operations
        case designer
        case softwareLicenses
    }
    
    private enum TechyThingsRow: Int, CaseIterable
    {
        case healthCheck
        case errorLog
        case storageExplorer
        case clearCache
    }
    private enum AdvancedSettingsRow: Int, CaseIterable
    {
        case sendFeedback           // row 0 - Send Feedback
        case refreshAttempts        // row 1 - View Refresh Attempts
        case refreshSideJITServer   // row 2 - SideJITServer
        case resetPairingFile       // row 3 - Reset Pairing File
        case anisetteServers        // row 4 - Anisette Servers
        case connectionConfig       // row 5 - Connection Configuration
        case developerServices      // row 6 - Developer Portal Services
        case certificateManagement  // row 7 - Certificate Management
        case backupAndRestore       // row 8 - Backup & Restore
        case userCustomizations     // row 9 - User Customizations

        static var allCases: [AdvancedSettingsRow] {
            var rows: [AdvancedSettingsRow] = [.sendFeedback, .refreshAttempts, .refreshSideJITServer, .resetPairingFile]
            if !UserDefaults.standard.useOnDeviceAnisette {
                rows.append(.anisetteServers)
            }
            rows.append(contentsOf: [
                .connectionConfig,
                .developerServices,
                .certificateManagement,
                .backupAndRestore,
                .userCustomizations
            ])
            return rows
        }
    }

    private enum BetaTestingRow: Int, CaseIterable {
        case betaUpdates
        case betaTrack
    }

    private enum DiagnosticsRow: Int, CaseIterable
    {
        case developerOptions            // row 0 - Developer Options
        case experimentalFeatures        // row 1 - Experimental Features
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
    @IBOutlet private var verboseOperationsLoggingSwitch: UISwitch!
    @IBOutlet private var altSignVerboseLoggingSwitch: UISwitch!
    @IBOutlet private var minimuxerVerboseLoggingSwitch: UISwitch!
    @IBOutlet private var rotateLogsOnStartupSwitch: UISwitch!
    
//    @IBOutlet private var refreshSideJITServer: UILabel!
    @IBOutlet private var disableResponseCachingSwitch: UISwitch!
    
    @IBOutlet private var mastodonButton: UIButton!
    @IBOutlet private var threadsButton: UIButton!
    @IBOutlet private var twitterButton: UIButton!
    @IBOutlet private var githubButton: UIButton!
    
    @IBOutlet private var versionLabel: UILabel!
    
    @IBOutlet private var recreateDatabaseSwitch: UISwitch!
    
    #if !os(tvOS)
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    #endif
    
    private static var exportDBInProgress = false
    private static var deleteDBInProgress = false
    
    required init?(coder aDecoder: NSCoder)
    {
        super.init(coder: aDecoder)
        
        NotificationCenter.default.addObserver(self, selector: #selector(SettingsViewController.openPatreonSettings(_:)), name: AppDelegate.openPatreonSettingsDeepLinkNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(SettingsViewController.openErrorLog(_:)), name: ToastView.openErrorLogNotification, object: nil)
    }
    
    
    private func handleReleaseChannelSelection(_ channel: String) {
        // Update your model/preferences
        UserDefaults.standard.betaUdpatesTrack = channel
        updateReleaseChannelButtonTitle()
    }
    
    private func updateReleaseChannelButtonTitle() {
        let channel = UserDefaults.standard.betaUdpatesTrack ?? UserDefaults.defaultBetaUpdatesTrack
        let displayTitle = ReleaseTrackType(rawValue: channel)?.displayName ?? channel
        betaTrackPopupButton.setTitle(displayTitle, for: .normal)
    }
    
    private func configureReleaseChannelButton() {
        let currentTrack = UserDefaults.standard.betaUdpatesTrack
        
        // get all tracks as string available except .stable and .unknown
        var trackOptions: [String] = ReleaseTrackType.betaTracks.map {$0.rawValue}

        if let currentTrack{
            // prepend currently selected beta track from the user defaults
            trackOptions = [currentTrack] + trackOptions.filter { $0 != currentTrack }
        }
    
        // Create menu items with proper styling
        let items = trackOptions.map{ channel in
            let displayTitle = ReleaseTrackType(rawValue: channel)?.displayName ?? channel
            return UIAction(title: displayTitle, handler: { [weak self] _ in
                self?.handleReleaseChannelSelection(channel)
            })
        }
        
        // Create menu with proper styling
        let menu = UIMenu(title: "",
                         options: [.singleSelection, .displayInline], // Add displayInline
                         children: items
        )
        #if !os(tvOS)
        betaTrackPopupButton.menu = menu
        #else
        if #available(tvOS 17.0, *) {
            betaTrackPopupButton.menu = menu
        }
        #endif

        // Set initial state
        updateReleaseChannelButtonTitle()
    }


    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        #if !os(tvOS)
        // --- iOS 26 fix ---
        if #available(iOS 26.0, *) {
            let appearance = UINavigationBarAppearance()
            appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
            appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
            navigationController?.navigationBar.standardAppearance = appearance
            navigationController?.navigationBar.scrollEdgeAppearance = appearance       // required for iOS 26, maybe enforce it in storyboard?
        }
        #endif 
        let nib = UINib(nibName: "SettingsHeaderFooterView", bundle: nil)
        self.prototypeHeaderFooterView = nib.instantiate(withOwner: nil, options: nil)[0] as? SettingsHeaderFooterView
        
        self.tableView.register(nib, forHeaderFooterViewReuseIdentifier: "HeaderFooterView")
        
        let debugModeGestureRecognizer = UISwipeGestureRecognizer(target: self, action: #selector(SettingsViewController.handleDebugModeGesture(_:)))
        debugModeGestureRecognizer.delegate = self
        debugModeGestureRecognizer.direction = .up
        #if !os(tvOS)
        debugModeGestureRecognizer.numberOfTouchesRequired = 3
        #endif
        self.tableView.addGestureRecognizer(debugModeGestureRecognizer)
        
        // set the version label to show in settings screen
        self.versionLabel.attributedText = getVersionAttributedString()
        self.versionLabel.isUserInteractionEnabled = true
        self.versionLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(copyVersionLabelTapped)))
        
        self.versionLabel.numberOfLines = 0
        self.versionLabel.lineBreakMode = .byWordWrapping
        self.versionLabel.setNeedsUpdateConstraints()
        
        self.tableView.contentInset.bottom = 40
        
        self.update()
        
        #if !os(tvOS)
        if let appearance = self.tabBarController?.tabBar.standardAppearance
        {
            appearance.stackedLayoutAppearance.normal.badgeBackgroundColor = .altPrimary
            self.navigationController?.tabBarItem.scrollEdgeAppearance = appearance
        }
        #endif
        
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
        if segue.identifier == "anisetteServers" || segue.identifier == "developerServices" || segue.identifier == "certificateManagement" || segue.identifier == "diagnostics" {
            let controller = segue.destination
            
        #if !os(tvOS)
            if segue.identifier == "anisetteServers"        || 
                segue.identifier == "developerServices"      ||
                segue.identifier == "certificateManagement" || 
                segue.identifier == "diagnostics"
            {
                let appearance = UINavigationBarAppearance()
                appearance.configureWithDefaultBackground()
                appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
                appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
                controller.navigationItem.largeTitleDisplayMode = .always
                controller.navigationItem.standardAppearance = appearance
                controller.navigationItem.scrollEdgeAppearance = appearance
            }
        #endif
            
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
    
    private func getVersionAttributedString() -> NSAttributedString {
        let appVersion = Bundle.Info.activeBundleVersion
        let iosVersion = "iOS \(UIDevice.current.systemVersion) (\(ProcessInfo.processInfo.operatingSystemBuild))"
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineSpacing = 4
        
        let fullString = NSMutableAttributedString()
        
        let appVersionAttr = NSAttributedString(
            string: appVersion,
            attributes: [
                .font: UIFont.systemFont(ofSize: 14),
                .foregroundColor: UIColor.white.withAlphaComponent(0.7),
                .paragraphStyle: paragraphStyle
            ]
        )
        
        let iosVersionAttr = NSAttributedString(
            string: "\n" + iosVersion,
            attributes: [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: UIColor.white.withAlphaComponent(0.5),
                .paragraphStyle: paragraphStyle
            ]
        )
        
        fullString.append(appVersionAttr)
        fullString.append(iosVersionAttr)
        return fullString
    }
    
    @objc private func copyVersionLabelTapped() {
        let appVersion = Bundle.Info.activeBundleVersion
        let iosVersion = "iOS \(UIDevice.current.systemVersion) (\(ProcessInfo.processInfo.operatingSystemBuild))"
        let fullText = "\(appVersion)\n\(iosVersion)"
        #if !os(tvOS)
        UIPasteboard.general.string = fullText.hasPrefix("Version ") ? String(fullText.dropFirst("Version ".count)) : fullText
        #endif
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let attributed = NSMutableAttributedString(
            string: "Copied! ",
            attributes: [
                .font: UIFont.systemFont(ofSize: 14),
                .foregroundColor: UIColor.white.withAlphaComponent(0.7),
                .paragraphStyle: paragraphStyle
            ]
        )
        attributed.append(NSAttributedString(string: "✓", attributes: [
            .font: UIFont.systemFont(ofSize: 14),
            .foregroundColor: UIColor.systemGreen
        ]))
        self.versionLabel.attributedText = attributed
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.versionLabel.attributedText = self?.getVersionAttributedString()
        }
    }
    
    
    func update()
    {
        let currentActiveTeam = DatabaseManager.shared.activeTeam()
        verboseLog("[SettingsVC] update() called. activeTeam: \(currentActiveTeam?.identifier ?? "nil"), account: \(currentActiveTeam?.account.appleID ?? "nil")")
        
        if let team = currentActiveTeam, AuthManager.shared.isAuthenticated
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

        // BetaTestingRow
        self.betaUpdatesSwitch.isOn = UserDefaults.standard.isBetaUpdatesEnabled
        self.betaTrackPopupButton.isEnabled = UserDefaults.standard.isBetaUpdatesEnabled

        // DiagnosticsRow
        // DiagnosticsRow (managed via DeveloperOptionsView)
        self.disableResponseCachingSwitch?.isOn = UserDefaults.standard.responseCachingDisabled
        self.verboseOperationsLoggingSwitch?.isOn = UserDefaults.standard.isVerboseOperationsLoggingEnabled
        self.altSignVerboseLoggingSwitch?.isOn = UserDefaults.standard.isAltSignVerboseLoggingEnabled
        self.minimuxerVerboseLoggingSwitch?.isOn = UserDefaults.standard.isMinimuxerVerboseLoggingEnabled
        self.rotateLogsOnStartupSwitch?.isOn = UserDefaults.standard.isRotateLogsOnStartupEnabled
        self.recreateDatabaseSwitch?.isOn = UserDefaults.standard.recreateDatabaseOnNextStart

        if self.isViewLoaded
        {
            self.tableView.reloadData()
        }
    }
    
    private func prepare(_ settingsHeaderFooterView: SettingsHeaderFooterView, for section: Section, isHeader: Bool)
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

        case .betaTesting:
            if isHeader
            {
                settingsHeaderFooterView.primaryLabel.text = NSLocalizedString("BETA TESTING", comment: "")
            }
            else
            {
                settingsHeaderFooterView.secondaryLabel.text = NSLocalizedString(
                    """
                    Opt in for beta testing to receive regular updates and early previews of upcoming releases.\n
                    Please note that these builds are experimental and may be unstable or break unexpectedly.
                    """,
                    comment: ""
                )
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
    
    private func preferredHeight(for settingsHeaderFooterView: SettingsHeaderFooterView, in section: Section, isHeader: Bool) -> CGFloat
    {
        let widthConstraint = settingsHeaderFooterView.contentView.widthAnchor.constraint(equalToConstant: tableView.bounds.width)
        NSLayoutConstraint.activate([widthConstraint])
        defer { NSLayoutConstraint.deactivate([widthConstraint]) }
        
        self.prepare(settingsHeaderFooterView, for: section, isHeader: isHeader)
        
        let size = settingsHeaderFooterView.contentView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        return size.height
    }
    
    private func isSectionHidden(_ section: Section) -> Bool
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
        debugLog("[SettingsVC] signIn() invoked by user action")
        AppManager.shared.signIn(presentingViewController: self) { [weak self] (result) in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result
                {
                case .failure(let error) where error is CancellationError:
                    debugLog("[SettingsVC] signIn() authentication cancelled by user")
                    break
                    
                case .failure(let error):
                    debugLog("[SettingsVC] signIn() authentication failed with error: \(error)")
                    let toastView = ToastView(error: error)
                    toastView.show(in: self.view)
                    
                case .success(let (team, _, _)):
                    debugLog("[SettingsVC] signIn() authentication succeeded for team: \(team.name) (\(team.identifier))")
                }
                
                debugLog("[SettingsVC] signIn() calling update()...")
                self.update()
            }
        }
    }
    
    @objc func signOut(_ sender: UIBarButtonItem)
    {
        debugLog("[SettingsVC] signOut() invoked by user action")
        let contentVC = SignOutAlertViewController()
        
        let alertController = UIAlertController(
            title: NSLocalizedString("Sign Out", comment: ""),
            message: NSLocalizedString("Are you sure you want to sign out? You will no longer be able to install or refresh apps once you sign out.", comment: ""),
            preferredStyle: .alert
        )
        
        alertController.setValue(contentVC, forKey: "contentViewController")
        
        let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil)
        
        let signOutAction = UIAlertAction(title: NSLocalizedString("Sign Out", comment: ""), style: .destructive) { _ in
            let keepCert = contentVC.isChecked
            let keepAnisette = contentVC.isKeepAnisetteChecked
            let keepAnisetteHeaders = contentVC.isKeepAnisetteHeadersChecked
            let keepSideSignHeaders = contentVC.isKeepSideSignHeadersChecked
            AuthManager.shared.signOut(
                keepCertificate: keepCert,
                keepAnisetteData: keepAnisette,
                keepAnisetteHeaders: keepAnisetteHeaders,
                keepSideSignHeaders: keepSideSignHeaders
            )
            self.update()
        }
        
        alertController.addAction(cancelAction)
        alertController.addAction(signOutAction)
        
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
    
    @IBAction func toggleVerboseOperationsLogging(_ sender: UISwitch) {
        // update it in database
        UserDefaults.standard.isVerboseOperationsLoggingEnabled = sender.isOn
    }

    @IBAction func toggleAltSignVerboseLogging(_ sender: UISwitch) {
        // update it in database
        UserDefaults.standard.isAltSignVerboseLoggingEnabled = sender.isOn
        AltSign.setLogging(sender.isOn)
    }

    @IBAction func toggleMinimuxerVerboseLogging(_ sender: UISwitch) {
        // update it in database
        UserDefaults.standard.isMinimuxerVerboseLoggingEnabled = sender.isOn
        minimuxerSetLogging(sender.isOn)
    }

    @IBAction func toggleRotateLogsOnStartup(_ sender: UISwitch) {
        UserDefaults.standard.isRotateLogsOnStartupEnabled = sender.isOn
        let suffixFormat: SuffixFormat = sender.isOn ? .timestamp : .none
        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        appDelegate.consoleLog.updateConfiguration(baseName: "console", suffixFormat: suffixFormat, policy: .immediate)
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
                    let toast = ToastView(text: NSLocalizedString("Database Delete Scheduled on Next Launch", comment: ""), detailText: String(format: NSLocalizedString("App is closing in %d seconds...", comment: ""), time))
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
    
    #if !os(tvOS)
    func addRefreshAppsShortcut()
    {
        guard let shortcut = INShortcut(intent: INInteraction.refreshAllApps().intent) else { return }
        
        let viewController = INUIAddVoiceShortcutViewController(shortcut: shortcut)
        viewController.delegate = self
        viewController.modalPresentationStyle = .formSheet
        self.present(viewController, animated: true, completion: nil)
    }
    #endif
    
    func clearCache()
    {
        let makeCacheTitle: (String) -> String = { sizeString in
            String(format: NSLocalizedString("Are you sure you want to clear SideStore's cache?\n\nCache Size: %@", comment: ""), sizeString)
        }
        let alertController = UIAlertController(title: makeCacheTitle(NSLocalizedString("Calculating…", comment: "")),
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
        
        // Update title once the actual cache size is computed in background
        CacheManager.shared.formattedCacheSize { [weak alertController] sizeString in
            DispatchQueue.main.async {
                alertController?.title = makeCacheTitle(sizeString)
            }
        }
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
                self.openWebURL(safariURL, preferredTintColor: .altPrimary)
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
        UIApplication.shared.open(AppConstants.URLs.sideStoreGitHub, options: [:])
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
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat
    {
        let effectiveIndexPath: IndexPath
        if Section.allCases[indexPath.section] == .advancedSettings {
            let row = AdvancedSettingsRow.allCases[indexPath.row]
            effectiveIndexPath = IndexPath(row: row.rawValue, section: indexPath.section)
        } else {
            effectiveIndexPath = indexPath
        }
        return super.tableView(tableView, heightForRowAt: effectiveIndexPath)
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
        case .advancedSettings: return AdvancedSettingsRow.allCases.count
        default: return super.tableView(tableView, numberOfRowsInSection: section.rawValue)
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell
    {
        let effectiveIndexPath: IndexPath
        if Section.allCases[indexPath.section] == .advancedSettings {
            let row = AdvancedSettingsRow.allCases[indexPath.row]
            effectiveIndexPath = IndexPath(row: row.rawValue, section: indexPath.section)
        } else {
            effectiveIndexPath = indexPath
        }
        let cell = super.tableView(tableView, cellForRowAt: effectiveIndexPath)
        

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
        case .signIn, .account, .patreon, .display, .appRefresh, .techyThings, .credits, .advancedSettings, .betaTesting, .diagnostics /* ,.macDirtyCow */:
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
        case .signIn, .patreon, .display, .appRefresh, .techyThings, .betaTesting:
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
        case .signIn, .account, .patreon, .display, .appRefresh, .techyThings, .credits, .advancedSettings, .betaTesting, .diagnostics:
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
        case .signIn, .patreon, .display, .appRefresh, .techyThings, .betaTesting:
            let height = self.preferredHeight(for: self.prototypeHeaderFooterView, in: section, isHeader: false)
            return height
            
        case .account, .credits, .advancedSettings, .instructions, .diagnostics: return 0.0
        }
    }
}

extension SettingsViewController
{
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath)
    {
        let section = Section.allCases[indexPath.section]
        verboseLog("[SettingsVC] didSelectRowAt: section \(section) (index \(indexPath.section)), row \(indexPath.row)")
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
                #if !os(tvOS)
                self.addRefreshAppsShortcut()
                #endif
            }
            
        case .techyThings:
            let row = TechyThingsRow.allCases[indexPath.row]
            switch row
            {
            case .healthCheck:
                let healthCheckView = HealthCheckView()
                let vc = UIHostingController(rootView: healthCheckView)
                
                #if !os(tvOS)
                let appearance = UINavigationBarAppearance()
                appearance.configureWithDefaultBackground()
                vc.navigationItem.scrollEdgeAppearance = appearance
                vc.navigationItem.standardAppearance = appearance
                #endif
                
                navigationController?.pushViewController(vc, animated: true)
                
            case .errorLog: break
            case .storageExplorer:
                verboseLog("[SettingsVC] Storage Explorer selected")
                StorageExplorerView.clearCache()
                func makeExplorerVC(url: URL? = nil) -> UIViewController {
                    let onSelectFolder: (URL) -> Void = { [weak self] targetURL in
                        guard let self = self else { return }
                        verboseLog("[SettingsVC] Navigating to child folder: \(targetURL.path)")
                        let childVC = makeExplorerVC(url: targetURL)
                        self.navigationController?.pushViewController(childVC, animated: true)
                    }
                    if let url = url {
                        verboseLog("[SettingsVC] Creating DirectoryExplorerView for: \(url.path)")
                        let view = DirectoryExplorerView(url: url, onSelectFolder: onSelectFolder)
                        return UIHostingController(rootView: view)
                    } else {
                        verboseLog("[SettingsVC] Creating root StorageExplorerView")
                        let view = StorageExplorerView(onSelectFolder: onSelectFolder)
                        return UIHostingController(rootView: view)
                    }
                }
                let vc = makeExplorerVC()
                verboseLog("[SettingsVC] Pushing root StorageExplorerView controller onto navigationController")
                navigationController?.pushViewController(vc, animated: true)
                
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
                let alertController = UIAlertController(title: NSLocalizedString("Send Feedback", comment: ""), message: NSLocalizedString("Choose a method to send feedback:", comment: ""), preferredStyle: .actionSheet)

                // Option 1: GitHub
                alertController.addAction(UIAlertAction(title: "GitHub", style: .default) { _ in
                    self.openWebURL(AppConstants.URLs.sideStoreIssues, preferredTintColor: .altPrimary)
                })

                // Option 2: Discord
                alertController.addAction(UIAlertAction(title: "Discord", style: .default) { _ in
                    self.openWebURL(AppConstants.URLs.sideStoreDiscord, preferredTintColor: .altPrimary)
                })

                #if !os(tvOS)
                // Option 3: Mail
                alertController.addAction(UIAlertAction(title: NSLocalizedString("Send Email", comment: ""), style: .default) { _ in
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
                #endif
                
                // Cancel action
                alertController.addAction(.cancel)
                
                // For iPad: Set the source view if presenting on iPad to avoid crashes
                if let popoverController = alertController.popoverPresentationController {
                    popoverController.sourceView = self.view
                    popoverController.sourceRect = self.view.bounds
                }
                
                // Present the action sheet
                self.present(alertController, animated: true, completion: nil)
                
            case .refreshSideJITServer:
                let jitConfigView = SideJITServerConfigView()
                let vc = UIHostingController(rootView: jitConfigView)
                #if !os(tvOS)
                let appearance = UINavigationBarAppearance()
                appearance.configureWithDefaultBackground()
                vc.navigationItem.scrollEdgeAppearance = appearance
                vc.navigationItem.standardAppearance = appearance
                #endif
                self.navigationController?.pushViewController(vc, animated: true)
                self.tableView.deselectRow(at: indexPath, animated: true)
                
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
                let anisetteServersView = AnisetteServersView(
                    selected: UserDefaults.standard.menuAnisetteURL,
                    onResetAdiPb: { [weak self] in
                        guard let self = self else { return }
                        ToastView(text: NSLocalizedString("Cleared adi.pb!", comment: ""), detailText: NSLocalizedString("You will need to log back into Apple ID in SideStore.", comment: ""))
                            .show(in: self)
                    }
                )
                
                let vc = UIHostingController(rootView: anisetteServersView)
                self.prepare(for: UIStoryboardSegue(identifier: "anisetteServers", source: self, destination: vc), sender: nil)

            case .connectionConfig:
                let connectionConfigView = ConnectionConfigView()
                let vc = UIHostingController(rootView: connectionConfigView)

                #if !os(tvOS)
                let appearance = UINavigationBarAppearance()
                appearance.configureWithDefaultBackground()   // gives solid background
                vc.navigationItem.scrollEdgeAppearance = appearance
                vc.navigationItem.standardAppearance = appearance
                #endif

                navigationController?.pushViewController(vc, animated: true)

            case .developerServices:
                let developerServicesView = DeveloperServicesView(presentingViewController: self)
                let vc = UIHostingController(rootView: developerServicesView)
                self.prepare(for: UIStoryboardSegue(identifier: "developerServices", source: self, destination: vc), sender: nil)

            case .certificateManagement:
                let certificateManagementView = CertificatesView(presentingViewController: self)
                let vc = UIHostingController(rootView: certificateManagementView)
                self.prepare(for: UIStoryboardSegue(identifier: "certificateManagement", source: self, destination: vc), sender: nil)
                
            case .backupAndRestore:
                let backupView = BackupAndRestoreView()
                let vc = UIHostingController(rootView: backupView)
                vc.view.backgroundColor = .settingsBackground
                vc.title = NSLocalizedString("Backup & Restore", comment: "")
                self.prepare(for: UIStoryboardSegue(identifier: "diagnostics", source: self, destination: vc), sender: nil)
                
            case .userCustomizations:
                let userCustomizationsView = UserCustomizationsView()
                let vc = UIHostingController(rootView: userCustomizationsView)
                vc.view.backgroundColor = .settingsBackground
                vc.title = NSLocalizedString("User Customizations", comment: "")
                self.prepare(for: UIStoryboardSegue(identifier: "diagnostics", source: self, destination: vc), sender: nil)
                
            case .refreshAttempts: break
            }
        
        case .diagnostics:
            let row = DiagnosticsRow.allCases[indexPath.row]
            switch row {
            case .developerOptions:
                let developerOptionsView = DeveloperOptionsView()
                let hostingController = UIHostingController(rootView: developerOptionsView)
                hostingController.view.backgroundColor = .settingsBackground
                hostingController.title = NSLocalizedString("Developer Options", comment: "")
                self.prepare(for: UIStoryboardSegue(identifier: "diagnostics", source: self, destination: hostingController), sender: nil)
            case .experimentalFeatures:
                let experimentalFeaturesView = ExperimentalFeaturesView()
                let hostingController = UIHostingController(rootView: experimentalFeaturesView)
                hostingController.view.backgroundColor = .settingsBackground
                hostingController.title = NSLocalizedString("Experimental Features", comment: "")
                self.prepare(for: UIStoryboardSegue(identifier: "diagnostics", source: self, destination: hostingController), sender: nil)
            }
            
            
        // case .account, .patreon, .display, .instructions, .macDirtyCow: break
        case .account, .patreon, .display, .instructions, .betaTesting: break
        }
        
        
        // deselect the row before returning (so that it doesn't look like stuck selected)
        tableView.deselectRow(at: indexPath, animated: true)
    }
}

#if !os(tvOS)
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
#endif

extension SettingsViewController: UIGestureRecognizerDelegate
{
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool
    {
        return true
    }
}

#if !os(tvOS)
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
#endif
