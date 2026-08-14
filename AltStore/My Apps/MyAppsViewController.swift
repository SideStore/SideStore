//
//  MyAppsViewController.swift
//  AltStore
//
//  Created by Riley Testut on 7/16/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

@preconcurrency import UIKit
@preconcurrency import Intents
@preconcurrency import AltSign
import SwiftUI
import MobileCoreServices
import Combine
import CoreData
import UniformTypeIdentifiers
import SemanticVersion

import Nuke

private let maximumCollapsedUpdatesCount = 2

extension MyAppsViewController
{
    private enum Section: Int, CaseIterable
    {
        case noUpdates
        case updates
        case activeApps
        case inactiveApps
    }
}

@objc(MyAppsViewController)
class MyAppsViewController: UICollectionViewController, PeekPopPreviewing
{
    private let coordinator = NSFileCoordinator()
    private let operationQueue = OperationQueue()
    
    private lazy var dataSource = self.makeDataSource()
    private lazy var noUpdatesDataSource = self.makeNoUpdatesDataSource()
    private lazy var updatesDataSource = self.makeUpdatesDataSource()
    private lazy var activeAppsDataSource = self.makeActiveAppsDataSource()
    private lazy var inactiveAppsDataSource = self.makeInactiveAppsDataSource()
    private lazy var unsupportedUpdates = Set<StoreApp>()
    
    private var prototypeUpdateCell: UpdateCollectionViewCell!
    private var sideloadingProgressView: UIProgressView!
    
    // State
    private var isUpdateSectionCollapsed = true
    private var expandedAppUpdates = Set<String>()
    private var isRefreshingAllApps = false
    private var refreshGroup: RefreshGroup?
    private var sideloadingProgress: Progress?
    private var dropDestinationIndexPath: IndexPath?
    private var isCheckingForUpdates = false
    private var didChangeActiveApps = false
    private var previousInactiveAppsCount = 0
    private var statusDotView: UIView?
    
    private var _imagePickerInstalledApp: InstalledApp?
    private var _viewDidAppear = false
    
    private var minimuxerStatusCheckTask: Task<Void, Never>?
    
    // Cache
    private var cachedUpdateSizes = [String: CGSize]()
    
    required init?(coder aDecoder: NSCoder)
    {
        super.init(coder: aDecoder)
        
        NotificationCenter.default.addObserver(self, selector: #selector(MyAppsViewController.didFetchSource(_:)), name: AppManager.didFetchSourceNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(MyAppsViewController.importApp(_:)), name: AppDelegate.importAppDeepLinkNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(MyAppsViewController.appIDsViewControllerDidDismiss(_:)), name: AppIDsViewController.didDismissNotification, object: nil)
    }
    
    deinit {
        if !(minimuxerStatusCheckTask?.isCancelled == true) {
            minimuxerStatusCheckTask?.cancel()
        }
    }
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        // Allows us to intercept delegate callbacks.
        self.updatesDataSource.fetchedResultsController.delegate = self
        self.activeAppsDataSource.fetchedResultsController.delegate = self
        self.inactiveAppsDataSource.fetchedResultsController.delegate = self
        
        self.collectionView.dataSource = self.dataSource
        self.collectionView.prefetchDataSource = self.dataSource
        self.dataSource.contentView = self.collectionView
        self.collectionView.dragDelegate = self
        self.collectionView.dropDelegate = self
        self.collectionView.dragInteractionEnabled = false
                
        self.prototypeUpdateCell = UpdateCollectionViewCell.instantiate(with: UpdateCollectionViewCell.nib)
        self.prototypeUpdateCell.contentView.translatesAutoresizingMaskIntoConstraints = false
        
        self.collectionView.register(UpdateCollectionViewCell.nib, forCellWithReuseIdentifier: "UpdateCell")
        self.collectionView.register(UpdatesCollectionHeaderView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "UpdatesHeader")
        self.collectionView.register(InstalledAppsCollectionHeaderView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "ActiveAppsHeader")
        self.collectionView.register(InstalledAppsCollectionHeaderView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "InactiveAppsHeader")
        
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(MyAppsViewController.checkForUpdates(_:)), for: .primaryActionTriggered)
        self.collectionView.refreshControl = refreshControl
        
        self.sideloadingProgressView = UIProgressView(progressViewStyle: .bar)
        self.sideloadingProgressView.translatesAutoresizingMaskIntoConstraints = false
        self.sideloadingProgressView.progressTintColor = .altPrimary
        self.sideloadingProgressView.progress = 0
        
        if let navigationBar = self.navigationController?.navigationBar
        {
            navigationBar.addSubview(self.sideloadingProgressView)
            NSLayoutConstraint.activate([self.sideloadingProgressView.leadingAnchor.constraint(equalTo: navigationBar.leadingAnchor),
                                         self.sideloadingProgressView.trailingAnchor.constraint(equalTo: navigationBar.trailingAnchor),
                                         self.sideloadingProgressView.bottomAnchor.constraint(equalTo: navigationBar.bottomAnchor)])
        }
        
        (self as PeekPopPreviewing).registerForPreviewing(with: self, sourceView: self.collectionView)
        
        NotificationCenter.default.addObserver(self, selector: #selector(MyAppsViewController.didChangeAppIcon(_:)), name: UIApplication.didChangeAppIconNotification, object: nil)
        
        if minimuxerStatusCheckTask == nil {
            minimuxerStatusCheckTask = Task {
                await updateStatusDot(with: getMinimuxerStatus())
                // Listen to subsequent updates reactively
                for await result in minimuxerStatusPublisher.values {
                    guard !Task.isCancelled else { break }
                    updateStatusDot(with: MinimuxerStatus.from(result))
                }
            }
        }
    }
    
    override func viewIsAppearing(_ animated: Bool)
    {
        super.viewIsAppearing(animated)
        
        self.collectionView.reloadData()
        
        self.update()
        
        self.fetchAppIDs()
        
        self.previousInactiveAppsCount = self.inactiveAppsDataSource.itemCount
    }
    
    override func viewDidLayoutSubviews()
    {
        super.viewDidLayoutSubviews()
    }

    override func viewDidAppear(_ animated: Bool)
    {
        super.viewDidAppear(animated)
        
        _viewDidAppear = true
    }
    
    override func viewWillDisappear(_ animated: Bool)
    {
        super.viewWillDisappear(animated)
    }
    
    private func findView(in view: UIView, where predicate: (UIView) -> Bool) -> UIView? {
        if predicate(view) {
            return view
        }
        for subview in view.subviews {
            if let found = findView(in: subview, where: predicate) {
                return found
            }
        }
        return nil
    }

    private func updateStatusDot(with status: MinimuxerStatus)
    {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            guard let navigationBar = self.navigationController?.navigationBar else { return }
            
            guard let largeTitleView = self.findView(in: navigationBar, where: { NSStringFromClass(type(of: $0)).contains("LargeTitle") }) else {
                return
            }
            
            let updateColorClosure: (MinimuxerStatus) -> Void = { [weak self] status in
                guard let self = self, let existingDot = self.statusDotView else { return }
                let targetColor: UIColor = (status == .ready) ? .systemGreen : .systemRed
                
                if existingDot.backgroundColor != targetColor {
                    UIView.animate(withDuration: 0.25, delay: 0.0, options: [.beginFromCurrentState, .curveEaseInOut]) {
                        existingDot.backgroundColor = targetColor
                        existingDot.transform = CGAffineTransform(scaleX: 1.25, y: 1.25)
                    } completion: { _ in
                        UIView.animate(withDuration: 0.15, delay: 0.0, options: .curveEaseInOut) {
                            existingDot.transform = .identity
                        }
                    }
                }
            }
            
            // If the dot is already created and attached to largeTitleView, just update color O(1)
            if let existingDot = self.statusDotView, existingDot.superview == largeTitleView {
                updateColorClosure(status)
                return
            }
            
            self.statusDotView?.removeFromSuperview()
            
            let titleText = NSLocalizedString("My Apps", comment: "")
            let font = UIFont.systemFont(ofSize: 34, weight: .bold)
            let textWidth = titleText.size(withAttributes: [.font: font]).width
            let leftMargin: CGFloat = 20
            
            let dot = UIView()
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.layer.cornerRadius = 3.5
            dot.transform = CGAffineTransform(scaleX: 0.01, y: 0.01)
            dot.alpha = 0.0
            largeTitleView.addSubview(dot)
            self.statusDotView = dot
            
            NSLayoutConstraint.activate([
                dot.leadingAnchor.constraint(equalTo: largeTitleView.leadingAnchor, constant: leftMargin + textWidth - 2),
                dot.bottomAnchor.constraint(equalTo: largeTitleView.bottomAnchor, constant: -32),
                dot.widthAnchor.constraint(equalToConstant: 7),
                dot.heightAnchor.constraint(equalToConstant: 7)
            ])
            
            let animateEntranceClosure: (MinimuxerStatus) -> Void = { status in
                let targetColor: UIColor = (status == .ready) ? .systemGreen : .systemRed
                dot.backgroundColor = targetColor
                UIView.animate(withDuration: 0.35, delay: 0.1, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.8, options: [], animations: {
                    dot.transform = .identity
                    dot.alpha = 1.0
                }, completion: nil)
            }
            
            animateEntranceClosure(status)
            return
        }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?)
    {
        guard let identifier = segue.identifier else { return }
        
        switch identifier
        {
        case "showApp", "showUpdate":
            guard let cell = sender as? UICollectionViewCell, let indexPath = self.collectionView.indexPath(for: cell) else { return }
            
            let installedApp = self.dataSource.item(at: indexPath)
            
            let appViewController = segue.destination as! AppViewController
            appViewController.app = installedApp.storeApp
            
        default: break
        }
    }
    
    override func shouldPerformSegue(withIdentifier identifier: String, sender: Any?) -> Bool
    {
        guard identifier == "showApp" else { return true }
        
        guard let cell = sender as? UICollectionViewCell, let indexPath = self.collectionView.indexPath(for: cell) else { return true }
        
        let installedApp = self.dataSource.item(at: indexPath)
        return !installedApp.isSideloaded
    }
    
    @IBAction func unwindToMyAppsViewController(_ segue: UIStoryboardSegue)
    {
    }


}

private extension MyAppsViewController
{
    func makeDataSource() -> RSTCompositeCollectionViewPrefetchingDataSource<InstalledApp, UIImage>
    {
        let dataSource = RSTCompositeCollectionViewPrefetchingDataSource<InstalledApp, UIImage>(dataSources: [self.noUpdatesDataSource, self.updatesDataSource, self.activeAppsDataSource, self.inactiveAppsDataSource])
        dataSource.proxy = self
        return dataSource
    }
    
    func makeNoUpdatesDataSource() -> RSTDynamicCollectionViewDataSource<InstalledApp>
    {
        let dynamicDataSource = RSTDynamicCollectionViewDataSource<InstalledApp>()
        dynamicDataSource.numberOfSectionsHandler = { 1 }
        dynamicDataSource.numberOfItemsHandler = { _ in self.updatesDataSource.itemCount == 0 ? 1 : 0 }
        dynamicDataSource.cellIdentifierHandler = { _ in "NoUpdatesCell" }
        dynamicDataSource.dynamicCellConfigurationHandler = { (cell, indexPath) in
            let cell = cell as! NoUpdatesCollectionViewCell
            cell.layoutMargins.left = self.view.layoutMargins.left
            cell.layoutMargins.right = self.view.layoutMargins.right
            
            cell.blurView.layer.cornerRadius = 20
            cell.blurView.layer.masksToBounds = true
            cell.blurView.backgroundColor = .altPrimary
            
            cell.button.addTarget(self, action: #selector(MyAppsViewController.showHiddenUpdatesAlert(_:)), for: .primaryActionTriggered)
            
            if !self.unsupportedUpdates.isEmpty
            {
                cell.textLabel.text = NSLocalizedString("Unsupported Updates Available", comment: "")
                cell.button.isHidden = false
            }
            else
            {
                cell.textLabel.text = NSLocalizedString("No Updates Available", comment: "")
                cell.button.isHidden = true
            }
        }
        
        return dynamicDataSource
    }
    
    func makeUpdatesDataSource() -> RSTFetchedResultsCollectionViewPrefetchingDataSource<InstalledApp, UIImage>
    {
        let fetchRequest = InstalledApp.supportedUpdatesFetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \InstalledApp.storeApp?.latestSupportedVersion?.date, ascending: false),
                                        NSSortDescriptor(keyPath: \InstalledApp.name, ascending: true)]
        fetchRequest.returnsObjectsAsFaults = false
        
        let dataSource = RSTFetchedResultsCollectionViewPrefetchingDataSource<InstalledApp, UIImage>(fetchRequest: fetchRequest, managedObjectContext: DatabaseManager.shared.viewContext)
        dataSource.liveFetchLimit = maximumCollapsedUpdatesCount
        dataSource.cellIdentifierHandler = { _ in "UpdateCell" }
        dataSource.cellConfigurationHandler = { [weak self] (cell, installedApp, indexPath) in
            guard let self = self else { return }
            guard let app = installedApp.storeApp, let latestSupportedVersion = app.latestSupportedVersion else { return }
            
            let cell = cell as! UpdateCollectionViewCell
            cell.layoutMargins.left = self.view.layoutMargins.left
            cell.layoutMargins.right = self.view.layoutMargins.right
            
            cell.tintColor = app.tintColor ?? .altPrimary
            cell.versionDescriptionTextView.maximumNumberOfLines = 3
            cell.versionDescriptionTextView.text = latestSupportedVersion.localizedDescription ?? "nil"
            
            if cell.bundleIdentifier != app.bundleIdentifier
            {
                cell.bundleIdentifier = app.bundleIdentifier
                cell.bannerView.iconImageView.image = nil
                cell.bannerView.iconImageView.isIndicatingActivity = true
            }
            
            cell.bannerView.button.isIndicatingActivity = false
            cell.bannerView.configure(for: app, action: .update)
            
            var versionText = latestSupportedVersion.localizedVersion

            // If the app is SideStore itself, remove the build number to save space
            if app.bundleIdentifier == Bundle.Info.appbundleIdentifier,
               let version = SemanticVersion(latestSupportedVersion.version)
            {
                // leave out the build so that it doesnt take up much space
                versionText = SemanticVersion(version.major, version.minor, version.patch, version.preRelease).description
            }
            
            cell.bannerView.subtitleLabel.text = String(format: NSLocalizedString("Version %@", comment: ""), versionText)

            let appName: String
            
            if ReleaseTrackType.betaTracks.contains(latestSupportedVersion.channel)
            {
                appName = String(format: NSLocalizedString("%@ beta", comment: ""), app.name)
            }
            else
            {
                appName = app.name
            }
            
            let versionDate = Date().relativeDateString(since: latestSupportedVersion.date)
            cell.bannerView.accessibilityLabel = String(format: NSLocalizedString("%@ %@ update. Released on %@.", comment: ""), appName, latestSupportedVersion.localizedVersion, versionDate)
            
            cell.bannerView.button.addTarget(self, action: #selector(MyAppsViewController.updateApp(_:)), for: .primaryActionTriggered)
            cell.bannerView.button.accessibilityLabel = String(format: NSLocalizedString("Update %@", comment: ""), installedApp.name)
            
            if self.expandedAppUpdates.contains(app.bundleIdentifier)
            {
                cell.mode = .expanded
            }
            else
            {
                cell.mode = .collapsed
            }
            
            cell.versionDescriptionTextView.toggleButton.addTarget(self, action: #selector(MyAppsViewController.toggleUpdateCellMode(_:)), for: .primaryActionTriggered)

            cell.setNeedsLayout()
            cell.layoutIfNeeded()
        }
        dataSource.prefetchHandler = { (installedApp, indexPath, completionHandler) in
            guard let iconURL = installedApp.storeApp?.iconURL else { return nil }
            
            Task.detached(priority: .background) {
                ImagePipeline.shared.loadImage(with: iconURL, progress: nil) { result in
                    switch result
                    {
                    case .success(let response): completionHandler(response.image, nil)
                    case .failure(let error): completionHandler(nil, error)
                    }
                }
            }
            return nil
        }
        dataSource.prefetchCompletionHandler = { (cell, image, indexPath, error) in
            let cell = cell as! UpdateCollectionViewCell
            cell.bannerView.iconImageView.isIndicatingActivity = false
            cell.bannerView.iconImageView.image = image
            
            if let error = error
            {
                debugLog("Error loading image: \(error)")
            }
        }
        
        return dataSource
    }
    
    func makeActiveAppsDataSource() -> RSTFetchedResultsCollectionViewPrefetchingDataSource<InstalledApp, UIImage>
    {
        let fetchRequest = InstalledApp.activeAppsFetchRequest()
        fetchRequest.relationshipKeyPathsForPrefetching = [#keyPath(InstalledApp.storeApp)]
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \InstalledApp.expirationDate, ascending: true),
                                        NSSortDescriptor(keyPath: \InstalledApp.refreshedDate, ascending: false),
                                        NSSortDescriptor(keyPath: \InstalledApp.name, ascending: true)]
        fetchRequest.returnsObjectsAsFaults = false
        
        let dataSource = RSTFetchedResultsCollectionViewPrefetchingDataSource<InstalledApp, UIImage>(fetchRequest: fetchRequest, managedObjectContext: DatabaseManager.shared.viewContext)
        dataSource.cellIdentifierHandler = { _ in "AppCell" }
        dataSource.cellConfigurationHandler = { (cell, installedApp, indexPath) in
            let tintColor = installedApp.storeApp?.tintColor ?? .altPrimary
            
            let cell = cell as! InstalledAppCollectionViewCell
            cell.layoutMargins.left = self.view.layoutMargins.left
            cell.layoutMargins.right = self.view.layoutMargins.right
            cell.tintColor = tintColor
            
            cell.deactivateBadge?.isHidden = false
            
            if let dropIndexPath = self.dropDestinationIndexPath, dropIndexPath.section == Section.activeApps.rawValue && dropIndexPath.item == indexPath.item
            {
                cell.bannerView.alpha = 0.4
                
                cell.deactivateBadge?.alpha = 1.0
                cell.deactivateBadge?.transform = .identity
            }
            else
            {
                cell.bannerView.alpha = 1.0
                
                cell.deactivateBadge?.alpha = 0.0
                cell.deactivateBadge?.transform = CGAffineTransform.identity.scaledBy(x: 0.33, y: 0.33)
            }
            
            cell.bannerView.button.configure(for: installedApp)
            cell.bannerView.button.isIndicatingActivity = false
            cell.bannerView.configure(for: installedApp, action: .custom(cell.bannerView.button.title(for: .normal) ?? ""))
            
            if cell.bundleIdentifier != installedApp.bundleIdentifier
            {
                cell.bundleIdentifier = installedApp.bundleIdentifier
                cell.bannerView.iconImageView.image = nil
                cell.bannerView.iconImageView.isIndicatingActivity = true
            }
            
            let currentDate = Date()
            let isExpired = currentDate > installedApp.expirationDate
            cell.bannerView.buttonLabel.isHidden = isExpired || installedApp.certificateStatus == .revoked
            cell.bannerView.buttonLabel.text = NSLocalizedString("Expires in", comment: "")
            
            cell.bannerView.button.removeTarget(self, action: nil, for: .primaryActionTriggered)
            cell.bannerView.button.addTarget(self, action: #selector(MyAppsViewController.refreshApp(_:)), for: .primaryActionTriggered)
            
            cell.bannerView.button.accessibilityLabel = String(format: NSLocalizedString("Refresh %@", comment: ""), installedApp.name)
            
            if let storeApp = installedApp.storeApp, storeApp.isPledgeRequired, !storeApp.isPledged
            {
                cell.bannerView.button.isEnabled = false
                cell.bannerView.button.alpha = 0.5
            }
            else
            {
                cell.bannerView.button.isEnabled = true
                cell.bannerView.button.alpha = 1.0
            }
            
            cell.layoutIfNeeded()
            
            if let progress = AppManager.shared.refreshProgress(for: installedApp), progress.fractionCompleted < 1.0
            {
                cell.bannerView.button.progress = progress
            }
            else
            {
                cell.bannerView.button.progress = nil
            }
        }
        dataSource.prefetchHandler = { (item, indexPath, completion) in
            Task.detached(priority: .background) {
                item.managedObjectContext?.perform {
                    item.loadIcon { (result) in
                        switch result
                        {
                        case .failure(let error): completion(nil, error)
                        case .success(let image): completion(image, nil)
                        }
                    }
                }
            }
            return nil
        }
        dataSource.prefetchCompletionHandler = { (cell, image, indexPath, error) in
            let cell = cell as! InstalledAppCollectionViewCell
            cell.bannerView.iconImageView.image = image
            cell.bannerView.iconImageView.isIndicatingActivity = false
        }
        
        return dataSource
    }
    
    func makeInactiveAppsDataSource() -> RSTFetchedResultsCollectionViewPrefetchingDataSource<InstalledApp, UIImage>
    {
        let fetchRequest = InstalledApp.fetchRequest() as NSFetchRequest<InstalledApp>
        fetchRequest.relationshipKeyPathsForPrefetching = [#keyPath(InstalledApp.storeApp)]
        fetchRequest.predicate = NSPredicate(format: "%K == NO", #keyPath(InstalledApp.isActive))
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \InstalledApp.expirationDate, ascending: true),
                                        NSSortDescriptor(keyPath: \InstalledApp.refreshedDate, ascending: false),
                                        NSSortDescriptor(keyPath: \InstalledApp.name, ascending: true)]
        fetchRequest.returnsObjectsAsFaults = false
        
        let dataSource = RSTFetchedResultsCollectionViewPrefetchingDataSource<InstalledApp, UIImage>(fetchRequest: fetchRequest, managedObjectContext: DatabaseManager.shared.viewContext)
        dataSource.cellIdentifierHandler = { _ in "AppCell" }
        dataSource.cellConfigurationHandler = { (cell, installedApp, indexPath) in
            let tintColor = installedApp.storeApp?.tintColor ?? .altPrimary
            
            let cell = cell as! InstalledAppCollectionViewCell
            cell.layoutMargins.left = self.view.layoutMargins.left
            cell.layoutMargins.right = self.view.layoutMargins.right
            cell.tintColor = UIColor.gray
            
            if cell.bundleIdentifier != installedApp.bundleIdentifier
            {
                cell.bundleIdentifier = installedApp.bundleIdentifier
                cell.bannerView.iconImageView.image = nil
                cell.bannerView.iconImageView.isIndicatingActivity = true
            }
            cell.bannerView.buttonLabel.isHidden = true
            cell.bannerView.alpha = 1.0
            
            cell.deactivateBadge?.isHidden = true
            cell.deactivateBadge?.alpha = 0.0
            cell.deactivateBadge?.transform = CGAffineTransform.identity.scaledBy(x: 0.5, y: 0.5)
            
            cell.bannerView.button.isIndicatingActivity = false
            cell.bannerView.configure(for: installedApp, action: .custom(NSLocalizedString("ACTIVATE", comment: "")))
            
            cell.bannerView.button.tintColor = tintColor
            cell.bannerView.button.removeTarget(self, action: nil, for: .primaryActionTriggered)
            cell.bannerView.button.addTarget(self, action: #selector(MyAppsViewController.activateApp(_:)), for: .primaryActionTriggered)
            cell.bannerView.button.accessibilityLabel = String(format: NSLocalizedString("Activate %@", comment: ""), installedApp.name)
            
            if let storeApp = installedApp.storeApp, storeApp.isPledgeRequired, !storeApp.isPledged
            {
                cell.bannerView.button.isEnabled = false
                cell.bannerView.button.alpha = 0.5
            }
            else
            {
                cell.bannerView.button.isEnabled = true
                cell.bannerView.button.alpha = 1.0
            }
            
            // Make sure refresh button is correct size.
            cell.layoutIfNeeded()
            
            // Ensure no leftover progress from active apps cell reuse.
            cell.bannerView.button.progress = nil
            
            if let progress = AppManager.shared.refreshProgress(for: installedApp), progress.fractionCompleted < 1.0
            {
                cell.bannerView.button.progress = progress
            }
            else
            {
                cell.bannerView.button.progress = nil
            }
        }
        dataSource.prefetchHandler = { (item, indexPath, completion) in
            Task.detached(priority: .background) {
                item.managedObjectContext?.perform {
                    item.loadIcon { (result) in
                        switch result
                        {
                        case .failure(let error): completion(nil, error)
                        case .success(let image): completion(image, nil)
                        }
                    }
                }
            }
            return nil
        }
        dataSource.prefetchCompletionHandler = { (cell, image, indexPath, error) in
            let cell = cell as! InstalledAppCollectionViewCell
            cell.bannerView.iconImageView.image = image
            cell.bannerView.iconImageView.isIndicatingActivity = false
        }
        
        return dataSource
    }
    
    func updateDataSource()
    {
        do
        {
            if self.updatesDataSource.fetchedResultsController.fetchedObjects == nil
            {
                try self.updatesDataSource.fetchedResultsController.performFetch()
            }
        }
        catch
        {
            debugLog("[ALTLog] Failed to fetch updates: \(error)")
        }
    }
}

private extension MyAppsViewController
{
    func update()
    {
        self.updateUnsupportedUpdates()
        
        if self.updatesDataSource.itemCount > 0
        {
            self.navigationController?.tabBarItem.badgeValue = String(describing: self.updatesDataSource.itemCount)
            UIApplication.shared.applicationIconBadgeNumber = Int(self.updatesDataSource.itemCount)
        }
        else
        {
            self.navigationController?.tabBarItem.badgeValue = nil
            UIApplication.shared.applicationIconBadgeNumber = 0
        }
        
        // Reloading collection view when not visible can mess with cell margins.
        guard self.isViewLoaded && self.view.window != nil else { return }
        
        if !self.isCheckingForUpdates && !self.isRefreshingAllApps
        {
            let indexPath = IndexPath(row: 0, section: Section.noUpdates.rawValue)
            self.collectionView.reconfigureItems(at: [indexPath])
        }
    }
    
    func updateUnsupportedUpdates()
    {
        // TIL includesPendingChanges does not apply to relationships, so we NEED to fetch InstalledApp to check isActive.
        // let fetchRequest = StoreApp.fetchRequest()
        // fetchRequest.includesPendingChanges = true // isActive might not be persisted to disk
        
        let predicate = NSPredicate(format: "%K == YES AND %K != nil", #keyPath(InstalledApp.isActive), #keyPath(InstalledApp.storeApp))
        let activeSourceApps = InstalledApp.all(satisfying: predicate, in: DatabaseManager.shared.viewContext)
                    
        let unsupportedUpdates = activeSourceApps.compactMap { (installedApp) -> StoreApp? in
            guard let storeApp = installedApp.storeApp, let appVersion = storeApp.latestAvailableVersion, !appVersion.isSupported else { return nil }
            return storeApp
        }
        
        // Keep StoreApp, not AppVersion, to prevent us accidentally holding onto AppVersions that may be deleted.
        self.unsupportedUpdates = Set(unsupportedUpdates)
    }
    
    func fetchAppIDs()
    {
        AppManager.shared.syncAppIDs(presentingViewController: self) { (result) in
            do
            {
                try result.get()
            }
            catch
            {
                debugLog("Failed to fetch App IDs. \(error)")
            }
        }
    }
    
    @objc private func appIDsViewControllerDidDismiss(_ notification: Notification)
    {
        DispatchQueue.main.async {
            self.fetchAppIDs()
        }
    }
    
    func refresh(_ installedApps: [InstalledApp], completionHandler: @escaping ([String : Result<InstalledApp, Error>]) -> Void)
    {
        let group = AppManager.shared.refresh(installedApps, presentingViewController: self, group: self.isRefreshingAllApps ? self.refreshGroup : nil)
        group.completionHandler = { (results) in
            DispatchQueue.main.async {
                let failures = results.compactMapValues { (result) -> Error? in
                    switch result
                    {
                    case .failure(let error) where error is CancellationError: return nil
                    case .failure(let error): return error
                    case .success: return nil
                    }
                }
                
                guard !failures.isEmpty else { return }
                
                if let failure = failures.first, results.count == 1
                {
                    ToastView(error: failure.value).show(in: self)
                }
                else
                {
                    let localizedText: String
                    
                    if failures.count == 1
                    {
                        localizedText = NSLocalizedString("Failed to refresh 1 app.", comment: "")
                    }
                    else
                    {
                        localizedText = String(format: NSLocalizedString("Failed to refresh %@ apps.", comment: ""), NSNumber(value: failures.count))
                    }
                    
                    let error = failures.first?.value as NSError?
                    let detailText = error?.localizedFailure ?? error?.localizedFailureReason ?? error?.localizedDescription
                    
                    let toastView = ToastView(text: localizedText, detailText: detailText, opensLog: true)
                    toastView.preferredDuration = 4.0
                    toastView.show(in: self)
                }
            }
            
            self.refreshGroup = nil
            completionHandler(results)
        }
        
        self.refreshGroup = group
        
        if self.isRefreshingAllApps
        {
            self.reconfigureVisibleCells()
        }
    }
}

private extension MyAppsViewController
{
    @IBAction func toggleAppUpdates(_ sender: UIButton)
    {
        let visibleCells = self.collectionView.visibleCells
        
        self.collectionView.performBatchUpdates({
            
            self.isUpdateSectionCollapsed.toggle()
            
            UIView.animate(withDuration: 0.3, animations: {
                if self.isUpdateSectionCollapsed
                {
                    self.updatesDataSource.liveFetchLimit = maximumCollapsedUpdatesCount
                    self.expandedAppUpdates.removeAll()
                    
                    for case let cell as UpdateCollectionViewCell in visibleCells
                    {
                        cell.mode = .collapsed
                    }
                    
                    self.cachedUpdateSizes.removeAll()
                    
                    sender.titleLabel?.transform = .identity
                }
                else
                {
                    self.updatesDataSource.liveFetchLimit = 0
                    
                    sender.titleLabel?.transform = CGAffineTransform.identity.rotated(by: .pi)
                }
            })
            
            self.collectionView.collectionViewLayout.invalidateLayout()
            
        }, completion: nil)
    }
    
    @IBAction func toggleUpdateCellMode(_ sender: UIButton)
    {
        let point = self.collectionView.convert(sender.center, from: sender.superview)
        guard let indexPath = self.collectionView.indexPathForItem(at: point) else { return }
        
        let installedApp = self.dataSource.item(at: indexPath)
        
        let cell = self.collectionView.cellForItem(at: indexPath) as? UpdateCollectionViewCell
        
        // Toggle the state
        if self.expandedAppUpdates.contains(installedApp.bundleIdentifier)
        {
            self.expandedAppUpdates.remove(installedApp.bundleIdentifier)
            // Set collapsed mode on the cell
            cell?.mode = .collapsed
        }
        else
        {
            self.expandedAppUpdates.insert(installedApp.bundleIdentifier)
            // Set expanded mode on the cell
            cell?.mode = .expanded
        }
        
        // Clear cached size so it's recalculated
        self.cachedUpdateSizes[installedApp.bundleIdentifier] = nil
        
        // Animate the change smoothly with a duration
        UIView.animate(withDuration: 0.25) {
            self.collectionView.performBatchUpdates({
                self.collectionView.collectionViewLayout.invalidateLayout()
            }, completion: nil)
        }
    }
    
    @IBAction func refreshApp(_ sender: UIButton)
    {
        let point = self.collectionView.convert(sender.center, from: sender.superview)
        guard let indexPath = self.collectionView.indexPathForItem(at: point) else { return }
        
        let installedApp = self.dataSource.item(at: indexPath)
        self.refresh(installedApp)
    }
    
    @IBAction func refreshAllApps(_ sender: UIBarButtonItem)
    {
        Task { @MainActor in
            let installedApps = InstalledApp.fetchAppsForRefreshingAll(in: DatabaseManager.shared.viewContext)
            guard !installedApps.isEmpty else {
                let error: Error
                
                if let altstoreApp = InstalledApp.fetchAltStore(in: DatabaseManager.shared.viewContext),
                   let storeApp = altstoreApp.storeApp, storeApp.isPledgeRequired && !storeApp.isPledged
                {
                    // Assume the reason there are no apps is because we are no longer pledged to AltStore beta.
                    error = OperationError(.pledgeInactive(appName: altstoreApp.name))
                }
                else
                {
                    // Otherwise, fall back to generic noInstalledApps.
                    error = RefreshError(.noInstalledApps)
                }
                
                let toastView = ToastView(error: error)
                toastView.show(in: self)
                return
            }
            
            self.isRefreshingAllApps = true
            if let activeAppsHeader = self.collectionView.supplementaryView(forElementKind: UICollectionView.elementKindSectionHeader, at: IndexPath(item: 0, section: Section.activeApps.rawValue)) as? InstalledAppsCollectionHeaderView {
                activeAppsHeader.button.isIndicatingActivity = true
                activeAppsHeader.button.accessibilityLabel = NSLocalizedString("Refreshing", comment: "")
            }
            self.reconfigureVisibleCells()
            
            self.refresh(installedApps) { (result) in
                DispatchQueue.main.async {
                    self.isRefreshingAllApps = false
                    if let activeAppsHeader = self.collectionView.supplementaryView(forElementKind: UICollectionView.elementKindSectionHeader, at: IndexPath(item: 0, section: Section.activeApps.rawValue)) as? InstalledAppsCollectionHeaderView {
                        activeAppsHeader.button.isIndicatingActivity = false
                        activeAppsHeader.button.accessibilityLabel = nil
                    }
                    self.reconfigureVisibleCells()
                }
            }
            
            let interaction = INInteraction.refreshAllApps()
            do {
                try await interaction.donate()
            } catch {
                debugLog("Donate intent failed \(interaction.intent). \(error)")
            }
        }
    }
    
    @IBAction func updateApp(_ sender: UIButton)
    {
        let point = self.collectionView.convert(sender.center, from: sender.superview)
        guard let indexPath = self.collectionView.indexPathForItem(at: point) else { return }
        
        let installedApp = self.dataSource.item(at: indexPath)
        
        let previousProgress = AppManager.shared.installationProgress(for: installedApp)
        guard previousProgress == nil else {
            previousProgress?.cancel()
            return
        }
        
        let progress = AppManager.shared.update(installedApp, presentingViewController: self) { (result) in
            DispatchQueue.main.async {
                switch result
                {
                case .failure(let error) where error is CancellationError:
                    self.collectionView.reloadItems(at: [indexPath])
                    
                case .failure(let error):
                    ToastView(error: error, opensLog: true).show(in: self)
                    
                    self.collectionView.reloadItems(at: [indexPath])
                    
                case .success:
                    debugLog("Updated app: \(installedApp.bundleIdentifier)")
                    // No need to reload, since the the update cell is gone now.
                }
                
                self.update()
            }
        }
        
        if let pillButton = sender as? PillButton
        {
            pillButton.progress = progress
        }
    }
    
    @IBAction func sideloadApp(_ sender: UIBarButtonItem)
    {
        Task { @MainActor in
            let supportedTypes = UTType.types(tag: "ipa", tagClass: .filenameExtension, conformingTo: nil)
            
            let documentPickerViewController = UIDocumentPickerViewController(forOpeningContentTypes: supportedTypes, asCopy: true)
            documentPickerViewController.delegate = self
            self.present(documentPickerViewController, animated: true, completion: nil)
        }
    }
    
    func sideloadApp(at url: URL, completion: @escaping (Result<Void, Error>) -> Void)
    {
        let progress = Progress.discreteProgress(totalUnitCount: 100)
        
        self.navigationItem.leftBarButtonItem?.isIndicatingActivity = true
        
        let temporaryDirectory = FileManager.default.uniqueTemporaryURL()
        let unzippedAppDirectory = temporaryDirectory.appendingPathComponent("App")
        
        let downloadProgress = Progress.discreteProgress(totalUnitCount: 100)
        let unzipProgress = Progress.discreteProgress(totalUnitCount: 1)
        let installProgress = Progress.discreteProgress(totalUnitCount: 100)
        
        if url.isFileURL
        {
            progress.totalUnitCount -= 20
        }
        else
        {
            progress.addChild(downloadProgress, withPendingUnitCount: 20)
        }
        progress.addChild(unzipProgress, withPendingUnitCount: 10)
        progress.addChild(installProgress, withPendingUnitCount: 70)
        
        self.sideloadingProgress = progress
        self.sideloadingProgressView.progress = 0
        self.sideloadingProgressView.isHidden = false
        self.sideloadingProgressView.observedProgress = self.sideloadingProgress
        
        Task.detached { [weak self] in
            guard let self else { return }
            
            var localFileURL = url
            
            do
            {
                // 1. Download if remote
                if !url.isFileURL
                {
                    localFileURL = try await withCheckedThrowingContinuation { continuation in
                        let downloadTask = URLSession.shared.downloadTask(with: url) { (fileURL, response, error) in
                            do
                            {
                                let (fileURL, _) = try Result((fileURL, response), error).get()
                                try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true, attributes: nil)
                                let destinationURL = temporaryDirectory.appendingPathComponent("App.ipa")
                                try FileManager.default.moveItem(at: fileURL, to: destinationURL)
                                continuation.resume(returning: destinationURL)
                            }
                            catch
                            {
                                continuation.resume(throwing: error)
                            }
                        }
                        downloadProgress.addChild(downloadTask.progress, withPendingUnitCount: 100)
                        downloadTask.resume()
                    }
                }
                
                // 2. Unzip
                defer {
                    if !url.isFileURL {
                        try? FileManager.default.removeItem(at: localFileURL)
                    }
                }
                
                try FileManager.default.createDirectory(at: unzippedAppDirectory, withIntermediateDirectories: true, attributes: nil)
                let unzippedApplicationURL = try FileManager.default.unzipAppBundle(at: localFileURL, toDirectory: unzippedAppDirectory)
                
                guard let appBundle = ALTApplication(fileURL: unzippedApplicationURL) else { throw OperationError.invalidApp }
                unzipProgress.completedUnitCount = 1
                
                // 3. Install app
                let installedApp = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<InstalledApp, Error>) in
                    DispatchQueue.main.async {
                        let group = AppManager.shared.install(appBundle, presentingViewController: self) { (result) in
                            switch result
                            {
                            case .success(let installedApp): continuation.resume(returning: installedApp)
                            case .failure(let error): continuation.resume(throwing: error)
                            }
                        }
                        installProgress.addChild(group.progress, withPendingUnitCount: 100)
                    }
                }
                
                // 4. Success UI callback
                try? FileManager.default.removeItem(at: temporaryDirectory)
                
                await MainActor.run {
                    self.navigationItem.leftBarButtonItem?.isIndicatingActivity = false
                    self.sideloadingProgressView.observedProgress = nil
                    self.sideloadingProgressView.setHidden(true, animated: true)
                    
                    completion(.success(()))
                    
                    installedApp.managedObjectContext?.perform {
                        debugLog("Successfully installed app: \(installedApp.bundleIdentifier)")
                    }
                }
            }
            catch
            {
                try? FileManager.default.removeItem(at: temporaryDirectory)
                
                await MainActor.run {
                    self.navigationItem.leftBarButtonItem?.isIndicatingActivity = false
                    self.sideloadingProgressView.observedProgress = nil
                    self.sideloadingProgressView.setHidden(true, animated: true)
                    
                    if error is CancellationError
                    {
                        completion(.failure(OperationError.cancelled))
                    }
                    else
                    {
                        ToastView(error: error, opensLog: true).show(in: self)
                        completion(.failure(error))
                    }
                }
            }
        }
    }
    
    @IBAction func activateApp(_ sender: UIButton)
    {
        let point = self.collectionView.convert(sender.center, from: sender.superview)
        guard let indexPath = self.collectionView.indexPathForItem(at: point) else { return }
        
        let installedApp = self.dataSource.item(at: indexPath)
        self.activate(installedApp)
    }
    
    @IBAction func deactivateApp(_ sender: UIButton)
    {
        let point = self.collectionView.convert(sender.center, from: sender.superview)
        guard let indexPath = self.collectionView.indexPathForItem(at: point) else { return }
        
        let installedApp = self.dataSource.item(at: indexPath)
        self.deactivate(installedApp)
    }
    
    @objc func presentInactiveAppsAlert()
    {
        var message: String
        
        if UserDefaults.standard.activeAppLimitIncludesExtensions
        {
            message = NSLocalizedString("Non-developer Apple IDs are limited to 3 apps and app extensions. Inactive apps don't count towards your total, but cannot be opened until activated.", comment: "")
        }
        else
        {
            message = NSLocalizedString("Non-developer Apple IDs are limited to 3 apps. Inactive apps are backed up and uninstalled so they don't count towards your total, but will be reinstalled with all their data when activated again.", comment: "")
            
            if UserDefaults.standard.isAppLimitDisabled
            {
                message += "\n\n"
                message += NSLocalizedString("If you're using the MacDirtyCow exploit to remove the 3-app limit, you can install up to 10 apps and app extensions instead.", comment: "")
            }
        }
                
        let alertController = UIAlertController(title: NSLocalizedString("What are inactive apps?", comment: ""), message: message, preferredStyle: .alert)
        alertController.addAction(.ok)
        self.present(alertController, animated: true, completion: nil)
    }
    
    func updateCell(at indexPath: IndexPath)
    {
        guard let cell = collectionView.cellForItem(at: indexPath) as? InstalledAppCollectionViewCell else { return }
        
        let installedApp = self.dataSource.item(at: indexPath)
        self.dataSource.cellConfigurationHandler(cell, installedApp, indexPath)
        
        cell.bannerView.iconImageView.isIndicatingActivity = false
    }
    
    func reconfigureVisibleCells()
    {
        for indexPath in self.collectionView.indexPathsForVisibleItems
        {
            guard let section = Section(rawValue: indexPath.section) else { continue }
            switch section
            {
            case .activeApps, .inactiveApps:
                self.updateCell(at: indexPath)
            default:
                break
            }
        }
    }
    
    @objc func showHiddenUpdatesAlert(_ sender: UIButton)
    {
        guard !self.unsupportedUpdates.isEmpty else { return }
        
        let sortedHiddenUpdates = self.unsupportedUpdates.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
        
        let title = sortedHiddenUpdates.count == 1 ? NSLocalizedString("Unsupported Update Available", comment: "") : String(format: NSLocalizedString("%@ Unsupported Updates Available", comment: ""), sortedHiddenUpdates.count as NSNumber)
        var message = String(format: NSLocalizedString("These updates don't support iOS %@. Please update your device to the latest iOS version to install them.", comment: ""), ProcessInfo.processInfo.operatingSystemVersion.stringValue)
        message += "\n"
        
        for storeApp in sortedHiddenUpdates
        {
            var title = storeApp.name
            if let appVersion = storeApp.latestAvailableVersion
            {
                title += " " + appVersion.localizedVersion
                
                var osVersion: String? = nil
                if let minOSVersion = appVersion.minOSVersion, !ProcessInfo.processInfo.isOperatingSystemAtLeast(minOSVersion)
                {
                    osVersion = String(format: NSLocalizedString("iOS %@ or later", comment: ""), minOSVersion.stringValue)
                }
                else if let maxOSVersion = appVersion.maxOSVersion, ProcessInfo.processInfo.operatingSystemVersion > maxOSVersion
                {
                    osVersion = String(format: NSLocalizedString("iOS %@ or earlier", comment: ""), maxOSVersion.stringValue)
                }
                
                if let osVersion
                {
                    title += " (" + osVersion + ")"
                }
            }
            
            message += "\n" + title
        }
        
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alertController.addAction(.ok)
        
        self.present(alertController, animated: true)
    }
}

private extension MyAppsViewController
{
    func open(_ installedApp: InstalledApp)
    {
        UIApplication.shared.open(installedApp.openAppURL) { success in
            guard !success else { return }
            
            ToastView(error: OperationError.openAppFailed(name: installedApp.name), opensLog: true).show(in: self)
        }
    }
    
    func refresh(_ installedApp: InstalledApp)
    {
        Task { @MainActor in
            let previousProgress = AppManager.shared.refreshProgress(for: installedApp)
            guard previousProgress == nil else { return }
            
            self.refresh([installedApp]) { (results) in
                // If an error occured, reload the section so the progress bar is no longer visible.
                if results.values.contains(where: { $0.error != nil })
                {
                    DispatchQueue.main.async {
                        self.reconfigureVisibleCells()
                    }
                }
                
                debugLog("Finished refreshing with results: \(results.map { ($0, $1.error?.localizedDescription ?? "success") })")
            }
        }
    }
    
    func resign(_ installedApp: InstalledApp, alternateIconMode: AlternateIconMode = .preserve)
    {
        Task { @MainActor in
            let previousProgress = AppManager.shared.refreshProgress(for: installedApp)
            guard previousProgress == nil else { return }
            
            AppManager.shared.resign(installedApp, alternateIconMode: alternateIconMode, presentingViewController: self) { (result) in
                switch result
                {
                case .failure(let error) where error is CancellationError:
                    debugLog("Resign app cancelled by user.")
                    DispatchQueue.main.async {
                        self.reconfigureVisibleCells()
                    }
                case .failure(let error):
                    debugLog("Failed to resign app: \(error)")
                    DispatchQueue.main.async {
                        ToastView(error: error, opensLog: true).show(in: self)
                        self.reconfigureVisibleCells()
                    }
                case .success(let app):
                    debugLog("Successfully resigned app: \(app.name)")
                }
            }
        }
    }
    
    func activate(_ installedApp: InstalledApp)
    {
        Task { @MainActor in
            func finish(_ result: Result<InstalledApp, Error>)
            {
                do
                {
                    let app = try result.get()
                    app.managedObjectContext?.perform {
                        app.isActive = true
                        try? app.managedObjectContext?.save()
                    }
                }
                catch is CancellationError
                {
                    // Ignore
                }
                catch
                {
                    debugLog("Failed to activate app: \(error)")
                    
                    DispatchQueue.main.async {
                        ToastView(error: error, opensLog: true).show(in: self)
                    }
                }
            }
                    
            if !UserDefaults.standard.isAppLimitDisabled && UserDefaults.standard.activeAppsLimit != nil, #available(iOS 13, *)
            {
                guard let appBundle = ALTApplication(fileURL: installedApp.fileURL) else { return finish(.failure(OperationError.invalidApp)) }
                
                AppManager.shared.deactivateApps(for: appBundle, presentingViewController: self) { result in
                    installedApp.managedObjectContext?.perform {
                        switch result
                        {
                        case .failure(let error):
                            finish(.failure(error))
                            
                        case .success:
                            AppManager.shared.activate(installedApp, presentingViewController: self, completionHandler: finish(_:))
                        }
                    }
                }
            }
            else
            {
                AppManager.shared.activate(installedApp, presentingViewController: self, completionHandler: finish(_:))
            }
        }
    }
    
    func deactivate(_ installedApp: InstalledApp, completionHandler: ((Result<InstalledApp, Error>) -> Void)? = nil)
    {
        guard installedApp.isActive else { return }
        
        Task { @MainActor in
            AppManager.shared.deactivate(installedApp, presentingViewController: self) { (result) in
                do
                {
                    let app = try result.get()
                    try? app.managedObjectContext?.save()
                    
                    debugLog("Finished deactivating app: \(app.bundleIdentifier)")
                }
                catch is CancellationError
                {
                    // Ignore
                }
                catch
                {
                    debugLog("Failed to deactivate app: \(error)")
                    
                    DispatchQueue.main.async {
                        ToastView(error: error, opensLog: true).show(in: self)
                    }
                }
                
                completionHandler?(result)
            }
        }
    }
    
    func deleteApp(_ installedApp: InstalledApp, completionHandler: ((Result<InstalledApp, Error>) -> Void)? = nil)
    {
        guard installedApp.isActive else { return }
        
        Task { @MainActor in
            AppManager.shared.deleteApp(installedApp, presentingViewController: self) { (result) in
                do
                {
                    let app = try result.get()
                    try? app.managedObjectContext?.save()
                    
                    debugLog("Finished deleting app: \(app.bundleIdentifier)")
                }
                catch is CancellationError
                {
                    // Ignore
                }
                catch
                {
                    debugLog("Failed to delete app: \(error)")
                    
                    DispatchQueue.main.async {
                        ToastView(error: error, opensLog: true).show(in: self)
                    }
                }
                
                completionHandler?(result)
            }
        }
    }
    
    func remove(_ installedApp: InstalledApp)
    {
        let title = String(format: NSLocalizedString("Remove “%@” from SideStore?", comment: ""), installedApp.name)
        let message: String
        
        if UserDefaults.standard.isLegacyDeactivationSupported
        {
            message = NSLocalizedString("You must also delete it from the home screen to fully uninstall the app.", comment: "")
        }
        else
        {
            message = NSLocalizedString("This will also erase all backup data for this app.", comment: "")
        }

        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alertController.addAction(.cancel)
        alertController.addAction(UIAlertAction(title: NSLocalizedString("Remove", comment: ""), style: .destructive, handler: { (action) in
            AppManager.shared.removeDeactivatedApp(installedApp) { (result) in
                switch result
                {
                case .success: break
                case .failure(let error):
                    DispatchQueue.main.async {
                        ToastView(error: error, opensLog: true).show(in: self)
                    }
                }
            }
        }))
        
        self.present(alertController, animated: true, completion: nil)
    }
    
    func backup(_ installedApp: InstalledApp)
    {
        debugLog("[UI] User clicked 'Back Up' for app: \(installedApp.bundleIdentifier)")
        Task { @MainActor in
            let title = NSLocalizedString("Start Backup?", comment: "")
            let message = NSLocalizedString("This will replace any previous backups. Please leave SideStore open until the backup is complete.", comment: "")

            let alertController = UIAlertController(title: title, message: message, preferredStyle: .actionSheet)
            alertController.addAction(.cancel)
            
            let actionTitle = String(format: NSLocalizedString("Back Up %@", comment: ""), installedApp.name)
            alertController.addAction(UIAlertAction(title: actionTitle, style: .default, handler: { (action) in
                debugLog("[UI] User confirmed backup dialog for app: \(installedApp.bundleIdentifier). Triggering AppManager.shared.backup.")
                AppManager.shared.backup(installedApp, presentingViewController: self) { (result) in
                    do
                    {
                        let app = try result.get()
                        try? app.managedObjectContext?.save()
                        
                        debugLog("Finished backing up app: \(app.bundleIdentifier)")
                    }
                    catch
                    {
                        debugLog("Failed to back up app: \(error)")
                        
                        DispatchQueue.main.async {
                            ToastView(error: error, opensLog: true).show(in: self)

                            self.reconfigureVisibleCells()
                        }
                    }
                }
                
                DispatchQueue.main.async {
                    self.reconfigureVisibleCells()
                }
            }))
            
            self.present(alertController, animated: true, completion: nil)
        }
    }
    
    func importBackup(for installedApp: InstalledApp){
        ImportExport.importBackup(presentingViewController: self, for: installedApp) { result in
            var toast: ToastView
            switch(result){
            case .failure(let error):
                toast = ToastView(error: error, opensLog: false)
                break
            case .success:
                toast = ToastView(text: "Import Backup successful for \(installedApp.name)",
                                  detailText: "Use 'Restore Backup' option to restore data from this imported backup")
            }
            DispatchQueue.main.async {
                toast.show(in: self)
            }
        }
    }
    
    private func getPreviousBackupURL(_ installedApp: InstalledApp) -> URL
    {
        let backupURL = FileManager.default.backupDirectoryURL(for: installedApp)!
        let backupBakURL = ImportExport.getPreviousBackupURL(backupURL)
        return backupBakURL
    }
    
    func restorePreviousBackup(for installedApp: InstalledApp){
        let backupURL = FileManager.default.backupDirectoryURL(for: installedApp)!
        let backupBakURL = ImportExport.getPreviousBackupURL(backupURL)
        
        // backupBakURL is expected to exist at this point, this needs to be ensured by caller logic
        // or invoke this action only when backupBakURL exists
        
        // delete the current backup
        if(FileManager.default.fileExists(atPath: backupURL.path)){
            try! FileManager.default.removeItem(at: backupURL)
        }
        
        // restore the previously saved backup as current backup
        // (don't delete the N-1 backup yet so copy instead of move)
        try! FileManager.default.copyItem(at: backupBakURL, to: backupURL)
        
        //perform restore of data from the backup
        restore(installedApp)
    }
    
    func restore(_ installedApp: InstalledApp)
    {
        Task { @MainActor in
            let message = String(format: NSLocalizedString("This will replace all data you currently have in %@.", comment: ""), installedApp.name)
            let alertController = UIAlertController(title: NSLocalizedString("Are you sure you want to restore this backup?", comment: ""), message: message, preferredStyle: .actionSheet)
            alertController.addAction(.cancel)
            alertController.addAction(UIAlertAction(title: NSLocalizedString("Restore Backup", comment: ""), style: .destructive, handler: { (action) in
                AppManager.shared.restore(installedApp, presentingViewController: self) { (result) in
                    do
                    {
                        let app = try result.get()
                        try? app.managedObjectContext?.save()
                        
                        debugLog("Finished restoring app: \(app.bundleIdentifier)")
                    }
                    catch
                    {
                        debugLog("Failed to restore app: \(error)")
                        
                        DispatchQueue.main.async {
                            ToastView(error: error, opensLog: true).show(in: self)
                        }
                    }
                }
                
                DispatchQueue.main.async {
                    self.collectionView.reloadSections([Section.activeApps.rawValue])
                }
            }))
            
            self.present(alertController, animated: true, completion: nil)
        }
    }
    
    func exportBackup(for installedApp: InstalledApp)
    {
        guard let backupURL = FileManager.default.backupDirectoryURL(for: installedApp) else { return }
        
        let documentPicker = UIDocumentPickerViewController(forExporting: [backupURL], asCopy: true)
        
        // Don't set delegate to avoid conflicting with import callbacks.
        // documentPicker.delegate = self
        
        self.present(documentPicker, animated: true, completion: nil)
    }
    
    func deleteBackup(for installedApp: InstalledApp)
    {
        let alertController = UIAlertController(
            title: String(format: NSLocalizedString("Delete Backup for “%@”?", comment: ""), installedApp.name),
            message: NSLocalizedString("Are you sure you want to delete the backup for this app? This action cannot be undone.", comment: ""),
            preferredStyle: .alert
        )
        alertController.addAction(UIAlertAction(title: UIAlertAction.cancel.title, style: UIAlertAction.cancel.style))
        alertController.addAction(UIAlertAction(title: NSLocalizedString("Delete Backup", comment: ""), style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            do
            {
                try FileManager.default.deleteBackup(for: installedApp)
                self.collectionView.reloadData()
            }
            catch
            {
                debugLog("Failed to delete backup for \(installedApp.bundleIdentifier): \(error)")
                ToastView(error: error, opensLog: true).show(in: self)
            }
        })
        self.present(alertController, animated: true)
    }
    
    func showAppInfo(_ installedApp: InstalledApp)
    {
        let appInfoView = AppInfoView(installedApp: installedApp)
        let hostingController = UIHostingController(rootView: appInfoView)
        self.present(hostingController, animated: true, completion: nil)
    }
    
    func chooseIcon(for installedApp: InstalledApp)
    {
        self._imagePickerInstalledApp = installedApp
        
        let imagePicker = UIImagePickerController()
        imagePicker.delegate = self
        imagePicker.allowsEditing = true
        self.present(imagePicker, animated: true, completion: nil)
    }
    
    func changeIcon(for installedApp: InstalledApp, to image: UIImage?)
    {
        // Remove previous icon from cache.
        self.activeAppsDataSource.prefetchItemCache.removeObject(forKey: installedApp)
        self.inactiveAppsDataSource.prefetchItemCache.removeObject(forKey: installedApp)
        
        if let image = image
        {
            guard let icon = image.resizing(toFill: CGSize(width: 256, height: 256)),
                  let iconData = icon.pngData()
            else { return }
            
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("Staged_\(installedApp.bundleIdentifier)_Icon.png")
            do
            {
                try iconData.write(to: tempURL, options: .atomic)
                self.resign(installedApp, alternateIconMode: .set(tempURL))
            }
            catch
            {
                debugLog("Failed to write temporary icon file: \(error)")
                ToastView(error: error, opensLog: true).show(in: self)
                return
            }
        }
        else
        {
            self.resign(installedApp, alternateIconMode: .remove)
        }
    }
    
    func enableJIT(for installedApp: InstalledApp) {
        guard UserDefaults.standard.sidejitenable else {
            debugLog("MyAppsViewController: userdefaults for 'sidejitenable' was not enabled")
            return
        }
        AppManager.shared.enableJIT(for: installedApp) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    break
                case .failure(let error):
                    ToastView(error: error, opensLog: true).show(in: self)
                    AppManager.shared.log(error, operation: .enableJIT, app: installedApp)
                }
            }
        }
    }
}

private extension MyAppsViewController
{
    @objc func didFetchSource(_ notification: Notification)
    {
        DispatchQueue.main.async {
            self.update()
        }
    }
    
    @objc func importApp(_ notification: Notification)
    {
        // Make sure left UIBarButtonItem has been set.
        self.loadViewIfNeeded()
        
        guard let url = notification.userInfo?[AppDelegate.importAppDeepLinkURLKey] as? URL else { return }
        
        let cleanup = {
            guard url.isFileURL else { return }
            do
            {
                try FileManager.default.removeItem(at: url)
            }
            catch
            {
                debugLog("Unable to remove imported .ipa. \(error)")
            }
        }
        
        InstallAppDialog.present(
            ipaURL: url,
            from: self,
            onConfirm: { [weak self] in
                self?.sideloadApp(at: url) { _ in
                    cleanup()
                }
            },
            onCancel: {
                cleanup()
            }
        )
    }
    
    @objc func checkForUpdates(_ sender: UIRefreshControl)
    {
        guard !self.isCheckingForUpdates else { return }
        self.isCheckingForUpdates = true
        
        Task {
            do
            {
                // async-let so the for-loop below runs first, ensuring we catch didFetchSourceNotification.
                async let result = try await AppManager.shared.fetchSources()
                                
                if #available(iOS 15, *)
                {
                    // .map { $0.name } to avoid "non-sendable type 'Notification?' cannot cross actor boundary" warning.
                    for await _ in NotificationCenter.default.notifications(named: AppManager.didFetchSourceNotification).map({ $0.name })
                    {
                        // Wait until _after_ didFetchSourceNotification
                        // to prevent incorrect update() animations.
                        break
                    }
                }
                
                do
                {
                    do
                    {
                        let (_, context) = try await result
                        
                        try await context.performAsync {
                            try context.save()
                        }
                    }
                    catch let error as AppManager.FetchSourcesError
                    {
                        debugLog("\(error)")
                        try await error.managedObjectContext?.performAsync {
                            try error.managedObjectContext?.save()
                        }
                        
                        throw error
                    }
                }
                catch let mergeError as MergeError
                {
                    guard let sourceID = mergeError.sourceID else { throw mergeError }
                    
                    let sanitizedError = (mergeError as NSError).sanitizedForSerialization()
                    await DatabaseManager.shared.persistentContainer.performBackgroundTask { context in
                        do
                        {
                            guard let source = Source.first(satisfying: NSPredicate(format: "%K == %@", #keyPath(Source.identifier), sourceID), in: context) else { return }
                            
                            source.error = sanitizedError
                            try context.save()
                        }
                        catch
                        {
                            debugLog("[ALTLog] Failed to assign error \(sanitizedError.localizedErrorCode) to source \(sourceID). \(error)")
                        }
                    }
                    
                    throw mergeError
                }
            }
            catch let error as NSError
            {
                debugLog("\(error)")
                let toastView = ToastView(error: error.withLocalizedTitle(NSLocalizedString("Unable to Check for Updates", comment: "")))
                toastView.addTarget(nil, action: #selector(TabBarController.presentSources), for: .touchUpInside)
                toastView.show(in: self)
            }
            
            self.isCheckingForUpdates = false
            
            // Call update() _after_ setting isCheckingForUpdates to false so it will actually update collection view,
            // but _before_ calling sender.endRefreshing() to avoid weird animation.
            self.update()
            
            sender.endRefreshing()
        }
    }
    
    @objc func didChangeAppIcon(_ notification: Notification)
    {
        guard let altStoreApp = InstalledApp.fetchAltStore(in: DatabaseManager.shared.viewContext) else { return }
        
        // Remove previous icon from cache.
        self.activeAppsDataSource.prefetchItemCache.removeObject(forKey: altStoreApp)
        self.inactiveAppsDataSource.prefetchItemCache.removeObject(forKey: altStoreApp)
        
        if let indexPath = self.activeAppsDataSource.fetchedResultsController.indexPath(forObject: altStoreApp)
        {
            let indexPath = IndexPath(item: indexPath.item, section: Section.activeApps.rawValue)
            
            if #available(iOS 15, *)
            {
                self.collectionView.reconfigureItems(at: [indexPath])
            }
            else
            {
                self.collectionView.reloadItems(at: [indexPath])
            }
        }
        
        if let indexPath = self.inactiveAppsDataSource.fetchedResultsController.indexPath(forObject: altStoreApp)
        {
            let indexPath = IndexPath(item: indexPath.item, section: Section.inactiveApps.rawValue)
            
            if #available(iOS 15, *)
            {
                self.collectionView.reconfigureItems(at: [indexPath])
            }
            else
            {
                self.collectionView.reloadItems(at: [indexPath])
            }
        }
    }
}

extension MyAppsViewController
{
    override func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView
    {
        let section = Section(rawValue: indexPath.section)!
        
        switch section
        {
        case .noUpdates: return UICollectionReusableView()
        case .updates:
            let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "UpdatesHeader", for: indexPath) as! UpdatesCollectionHeaderView
            
            UIView.performWithoutAnimation {
                headerView.button.backgroundColor = UIColor.altPrimary.withAlphaComponent(0.15)
                headerView.button.setTitle("▾", for: .normal)
                headerView.button.titleLabel?.font = UIFont.boldSystemFont(ofSize: 28)
                headerView.button.setTitleColor(.altPrimary, for: .normal)
                headerView.button.addTarget(self, action: #selector(MyAppsViewController.toggleAppUpdates), for: .primaryActionTriggered)
                
                if self.isUpdateSectionCollapsed
                {
                    headerView.button.titleLabel?.transform = .identity
                }
                else
                {
                    headerView.button.titleLabel?.transform = CGAffineTransform.identity.rotated(by: .pi)
                }
                
                headerView.isHidden = (self.updatesDataSource.fetchedResultsController.fetchedObjects?.count ?? 0 <= maximumCollapsedUpdatesCount)
                
                headerView.button.layoutIfNeeded()
            }
            
            return headerView
            
        case .activeApps where kind == UICollectionView.elementKindSectionHeader:
            let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "ActiveAppsHeader", for: indexPath) as! InstalledAppsCollectionHeaderView
            
            UIView.performWithoutAnimation {
                headerView.layoutMargins.left = self.view.layoutMargins.left
                headerView.layoutMargins.right = self.view.layoutMargins.right
                
                if UserDefaults.standard.activeAppsLimit == nil || UserDefaults.standard.isAppLimitDisabled
                {
                    headerView.textLabel.text = NSLocalizedString("Installed", comment: "")
                }
                else
                {
                    headerView.textLabel.text = NSLocalizedString("Active", comment: "")
                }
                
                headerView.button.isIndicatingActivity = false
                headerView.button.activityIndicatorView.color = .altPrimary
                headerView.button.setTitle(NSLocalizedString("Refresh All", comment: ""), for: .normal)
                headerView.button.addTarget(self, action: #selector(MyAppsViewController.refreshAllApps(_:)), for: .primaryActionTriggered)
                
                headerView.button.layoutIfNeeded()
                
                if self.isRefreshingAllApps
                {
                    headerView.button.isIndicatingActivity = true
                    headerView.button.accessibilityLabel = NSLocalizedString("Refreshing", comment: "")
                    headerView.button.accessibilityTraits.remove(.notEnabled)
                }
                else
                {
                    headerView.button.isIndicatingActivity = false
                    headerView.button.accessibilityLabel = nil
                }
            }
            
            return headerView
            
        case .inactiveApps where kind == UICollectionView.elementKindSectionHeader:
            let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "InactiveAppsHeader", for: indexPath) as! InstalledAppsCollectionHeaderView
            
            UIView.performWithoutAnimation {
                headerView.layoutMargins.left = self.view.layoutMargins.left
                headerView.layoutMargins.right = self.view.layoutMargins.right
                
                headerView.textLabel.text = NSLocalizedString("Inactive", comment: "")
                headerView.button.setTitle(nil, for: .normal)
                headerView.button.setImage(UIImage(systemName: "questionmark.circle"), for: .normal)
                headerView.button.addTarget(self, action: #selector(MyAppsViewController.presentInactiveAppsAlert), for: .primaryActionTriggered)
                
                headerView.isHidden = (self.inactiveAppsDataSource.itemCount == 0)
            }
            
            return headerView
            
        case .activeApps, .inactiveApps:
            let footerView = collectionView.dequeueReusableSupplementaryView(ofKind: UICollectionView.elementKindSectionFooter, withReuseIdentifier: "InstalledAppsFooter", for: indexPath) as! InstalledAppsCollectionFooterView
            
            guard let team = DatabaseManager.shared.activeTeam() else { return footerView }
            switch team.type
            {
            case .free:
                let registeredAppIDs = team.appIDs.count
                
                let maximumAppIDCount = 10
                let remainingAppIDs = maximumAppIDCount - registeredAppIDs
                
                if remainingAppIDs == 1
                {
                    footerView.textLabel.text = String(format: NSLocalizedString("1 App ID Remaining", comment: ""))
                }
                else
                {
                    footerView.textLabel.text = String(format: NSLocalizedString("%@ App IDs Remaining", comment: ""), NSNumber(value: remainingAppIDs))
                }
                
                footerView.textLabel.isHidden = remainingAppIDs < 0
                
            case .individual, .organization, .unknown: footerView.textLabel.isHidden = true
            @unknown default: break
            }
            
            return footerView
        }
    }
    
    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath)
    {
        let section = Section.allCases[indexPath.section]
        switch section
        {
        case .updates:
            guard let cell = collectionView.cellForItem(at: indexPath) else { break }
            self.performSegue(withIdentifier: "showUpdate", sender: cell)
            
        default: break
        }
    }
}

extension MyAppsViewController
{
    private func contextMenu(for installedApp: InstalledApp) -> UIMenu
    {
        var actions = [UIMenuElement]()
        
        let openAction = UIAction(title: NSLocalizedString("Open", comment: ""), image: UIImage(systemName: "arrow.up.forward.app")) { (action) in
            self.open(installedApp)
        }
        
        let openMenu = UIMenu(title: "", options: .displayInline, children: [openAction])
        
        let refreshAction = UIAction(title: NSLocalizedString("Refresh", comment: ""), image: UIImage(systemName: "arrow.clockwise")) { (action) in
            self.refresh(installedApp)
        }
        
        let resignAction = UIAction(title: NSLocalizedString("Resign", comment: ""), image: UIImage(systemName: "signature")) { (action) in
            self.resign(installedApp)
        }
        
        let activateAction = UIAction(title: NSLocalizedString("Activate", comment: ""), image: UIImage(systemName: "checkmark.circle")) { (action) in
            self.activate(installedApp)
        }
        
        let deactivateAction = UIAction(title: NSLocalizedString("Deactivate", comment: ""), image: UIImage(systemName: "xmark.circle"), attributes: .destructive) { (action) in
            self.deactivate(installedApp)
        }
        
        let deleteAppAction = UIAction(title: NSLocalizedString("Delete App", comment: ""), image: UIImage(systemName: "trash"), attributes: .destructive) { (action) in
            self.deleteApp(installedApp)
        }
        
        let removeAction = UIAction(title: NSLocalizedString("Remove", comment: ""), image: UIImage(systemName: "trash"), attributes: .destructive) { (action) in
            self.remove(installedApp)
        }
        
        let jitAction = UIAction(title: NSLocalizedString("Enable JIT", comment: ""), image: UIImage(systemName: "bolt")) { (action) in
            self.enableJIT(for: installedApp)
        }
        
        let backupAction = UIAction(title: NSLocalizedString("Create Backup", comment: ""), image: UIImage(systemName: "doc.on.doc")) { (action) in
            self.backup(installedApp)
        }
        
        let exportBackupAction = UIAction(title: NSLocalizedString("Export Backup", comment: ""), image: UIImage(systemName: "arrow.up.doc")) { (action) in
            self.exportBackup(for: installedApp)
        }
        
        let importBackupAction = UIAction(title: NSLocalizedString("Import Backup", comment: ""), image: UIImage(systemName: "arrow.down.doc")) { (action) in
            self.importBackup(for: installedApp)
        }
        
        let restoreBackupAction = UIAction(title: NSLocalizedString("Restore Backup", comment: "Restores the last or current backup of this app"), image: UIImage(systemName: "arrow.down.doc")) { (action) in
            self.restore(installedApp)
        }

        let restorePreviousBackupAction = UIAction(title: NSLocalizedString("Restore Previous Backup", comment: "Restores the backup saved before the current backup was created."), image: UIImage(systemName: "arrow.down.doc")) { (action) in
            self.restorePreviousBackup(for: installedApp)
        }
        
        let deleteBackupAction = UIAction(title: NSLocalizedString("Delete Backup", comment: ""), image: UIImage(systemName: "trash"), attributes: .destructive) { (action) in
            self.deleteBackup(for: installedApp)
        }
        
        let chooseIconAction = UIAction(title: NSLocalizedString("Photos", comment: ""), image: UIImage(systemName: "photo")) { (action) in
            self.chooseIcon(for: installedApp)
        }
        
        let removeIconAction = UIAction(title: NSLocalizedString("Remove Icon", comment: ""), image: UIImage(systemName: "trash"), attributes: [.destructive]) { (action) in
            self.changeIcon(for: installedApp, to: nil)
        }
        
        let infoAction = UIAction(title: NSLocalizedString("Info", comment: ""), image: UIImage(systemName: "info.circle")) { [weak self] (action) in
            self?.showAppInfo(installedApp)
        }
        
        var changeIconActions = [chooseIconAction]
        if installedApp.hasAlternateIcon
        {
            changeIconActions.append(removeIconAction)
        }
        
        let changeIconMenu = UIMenu(title: NSLocalizedString("Change Icon", comment: ""), image: UIImage(systemName: "photo"), children: changeIconActions)
        
        var backupSubmenuActions = [UIMenuElement]()
        
        if installedApp.isActive
        {
            backupSubmenuActions.append(backupAction)
        }
        else if UTType(installedApp.installedAppUTI) != nil, !UserDefaults.standard.isLegacyDeactivationSupported
        {
            // Allow backing up inactive apps if they are still installed,
            // but on an iOS version that no longer supports legacy deactivation.
            // This handles edge case where you can't install more apps until you
            // delete some, but can't activate inactive apps again to back them up first.
            backupSubmenuActions.append(backupAction)
        }
                
        if let backupDirectoryURL = FileManager.default.backupDirectoryURL(for: installedApp)
        {
            var backupExists = false
            var outError: NSError? = nil
            
            self.coordinator.coordinate(readingItemAt: backupDirectoryURL, options: [.withoutChanges], error: &outError) { (backupDirectoryURL) in

                #if DEBUG && targetEnvironment(simulator)
                backupExists = true
                #else
                backupExists = FileManager.default.fileExists(atPath: backupDirectoryURL.path)
                #endif
            }
            
            if backupExists
            {
                backupSubmenuActions.append(exportBackupAction)
                
                if installedApp.isActive
                {
                    backupSubmenuActions.append(restoreBackupAction)
                }
                
                backupSubmenuActions.append(deleteBackupAction)
            }
            else if let error = outError
            {
                debugLog("Unable to check if backup exists: \(error)")
            }
        }
        
        if installedApp.isActive
        {
            // import backup into shared backups dir is allowed
            backupSubmenuActions.append(importBackupAction)
        }
        
        // have an option to restore the n-1 backup
        if FileManager.default.fileExists(atPath: getPreviousBackupURL(installedApp).path){
            backupSubmenuActions.append(restorePreviousBackupAction)
        }
        
        let backupMenu = UIMenu(title: NSLocalizedString("Backup", comment: ""), image: UIImage(systemName: "archivebox"), children: backupSubmenuActions)
        
        let setCertAction = UIAction(title: NSLocalizedString("Change Certificate", comment: ""), image: UIImage(systemName: "key.icloud")) { [weak self] _ in
            self?.presentSetCertificateAlert(for: installedApp)
        }
        
        let resetCertAction = UIAction(title: NSLocalizedString("Reset Certificate", comment: ""), image: UIImage(systemName: "arrow.counterclockwise")) { [weak self] _ in
            self?.resetCertificate(for: installedApp)
        }
        
        var certSubmenuActions: [UIMenuElement] = [setCertAction]
        if installedApp.certificateSerialNumber != nil {
            certSubmenuActions.append(resetCertAction)
        }
        let certificateMenu = UIMenu(title: NSLocalizedString("Certificate", comment: ""), image: UIImage(systemName: "key"), children: certSubmenuActions)
        
        if installedApp.resignedBundleIdentifier.isAltStoreAppID
        {
            actions = [refreshAction, resignAction, certificateMenu, changeIconMenu]
        }
        else
        {
            if installedApp.isActive
            {
                actions.append(openMenu)
                actions.append(refreshAction)
                actions.append(resignAction)
                actions.append(certificateMenu)
            }
            else
            {
                actions.append(activateAction)
                actions.append(resignAction)
                actions.append(certificateMenu)
            }
            
            if installedApp.isActive
            {
                actions.append(jitAction)
            }
            
            actions.append(changeIconMenu)
            
            if !backupSubmenuActions.isEmpty
            {
                actions.append(backupMenu)
            }
            
            if installedApp.isActive
            {
                if installedApp.bundleIdentifier != StoreApp.altstoreAppID
                {
                    actions.append(deactivateAction)
                    actions.append(deleteAppAction)
                }
            }
            
            #if DEBUG && targetEnvironment(simulator)
            if installedApp.bundleIdentifier != StoreApp.altstoreAppID
            {
                actions.append(removeAction)
            }
            #else
            
            if (UserDefaults.standard.legacySideloadedApps ?? []).contains(installedApp.bundleIdentifier)
            {
                // Legacy sideloaded app, so can't detect if it's deleted.
                actions.append(removeAction)
            }
            else if !UserDefaults.standard.isLegacyDeactivationSupported && !installedApp.isActive
            {
                // Inactive apps are actually deleted, so we need another way
                // for user to remove them from AltStore.
                actions.append(removeAction)
            }
            
            #endif
        }
        
        actions.append(infoAction)
        
        // Change the order of entries to make changes to how the context menu is displayed
        let orderedActions = [
            openMenu,
            refreshAction,
            resignAction,
            certificateMenu,
            activateAction,
            jitAction,
            changeIconMenu,
            backupMenu,
            infoAction,
            deactivateAction,
            deleteAppAction,
            removeAction,
        ]
        
        // remove non-selected actions from the all-actions ordered list
        // this way the declaration of the action in the above code doesn't determine the context menu order
        actions = orderedActions.filter{ action in actions.contains(action)}
        
        var title: String?
                
        if let storeApp = installedApp.storeApp, storeApp.isPledgeRequired, !storeApp.isPledged
        {
            let error = OperationError.pledgeInactive(appName: installedApp.name)
            title = error.localizedDescription
            
            let allowedActions: Set<UIMenuElement> = [
                openMenu,
                deactivateAction,
                removeAction,
                backupMenu,
                infoAction
            ]
            
            for action in actions where !allowedActions.contains(action)
            {
                if let action = action as? UIAction
                {
                    action.attributes = .disabled
                }
                else if let menu = action as? UIMenu
                {
                    for case let action as UIAction in menu.children
                    {
                        action.attributes = .disabled
                    }
                }
            }
        }
        
        let menu = UIMenu(title: title ?? "", children: actions)
        return menu
    }
    
    override func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration?
    {
        guard !self.isRefreshingAllApps else { return nil }
        
        let section = Section(rawValue: indexPath.section)!
        switch section
        {
        case .updates, .noUpdates: return nil
        case .activeApps, .inactiveApps:
            let installedApp = self.dataSource.item(at: indexPath)
            guard !AppManager.shared.isActivelyManagingApp(withBundleID: installedApp.bundleIdentifier) else { return nil }
            
            return UIContextMenuConfiguration(identifier: indexPath as NSIndexPath, previewProvider: nil) { (suggestedActions) -> UIMenu? in
                let menu = self.contextMenu(for: installedApp)
                return menu
            }
        }
    }
    
    override func collectionView(_ collectionView: UICollectionView, previewForHighlightingContextMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview?
    {
        guard let indexPath = configuration.identifier as? NSIndexPath else { return nil }
        guard let cell = collectionView.cellForItem(at: indexPath as IndexPath) as? InstalledAppCollectionViewCell else { return nil }
        
        let parameters = UIPreviewParameters()
        parameters.backgroundColor = .clear
        parameters.visiblePath = UIBezierPath(roundedRect: cell.bannerView.bounds, cornerRadius: cell.bannerView.layer.cornerRadius)
        
        let preview = UITargetedPreview(view: cell.bannerView, parameters: parameters)
        return preview
    }
    
    override func collectionView(_ collectionView: UICollectionView, previewForDismissingContextMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview?
    {
        return self.collectionView(collectionView, previewForHighlightingContextMenuWithConfiguration: configuration)
    }
}

extension MyAppsViewController: UICollectionViewDelegateFlowLayout
{
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize
    {
        let section = Section.allCases[indexPath.section]
        switch section
        {
        case .noUpdates:
            let size = CGSize(width: collectionView.bounds.width, height: 44)
            return size
            
        case .updates:
            let item = self.dataSource.item(at: indexPath)
            
            if let previousHeight = self.cachedUpdateSizes[item.bundleIdentifier]
            {
                return previousHeight
            }
            
            // Manually change cell's width to prevent conflicting with UIView-Encapsulated-Layout-Width constraints.
            self.prototypeUpdateCell.frame.size.width = collectionView.bounds.width
            
            self.dataSource.cellConfigurationHandler(self.prototypeUpdateCell, item, indexPath)
            
            let size = self.prototypeUpdateCell.systemLayoutSizeFitting(CGSize(width: collectionView.frame.width, height: UIView.layoutFittingCompressedSize.height),
                                                                        withHorizontalFittingPriority: .required, // Width is fixed
                                                                        verticalFittingPriority: .fittingSizeLevel) // Height can be as large as needed
            
            self.cachedUpdateSizes[item.bundleIdentifier] = size
            return size
            
        case .activeApps, .inactiveApps:
            return CGSize(width: collectionView.bounds.width, height: 88)
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize
    {
        let section = Section.allCases[section]
        switch section
        {
        case .noUpdates: return .zero
        case .updates:
            let height: CGFloat = (self.updatesDataSource.fetchedResultsController.fetchedObjects?.count ?? 0 > maximumCollapsedUpdatesCount) ? 26 : 0
            return CGSize(width: collectionView.bounds.width, height: height)
            
        case .activeApps: return CGSize(width: collectionView.bounds.width, height: 29)
        case .inactiveApps where self.inactiveAppsDataSource.itemCount == 0: return .zero
        case .inactiveApps: return CGSize(width: collectionView.bounds.width, height: 29)
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForFooterInSection section: Int) -> CGSize
    {
        let section = Section.allCases[section]
        
        func appIDsFooterSize() -> CGSize
        {
            guard let _ = DatabaseManager.shared.activeTeam() else { return .zero }
            
            // let indexPath = IndexPath(row: 0, section: section.rawValue)
            // let footerView = self.collectionView(collectionView, viewForSupplementaryElementOfKind: UICollectionView.elementKindSectionFooter, at: indexPath) as! InstalledAppsCollectionFooterView
                        
            // let size = footerView.systemLayoutSizeFitting(CGSize(width: collectionView.frame.width, height: UIView.layoutFittingExpandedSize.height),
            //                                               withHorizontalFittingPriority: .required,
            //                                               verticalFittingPriority: .fittingSizeLevel)
            // return size

            // NOTE: double dequeue of cell has been discontinued
            // TODO: Using harcoded value until this is fixed
            return CGSize(width: collectionView.bounds.width, height: 60.5)
        }
        
        switch section
        {
        case .noUpdates: return .zero
        case .updates: return .zero
            
        case .activeApps where self.inactiveAppsDataSource.itemCount == 0: return appIDsFooterSize()
        case .activeApps: return .zero
            
        case .inactiveApps where self.inactiveAppsDataSource.itemCount == 0: return .zero
        case .inactiveApps: return appIDsFooterSize()
        }
    }
    
    func collectionView(_ myCV: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets
    {
        let section = Section.allCases[section]
        switch section
        {
        case .noUpdates where self.updatesDataSource.itemCount != 0: return .zero
        case .updates where self.updatesDataSource.itemCount == 0: return .zero
        default: return UIEdgeInsets(top: 12, left: 0, bottom: 20, right: 0)
        }
    }
}

extension MyAppsViewController: UICollectionViewDragDelegate
{
    func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem]
    {
        return []
    }
    
    func collectionView(_ collectionView: UICollectionView, dragPreviewParametersForItemAt indexPath: IndexPath) -> UIDragPreviewParameters?
    {
        guard let cell = collectionView.cellForItem(at: indexPath as IndexPath) as? InstalledAppCollectionViewCell else { return nil }
        
        let parameters = UIDragPreviewParameters()
        parameters.backgroundColor = .clear
        parameters.visiblePath = UIBezierPath(roundedRect: cell.bannerView.frame, cornerRadius: cell.bannerView.layer.cornerRadius)
        
        return parameters
    }
    
    func collectionView(_ collectionView: UICollectionView, dragSessionDidEnd session: UIDragSession)
    {
        let previousDestinationIndexPath = self.dropDestinationIndexPath
        self.dropDestinationIndexPath = nil
        
        if let indexPath = previousDestinationIndexPath
        {
            // Access cell directly to prevent UI glitches due to race conditions when refreshing
            self.updateCell(at: indexPath)
        }
    }
}

extension MyAppsViewController: UICollectionViewDropDelegate
{
    func collectionView(_ collectionView: UICollectionView, canHandle session: UIDropSession) -> Bool
    {
        return session.localDragSession != nil
    }
    
    func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal
    {
        guard
            !UserDefaults.standard.isAppLimitDisabled,
            let activeAppsLimit = UserDefaults.standard.activeAppsLimit,
            let installedApp = session.items.first?.localObject as? InstalledApp
        else { return UICollectionViewDropProposal(operation: .cancel) }
        
        // Retrieve header attributes for location calculations.
        guard
            let activeAppsHeaderAttributes = collectionView.layoutAttributesForSupplementaryElement(ofKind: UICollectionView.elementKindSectionHeader, at: IndexPath(item: 0, section: Section.activeApps.rawValue)),
            let inactiveAppsHeaderAttributes = collectionView.layoutAttributesForSupplementaryElement(ofKind: UICollectionView.elementKindSectionHeader, at: IndexPath(item: 0, section: Section.inactiveApps.rawValue))
        else { return UICollectionViewDropProposal(operation: .cancel) }
        
        var dropDestinationIndexPath: IndexPath? = nil
        
        defer
        {
            // Animate selection changes.
            
            if dropDestinationIndexPath != self.dropDestinationIndexPath
            {
                let previousIndexPath = self.dropDestinationIndexPath
                self.dropDestinationIndexPath = dropDestinationIndexPath
                
                let indexPaths = [previousIndexPath, dropDestinationIndexPath].compactMap { $0 }
                
                let propertyAnimator = UIViewPropertyAnimator(springTimingParameters: UISpringTimingParameters()) {
                    for indexPath in indexPaths
                    {
                        // Access cell directly so we can animate it correctly.
                        self.updateCell(at: indexPath)
                    }
                }
                propertyAnimator.startAnimation()
            }
        }
        
        let point = session.location(in: collectionView)
        
        if installedApp.isActive
        {
            // Deactivating
            
            if point.y > inactiveAppsHeaderAttributes.frame.minY
            {
                // Inactive apps section.
                return UICollectionViewDropProposal(operation: .copy, intent: .insertAtDestinationIndexPath)
            }
            else if point.y > activeAppsHeaderAttributes.frame.minY
            {
                // Active apps section.
                return UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
            }
            else
            {
                return UICollectionViewDropProposal(operation: .cancel)
            }
        }
        else
        {
            // Activating
            
            guard point.y > activeAppsHeaderAttributes.frame.minY else {
                // Above active apps section.
                return UICollectionViewDropProposal(operation: .cancel)
            }
            
            guard point.y < inactiveAppsHeaderAttributes.frame.minY else {
                // Inactive apps section.
                return UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
            }
            
            let activeAppsCount = (self.activeAppsDataSource.fetchedResultsController.fetchedObjects ?? []).map { $0.requiredActiveSlots }.reduce(0, +)
            let availableActiveApps = max(activeAppsLimit - activeAppsCount, 0)
            
            if installedApp.requiredActiveSlots <= availableActiveApps
            {
                // Enough active app slots, so no need to deactivate app first.
                return UICollectionViewDropProposal(operation: .copy, intent: .insertAtDestinationIndexPath)
            }
            else
            {
                // Not enough active app slots, so we need to deactivate an app.
                
                // Provided destinationIndexPath is inaccurate.
                guard let indexPath = collectionView.indexPathForItem(at: point), indexPath.section == Section.activeApps.rawValue else {
                    // Invalid destination index path.
                    return UICollectionViewDropProposal(operation: .cancel)
                }
                
                let installedApp = self.dataSource.item(at: indexPath)
                guard installedApp.bundleIdentifier != StoreApp.altstoreAppID else {
                    // Can't deactivate AltStore.
                    return UICollectionViewDropProposal(operation: .forbidden, intent: .insertIntoDestinationIndexPath)
                }
                
                // This app can be deactivated!
                dropDestinationIndexPath = indexPath
                return UICollectionViewDropProposal(operation: .move, intent: .insertIntoDestinationIndexPath)
            }
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator)
    {
        guard let installedApp = coordinator.session.items.first?.localObject as? InstalledApp else { return }
        guard let destinationIndexPath = coordinator.destinationIndexPath else { return }
        
        if installedApp.isActive
        {
            guard destinationIndexPath.section == Section.inactiveApps.rawValue else { return }
            self.deactivate(installedApp)
        }
        else
        {
            guard destinationIndexPath.section == Section.activeApps.rawValue else { return }
            
            switch coordinator.proposal.intent
            {
            case .insertIntoDestinationIndexPath:
                installedApp.isActive = true
                
                let previousInstalledApp = self.dataSource.item(at: destinationIndexPath)
                self.deactivate(previousInstalledApp) { (result) in
                    installedApp.managedObjectContext?.perform {
                        switch result
                        {
                        case .failure: installedApp.isActive = false
                        case .success: self.activate(installedApp)
                        }
                    }
                }
                
            case .insertAtDestinationIndexPath:
                self.activate(installedApp)
                
            case .unspecified: break
            @unknown default: break
            }
        }
    }
}

extension MyAppsViewController: NSFetchedResultsControllerDelegate
{
    func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>)
    {
        guard let dataSource = self.dataSource(for: controller) else { return }
        
        if self.collectionView.window != nil
        {
            switch dataSource
            {
            case self.activeAppsDataSource: self.didChangeActiveApps = false
            case self.updatesDataSource where !_viewDidAppear:
                // Responding to NSFetchedResultsController updates before the collection view has
                // been shown may throw exceptions because the collection view cannot accurately
                // count the number of items before the update. However, if we manually call
                // performBatchUpdates _before_ responding to updates, the collection view can get
                // an accurate pre-update item count.
                self.collectionView.performBatchUpdates(nil, completion: nil)
                
            default: break
            }
        }
        
        dataSource.controllerWillChangeContent(controller)
    }
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange sectionInfo: NSFetchedResultsSectionInfo, atSectionIndex sectionIndex: Int, for type: NSFetchedResultsChangeType)
    {
        guard let dataSource = self.dataSource(for: controller) else { return }
        
        dataSource.controller(controller, didChange: sectionInfo, atSectionIndex: sectionIndex, for: type)
    }
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?)
    {
        guard let dataSource = self.dataSource(for: controller) else { return }
        
        switch dataSource
        {
        case self.activeAppsDataSource where type == .insert || type == .delete:
            // Update unsupportedUpdates if there is insertion or deletion in active apps section.
            self.didChangeActiveApps = true
            
        default: break
        }
        
        dataSource.controller(controller, didChange: anObject, at: indexPath, for: type, newIndexPath: newIndexPath)
    }
    
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>)
    {
        guard let dataSource = self.dataSource(for: controller) else { return }
        
        if self.collectionView.window != nil
        {
            switch dataSource
            {
            case self.activeAppsDataSource, self.inactiveAppsDataSource:
                DispatchQueue.main.async {
                    let inactiveAppsCount = self.inactiveAppsDataSource.itemCount
                    if (inactiveAppsCount == 0) != (self.previousInactiveAppsCount == 0)
                    {
                        self.previousInactiveAppsCount = inactiveAppsCount
                        if let headerView = self.collectionView.supplementaryView(forElementKind: UICollectionView.elementKindSectionHeader, at: IndexPath(item: 0, section: Section.inactiveApps.rawValue)) {
                            headerView.isHidden = (inactiveAppsCount == 0)
                        }
                        self.collectionView.collectionViewLayout.invalidateLayout()
                    }
                    else
                    {
                        self.previousInactiveAppsCount = inactiveAppsCount
                    }
                    
                    if dataSource == self.activeAppsDataSource && self.didChangeActiveApps {
                        self.update()
                    }
                }
                
            case self.updatesDataSource:
                let previousUpdateCount = self.collectionView.numberOfItems(inSection: Section.updates.rawValue)
                let updateCount = Int(self.updatesDataSource.itemCount)
                
                if previousUpdateCount == 0 && updateCount > 0
                {
                    // Remove "No Updates Available" cell.
                    let change = RSTCellContentChange(type: .delete, currentIndexPath: IndexPath(item: 0, section: Section.noUpdates.rawValue), destinationIndexPath: nil)
                    self.collectionView.add(change)
                }
                else if previousUpdateCount > 0 && updateCount == 0
                {
                    // Insert "No Updates Available" cell.
                    let change = RSTCellContentChange(type: .insert, currentIndexPath: nil, destinationIndexPath: IndexPath(item: 0, section: Section.noUpdates.rawValue))
                    self.collectionView.add(change)
                    
                    // Update unsupported updates _before_ calling controllerDidChangeContent()
                    self.updateUnsupportedUpdates()
                }
            
            default: break
            }
        }
        
        dataSource.controllerDidChangeContent(controller)
    }
    
    private func dataSource(for controller: NSFetchedResultsController<NSFetchRequestResult>) -> RSTFetchedResultsCollectionViewPrefetchingDataSource<InstalledApp, UIImage>?
    {
        switch controller
        {
        case self.updatesDataSource.fetchedResultsController: return self.updatesDataSource
        case self.activeAppsDataSource.fetchedResultsController: return self.activeAppsDataSource
        case self.inactiveAppsDataSource.fetchedResultsController: return self.inactiveAppsDataSource
        default: return nil
        }
    }
}

extension MyAppsViewController: UIDocumentPickerDelegate
{
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL])
    {
        guard let fileURL = urls.first else { return }
        
        self.sideloadApp(at: fileURL) { (result) in
            debugLog("Sideloaded app at \(fileURL) with result: \(result)")
        }
    }
}

extension MyAppsViewController: UIViewControllerPreviewingDelegate
{
    @available(iOS, deprecated: 13.0)
    func previewingContext(_ previewingContext: UIViewControllerPreviewing, viewControllerForLocation location: CGPoint) -> UIViewController?
    {
        guard
            let indexPath = self.collectionView.indexPathForItem(at: location),
            let cell = self.collectionView.cellForItem(at: indexPath)
        else { return nil }
        
        let section = Section.allCases[indexPath.section]
        switch section
        {
        case .updates:
            previewingContext.sourceRect = cell.frame
            
            let app = self.dataSource.item(at: indexPath)
            guard let storeApp = app.storeApp else { return nil}
            
            let appViewController = AppViewController.makeAppViewController(app: storeApp)
            return appViewController
            
        default: return nil
        }
    }
    
    @available(iOS, deprecated: 13.0)
    func previewingContext(_ previewingContext: UIViewControllerPreviewing, commit viewControllerToCommit: UIViewController)
    {
        let point = CGPoint(x: previewingContext.sourceRect.midX, y: previewingContext.sourceRect.midY)
        guard let indexPath = self.collectionView.indexPathForItem(at: point), let cell = self.collectionView.cellForItem(at: indexPath) else { return }
        
        self.performSegue(withIdentifier: "showUpdate", sender: cell)
    }
}

extension MyAppsViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate
{
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any])
    {
        defer {
            picker.dismiss(animated: true, completion: nil)
            self._imagePickerInstalledApp = nil
        }
        
        guard let image = info[.editedImage] as? UIImage, let installedApp = self._imagePickerInstalledApp else { return }
        self.changeIcon(for: installedApp, to: image)
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController)
    {
        picker.dismiss(animated: true, completion: nil)
        self._imagePickerInstalledApp = nil
    }
}

extension MyAppsViewController {
    private func presentSetCertificateAlert(for installedApp: InstalledApp) {
        let picker = SignableCertificatesListViewController(installedApp: installedApp)
        picker.onSelectCertificate = { [weak self] cert in
            guard let self = self else { return }
            
            let binaryCert = CertificateManager.shared.getSigningCertificate(at: installedApp.fileURL)
            if let binaryCert = binaryCert, cert.serialNumber == binaryCert.serialNumber {
                let alert = UIAlertController(
                    title: NSLocalizedString("Same Certificate", comment: ""),
                    message: NSLocalizedString("The selected certificate is already being used for this app. Please use the Resign option instead.", comment: ""),
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default))
                self.present(alert, animated: true)
            } else {
                self.setCertificate(cert, for: installedApp)
            }
        }
        picker.present(from: self)
    }
    
    private func setCertificate(_ cert: ALTCertificate, for installedApp: InstalledApp) {
        let context = DatabaseManager.shared.viewContext
        context.performAndWait {
            installedApp.certificateSerialNumber = cert.serialNumber
            try? context.save()
        }
        self.resign(installedApp)
    }
    
    private func resetCertificate(for installedApp: InstalledApp) {
        let context = DatabaseManager.shared.viewContext
        context.performAndWait {
            installedApp.certificateSerialNumber = nil
            try? context.save()
        }
        self.resign(installedApp)
    }
}
