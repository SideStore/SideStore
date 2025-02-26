//
//  AddSourceViewController.swift
//  AltStore
//
//  Created by Riley Testut on 9/26/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import UIKit
import Combine

import AltStoreCore
import Roxas

import Nuke

private extension UIAction.Identifier
{
    static let addSource = UIAction.Identifier("io.sidestore.AddSource")
}

private typealias SourcePreviewResult = (sourceURL: URL, result: Result<Managed<Source>, Error>)

extension AddSourceViewController
{
    private enum Section: Int
    {
        case add
        case preview
        case recommended
    }
    
    private enum ReuseID: String
    {
        case textFieldCell = "TextFieldCell"
        case placeholderFooter = "PlaceholderFooter"
    }
    
    private class ViewModel: ObservableObject
    {
        /* Pipeline */
        @Published
        var sourceAddress: String = ""
        
        @Published
        var sourceURLs: [URL] = []

        @Published
        var sourcePreviewResults: [SourcePreviewResult] = []
        
        
        /* State */
        @Published
        var isLoadingPreview: Bool = false
        
        @Published
        var isShowingPreviewStatus: Bool = false
    }
}

class AddSourceViewController: UICollectionViewController 
{
    private var stagedForAdd: LinkedHashMap<Source, Bool> = LinkedHashMap()
    
    private lazy var dataSource = self.makeDataSource()
    private lazy var addSourceDataSource = self.makeAddSourceDataSource()
    private lazy var sourcePreviewDataSource = self.makeSourcePreviewDataSource()
    private lazy var recommendedSourcesDataSource = self.makeRecommendedSourcesDataSource()
    
    private var fetchRecommendedSourcesOperation: UpdateKnownSourcesOperation?
    private var fetchRecommendedSourcesResult: Result<Void, Error>?
    private var _fetchRecommendedSourcesContext: NSManagedObjectContext?
    
    private let viewModel = ViewModel()
    private var cancellables: Set<AnyCancellable> = []
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
                
        self.navigationController?.isModalInPresentation = true
        self.navigationController?.view.tintColor = .altPrimary
        
        let layout = self.makeLayout()
        self.collectionView.collectionViewLayout = layout
        
        self.collectionView.register(AppBannerCollectionViewCell.self, forCellWithReuseIdentifier: RSTCellContentGenericCellIdentifier)
        self.collectionView.register(AddSourceTextFieldCell.self, forCellWithReuseIdentifier: ReuseID.textFieldCell.rawValue)
        
        self.collectionView.register(UICollectionViewListCell.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: UICollectionView.elementKindSectionHeader)
        self.collectionView.register(UICollectionViewListCell.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter, withReuseIdentifier: UICollectionView.elementKindSectionFooter)
        self.collectionView.register(PlaceholderCollectionReusableView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter, withReuseIdentifier: ReuseID.placeholderFooter.rawValue)
        
        self.collectionView.backgroundColor = .altBackground
        self.collectionView.keyboardDismissMode = .onDrag
        
        self.collectionView.dataSource = self.dataSource
        self.collectionView.prefetchDataSource = self.dataSource
        
        self.startPipeline()
    }
    
    override func viewWillAppear(_ animated: Bool)
    {
        super.viewWillAppear(animated)
        
        if self.fetchRecommendedSourcesOperation == nil
        {
            self.fetchRecommendedSources()
        }
    }
}

private extension AddSourceViewController
{
    func makeLayout() -> UICollectionViewCompositionalLayout
    {
        let layoutConfig = UICollectionViewCompositionalLayoutConfiguration()
        layoutConfig.contentInsetsReference = .safeArea
        
        let layout = UICollectionViewCompositionalLayout(sectionProvider: { [weak self] (sectionIndex, layoutEnvironment) -> NSCollectionLayoutSection? in
            
            guard let self, let section = Section(rawValue: sectionIndex) else { return nil }
            switch section
            {
            case .add:
                let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(44))
                let item = NSCollectionLayoutItem(layoutSize: itemSize)
                
                let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(44))
                let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
                
                let headerSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(20))
                let headerItem = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: headerSize, elementKind: UICollectionView.elementKindSectionHeader, alignment: .top)
                
                let layoutSection = NSCollectionLayoutSection(group: group)
                layoutSection.interGroupSpacing = 10
                layoutSection.boundarySupplementaryItems = [headerItem]
                return layoutSection
                
            case .preview:
                var configuration = UICollectionLayoutListConfiguration(appearance: .grouped)
                configuration.showsSeparators = false
                configuration.backgroundColor = .clear
                
                if !self.viewModel.sourceURLs.isEmpty && self.viewModel.isShowingPreviewStatus
                {
                    for result in self.viewModel.sourcePreviewResults
                    {
                        switch result
                        {
                        case (_, .success): configuration.footerMode = .none
                        case (_, .failure): configuration.footerMode = .supplementary
                            break
//                        case nil where self.viewModel.isLoadingPreview: configuration.footerMode = .supplementary
//                            break
//                        default: configuration.footerMode = .none
                        }
                    }
                }
                else
                {
                    configuration.footerMode = .none
                }
                
                let layoutSection = NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: layoutEnvironment)
                return layoutSection
                
            case .recommended:
                var configuration = UICollectionLayoutListConfiguration(appearance: .grouped)
                configuration.showsSeparators = false
                configuration.backgroundColor = .clear
                
                switch self.fetchRecommendedSourcesResult
                {
                case nil:
                    configuration.headerMode = .supplementary
                    configuration.footerMode = .supplementary
                    
                case .failure: configuration.footerMode = .supplementary
                case .success: configuration.headerMode = .supplementary
                }
                
                let layoutSection = NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: layoutEnvironment)
                return layoutSection
            }
        }, configuration: layoutConfig)
        
        return layout
    }
    
    func makeDataSource() -> RSTCompositeCollectionViewPrefetchingDataSource<Source, UIImage>
    {
        let dataSource = RSTCompositeCollectionViewPrefetchingDataSource<Source, UIImage>(dataSources: [self.addSourceDataSource, 
                                                                                                        self.sourcePreviewDataSource,
                                                                                                        self.recommendedSourcesDataSource])
        dataSource.proxy = self
        return dataSource
    }
    
    func makeAddSourceDataSource() -> RSTDynamicCollectionViewPrefetchingDataSource<Source, UIImage>
    {
        let dataSource = RSTDynamicCollectionViewPrefetchingDataSource<Source, UIImage>()
        dataSource.numberOfSectionsHandler = { 1 }
        dataSource.numberOfItemsHandler = { _ in 1 }
        dataSource.cellIdentifierHandler = { _ in ReuseID.textFieldCell.rawValue }
        dataSource.cellConfigurationHandler = { [weak self] cell, source, indexPath in
            guard let self else { return }
            
            let cell = cell as! AddSourceTextFieldCell
            cell.contentView.layoutMargins.left = self.view.layoutMargins.left
            cell.contentView.layoutMargins.right = self.view.layoutMargins.right
            
            cell.textField.delegate = self
            
            cell.setNeedsLayout()
            cell.layoutIfNeeded()
            
            NotificationCenter.default
                .publisher(for: UITextField.textDidChangeNotification, object: cell.textField)
                .map { ($0.object as? UITextField)?.text ?? "" }
                .assign(to: &self.viewModel.$sourceAddress)
            
                // Results in memory leak
                // .assign(to: \.viewModel.sourceAddress, on: self)
        }
        
        return dataSource
    }
    
    func makeSourcePreviewDataSource() -> RSTArrayCollectionViewPrefetchingDataSource<Source, UIImage>
    {
        let dataSource = RSTArrayCollectionViewPrefetchingDataSource<Source, UIImage>(items: [])
        dataSource.cellConfigurationHandler = { [weak self] cell, source, indexPath in
            guard let self else { return }
            
            let cell = cell as! AppBannerCollectionViewCell
            self.configure(cell, with: source)
        }
        dataSource.prefetchHandler = { (source, indexPath, completionHandler) in
            guard let imageURL = source.effectiveIconURL else { return nil }
            
            return RSTAsyncBlockOperation() { (operation) in
                ImagePipeline.shared.loadImage(with: imageURL, progress: nil) { result in
                    guard !operation.isCancelled else { return operation.finish() }
                    
                    switch result
                    {
                    case .success(let response): completionHandler(response.image, nil)
                    case .failure(let error): completionHandler(nil, error)
                    }
                }
            }
        }
        dataSource.prefetchCompletionHandler = { (cell, image, indexPath, error) in
            let cell = cell as! AppBannerCollectionViewCell
            cell.bannerView.iconImageView.isIndicatingActivity = false
            cell.bannerView.iconImageView.image = image
            
            if let error = error
            {
                print("Error loading image:", error)
            }
        }
        
        return dataSource
    }
    
    func makeRecommendedSourcesDataSource() -> RSTArrayCollectionViewPrefetchingDataSource<Source, UIImage>
    {
        let dataSource = RSTArrayCollectionViewPrefetchingDataSource<Source, UIImage>(items: [])
        dataSource.cellConfigurationHandler = { [weak self] cell, source, indexPath in
            guard let self else { return }
            
            let cell = cell as! AppBannerCollectionViewCell
            self.configure(cell, with: source)
        }
        dataSource.prefetchHandler = { (source, indexPath, completionHandler) in
            guard let imageURL = source.effectiveIconURL else { return nil }
            
            return RSTAsyncBlockOperation() { (operation) in
                ImagePipeline.shared.loadImage(with: imageURL, progress: nil) { result in
                    guard !operation.isCancelled else { return operation.finish() }
                    
                    switch result
                    {
                    case .success(let response): completionHandler(response.image, nil)
                    case .failure(let error): completionHandler(nil, error)
                    }
                }
            }
        }
        dataSource.prefetchCompletionHandler = { (cell, image, indexPath, error) in
            let cell = cell as! AppBannerCollectionViewCell
            cell.bannerView.iconImageView.isIndicatingActivity = false
            cell.bannerView.iconImageView.image = image
            
            if let error = error
            {
                print("Error loading image:", error)
            }
        }
        
        return dataSource
    }
}

private extension AddSourceViewController
{
    func startPipeline()
    {
        /* Pipeline */
        
        // Map UITextField text -> URLs
        self.viewModel.$sourceAddress
            .map { [weak self] in
                guard let self else { return [] }
                
                // Preserve order of parsed URLs
                let lines = $0.split(whereSeparator: { $0.isWhitespace })
                                .map(String.init)
                                .compactMap(self.sourceURL)
                
                return NSOrderedSet(array: lines).array as! [URL] // de-duplicate while preserving order
            }
            .assign(to: &self.viewModel.$sourceURLs)

        let showPreviewStatusPublisher = self.viewModel.$isShowingPreviewStatus
            .filter { $0 == true }
        
        let sourceURLsPublisher = self.viewModel.$sourceURLs
            .removeDuplicates()
            .debounce(for: 0.2, scheduler: RunLoop.main)
            .receive(on: RunLoop.main)
            .map { [weak self] sourceURLs in
                // Only set sourcePreviewResult to nil if sourceURL actually changes.
                self?.viewModel.sourcePreviewResults = []
                return sourceURLs
            }
        
        // Map URL -> Source Preview
        Publishers.CombineLatest(sourceURLsPublisher, showPreviewStatusPublisher.prepend(false))
            .receive(on: RunLoop.main)
            .map { $0.0 }
            .flatMap { [weak self] (sourceURLs: [URL]) -> AnyPublisher<[SourcePreviewResult?], Never> in
                guard let self else { return Just([]).eraseToAnyPublisher() }
                
                self.viewModel.isLoadingPreview = true
                
                // Create publishers maintaining order
                let publishers = sourceURLs.enumerated().map { index, sourceURL in
                    self.fetchSourcePreview(sourceURL: sourceURL)
                        .map { result in
                            // Add index to maintain order
                            (index: index, result: result)
                        }
                        .eraseToAnyPublisher()
                }
                
                // since network requests are concurrent, we sort the values when they are received
                return publishers.isEmpty
                    ? Just([]).eraseToAnyPublisher()
                    : Publishers.MergeMany(publishers)
                        .collect()                                      // await all publishers to emit the results
                        .map { results in                               // perform sorting of the collected results
                            // Sort by original index before returning
                            results.sorted { $0.index < $1.index }
                                .map { $0.result }
                        }
                        .eraseToAnyPublisher()
            }
            .sink { [weak self] sourcePreviewResults in
                self?.viewModel.isLoadingPreview = false
                self?.viewModel.sourcePreviewResults = sourcePreviewResults.compactMap{$0}
            }
            .store(in: &self.cancellables)
        
        /* Update UI */
        Publishers.CombineLatest(self.viewModel.$isLoadingPreview.removeDuplicates(),
                                 self.viewModel.$isShowingPreviewStatus.removeDuplicates())
        .sink { [weak self] _ in
            guard let self else { return }
            
            // @Published fires _before_ property is updated, so wait until next run loop.
            DispatchQueue.main.async {
                self.collectionView.performBatchUpdates {
                    let indexPath = IndexPath(item: 0, section: Section.preview.rawValue)
                    
                    if let footerView = self.collectionView.supplementaryView(forElementKind: UICollectionView.elementKindSectionFooter, at: indexPath) as? PlaceholderCollectionReusableView
                    {
                        self.configure(footerView, with: self.viewModel.sourcePreviewResults)
                    }
                    
                    let context = UICollectionViewLayoutInvalidationContext()
                    context.invalidateSupplementaryElements(ofKind: UICollectionView.elementKindSectionFooter, at: [indexPath])
                    self.collectionView.collectionViewLayout.invalidateLayout(with: context)
                }
            }
        }
        .store(in: &self.cancellables)
        
        self.viewModel.$sourcePreviewResults
            .map { sourcePreviewResults -> [Source] in
                // Maintain order based on original sourceURLs array
                let orderedSources = self.viewModel.sourceURLs.compactMap { sourceURL -> Source? in
                    // Find the preview result matching this URL
                    guard let previewResult = sourcePreviewResults.first(where: { $0.sourceURL == sourceURL }),
                          case .success(let managedSource) = previewResult.result
                    else {
                        return nil
                    }
                    
                    return managedSource.wrappedValue
                }
                
                return orderedSources
            }
            .receive(on: RunLoop.main)
            .sink { [weak self] sources in
                self?.updateSourcesPreview(for: sources)
            }
            .store(in: &self.cancellables)

        
        let mergedNotificationPublisher = Publishers.Merge(
            NotificationCenter.default.publisher(for: AppManager.didAddSourceNotification),
            NotificationCenter.default.publisher(for: AppManager.didRemoveSourceNotification)
        )
        .receive(on: RunLoop.main)
        .share() // Shares the upstream publisher with multiple subscribers
        
        // Update recommended sources section when sources are added/removed
        mergedNotificationPublisher
            .compactMap { notification -> String? in
                guard let source = notification.object as? Source,
                      let context = source.managedObjectContext
                else { return nil }
                
                let sourceID = context.performAndWait { source.identifier }
                return sourceID
            }
            .compactMap { [dataSource = recommendedSourcesDataSource] sourceID -> IndexPath? in
                guard let index = dataSource.items.firstIndex(where: { $0.identifier == sourceID }) else { return nil }
                
                let indexPath = IndexPath(item: index, section: Section.recommended.rawValue)
                return indexPath
            }
            .sink { [weak self] indexPath in
                // Added or removed a recommended source, so make sure to update its state.
                self?.collectionView.reloadItems(at: [indexPath])
            }
            .store(in: &self.cancellables)
        
        // Update previews section when sources are added/removed
//        mergedNotificationPublisher
//            .sink { [weak self] _ in
//                // reload the entire of previews section to get latest state
//                self?.collectionView.reloadSections(IndexSet(integer: Section.preview.rawValue))
//            }
//            .store(in: &self.cancellables)
        
        mergedNotificationPublisher
            .compactMap { notification -> String? in
                guard let source = notification.object as? Source,
                      let context = source.managedObjectContext
                else { return nil }
                return context.performAndWait { source.identifier }
            }
            .compactMap { [weak self] sourceID -> IndexPath? in
                guard let dataSource = self?.sourcePreviewDataSource,
                      let index = dataSource.items.firstIndex(where: { $0.identifier == sourceID })
                else { return nil }
                return IndexPath(item: index, section: Section.preview.rawValue)
            }
            .sink { [weak self] indexPath in
                self?.collectionView.reloadItems(at: [indexPath])
            }
            .store(in: &self.cancellables)
    }
    
    func sourceURL(from address: String) -> URL?
    {
        guard let sourceURL = URL(string: address) else { return nil }
        
        // URLs without hosts are OK (e.g. localhost:8000)
        // guard sourceURL.host != nil else { return }
        
        guard let scheme = sourceURL.scheme else {
            let sanitizedURL = URL(string: "https://" + address)
            return sanitizedURL
        }
        
        guard scheme.lowercased() != "localhost" else {
            let sanitizedURL = URL(string: "http://" + address)
            return sanitizedURL
        }
        
        return sourceURL
    }
    
    func fetchSourcePreview(sourceURL: URL) -> some Publisher<SourcePreviewResult?, Never>
    {
        let context = DatabaseManager.shared.persistentContainer.newBackgroundSavingViewContext()
        
        var fetchOperation: FetchSourceOperation?
        return Future<Source, Error> { promise in
            fetchOperation = AppManager.shared.fetchSource(sourceURL: sourceURL, managedObjectContext: context) { result in
                promise(result)
            }
        }
        .map { source in
            let result = SourcePreviewResult(sourceURL, .success(Managed(wrappedValue: source)))
            return result
        }
        .catch { error in
            print("Failed to fetch source for URL \(sourceURL).", error.localizedDescription)
            
            let result = SourcePreviewResult(sourceURL, .failure(error))
            return Just<SourcePreviewResult?>(result)
        }
        .handleEvents(receiveCancel: {
            fetchOperation?.cancel()
        })
    }
    
    func updateSourcesPreview(for sources: [Source]) {
        // Calculate changes needed to go from current items to new items
        let currentItemCount = self.sourcePreviewDataSource.items.count
        let newItemCount = sources.count
        
        var changes: [RSTCellContentChange] = []
        
        if currentItemCount == 0 && newItemCount > 0 {
            // Insert all items if we currently have none
            for i in 0..<newItemCount {
                let indexPath = IndexPath(row: i, section: 0)
                let change = RSTCellContentChange(type: .insert,
                                                currentIndexPath: nil,
                                                destinationIndexPath: indexPath)
                changes.append(change)
            }
        } else if currentItemCount > 0 && newItemCount == 0 {
            // Delete all items if we're going to have none
            for i in 0..<currentItemCount {
                let indexPath = IndexPath(row: i, section: 0)
                let change = RSTCellContentChange(type: .delete,
                                                currentIndexPath: indexPath,
                                                destinationIndexPath: nil)
                changes.append(change)
            }
        } else if currentItemCount != newItemCount {
            // If counts differ, do a section update
            let change = RSTCellContentChange(type: .update, sectionIndex: 0)
            changes = [change]
        } else {
            // Update existing items in place
            for i in 0..<newItemCount {
                let indexPath = IndexPath(row: i, section: 0)
                let change = RSTCellContentChange(type: .update,
                                                currentIndexPath: indexPath,
                                                destinationIndexPath: indexPath)
                changes.append(change)
            }
        }
        
        self.sourcePreviewDataSource.setItems(sources, with: changes)
        
        if sources.isEmpty {
            self.collectionView.reloadSections([Section.preview.rawValue])
        } else {
            self.collectionView.collectionViewLayout.invalidateLayout()
        }
    }
}

private extension AddSourceViewController
{
    func configure(_ cell: AppBannerCollectionViewCell, with source: Source)
    {
        cell.bannerView.style = .source
        cell.layoutMargins.top = 5
        cell.layoutMargins.bottom = 5
        cell.layoutMargins.left = self.view.layoutMargins.left
        cell.layoutMargins.right = self.view.layoutMargins.right
        cell.contentView.backgroundColor = .altBackground
        
        cell.bannerView.configure(for: source)
        cell.bannerView.subtitleLabel.numberOfLines = 2
        
        cell.bannerView.iconImageView.image = nil
        cell.bannerView.iconImageView.isIndicatingActivity = true
        
        let config = UIImage.SymbolConfiguration(scale: .medium)
        cell.bannerView.button.setTitle(nil, for: .normal)
        cell.bannerView.button.imageView?.contentMode = .scaleAspectFit
        cell.bannerView.button.contentHorizontalAlignment = .fill // Fill entire button with imageView
        cell.bannerView.button.contentVerticalAlignment = .fill
        cell.bannerView.button.contentEdgeInsets = .zero
        cell.bannerView.button.tintColor = .clear
        cell.bannerView.button.isHidden = false
        
        // mark the button with label (useful for accessibility and for UITests)
        cell.bannerView.button.accessibilityIdentifier = "add"
        
        func setButtonIcon()
        {
            Task<Void, Never>(priority: .userInitiated) { [weak cell] in
                guard let cell else { return }
                
                var isSourceAlreadyPersisted = false
                do
                {
                    isSourceAlreadyPersisted = try await source.isAdded
                }
                catch
                {
                    print("Failed to determine if source is added.", error)
                }
                    
                // use the plus icon by default
                var buttonIcon = UIImage(systemName: "plus.circle.fill", withConfiguration: config)?.withTintColor(.white, renderingMode: .alwaysOriginal)
                
                // if the source is already added/staged for adding, use the checkmark icon
                let isStagedForAdd = self.stagedForAdd[source] == true
                if isStagedForAdd || isSourceAlreadyPersisted
                {
                    buttonIcon = UIImage(systemName: "checkmark.circle.fill", withConfiguration: config)?
                                    .withTintColor(isSourceAlreadyPersisted ? .green : .white, renderingMode: .alwaysOriginal)
                }
                cell.bannerView.button.setImage(buttonIcon, for: .normal)
                cell.bannerView.button.isEnabled = !isSourceAlreadyPersisted
            }
        }
        
        // set the icon
        setButtonIcon()
        
        let action = UIAction(identifier: .addSource) { [weak self] _ in
            guard let self else { return }
            
            self.stagedForAdd[source, default: false].toggle()

            // update the button icon
            setButtonIcon()
        }
        cell.bannerView.button.addAction(action, for: .primaryActionTriggered)
    }
    
    func configure(_ footerView: PlaceholderCollectionReusableView, with sourcePreviewResults: [SourcePreviewResult?])
    {
        footerView.placeholderView.stackView.isLayoutMarginsRelativeArrangement = false
        
        footerView.placeholderView.textLabel.textColor = .secondaryLabel
        footerView.placeholderView.textLabel.font = .preferredFont(forTextStyle: .subheadline)
        footerView.placeholderView.textLabel.textAlignment = .center
        
        footerView.placeholderView.detailTextLabel.isHidden = true
        
        var errorText: String? = nil
        var isError: Bool = false
        for result in sourcePreviewResults
        {
            switch result
            {
            case (let sourceURL, .failure(let previewError))? where (self.viewModel.sourceURLs.contains(sourceURL) && !self.viewModel.isLoadingPreview):
                // The current URL matches the error being displayed, and we're not loading another preview, so show error.
                
                errorText = (previewError as NSError).localizedDebugDescription ?? previewError.localizedDescription
                footerView.placeholderView.textLabel.text = errorText
                footerView.placeholderView.textLabel.isHidden = false
                
                isError = true
                
            default:
                // The current URL does not match the URL of the source/error being displayed, so show loading indicator.
                errorText = nil
                footerView.placeholderView.textLabel.isHidden = true
            }
        }
        footerView.placeholderView.textLabel.text = errorText
        
        if !isError{
            footerView.placeholderView.activityIndicatorView.startAnimating()
        } else{
            footerView.placeholderView.activityIndicatorView.stopAnimating()
        }
    }
    
    func fetchRecommendedSources()
    {
        // Closure instead of local function so we can capture `self` weakly.
        let finish: (Result<[Source], Error>) -> Void = { [weak self] result in
            self?.fetchRecommendedSourcesResult = result.map { _ in () }
            
            DispatchQueue.main.async {
                do
                {
                    let sources = try result.get()
                    print("Fetched recommended sources:", sources.map { $0.identifier })
                    
                    let sectionUpdate = RSTCellContentChange(type: .update, sectionIndex: 0)
                    self?.recommendedSourcesDataSource.setItems(sources, with: [sectionUpdate])
                }
                catch
                {
                    print("Error fetching recommended sources:", error)
                    
                    let sectionUpdate = RSTCellContentChange(type: .update, sectionIndex: 0)
                    self?.recommendedSourcesDataSource.setItems([], with: [sectionUpdate])
                }
            }
        }
        
        self.fetchRecommendedSourcesOperation = AppManager.shared.updateKnownSources { [weak self] result in
            switch result
            {
            case .failure(let error): finish(.failure(error))
            case .success((let trustedSources, _)):
                
                // Don't show sources without a sourceURL.
                let featuredSourceURLs = trustedSources.compactMap { $0.sourceURL }
                
                // This context is never saved, but keeps the managed sources alive.
                let context = DatabaseManager.shared.persistentContainer.newBackgroundSavingViewContext()
                self?._fetchRecommendedSourcesContext = context
                
                let dispatchGroup = DispatchGroup()
                
                var sourcesByURL = [URL: Source]()
                var fetchError: Error?
                
                for sourceURL in featuredSourceURLs
                {
                    dispatchGroup.enter()
                    
                    AppManager.shared.fetchSource(sourceURL: sourceURL, managedObjectContext: context) { result in
                        // Serialize access to sourcesByURL.
                        context.performAndWait {
                            switch result
                            {
                            case .failure(let error):
                                print("Failed to load recommended source \(sourceURL.absoluteString):", error.localizedDescription, error)
                                fetchError = error
                                
                            case .success(let source): sourcesByURL[source.sourceURL] = source
                            }
                            
                            dispatchGroup.leave()
                        }
                    }
                }
                
                dispatchGroup.notify(queue: .main) {
                    let sources = featuredSourceURLs.compactMap { sourcesByURL[$0] }
                    
                    if let error = fetchError, sources.isEmpty
                    {
                        finish(.failure(error))
                    }
                    else
                    {
                        finish(.success(sources))
                    }
                }
            }
        }
    }
    
    @IBAction func commitChanges(_ sender: UIBarButtonItem)
    {
        struct StagedSource: Hashable {
            @AsyncManaged var source: Source

            // Conformance for Equatable/Hashable by comparing the underlying source
            static func == (lhs: StagedSource, rhs: StagedSource) -> Bool {
                return lhs.source.identifier == rhs.source.identifier
            }

            func hash(into hasher: inout Hasher) {
                hasher.combine(source)
            }
        }
        
        Task<Void, Never> {
            var isCancelled = false
            // OK: COMMIT the staged changes now
            // Convert the stagedForAdd dictionary into an array of StagedSource
            let stagedSources: [StagedSource] = self.stagedForAdd.filter { $0.value }
                .map { StagedSource(source: $0.key) }
            
            for staged in stagedSources {
                do
                {
                    // Use the projected value to safely access isRecommended asynchronously
                    let isRecommended = await staged.$source.isRecommended
                    if isRecommended
                    {
                        try await AppManager.shared.add(staged.source, message: nil, presentingViewController: self)
                    }
                    else
                    {
                        // Use default message
                        try await AppManager.shared.add(staged.source, presentingViewController: self)
                    }
                    
                    // remove this kv pair
                    _ = self.stagedForAdd.removeValue(forKey: staged.source)
                }
                catch is CancellationError {
                    isCancelled = true
                    break
                }
                catch
                {
                    let errorTitle = NSLocalizedString("Unable to Add Source", comment: "")
                    await self.presentAlert(title: errorTitle, message: error.localizedDescription)
                }
            }
            
            if !isCancelled {
                // finally dismiss the sheet/viewcontroller
                self.dismiss()
            }
        }
    }
    
    func dismiss()
    {
        guard 
            let navigationController = self.navigationController, let presentingViewController = navigationController.presentingViewController
        else { return }
        
        presentingViewController.dismiss(animated: true)
    }
}

private extension AddSourceViewController
{
    @IBSegueAction
    func makeSourceDetailViewController(_ coder: NSCoder, sender: Any?) -> UIViewController?
    {
        guard let source = sender as? Source else { return nil }
        
        let sourceDetailViewController = SourceDetailViewController(source: source, coder: coder)
        sourceDetailViewController?.addedSourceHandler = { [weak self] _ in
            self?.dismiss()
        }
        return sourceDetailViewController
    }
}

extension AddSourceViewController
{
    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) 
    {
        guard Section(rawValue: indexPath.section) != .add else { return }
        
        let source = self.dataSource.item(at: indexPath)
        self.performSegue(withIdentifier: "showSourceDetails", sender: source)
    }
}

extension AddSourceViewController: UICollectionViewDelegateFlowLayout
{
    override func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView
    {
        let section = Section(rawValue: indexPath.section)!
        switch (section, kind)
        {
        case (.add, UICollectionView.elementKindSectionHeader):
            let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: kind, for: indexPath) as! UICollectionViewListCell
            
            var configuation = UIListContentConfiguration.cell()
            configuation.text = NSLocalizedString("Enter a source's URL below, or add one of the recommended sources.", comment: "")
            configuation.textProperties.color = .secondaryLabel
            
            headerView.contentConfiguration = configuation
            
            return headerView
            
        case (.preview, UICollectionView.elementKindSectionFooter):
            let footerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: ReuseID.placeholderFooter.rawValue, for: indexPath) as! PlaceholderCollectionReusableView
            
            self.configure(footerView, with: self.viewModel.sourcePreviewResults)
            
            return footerView
                        
        case (.recommended, UICollectionView.elementKindSectionHeader):
            let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: kind, for: indexPath) as! UICollectionViewListCell
            
            var configuation = UIListContentConfiguration.groupedHeader()
            configuation.text = NSLocalizedString("Recommended Sources", comment: "")
            configuation.textProperties.color = .secondaryLabel
            
            headerView.contentConfiguration = configuation
            
            return headerView
            
        case (.recommended, UICollectionView.elementKindSectionFooter):
            let footerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: ReuseID.placeholderFooter.rawValue, for: indexPath) as! PlaceholderCollectionReusableView
            
            footerView.placeholderView.stackView.spacing = 15
            footerView.placeholderView.stackView.directionalLayoutMargins.top = 20
            footerView.placeholderView.stackView.isLayoutMarginsRelativeArrangement = true
            
            if let result = self.fetchRecommendedSourcesResult, case .failure(let error) = result
            {
                footerView.placeholderView.textLabel.isHidden = false
                footerView.placeholderView.textLabel.font = UIFont.preferredFont(forTextStyle: .headline)
                footerView.placeholderView.textLabel.text = NSLocalizedString("Unable to Load Recommended Sources", comment: "")
                
                footerView.placeholderView.detailTextLabel.isHidden = false
                footerView.placeholderView.detailTextLabel.text = error.localizedDescription
                
                footerView.placeholderView.activityIndicatorView.stopAnimating()
            }
            else
            {
                footerView.placeholderView.textLabel.isHidden = true
                footerView.placeholderView.detailTextLabel.isHidden = true
                
                footerView.placeholderView.activityIndicatorView.startAnimating()
            }
            
            return footerView
            
        default: fatalError()
        }
    }
}

extension AddSourceViewController: UITextFieldDelegate
{
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool 
    {
        self.viewModel.isShowingPreviewStatus = false
        return true
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool
    {
        textField.resignFirstResponder()
        return false
    }
    
    func textFieldDidEndEditing(_ textField: UITextField) 
    {
        self.viewModel.isShowingPreviewStatus = true
    }
}

@available(iOS 17.0, *)
#Preview(traits: .portrait) {
    DatabaseManager.shared.startForPreview()
    
    let storyboard = UIStoryboard(name: "Sources", bundle: .main)
    
    let addSourceNavigationController = storyboard.instantiateViewController(withIdentifier: "addSourceNavigationController")
    return addSourceNavigationController
}
