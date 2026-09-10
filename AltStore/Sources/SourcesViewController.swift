//
//  SourcesViewController.swift
//  AltStore
//
//  Created by Riley Testut on 3/17/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

@preconcurrency import UIKit
import CoreData
import Nuke

@objc(SourcesFooterView)
private final class SourcesFooterView: TextCollectionReusableView
{
    @IBOutlet var activityIndicatorView: UIActivityIndicatorView!
    @IBOutlet var textView: UITextView!
}

private extension UIAction.Identifier
{
    static let showDetails = UIAction.Identifier("io.sidestore.showDetails")
    static let showError = UIAction.Identifier("io.sidestore.showError")
}

final class SourcesViewController: UICollectionViewController
{
    var deepLinkSourceURL: URL? {
        didSet {
            self.handleAddSourceDeepLink()
        }
    }
    
    private lazy var dataSource = self.makeDataSource()
    
    private weak var _installingApp: StoreApp?
    
    private var placeholderView: PlaceholderView!
    private var placeholderViewButton: UIButton!
    private var placeholderViewCenterYConstraint: NSLayoutConstraint!
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        // Ensure large titles
        #if !os(tvOS)
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .automatic
        #endif

        // Set title
        navigationItem.title = "Sources"
        navigationController?.navigationBar.layoutMargins.left = 20
        
        let layout = self.makeLayout()
        self.collectionView.collectionViewLayout = layout
        
        self.navigationController?.view.tintColor = .altPrimary
        
        self.collectionView.register(AppBannerCollectionViewCell.self, forCellWithReuseIdentifier: CellContentGenericCellIdentifier)
        
        self.collectionView.dataSource = self.dataSource
        self.collectionView.prefetchDataSource = self.dataSource
        self.dataSource.contentView = self.collectionView
        self.collectionView.allowsSelectionDuringEditing = false
        
        let backgroundView = UIView(frame: .zero)
        backgroundView.backgroundColor = .altBackground
        self.collectionView.backgroundView = backgroundView
        
        self.placeholderView = PlaceholderView(frame: .zero)
        self.placeholderView.translatesAutoresizingMaskIntoConstraints = false
        self.placeholderView.textLabel.text = NSLocalizedString("Add More Sources!", comment: "")
        self.placeholderView.detailTextLabel.text = NSLocalizedString("Sources determine what apps are available in SideStore. The more sources you add, the better your SideStore experience will be.\n\nDon’t know where to start? Try adding one of our Recommended Sources!", comment: "")
        self.placeholderView.detailTextLabel.textAlignment = .natural
        backgroundView.addSubview(self.placeholderView)
        
        let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .title3).bolded()
        self.placeholderView.textLabel.font = UIFont(descriptor: fontDescriptor, size: 0.0)
        self.placeholderView.detailTextLabel.font = UIFont.preferredFont(forTextStyle: .body)
        self.placeholderView.detailTextLabel.textAlignment = .natural
        
        self.placeholderViewButton = UIButton(type: .system, primaryAction: UIAction(title: NSLocalizedString("View Recommended Sources", comment: "")) { [weak self] _ in
            self?.performSegue(withIdentifier: "addSource", sender: nil)
        })
        self.placeholderViewButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .body)
        self.placeholderView.stackView.spacing = 15
        self.placeholderView.stackView.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 15, leading: 15, bottom: 15, trailing: 15)
        self.placeholderView.stackView.isLayoutMarginsRelativeArrangement = true
        self.placeholderView.stackView.addArrangedSubview(self.placeholderViewButton)
        
        self.placeholderViewCenterYConstraint = self.placeholderView.safeAreaLayoutGuide.centerYAnchor.constraint(equalTo: backgroundView.centerYAnchor, constant: 0)
        
        NSLayoutConstraint.activate([
            self.placeholderViewCenterYConstraint,
            self.placeholderView.centerXAnchor.constraint(equalTo: backgroundView.centerXAnchor),
            self.placeholderView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor),
            self.placeholderView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
            
            self.placeholderView.topAnchor.constraint(equalTo: self.placeholderView.stackView.topAnchor),
            self.placeholderView.bottomAnchor.constraint(equalTo: self.placeholderView.stackView.bottomAnchor),
        ])

        // self.navigationItem.rightBarButtonItem = self.editButtonItem
        
        NotificationCenter.default.addObserver(self, selector: #selector(SourcesViewController.showInstallingAppToastView(_:)), name: AppManager.willInstallAppFromNewSourceNotification, object: nil)
        
        self.update()
    }
    
    override func viewDidAppear(_ animated: Bool)
    {
        super.viewDidAppear(animated)
        
        self.handleAddSourceDeepLink()
    }
    
    override func viewDidLayoutSubviews() 
    {
        super.viewDidLayoutSubviews()
        
        // Vertically center placeholder view in gap below first item.
        
        let indexPath = IndexPath(item: 0, section: 0)
        guard let layoutAttributes = self.collectionView.layoutAttributesForItem(at: indexPath) else { return }
        
        let maxY = layoutAttributes.frame.maxY
        
        let constant = maxY / 2
        if self.placeholderViewCenterYConstraint.constant != constant
        {
            self.placeholderViewCenterYConstraint.constant = constant
        }
    }
}

private extension SourcesViewController
{
    func makeLayout() -> UICollectionViewCompositionalLayout
    {
        var configuration = UICollectionLayoutListConfiguration(appearance: .grouped)
        #if !os(tvOS)
        configuration.showsSeparators = false
        #endif
        configuration.backgroundColor = .clear
        
        #if !os(tvOS)
        configuration.trailingSwipeActionsConfigurationProvider = { [weak self] indexPath in
            guard let self else { return UISwipeActionsConfiguration(actions: []) }
            
            let source = self.dataSource.item(at: indexPath)
            var actions: [UIContextualAction] = []
            
            if source.identifier != Source.altStoreIdentifier
            {
                // Prevent users from removing AltStore source.
                
                let removeAction = UIContextualAction(style: .destructive,
                                                      title: NSLocalizedString("Remove", comment: "")) { _, _, completion in
                    self.remove(source, completionHandler: completion)
                }
                removeAction.image = UIImage(systemName: "trash.fill")
                
                actions.append(removeAction)
            }
            
            if let error = source.error
            {
                let viewErrorAction = UIContextualAction(style: .normal,
                                                         title: NSLocalizedString("View Error", comment: "")) { _, _, completion in
                    self.present(error)
                    completion(true)
                }
                viewErrorAction.backgroundColor = .systemYellow
                viewErrorAction.image = UIImage(systemName: "exclamationmark.circle.fill")
                
                actions.append(viewErrorAction)
            }
            
            let config = UISwipeActionsConfiguration(actions: actions)
            config.performsFirstActionWithFullSwipe = false
            
            return config
        }
        #endif
        
        let layout = UICollectionViewCompositionalLayout.list(using: configuration)
        return layout
    }
    
    func makeDataSource() -> FetchedResultsCollectionViewPrefetchingDataSource<Source, UIImage>
    {
        // TODO: @mahee96: Need implementation to keep SideStore-Official source always on top
        let fetchRequest = Source.fetchRequest() as NSFetchRequest<Source>
        fetchRequest.returnsObjectsAsFaults = false
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Source.name, ascending: true),
                                        
                                        // Can't sort by URLs or else app will crash.
                                        // NSSortDescriptor(keyPath: \Source.sourceURL, ascending: true),
                                        
                                        NSSortDescriptor(keyPath: \Source.identifier, ascending: true)]
        
        let fetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: DatabaseManager.shared.viewContext, sectionNameKeyPath: nil, cacheName: nil)
        fetchedResultsController.delegate = self
        
        let dataSource = FetchedResultsCollectionViewPrefetchingDataSource<Source, UIImage>(fetchedResultsController: fetchedResultsController)
        dataSource.proxy = self
        dataSource.cellConfigurationHandler = { [weak self] (cell, source, indexPath) in
            guard let self else { return }
                        
            let cell = cell as! AppBannerCollectionViewCell
            cell.layoutMargins.top = 5
            cell.layoutMargins.bottom = 5
            cell.layoutMargins.left = self.view.layoutMargins.left
            cell.layoutMargins.right = self.view.layoutMargins.right
            
            cell.bannerView.configure(for: source)
            
            cell.bannerView.iconImageView.image = nil
            cell.bannerView.iconImageView.isIndicatingActivity = true
            
            let numberOfApps = source.apps.filter { StoreApp.visibleAppsPredicate.evaluate(with: $0) }.count
            
            UIView.performWithoutAnimation {
                cell.bannerView.button.style = .custom
                
                let contentWidth: CGFloat
                if let error = source.error
                {
                    let image = UIImage(systemName: "exclamationmark")?.withTintColor(.white, renderingMode: .alwaysOriginal)
                    cell.bannerView.button.setImage(image, for: .normal)
                    cell.bannerView.button.setTitle(nil, for: .normal)
                    cell.bannerView.button.tintColor = .systemYellow.withAlphaComponent(0.75)
                    contentWidth = image?.size.width ?? 7.0
                    
                    let action = UIAction(identifier: .showError) { _ in
                        self.present(error)
                    }
                    cell.bannerView.button.addAction(action, for: .primaryActionTriggered)
                    cell.bannerView.button.removeAction(identifiedBy: .showDetails, for: .primaryActionTriggered)
                }
                else
                {
                    let text = numberOfApps.description
                    cell.bannerView.button.setImage(nil, for: .normal)
                    cell.bannerView.button.setTitle(text, for: .normal)
                    cell.bannerView.button.tintColor = .white.withAlphaComponent(0.2)
                    
                    let font = UIFont.boldSystemFont(ofSize: 14)
                    contentWidth = (text as NSString).size(withAttributes: [.font: font]).width
                    
                    let action = UIAction(identifier: .showDetails) { _ in
                        self.showSourceDetails(for: source)
                    }
                    cell.bannerView.button.addAction(action, for: .primaryActionTriggered)
                    cell.bannerView.button.removeAction(identifiedBy: .showError, for: .primaryActionTriggered)
                }
                
                var config = cell.bannerView.button.configuration ?? UIButton.Configuration.plain()
                config.cornerStyle = .capsule
                let horizontalPadding = max(0, (31.0 - contentWidth) / 2.0)
                config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: horizontalPadding, bottom: 0, trailing: horizontalPadding)
                cell.bannerView.button.configuration = config
            }
            
            let dateText: String
            if let lastUpdatedDate = source.lastUpdatedDate
            {
                dateText = Date().relativeDateString(since: lastUpdatedDate, dateFormatter: Date.shortDateFormatter)
            }
            else
            {
                dateText = NSLocalizedString("Never", comment: "")
            }
                            
            let text = String(format: NSLocalizedString("Last Updated: %@", comment: ""), dateText)
            cell.bannerView.subtitleLabel.text = text
            cell.bannerView.subtitleLabel.numberOfLines = 1
            
            let attributedOutput = AttributedString(localized: "^[\(numberOfApps) app](inflect: true)")
            let numberOfAppsText = String(attributedOutput.characters)
            
            let accessibilityLabel = source.name + "\n" + text + ".\n" + numberOfAppsText
            cell.bannerView.accessibilityLabel = accessibilityLabel
                        
            if source.identifier != Source.altStoreIdentifier
            {
                cell.accessories = [.delete(displayed: .whenEditing)]
            }
            else
            {
                cell.accessories = []
            }
            
            cell.bannerView.accessibilityTraits.remove(.button)
            
            // Make sure refresh button is correct size.
            cell.layoutIfNeeded()
        }
        dataSource.prefetchHandler = { (source, indexPath) in
            guard let imageURL = source.effectiveIconURL else { return nil }
            return try await ImagePipeline.shared.image(for: imageURL)
        }
        dataSource.prefetchCompletionHandler = { (cell, image, indexPath, error) in
            let cell = cell as! AppBannerCollectionViewCell
            cell.bannerView.iconImageView.isIndicatingActivity = false
            cell.bannerView.iconImageView.image = image
            
            if let error = error
            {
                debugLog("Error loading image: \(error)")
            }
        }
        
        return dataSource
    }
    
    @IBSegueAction
    func makeSourceDetailViewController(_ coder: NSCoder, sender: Any?) -> UIViewController?
    {
        guard let source = sender as? Source else { return nil }
        
        let sourceDetailViewController = SourceDetailViewController(source: source, coder: coder)
        return sourceDetailViewController
    }
    
    @IBAction
    func unwindFromAddSource(_ segue: UIStoryboardSegue)
    {
    }
}

private extension SourcesViewController
{
    func handleAddSourceDeepLink()
    {
        Task {
            guard let url = self.deepLinkSourceURL, self.view.window != nil else { return }
            
            // Only handle deep link once.
            self.deepLinkSourceURL = nil
            
            self.navigationItem.leftBarButtonItem?.isIndicatingActivity = true
            
            func finish(_ result: Result<Void, Error>)
            {
                DispatchQueue.main.async {
                    switch result
                    {
                    case .success: break
                    case .failure(let error) where error is CancellationError: break
                        
                    case .failure(var error as SourceError):
                        let title = String(format: NSLocalizedString("“%@” could not be added to SideStore.", comment: ""), error.$source.name)
                        error.errorTitle = title
                        self.present(error)
                        
                    case .failure(let error as NSError):
                        self.present(error.withLocalizedTitle(NSLocalizedString("Unable to Add Source", comment: "")))
                    }
                    
                    self.navigationItem.leftBarButtonItem?.isIndicatingActivity = false
                }
            }
            
            let backgroundContext = DatabaseManager.shared.persistentContainer.newBackgroundContext()
            let source = try await AppManager.shared.fetchSource(sourceURL: url, managedObjectContext: backgroundContext)
            await MainActor.run {
                showSourceDetails(for: source)
            }
            finish(.success(()))
        }
    }

    func present(_ error: Error)
    {
        if let transitionCoordinator = self.transitionCoordinator
        {
            transitionCoordinator.animate(alongsideTransition: nil) { _ in
                self.present(error)
            }
            
            return
        }
        
        let nsError = error as NSError
        let title = nsError.localizedTitle // OK if nil.
        let message = [nsError.localizedDescription, nsError.localizedDebugDescription, nsError.localizedRecoverySuggestion].compactMap { $0 }.joined(separator: "\n\n")
        
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alertController.addAction(.ok)
        self.present(alertController, animated: true, completion: nil)
    }
    
    func remove(_ source: Source, completionHandler: ((Bool) -> Void)? = nil)
    {
        Task {
            do
            {
                try await AppManager.shared.remove(source, presentingViewController: self)
                
                completionHandler?(true)
            }
            catch is CancellationError
            {
                completionHandler?(false)
            }
            catch
            {
                completionHandler?(false)
                self.present(error)
            }
        }
    }
    
    func showSourceDetails(for source: Source)
    {
        self.performSegue(withIdentifier: "showSourceDetails", sender: source)
    }
    
    func update()
    {
        let sources = self.dataSource.fetchedResultsController.fetchedObjects ?? []
        let hasOtherSources = sources.contains { $0.identifier != Source.altStoreIdentifier }
        
        if !hasOtherSources
        {
            // Show placeholder view
            
            self.placeholderView.isHidden = false
            self.collectionView.alwaysBounceVertical = false
            
            self.setEditing(false, animated: true)
        }
        else
        {
            self.placeholderView.isHidden = true
            self.collectionView.alwaysBounceVertical = true
        }
    }
    
    @objc func showInstallingAppToastView(_ notification: Notification)
    {
        guard let app = notification.object as? StoreApp else { return }
        self._installingApp = app
        
        let text = String(format: NSLocalizedString("Downloading %@…", comment: ""), app.name)        
        let toastView = ToastView(text: text, detailText: NSLocalizedString("Tap to view progress.", comment: ""))
        toastView.addTarget(self, action: #selector(SourcesViewController.showAppDetail), for: .touchUpInside)
        toastView.show(in: self)
    }
    
    @objc func showAppDetail()
    {
        guard let app = self._installingApp else { return }
        self._installingApp = nil
        
        let appViewController = AppViewController.makeAppViewController(app: app)
        self.navigationController?.pushViewController(appViewController, animated: true)
    }
}

extension SourcesViewController
{
    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath)
    {
        self.collectionView.deselectItem(at: indexPath, animated: true)
        
        let source = self.dataSource.item(at: indexPath)
        self.showSourceDetails(for: source)
    }
}

extension SourcesViewController: NSFetchedResultsControllerDelegate
{
    func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) 
    {
        self.dataSource.controllerWillChangeContent(controller)
    }
    
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) 
    {
        self.dataSource.controllerDidChangeContent(controller)
        
        self.update()
    }
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) 
    {
        self.dataSource.controller(controller, didChange: anObject, at: indexPath, for: type, newIndexPath: newIndexPath)
    }
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange sectionInfo: NSFetchedResultsSectionInfo, atSectionIndex sectionIndex: Int, for type: NSFetchedResultsChangeType) 
    {
        self.dataSource.controller(controller, didChange: sectionInfo, atSectionIndex: sectionIndex, for: type)
    }
}

