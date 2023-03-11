//
//  NewsViewController.swift
//  AltStore
//
//  Created by Riley Testut on 8/29/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import SafariServices
import UIKit

import SideStoreCore
import RoxasUIKit

import Nuke
import os.log

private final class AppBannerFooterView: UICollectionReusableView {
    let bannerView = AppBannerView(frame: .zero)
    let tapGestureRecognizer = UITapGestureRecognizer(target: nil, action: nil)

    override init(frame: CGRect) {
        super.init(frame: frame)

        addGestureRecognizer(tapGestureRecognizer)

        bannerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bannerView)

        NSLayoutConstraint.activate([
            bannerView.topAnchor.constraint(equalTo: topAnchor),
            bannerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            bannerView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            bannerView.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class NewsViewController: UICollectionViewController {
    private lazy var dataSource = self.makeDataSource()
    private lazy var placeholderView = RSTPlaceholderView(frame: .zero)

    private var prototypeCell: NewsCollectionViewCell!

    private var loadingState: LoadingState = .loading {
        didSet {
            update()
        }
    }

    // Cache
    private var cachedCellSizes = [String: CGSize]()

    required init?(coder: NSCoder) {
        super.init(coder: coder)

        NotificationCenter.default.addObserver(self, selector: #selector(NewsViewController.importApp(_:)), name: SideStoreAppDelegate.importAppDeepLinkNotification, object: nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        prototypeCell = NewsCollectionViewCell.instantiate(with: NewsCollectionViewCell.nib!)
        prototypeCell.contentView.translatesAutoresizingMaskIntoConstraints = false

        collectionView.dataSource = dataSource
        collectionView.prefetchDataSource = dataSource

        collectionView.register(NewsCollectionViewCell.nib, forCellWithReuseIdentifier: RSTCellContentGenericCellIdentifier)
        collectionView.register(AppBannerFooterView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter, withReuseIdentifier: "AppBanner")

        registerForPreviewing(with: self, sourceView: collectionView)

        update()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        fetchSource()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()

        if collectionView.contentInset.bottom != 20 {
            // Triggers collection view update in iOS 13, which crashes if we do it in viewDidLoad()
            // since the database might not be loaded yet.
            collectionView.contentInset.bottom = 20
        }
    }

    @IBAction private func unwindFromSourcesViewController(_: UIStoryboardSegue) {
        fetchSource()
    }
}

private extension NewsViewController {
    func makeDataSource() -> RSTFetchedResultsCollectionViewPrefetchingDataSource<NewsItem, UIImage> {
        let fetchRequest = NewsItem.fetchRequest() as NSFetchRequest<NewsItem>
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \NewsItem.date, ascending: false),
                                        NSSortDescriptor(keyPath: \NewsItem.sortIndex, ascending: true),
                                        NSSortDescriptor(keyPath: \NewsItem.sourceIdentifier, ascending: true)]

        let fetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: DatabaseManager.shared.viewContext, sectionNameKeyPath: #keyPath(NewsItem.objectID), cacheName: nil)

        let dataSource = RSTFetchedResultsCollectionViewPrefetchingDataSource<NewsItem, UIImage>(fetchedResultsController: fetchedResultsController)
        dataSource.proxy = self
        dataSource.cellConfigurationHandler = { cell, newsItem, _ in
            let cell = cell as! NewsCollectionViewCell
            cell.layoutMargins.left = self.view.layoutMargins.left
            cell.layoutMargins.right = self.view.layoutMargins.right

            cell.titleLabel.text = newsItem.title
            cell.captionLabel.text = newsItem.caption
            cell.contentBackgroundView.backgroundColor = newsItem.tintColor

            cell.imageView.image = nil

            if newsItem.imageURL != nil {
                cell.imageView.isIndicatingActivity = true
                cell.imageView.isHidden = false
            } else {
                cell.imageView.isIndicatingActivity = false
                cell.imageView.isHidden = true
            }

            cell.isAccessibilityElement = true
            cell.accessibilityLabel = (cell.titleLabel.text ?? "") + ". " + (cell.captionLabel.text ?? "")

            if newsItem.storeApp != nil || newsItem.externalURL != nil {
                cell.accessibilityTraits.insert(.button)
            } else {
                cell.accessibilityTraits.remove(.button)
            }
        }
        dataSource.prefetchHandler = { newsItem, _, completionHandler in
            guard let imageURL = newsItem.imageURL else { return nil }

            return RSTAsyncBlockOperation { operation in
                ImagePipeline.shared.loadImage(with: imageURL, progress: nil, completion: { response, error in
                    guard !operation.isCancelled else { return operation.finish() }

                    if let image = response?.image {
                        completionHandler(image, nil)
                    } else {
                        completionHandler(nil, error)
                    }
                })
            }
        }
        dataSource.prefetchCompletionHandler = { cell, image, _, error in
            let cell = cell as! NewsCollectionViewCell
            cell.imageView.isIndicatingActivity = false
            cell.imageView.image = image

            if let error = error {
                os_log("Error loading image: %@", type: .error , error.localizedDescription)
            }
        }

        dataSource.placeholderView = placeholderView

        return dataSource
    }

    func fetchSource() {
        loadingState = .loading

        AppManager.shared.fetchSources { result in
            do {
                do {
                    let (_, context) = try result.get()
                    try context.save()

                    DispatchQueue.main.async {
                        self.loadingState = .finished(.success(()))
                    }
                } catch let error as AppManager.FetchSourcesError {
                    try error.managedObjectContext?.save()
                    throw error
                }
            } catch {
                DispatchQueue.main.async {
                    if self.dataSource.itemCount > 0 {
                        let toastView = ToastView(error: error)
                        toastView.addTarget(nil, action: #selector(TabBarController.presentSources), for: .touchUpInside)
                        toastView.show(in: self)
                    }

                    self.loadingState = .finished(.failure(error))
                }
            }
        }
    }

    func update() {
        switch loadingState {
        case .loading:
            placeholderView.textLabel.isHidden = true
            placeholderView.detailTextLabel.isHidden = false

            placeholderView.detailTextLabel.text = NSLocalizedString("Loading...", comment: "")

            placeholderView.activityIndicatorView.startAnimating()

        case let .finished(.failure(error)):
            placeholderView.textLabel.isHidden = false
            placeholderView.detailTextLabel.isHidden = false

            placeholderView.textLabel.text = NSLocalizedString("Unable to Fetch News", comment: "")
            placeholderView.detailTextLabel.text = error.localizedDescription

            placeholderView.activityIndicatorView.stopAnimating()

        case .finished(.success):
            placeholderView.textLabel.isHidden = true
            placeholderView.detailTextLabel.isHidden = true

            placeholderView.activityIndicatorView.stopAnimating()
        }
    }
}

private extension NewsViewController {
    @objc func handleTapGesture(_ gestureRecognizer: UITapGestureRecognizer) {
        guard let footerView = gestureRecognizer.view as? UICollectionReusableView else { return }

        let indexPaths = collectionView.indexPathsForVisibleSupplementaryElements(ofKind: UICollectionView.elementKindSectionFooter)

        guard let indexPath = indexPaths.first(where: { indexPath -> Bool in
            let supplementaryView = self.collectionView.supplementaryView(forElementKind: UICollectionView.elementKindSectionFooter, at: indexPath)
            return supplementaryView == footerView
        }) else { return }

        let item = dataSource.item(at: indexPath)
        guard let storeApp = item.storeApp else { return }

        let appViewController = AppViewController.makeAppViewController(app: storeApp)
        navigationController?.pushViewController(appViewController, animated: true)
    }

    @objc func performAppAction(_ sender: PillButton) {
        let point = collectionView.convert(sender.center, from: sender.superview)
        let indexPaths = collectionView.indexPathsForVisibleSupplementaryElements(ofKind: UICollectionView.elementKindSectionFooter)

        guard let indexPath = indexPaths.first(where: { indexPath -> Bool in
            let supplementaryView = self.collectionView.supplementaryView(forElementKind: UICollectionView.elementKindSectionFooter, at: indexPath)
            return supplementaryView?.frame.contains(point) ?? false
        }) else { return }

        let app = dataSource.item(at: indexPath)
        guard let storeApp = app.storeApp else { return }

        if let installedApp = app.storeApp?.installedApp {
            open(installedApp)
        } else {
            install(storeApp, at: indexPath)
        }
    }

    @objc func install(_ storeApp: StoreApp, at indexPath: IndexPath) {
        let previousProgress = AppManager.shared.installationProgress(for: storeApp)
        guard previousProgress == nil else {
            previousProgress?.cancel()
            return
        }

        _ = AppManager.shared.install(storeApp, presentingViewController: self) { result in
            DispatchQueue.main.async {
                switch result {
                case .failure(OperationError.cancelled): break // Ignore
                case let .failure(error):
                    let toastView = ToastView(error: error)
                    toastView.show(in: self)

                case .success: os_log("Installed app: %@", type: .info, storeApp.bundleIdentifier)
                }

                UIView.performWithoutAnimation {
                    self.collectionView.reloadSections(IndexSet(integer: indexPath.section))
                }
            }
        }

        UIView.performWithoutAnimation {
            self.collectionView.reloadSections(IndexSet(integer: indexPath.section))
        }
    }

    func open(_ installedApp: InstalledApp) {
        UIApplication.shared.open(installedApp.openAppURL)
    }
}

private extension NewsViewController {
    @objc func importApp(_: Notification) {
        presentedViewController?.dismiss(animated: true, completion: nil)
    }
}

extension NewsViewController {
    override func collectionView(_: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let newsItem = dataSource.item(at: indexPath)

        if let externalURL = newsItem.externalURL {
            let safariViewController = SFSafariViewController(url: externalURL)
            safariViewController.preferredControlTintColor = newsItem.tintColor
            present(safariViewController, animated: true, completion: nil)
        } else if let storeApp = newsItem.storeApp {
            let appViewController = AppViewController.makeAppViewController(app: storeApp)
            navigationController?.pushViewController(appViewController, animated: true)
        }
    }

    override func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind _: String, at indexPath: IndexPath) -> UICollectionReusableView {
        let item = dataSource.item(at: indexPath)

        let footerView = collectionView.dequeueReusableSupplementaryView(ofKind: UICollectionView.elementKindSectionFooter, withReuseIdentifier: "AppBanner", for: indexPath) as! AppBannerFooterView
        guard let storeApp = item.storeApp else { return footerView }

        footerView.layoutMargins.left = view.layoutMargins.left
        footerView.layoutMargins.right = view.layoutMargins.right

        footerView.bannerView.configure(for: storeApp)

        footerView.bannerView.tintColor = storeApp.tintColor
        footerView.bannerView.button.addTarget(self, action: #selector(NewsViewController.performAppAction(_:)), for: .primaryActionTriggered)
        footerView.tapGestureRecognizer.addTarget(self, action: #selector(NewsViewController.handleTapGesture(_:)))

        footerView.bannerView.button.isIndicatingActivity = false

        if storeApp.installedApp == nil {
            let buttonTitle = NSLocalizedString("Free", comment: "")
            footerView.bannerView.button.setTitle(buttonTitle.uppercased(), for: .normal)
            footerView.bannerView.button.accessibilityLabel = String(format: NSLocalizedString("Download %@", comment: ""), storeApp.name)
            footerView.bannerView.button.accessibilityValue = buttonTitle

            let progress = AppManager.shared.installationProgress(for: storeApp)
            footerView.bannerView.button.progress = progress

            if let versionDate = storeApp.latestVersion?.date, versionDate > Date() {
                footerView.bannerView.button.countdownDate = storeApp.versionDate
            } else {
                footerView.bannerView.button.countdownDate = nil
            }
        } else {
            footerView.bannerView.button.setTitle(NSLocalizedString("OPEN", comment: ""), for: .normal)
            footerView.bannerView.button.accessibilityLabel = String(format: NSLocalizedString("Open %@", comment: ""), storeApp.name)
            footerView.bannerView.button.accessibilityValue = nil
            footerView.bannerView.button.progress = nil
            footerView.bannerView.button.countdownDate = nil
        }

        Nuke.loadImage(with: storeApp.iconURL, into: footerView.bannerView.iconImageView)

        return footerView
    }
}

extension NewsViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout _: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let item = dataSource.item(at: indexPath)

        if let previousSize = cachedCellSizes[item.identifier] {
            return previousSize
        }

        let widthConstraint = prototypeCell.contentView.widthAnchor.constraint(equalToConstant: collectionView.bounds.width)
        NSLayoutConstraint.activate([widthConstraint])
        defer { NSLayoutConstraint.deactivate([widthConstraint]) }

        dataSource.cellConfigurationHandler(prototypeCell, item, indexPath)

        let size = prototypeCell.contentView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        cachedCellSizes[item.identifier] = size
        return size
    }

    func collectionView(_: UICollectionView, layout _: UICollectionViewLayout, referenceSizeForFooterInSection section: Int) -> CGSize {
        let item = dataSource.item(at: IndexPath(row: 0, section: section))

        if item.storeApp != nil {
            return CGSize(width: 88, height: 88)
        } else {
            return .zero
        }
    }

    func collectionView(_: UICollectionView, layout _: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        var insets = UIEdgeInsets(top: 30, left: 0, bottom: 13, right: 0)

        if section == 0 {
            insets.top = 10
        }

        return insets
    }
}

extension NewsViewController: UIViewControllerPreviewingDelegate {
    func previewingContext(_ previewingContext: UIViewControllerPreviewing, viewControllerForLocation location: CGPoint) -> UIViewController? {
        if let indexPath = collectionView.indexPathForItem(at: location), let cell = collectionView.cellForItem(at: indexPath) {
            // Previewing news item.

            previewingContext.sourceRect = cell.frame

            let newsItem = dataSource.item(at: indexPath)

            if let externalURL = newsItem.externalURL {
                let safariViewController = SFSafariViewController(url: externalURL)
                safariViewController.preferredControlTintColor = newsItem.tintColor
                return safariViewController
            } else if let storeApp = newsItem.storeApp {
                let appViewController = AppViewController.makeAppViewController(app: storeApp)
                return appViewController
            }

            return nil
        } else {
            // Previewing app banner (or nothing).

            let indexPaths = collectionView.indexPathsForVisibleSupplementaryElements(ofKind: UICollectionView.elementKindSectionFooter)

            guard let indexPath = indexPaths.first(where: { indexPath -> Bool in
                let layoutAttributes = self.collectionView.layoutAttributesForSupplementaryElement(ofKind: UICollectionView.elementKindSectionFooter, at: indexPath)
                return layoutAttributes?.frame.contains(location) ?? false
            }) else { return nil }

            guard let layoutAttributes = collectionView.layoutAttributesForSupplementaryElement(ofKind: UICollectionView.elementKindSectionFooter, at: indexPath) else { return nil }
            previewingContext.sourceRect = layoutAttributes.frame

            let item = dataSource.item(at: indexPath)
            guard let storeApp = item.storeApp else { return nil }

            let appViewController = AppViewController.makeAppViewController(app: storeApp)
            return appViewController
        }
    }

    func previewingContext(_: UIViewControllerPreviewing, commit viewControllerToCommit: UIViewController) {
        if let safariViewController = viewControllerToCommit as? SFSafariViewController {
            present(safariViewController, animated: true, completion: nil)
        } else {
            navigationController?.pushViewController(viewControllerToCommit, animated: true)
        }
    }
}
