//
//  NewsViewController.swift
//  AltStore
//
//  Created by Riley Testut on 8/29/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

@preconcurrency import UIKit
import Combine
import CoreData

import Nuke

private final class AppBannerFooterView: UICollectionReusableView
{
    let bannerView = AppBannerView(frame: .zero)
    let tapGestureRecognizer = UITapGestureRecognizer(target: nil, action: nil)
    
    override init(frame: CGRect)
    {
        super.init(frame: frame)
        
        self.addGestureRecognizer(self.tapGestureRecognizer)
        
        self.bannerView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.bannerView)
        
        NSLayoutConstraint.activate([
            self.bannerView.topAnchor.constraint(equalTo: self.topAnchor),
            self.bannerView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            self.bannerView.leadingAnchor.constraint(equalTo: self.layoutMarginsGuide.leadingAnchor),
            self.bannerView.trailingAnchor.constraint(equalTo: self.layoutMarginsGuide.trailingAnchor)
        ])
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class NewsViewController: UICollectionViewController
{
    // Nil == Show news from all sources.
    var source: Source?
    
    private lazy var dataSource = self.makeDataSource()
    private lazy var placeholderView = PlaceholderView(frame: .zero)
    private var retryButton: UIButton!
    
    private var prototypeCell: NewsCollectionViewCell!
    
    // Cache
    private var cachedCellSizes = [String: CGSize]()
    private var cancellables = Set<AnyCancellable>()
    
    init?(source: Source?, coder: NSCoder)
    {
        self.source = source
        
        super.init(coder: coder)
        
        self.initialize()
    }
    
    required init?(coder: NSCoder)
    {
        super.init(coder: coder)
        
        self.initialize()
    }
    
    private func initialize()
    {
        NotificationCenter.default.addObserver(self, selector: #selector(NewsViewController.importApp(_:)), name: AppDelegate.importAppDeepLinkNotification, object: nil)
    }
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.collectionView.backgroundColor = .altBackground
        
        self.prototypeCell = NewsCollectionViewCell.instantiate(with: NewsCollectionViewCell.nib)
        self.prototypeCell.contentView.translatesAutoresizingMaskIntoConstraints = false
        
        // Need to add dummy constraint + layout subviews before we can remove Interface Builder's width constraint.
        self.prototypeCell.widthAnchor.constraint(greaterThanOrEqualToConstant: 0).isActive = true
        self.prototypeCell.layoutIfNeeded()
        
        let constraints = self.prototypeCell.constraintsAffectingLayout(for: .horizontal)
        for constraint in constraints where constraint.identifier?.contains("Encapsulated-Layout-Width") == true
        {
            self.prototypeCell.removeConstraint(constraint)
        }
        
        self.collectionView.dataSource = self.dataSource
        self.collectionView.prefetchDataSource = self.dataSource
        self.dataSource.contentView = self.collectionView
        
        self.collectionView.register(NewsCollectionViewCell.nib, forCellWithReuseIdentifier: CellContentGenericCellIdentifier)
        self.collectionView.register(AppBannerFooterView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter, withReuseIdentifier: "AppBanner")
        
        #if !os(tvOS)
        self.registerForPreviewing(with: self, sourceView: self.collectionView)
        
        let refreshControl = UIRefreshControl(frame: .zero)
        refreshControl.addTarget(self, action: #selector(NewsViewController.updateSources), for: .primaryActionTriggered)
        self.collectionView.refreshControl = refreshControl
        #endif
        
        self.retryButton = UIButton(type: .system)
        self.retryButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .body)
        self.retryButton.setTitle(NSLocalizedString("Try Again", comment: ""), for: .normal)
        self.retryButton.addTarget(self, action: #selector(NewsViewController.updateSources), for: .primaryActionTriggered)
        self.placeholderView.stackView.addArrangedSubview(self.retryButton)
        
        if let source = self.source
        {
            let tintColor = source.effectiveTintColor ?? .altPrimary
            self.view.tintColor = tintColor
            
            #if !os(tvOS)
            let appearance = NavigationBarAppearance()
            appearance.configureWithTintColor(tintColor)
            appearance.configureWithDefaultBackground()
            
            let edgeAppearance = appearance.copy()
            edgeAppearance.configureWithTransparentBackground()
            
            self.navigationItem.standardAppearance = appearance
            self.navigationItem.scrollEdgeAppearance = edgeAppearance
            #endif
        }
        
        self.preparePipeline()
        self.update()
    }
    
    override func viewWillLayoutSubviews()
    {
        super.viewWillLayoutSubviews()
        
        if self.collectionView.contentInset.bottom != 20
        {
            // Triggers collection view update in iOS 13, which crashes if we do it in viewDidLoad()
            // since the database might not be loaded yet.
            self.collectionView.contentInset.bottom = 20
        }
    }
}

private extension NewsViewController
{
    func preparePipeline()
    {
        AppManager.shared.$updateSourcesResult
            .receive(on: RunLoop.main) // Delay to next run loop so we receive _current_ value (not previous value).
            .sink { result in
                self.update()
            }
            .store(in: &self.cancellables)
    }
    
    func makeDataSource() -> FetchedResultsCollectionViewPrefetchingDataSource<NewsItem, UIImage>
    {
        let fetchRequest = NewsItem.sortedFetchRequest(for: self.source)
        let context = self.source?.managedObjectContext ?? DatabaseManager.shared.viewContext
        
        // Use fetchedResultsController to split NewsItems up into sections.
        let fetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: context, sectionNameKeyPath: #keyPath(NewsItem.objectID), cacheName: nil)
        
        let dataSource = FetchedResultsCollectionViewPrefetchingDataSource<NewsItem, UIImage>(fetchedResultsController: fetchedResultsController)
        dataSource.proxy = self
        dataSource.cellConfigurationHandler = { [weak self] (cell, newsItem, indexPath) in
            guard let self else { return }
            
            let cell = cell as! NewsCollectionViewCell
            cell.contentView.layoutMargins.left = self.view.layoutMargins.left
            cell.contentView.layoutMargins.right = self.view.layoutMargins.right
            
            cell.titleLabel.text = newsItem.title
            cell.captionLabel.text = newsItem.caption
            cell.contentBackgroundView.backgroundColor = newsItem.tintColor
            
            cell.imageView.image = nil
            
            if newsItem.imageURL != nil
            {
                cell.imageView.isIndicatingActivity = true
                cell.imageView.isHidden = false
            }
            else
            {
                cell.imageView.isIndicatingActivity = false
                cell.imageView.isHidden = true
            }
            
            cell.isAccessibilityElement = true
            cell.accessibilityLabel = (cell.titleLabel.text ?? "") + ". " + (cell.captionLabel.text ?? "")
            
            if newsItem.storeApp != nil || newsItem.externalURL != nil
            {
                cell.accessibilityTraits.insert(.button)
            }
            else
            {
                cell.accessibilityTraits.remove(.button)
            }
        }
        dataSource.prefetchHandler = { (newsItem, indexPath) in
            guard let imageURL = newsItem.imageURL else { return nil }
            return try await ImagePipeline.shared.image(for: imageURL)
        }
        dataSource.prefetchCompletionHandler = { (cell, image, indexPath, error) in
            let cell = cell as! NewsCollectionViewCell
            cell.imageView.isIndicatingActivity = false
            cell.imageView.image = image
            
            if let error = error
            {
                debugLog("Error loading image: \(error)")
            }
        }
        
        dataSource.placeholderView = self.placeholderView
        
        return dataSource
    }
    
    @objc func updateSources()
    {
        AppManager.shared.updateAllSources() { result in
            #if !os(tvOS)
            self.collectionView.refreshControl?.endRefreshing()
            #endif
            
            guard case .failure(let error) = result else { return }
            
            if self.dataSource.itemCount > 0
            {
                let toastView = ToastView(error: error)
                toastView.addTarget(nil, action: #selector(TabBarController.presentSources), for: .touchUpInside)
                toastView.show(in: self)
            }
        }
    }
    
    func update()
    {
        switch AppManager.shared.updateSourcesResult
        {
        case nil:
            self.placeholderView.textLabel.isHidden = true
            self.placeholderView.detailTextLabel.isHidden = false
            
            self.placeholderView.detailTextLabel.text = NSLocalizedString("Loading...", comment: "")
            
            self.retryButton.isHidden = true
            self.placeholderView.activityIndicatorView.startAnimating()
            
        case .failure(let error):
            self.placeholderView.textLabel.isHidden = false
            self.placeholderView.detailTextLabel.isHidden = false
            
            self.placeholderView.textLabel.text = NSLocalizedString("Unable to Fetch News", comment: "")
            self.placeholderView.detailTextLabel.text = error.localizedDescription
            
            self.retryButton.isHidden = false
            self.placeholderView.activityIndicatorView.stopAnimating()
            
        case .success:
            self.placeholderView.textLabel.isHidden = true
            self.placeholderView.detailTextLabel.isHidden = true
            
            self.retryButton.isHidden = true
            self.placeholderView.activityIndicatorView.stopAnimating()
        }
    }
}

private extension NewsViewController
{
    @objc func handleTapGesture(_ gestureRecognizer: UITapGestureRecognizer)
    {
        guard let footerView = gestureRecognizer.view as? UICollectionReusableView else { return }
        
        let indexPaths = self.collectionView.indexPathsForVisibleSupplementaryElements(ofKind: UICollectionView.elementKindSectionFooter)
        
        guard let indexPath = indexPaths.first(where: { (indexPath) -> Bool in
            let supplementaryView = self.collectionView.supplementaryView(forElementKind: UICollectionView.elementKindSectionFooter, at: indexPath)
            return supplementaryView == footerView
        }) else { return }
        
        let item = self.dataSource.item(at: indexPath)
        guard let storeApp = item.storeApp else { return }
        
        let appViewController = AppViewController.makeAppViewController(app: storeApp)
        self.navigationController?.pushViewController(appViewController, animated: true)
    }
    
    @objc func performAppAction(_ sender: PillButton)
    {
        let point = self.collectionView.convert(sender.center, from: sender.superview)
        let indexPaths = self.collectionView.indexPathsForVisibleSupplementaryElements(ofKind: UICollectionView.elementKindSectionFooter)
        
        guard let indexPath = indexPaths.first(where: { (indexPath) -> Bool in
            let supplementaryView = self.collectionView.supplementaryView(forElementKind: UICollectionView.elementKindSectionFooter, at: indexPath)
            return supplementaryView?.frame.contains(point) ?? false
        }) else { return }
        
        let app = self.dataSource.item(at: indexPath)
        guard let storeApp = app.storeApp else { return }
        
        // if let installedApp = storeApp.installedApp, !installedApp.isUpdateAvailable
        if let installedApp = storeApp.installedApp, !installedApp.hasUpdate
        {
            self.open(installedApp)
        }
        else
        {
            self.install(storeApp, at: indexPath) { progress in
                sender.progress = progress
            }
        }
    }
    
    func install(_ storeApp: StoreApp, at indexPath: IndexPath, progressUpdateHandler: @escaping (Progress) -> Void)
    {
        let previousProgress = AppManager.shared.installationProgress(for: storeApp)
        guard previousProgress == nil else {
            previousProgress?.cancel()
            return
        }
        
        if let installedApp = storeApp.installedApp, installedApp.hasUpdate
        {
            let progress = AppManager.shared.update(installedApp, presentingViewController: self, completionHandler: finish(_:))
            progressUpdateHandler(progress)
        }
        else
        {
            let group = AppManager.shared.install(
                .app(storeApp),
                presentingViewController: self,
                completionHandler: finish(_:)
            )
            progressUpdateHandler(group.progress)
        }
        
        func finish(_ result: Result<InstalledApp, Error>) -> Void
        {
            DispatchQueue.main.async {
                switch result
                {
                case .failure(let error) where error is CancellationError: break // Ignore
                case .failure(let error):
                    let toastView = ToastView(error: error)
                    toastView.opensErrorLog = true
                    toastView.show(in: self)

                case .success: debugLog("Installed app: \(storeApp.bundleIdentifier)")
                }
                
                UIView.performWithoutAnimation {
                    self.collectionView.reloadSections(IndexSet(integer: indexPath.section))
                }
            }
        }
    }
    
    func open(_ installedApp: InstalledApp)
    {
        UIApplication.shared.open(installedApp.openAppURL)
    }
}

private extension NewsViewController
{
    @objc func importApp(_ notification: Notification)
    {
        self.presentedViewController?.dismiss(animated: true, completion: nil)
    }
}

extension NewsViewController
{
    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath)
    {
        let newsItem = self.dataSource.item(at: indexPath)
        
        if let externalURL = newsItem.externalURL
        {
            self.openWebURL(externalURL, preferredTintColor: newsItem.tintColor)
        }
        else if let storeApp = newsItem.storeApp
        {
            let appViewController = AppViewController.makeAppViewController(app: storeApp)
            self.navigationController?.pushViewController(appViewController, animated: true)
        }
    }
    
    override func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView
    {
        let item = self.dataSource.item(at: indexPath)
        
        let footerView = collectionView.dequeueReusableSupplementaryView(ofKind: UICollectionView.elementKindSectionFooter, withReuseIdentifier: "AppBanner", for: indexPath) as! AppBannerFooterView
        guard let storeApp = item.storeApp else { return footerView }
        
        footerView.layoutMargins.left = self.view.layoutMargins.left
        footerView.layoutMargins.right = self.view.layoutMargins.right
        
        footerView.bannerView.button.isIndicatingActivity = false
        footerView.bannerView.configure(for: storeApp)
        
        footerView.bannerView.tintColor = storeApp.tintColor
        footerView.bannerView.button.addTarget(self, action: #selector(NewsViewController.performAppAction(_:)), for: .primaryActionTriggered)
        footerView.tapGestureRecognizer.addTarget(self, action: #selector(NewsViewController.handleTapGesture(_:)))
        
        footerView.bannerView.iconImageView.isIndicatingActivity = true
        Task { [weak footerView] in
            defer { footerView?.bannerView.iconImageView.isIndicatingActivity = false }
            if let image = try? await ImagePipeline.shared.image(for: storeApp.iconURL)
            {
                footerView?.bannerView.iconImageView.image = image
            }
        }
        
        return footerView
    }
}

extension NewsViewController: UICollectionViewDelegateFlowLayout
{
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize
    {        
        let item = self.dataSource.item(at: indexPath)
        let globallyUniqueID = item.globallyUniqueID ?? item.identifier
        
        if let previousSize = self.cachedCellSizes[globallyUniqueID]
        {
            return previousSize
        }
        
        let widthConstraint = self.prototypeCell.contentView.widthAnchor.constraint(equalToConstant: collectionView.bounds.width)
        NSLayoutConstraint.activate([widthConstraint])
        defer { NSLayoutConstraint.deactivate([widthConstraint]) }
        
        self.dataSource.cellConfigurationHandler(self.prototypeCell, item, indexPath)
        
        let size = self.prototypeCell.contentView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        self.cachedCellSizes[globallyUniqueID] = size
        return size
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForFooterInSection section: Int) -> CGSize
    {
        guard self.dataSource.contentView(collectionView, numberOfItemsInSection: section) > 0 else {
            return .zero
        }
        
        let item = self.dataSource.item(at: IndexPath(row: 0, section: section))
        
        if item.storeApp != nil
        {
            return CGSize(width: 88, height: 88)
        }
        else
        {
            return .zero
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets
    {
        var insets = UIEdgeInsets(top: 30, left: 0, bottom: 13, right: 0)
        
        if section == 0
        {
            insets.top = 10
        }
        
        return insets
    }
}

#if !os(tvOS)
extension NewsViewController: UIViewControllerPreviewingDelegate
{
    @available(iOS, deprecated: 13.0)
    func previewingContext(_ previewingContext: UIViewControllerPreviewing, viewControllerForLocation location: CGPoint) -> UIViewController?
    {
        if let indexPath = self.collectionView.indexPathForItem(at: location), let cell = self.collectionView.cellForItem(at: indexPath)
        {
            // Previewing news item.
            
            previewingContext.sourceRect = cell.frame
            
            let newsItem = self.dataSource.item(at: indexPath)
            
            if let externalURL = newsItem.externalURL
            {
                return self.makeWebViewController(for: externalURL, preferredTintColor: newsItem.tintColor)
            }
            else if let storeApp = newsItem.storeApp
            {
                let appViewController = AppViewController.makeAppViewController(app: storeApp)
                return appViewController
            }
            
            return nil
        }
        else
        {
            // Previewing app banner (or nothing).
            
            let indexPaths = self.collectionView.indexPathsForVisibleSupplementaryElements(ofKind: UICollectionView.elementKindSectionFooter)
            
            guard let indexPath = indexPaths.first(where: { (indexPath) -> Bool in
                let layoutAttributes = self.collectionView.layoutAttributesForSupplementaryElement(ofKind: UICollectionView.elementKindSectionFooter, at: indexPath)
                return layoutAttributes?.frame.contains(location) ?? false
            }) else { return nil }
            
            guard let layoutAttributes = self.collectionView.layoutAttributesForSupplementaryElement(ofKind: UICollectionView.elementKindSectionFooter, at: indexPath) else { return nil }
            previewingContext.sourceRect = layoutAttributes.frame
            
            let item = self.dataSource.item(at: indexPath)
            guard let storeApp = item.storeApp else { return nil }
            
            let appViewController = AppViewController.makeAppViewController(app: storeApp)
            return appViewController
        }
    }
    
    @available(iOS, deprecated: 13.0)
    func previewingContext(_ previewingContext: UIViewControllerPreviewing, commit viewControllerToCommit: UIViewController)
    {
        if viewControllerToCommit is AppViewController
        {
            self.navigationController?.pushViewController(viewControllerToCommit, animated: true)
        }
        else
        {
            self.present(viewControllerToCommit, animated: true, completion: nil)
        }
    }
}
#endif
