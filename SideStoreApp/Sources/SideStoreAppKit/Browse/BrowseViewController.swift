//
//  BrowseViewController.swift
//  AltStore
//
//  Created by Riley Testut on 7/15/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

import SideStoreCore
import RoxasUIKit
import os.log

import Nuke

class BrowseViewController: UICollectionViewController {
    private lazy var dataSource = self.makeDataSource()
    private lazy var placeholderView = RSTPlaceholderView(frame: .zero)

    private let prototypeCell = BrowseCollectionViewCell.instantiate(with: BrowseCollectionViewCell.nib!)!

    private var loadingState: LoadingState = .loading {
        didSet {
            update()
        }
    }

    private var cachedItemSizes = [String: CGSize]()

    @IBOutlet private var sourcesBarButtonItem: UIBarButtonItem!

    override func viewDidLoad() {
        super.viewDidLoad()

        #if BETA
            dataSource.searchController.searchableKeyPaths = [#keyPath(InstalledApp.name)]
            navigationItem.searchController = dataSource.searchController
        #endif

        prototypeCell.contentView.translatesAutoresizingMaskIntoConstraints = false

        collectionView.register(BrowseCollectionViewCell.nib, forCellWithReuseIdentifier: RSTCellContentGenericCellIdentifier)

        collectionView.dataSource = dataSource
        collectionView.prefetchDataSource = dataSource

        registerForPreviewing(with: self, sourceView: collectionView)

        update()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        fetchSource()
        updateDataSource()

        update()
    }

    @IBAction private func unwindFromSourcesViewController(_: UIStoryboardSegue) {
        fetchSource()
    }
}

private extension BrowseViewController {
    func makeDataSource() -> RSTFetchedResultsCollectionViewPrefetchingDataSource<StoreApp, UIImage> {
        let fetchRequest = StoreApp.fetchRequest() as NSFetchRequest<StoreApp>
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \StoreApp.sourceIdentifier, ascending: true),
                                        NSSortDescriptor(keyPath: \StoreApp.sortIndex, ascending: true),
                                        NSSortDescriptor(keyPath: \StoreApp.name, ascending: true),
                                        NSSortDescriptor(keyPath: \StoreApp.bundleIdentifier, ascending: true)]
        fetchRequest.returnsObjectsAsFaults = false
        fetchRequest.predicate = NSPredicate(format: "%K != %@", #keyPath(StoreApp.bundleIdentifier), StoreApp.altstoreAppID)

        let dataSource = RSTFetchedResultsCollectionViewPrefetchingDataSource<StoreApp, UIImage>(fetchRequest: fetchRequest, managedObjectContext: DatabaseManager.shared.viewContext)
        dataSource.cellConfigurationHandler = { cell, app, _ in
            let cell = cell as! BrowseCollectionViewCell
            cell.layoutMargins.left = self.view.layoutMargins.left
            cell.layoutMargins.right = self.view.layoutMargins.right

            cell.subtitleLabel.text = app.subtitle
            cell.imageURLs = Array(app.screenshotURLs.prefix(2))

            cell.bannerView.configure(for: app)

            cell.bannerView.iconImageView.image = nil
            cell.bannerView.iconImageView.isIndicatingActivity = true

            cell.bannerView.button.addTarget(self, action: #selector(BrowseViewController.performAppAction(_:)), for: .primaryActionTriggered)
            cell.bannerView.button.activityIndicatorView.style = .medium

            // Explicitly set to false to ensure we're starting from a non-activity indicating state.
            // Otherwise, cell reuse can mess up some cached values.
            cell.bannerView.button.isIndicatingActivity = false

            let tintColor = app.tintColor ?? .altPrimary
            cell.tintColor = tintColor

            if app.installedApp == nil {
                let buttonTitle = NSLocalizedString("Free", comment: "")
                cell.bannerView.button.setTitle(buttonTitle.uppercased(), for: .normal)
                cell.bannerView.button.accessibilityLabel = String(format: NSLocalizedString("Download %@", comment: ""), app.name)
                cell.bannerView.button.accessibilityValue = buttonTitle

                let progress = AppManager.shared.installationProgress(for: app)
                cell.bannerView.button.progress = progress

                if let versionDate = app.latestVersion?.date, versionDate > Date() {
                    cell.bannerView.button.countdownDate = app.versionDate
                } else {
                    cell.bannerView.button.countdownDate = nil
                }
            } else {
                cell.bannerView.button.setTitle(NSLocalizedString("OPEN", comment: ""), for: .normal)
                cell.bannerView.button.accessibilityLabel = String(format: NSLocalizedString("Open %@", comment: ""), app.name)
                cell.bannerView.button.accessibilityValue = nil
                cell.bannerView.button.progress = nil
                cell.bannerView.button.countdownDate = nil
            }
        }
        dataSource.prefetchHandler = { storeApp, _, completionHandler -> Foundation.Operation? in
            let iconURL = storeApp.iconURL

            return RSTAsyncBlockOperation { operation in
                ImagePipeline.shared.loadImage(with: iconURL, progress: nil, completion: { response, error in
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
            let cell = cell as! BrowseCollectionViewCell
            cell.bannerView.iconImageView.isIndicatingActivity = false
            cell.bannerView.iconImageView.image = image

            if let error = error {
                os_log("Error loading image: %@", type: .error , error.localizedDescription)
            }
        }

        dataSource.placeholderView = placeholderView

        return dataSource
    }

    func updateDataSource() {
        dataSource.predicate = nil
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

            placeholderView.textLabel.text = NSLocalizedString("Unable to Fetch Apps", comment: "")
            placeholderView.detailTextLabel.text = error.localizedDescription

            placeholderView.activityIndicatorView.stopAnimating()

        case .finished(.success):
            placeholderView.textLabel.isHidden = true
            placeholderView.detailTextLabel.isHidden = true

            placeholderView.activityIndicatorView.stopAnimating()
        }
    }
}

private extension BrowseViewController {
    @IBAction func performAppAction(_ sender: PillButton) {
        let point = collectionView.convert(sender.center, from: sender.superview)
        guard let indexPath = collectionView.indexPathForItem(at: point) else { return }

        let app = dataSource.item(at: indexPath)

        if let installedApp = app.installedApp {
            open(installedApp)
        } else {
            install(app, at: indexPath)
        }
    }

    func install(_ app: StoreApp, at indexPath: IndexPath) {
        let previousProgress = AppManager.shared.installationProgress(for: app)
        guard previousProgress == nil else {
            previousProgress?.cancel()
            return
        }

        _ = AppManager.shared.install(app, presentingViewController: self) { result in
            DispatchQueue.main.async {
                switch result {
                case .failure(OperationError.cancelled): break // Ignore
                case let .failure(error):
                    let toastView = ToastView(error: error)
                    toastView.show(in: self)

                case .success: os_log("Installed app: %@", type: .info , app.bundleIdentifier)
                }

                self.collectionView.reloadItems(at: [indexPath])
            }
        }

        collectionView.reloadItems(at: [indexPath])
    }

    func open(_ installedApp: InstalledApp) {
        UIApplication.shared.open(installedApp.openAppURL)
    }
}

extension BrowseViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout _: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let item = dataSource.item(at: indexPath)

        if let previousSize = cachedItemSizes[item.bundleIdentifier] {
            return previousSize
        }

        let maxVisibleScreenshots = 2 as CGFloat
        let aspectRatio: CGFloat = 16.0 / 9.0

        let layout = prototypeCell.screenshotsCollectionView.collectionViewLayout as! UICollectionViewFlowLayout
        let padding = (layout.minimumInteritemSpacing * (maxVisibleScreenshots - 1)) + layout.sectionInset.left + layout.sectionInset.right

        dataSource.cellConfigurationHandler(prototypeCell, item, indexPath)

        let widthConstraint = prototypeCell.contentView.widthAnchor.constraint(equalToConstant: collectionView.bounds.width)
        widthConstraint.isActive = true
        defer { widthConstraint.isActive = false }

        // Manually update cell width & layout so we can accurately calculate screenshot sizes.
        prototypeCell.frame.size.width = widthConstraint.constant
        prototypeCell.layoutIfNeeded()

        let collectionViewWidth = prototypeCell.screenshotsCollectionView.bounds.width
        let screenshotWidth = ((collectionViewWidth - padding) / maxVisibleScreenshots).rounded(.down)
        let screenshotHeight = screenshotWidth * aspectRatio

        let heightConstraint = prototypeCell.screenshotsCollectionView.heightAnchor.constraint(equalToConstant: screenshotHeight)
        heightConstraint.priority = .defaultHigh // Prevent temporary unsatisfiable constraints error.
        heightConstraint.isActive = true
        defer { heightConstraint.isActive = false }

        let itemSize = prototypeCell.contentView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        cachedItemSizes[item.bundleIdentifier] = itemSize
        return itemSize
    }

    override func collectionView(_: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let app = dataSource.item(at: indexPath)

        let appViewController = AppViewController.makeAppViewController(app: app)
        navigationController?.pushViewController(appViewController, animated: true)
    }
}

extension BrowseViewController: UIViewControllerPreviewingDelegate {
    func previewingContext(_ previewingContext: UIViewControllerPreviewing, viewControllerForLocation location: CGPoint) -> UIViewController? {
        guard
            let indexPath = collectionView.indexPathForItem(at: location),
            let cell = collectionView.cellForItem(at: indexPath)
        else { return nil }

        previewingContext.sourceRect = cell.frame

        let app = dataSource.item(at: indexPath)

        let appViewController = AppViewController.makeAppViewController(app: app)
        return appViewController
    }

    func previewingContext(_: UIViewControllerPreviewing, commit viewControllerToCommit: UIViewController) {
        navigationController?.pushViewController(viewControllerToCommit, animated: true)
    }
}
