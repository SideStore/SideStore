//
//  HelperFile.swift
//  AltStoreCore
//
//  Created by Magesh K on 6/17/26.
//

import UIKit
import CoreData

public let RSTCellContentGenericCellIdentifier = "Cell"

public protocol RSTCellContentCell: AnyObject {}
public protocol RSTCellContentView: AnyObject {}

public protocol RSTCellContentPrefetchingDataSource: AnyObject {
    associatedtype ContentType
    associatedtype CellType
    associatedtype PrefetchContentType

    var prefetchItemCache: NSCache<AnyObject, AnyObject> { get set }
    var prefetchHandler: ((ContentType, IndexPath, @escaping (PrefetchContentType?, Error?) -> Void) -> Operation?)? { get set }
    var prefetchCompletionHandler: ((CellType, PrefetchContentType?, IndexPath, Error?) -> Void)? { get set }
}

private protocol RSTAnyCellContentDataSource: AnyObject {
    var anyItemCount: Int { get }
    func setAnyContentView(_ contentView: UIScrollView?)
    func anyNumberOfSections() -> Int
    func anyNumberOfItems(in section: Int) -> Int
    func anyItem(at indexPath: IndexPath) -> Any
    func anyCellIdentifier(at indexPath: IndexPath) -> String
    func configureAnyCell(_ cell: UIView, at indexPath: IndexPath)
}

private protocol RSTAnyCompositeDataSource: AnyObject {
    func compositeCollectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell
    func compositeTableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell
}

private final class RSTPlaceholderItem: NSObject {}

@objc(RSTCellContentChange)
public final class RSTCellContentChange: NSObject {
    public enum ChangeType: Int {
        case insert
        case delete
        case move
        case update
    }

    public let type: ChangeType
    public let currentIndexPath: IndexPath?
    public let destinationIndexPath: IndexPath?
    public let sectionIndex: Int?

    public init(type: ChangeType, currentIndexPath: IndexPath?, destinationIndexPath: IndexPath?) {
        self.type = type
        self.currentIndexPath = currentIndexPath
        self.destinationIndexPath = destinationIndexPath
        self.sectionIndex = nil
        super.init()
    }

    public init(type: ChangeType, sectionIndex: Int) {
        self.type = type
        self.currentIndexPath = nil
        self.destinationIndexPath = nil
        self.sectionIndex = sectionIndex
        super.init()
    }
}

open class RSTCellContentDataSource<ContentType, CellType: UIView & RSTCellContentCell, ViewType: UIScrollView, DataSourceType>: NSObject, UITableViewDataSource, UICollectionViewDataSource {
    open weak var contentView: ViewType?
    open weak var proxy: AnyObject?
    open var cellIdentifierHandler: ((IndexPath) -> String) = { _ in RSTCellContentGenericCellIdentifier }
    open var cellConfigurationHandler: ((CellType, ContentType, IndexPath) -> Void) = { _, _, _ in }
    open var predicate: NSPredicate?
        open var placeholderView: UIView? {
        didSet {
            placeholderView?.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            updatePlaceholderVisibility()
        }
    }
    
    private var isPlaceholderViewVisible: Bool = false
    private var previousSeparatorStyle: UITableViewCell.SeparatorStyle = .none
    private var previousScrollEnabled: Bool = true
    private var previousBackgroundView: UIView?

    private func showPlaceholderView() {
        guard !isPlaceholderViewVisible, let placeholderView, let contentView else { return }
        isPlaceholderViewVisible = true
        if let tableView = contentView as? UITableView {
            previousSeparatorStyle = tableView.separatorStyle
            tableView.separatorStyle = .none
        }
        previousScrollEnabled = contentView.isScrollEnabled
        contentView.isScrollEnabled = false
        previousBackgroundView = (contentView as? UITableView)?.backgroundView ?? (contentView as? UICollectionView)?.backgroundView
        (contentView as? UITableView)?.backgroundView = placeholderView
        (contentView as? UICollectionView)?.backgroundView = placeholderView
    }

    private func hidePlaceholderView() {
        guard isPlaceholderViewVisible, let contentView else { return }
        isPlaceholderViewVisible = false
        if let tableView = contentView as? UITableView {
            tableView.separatorStyle = previousSeparatorStyle
        }
        contentView.isScrollEnabled = previousScrollEnabled
        (contentView as? UITableView)?.backgroundView = previousBackgroundView
        (contentView as? UICollectionView)?.backgroundView = previousBackgroundView
    }

    private func updatePlaceholderVisibility() {
        guard let contentView else { return }
        var shouldShowPlaceholderView = true
        for i in 0..<numberOfSections(in: contentView) {
            if self.contentView(contentView, numberOfItemsInSection: i) > 0 {
                shouldShowPlaceholderView = false
                break
            }
        }
        if shouldShowPlaceholderView {
            showPlaceholderView()
        } else {
            hidePlaceholderView()
        }
    }
    open var rowAnimation: UITableView.RowAnimation = .automatic
    public var itemCount: Int = 0

    public lazy var searchController: RSTSearchController = {
        let controller = RSTSearchController(searchResultsController: nil)
        controller.searchHandler = { [weak self] searchValue, _ in
            self?.predicate = searchValue.predicate
            return nil
        }
        return controller
    }()

    open func item(at indexPath: IndexPath) -> ContentType { fatalError("override") }
    open func item(atIndexPath indexPath: IndexPath) -> ContentType { item(at: indexPath) }

    open func numberOfSections(in contentView: ViewType) -> Int { 1 }
    open func contentView(_ contentView: ViewType, numberOfItemsInSection section: Int) -> Int { 0 }
    open func filterContent(with predicate: NSPredicate?) {}
    open func setPredicate(_ predicate: NSPredicate?, refreshContent: Bool) {
        self.predicate = predicate
        filterContent(with: predicate)
        if refreshContent { (contentView as? UICollectionView)?.reloadData(); (contentView as? UITableView)?.reloadData() }
    }

        open func addChange(_ change: RSTCellContentChange) {
        let transformedChange = change
        (contentView as? RSTCellContentUpdateableView)?.addChange(transformedChange)
    }

    public func numberOfSections(in tableView: UITableView) -> Int {
        contentView = tableView as? ViewType
        guard let contentView else { return 0 }
        let sections = numberOfSections(in: contentView)
        updatePlaceholderVisibility()
        return sections
    }

    public func numberOfSections(in collectionView: UICollectionView) -> Int {
        contentView = collectionView as? ViewType
        guard let contentView else { return 0 }
        let sections = numberOfSections(in: contentView)
        updatePlaceholderVisibility()
        return sections
    }

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        contentView = tableView as? ViewType
        guard let contentView else { return 0 }
        return self.contentView(contentView, numberOfItemsInSection: section)
    }

    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        contentView = collectionView as? ViewType
        guard let contentView else { return 0 }
        return self.contentView(contentView, numberOfItemsInSection: section)
    }

    open func configureCell(_ cell: CellType, at indexPath: IndexPath) {
        cellConfigurationHandler(cell, item(at: indexPath), indexPath)
    }

    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if let compositeDataSource = self as? RSTAnyCompositeDataSource {
            return compositeDataSource.compositeCollectionView(collectionView, cellForItemAt: indexPath)
        }

        contentView = collectionView as? ViewType
        let identifier = cellIdentifierHandler(indexPath)
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: identifier, for: indexPath)
        if let typedCell = cell as? CellType {
            configureCell(typedCell, at: indexPath)
        }
        return cell
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if let compositeDataSource = self as? RSTAnyCompositeDataSource {
            return compositeDataSource.compositeTableView(tableView, cellForRowAt: indexPath)
        }

        contentView = tableView as? ViewType
        let identifier = cellIdentifierHandler(indexPath)
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier, for: indexPath)
        if let typedCell = cell as? CellType {
            configureCell(typedCell, at: indexPath)
        }
        return cell
    }
}

extension RSTCellContentDataSource: RSTAnyCellContentDataSource {
    fileprivate var anyItemCount: Int { itemCount }

    fileprivate func setAnyContentView(_ contentView: UIScrollView?) {
        self.contentView = contentView as? ViewType
    }

    fileprivate func anyNumberOfSections() -> Int {
        guard let contentView else { return 0 }
        return numberOfSections(in: contentView)
    }

    fileprivate func anyNumberOfItems(in section: Int) -> Int {
        guard let contentView else { return 0 }
        return self.contentView(contentView, numberOfItemsInSection: section)
    }

    fileprivate func anyItem(at indexPath: IndexPath) -> Any {
        item(at: indexPath)
    }

    fileprivate func anyCellIdentifier(at indexPath: IndexPath) -> String {
        cellIdentifierHandler(indexPath)
    }

    fileprivate func configureAnyCell(_ cell: UIView, at indexPath: IndexPath) {
        guard let cell = cell as? CellType else { return }
        configureCell(cell, at: indexPath)
    }
}

open class RSTDynamicDataSource<ContentType, CellType: UIView & RSTCellContentCell, ViewType: UIScrollView, DataSourceType>: RSTCellContentDataSource<ContentType, CellType, ViewType, DataSourceType> {
    open var numberOfSectionsHandler: (() -> Int) = { 0 }
    open var numberOfItemsHandler: ((Int) -> Int) = { _ in 0 }
    open var dynamicCellConfigurationHandler: ((CellType, IndexPath) -> Void) = { _, _ in }
    
    public override func numberOfSections(in contentView: ViewType) -> Int { numberOfSectionsHandler() }
    public override func contentView(_ contentView: ViewType, numberOfItemsInSection section: Int) -> Int { numberOfItemsHandler(section) }
    
    public override func item(at indexPath: IndexPath) -> ContentType {
        fatalError("item(at:) should not be called on RSTDynamicDataSource")
    }

    public override func configureCell(_ cell: CellType, at indexPath: IndexPath) {
        dynamicCellConfigurationHandler(cell, indexPath)
    }
}

open class RSTDynamicCollectionViewDataSource<ContentType>: RSTDynamicDataSource<ContentType, UICollectionViewCell, UICollectionView, UICollectionViewDataSource> {}
open class RSTDynamicTableViewDataSource<ContentType>: RSTDynamicDataSource<ContentType, UITableViewCell, UITableView, UITableViewDataSource> {}
open class RSTDynamicCollectionViewPrefetchingDataSource<ContentType, PrefetchContentType>: RSTDynamicCollectionViewDataSource<ContentType>, RSTCellContentPrefetchingDataSource, UICollectionViewDataSourcePrefetching {
    public var prefetchItemCache = NSCache<AnyObject, AnyObject>()
    public var prefetchHandler: ((ContentType, IndexPath, @escaping (PrefetchContentType?, Error?) -> Void) -> Operation?)?
    public var prefetchCompletionHandler: ((UICollectionViewCell, PrefetchContentType?, IndexPath, Error?) -> Void)?
    
    private var prefetchOperations: [IndexPath: Operation] = [:]
    private var prefetchOperationQueue = OperationQueue()

    public override func configureCell(_ cell: UICollectionViewCell, at indexPath: IndexPath) {
        super.configureCell(cell, at: indexPath)
        
        // Cancel existing operation for this index path if any
        prefetchOperations[indexPath]?.cancel()
        
        let item = self.item(at: indexPath)
        if let operation = prefetchHandler?(item, indexPath, { [weak self, weak cell] (content, error) in
            guard let self, let cell else { return }
            DispatchQueue.main.async {
                self.prefetchCompletionHandler?(cell, content, indexPath, error)
            }
        }) {
            prefetchOperations[indexPath] = operation
            prefetchOperationQueue.addOperation(operation)
        }
    }

    public func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            let item = self.item(at: indexPath)
            if let operation = prefetchHandler?(item, indexPath, { _, _ in }) {
                prefetchOperations[indexPath] = operation
                prefetchOperationQueue.addOperation(operation)
            }
        }
    }
    public func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            prefetchOperations[indexPath]?.cancel()
            prefetchOperations.removeValue(forKey: indexPath)
        }
    }
}
open class RSTDynamicTableViewPrefetchingDataSource<ContentType, PrefetchContentType>: RSTDynamicTableViewDataSource<ContentType>, RSTCellContentPrefetchingDataSource, UITableViewDataSourcePrefetching {
    public var prefetchItemCache = NSCache<AnyObject, AnyObject>()
    public var prefetchHandler: ((ContentType, IndexPath, @escaping (PrefetchContentType?, Error?) -> Void) -> Operation?)?
    public var prefetchCompletionHandler: ((UITableViewCell, PrefetchContentType?, IndexPath, Error?) -> Void)?
    
    private var prefetchOperations: [IndexPath: Operation] = [:]
    private var prefetchOperationQueue = OperationQueue()

    public override func configureCell(_ cell: UITableViewCell, at indexPath: IndexPath) {
        super.configureCell(cell, at: indexPath)
        
        // Cancel existing operation for this index path if any
        prefetchOperations[indexPath]?.cancel()
        
        let item = self.item(at: indexPath)
        if let operation = prefetchHandler?(item, indexPath, { [weak self, weak cell] (content, error) in
            guard let self, let cell else { return }
            DispatchQueue.main.async {
                self.prefetchCompletionHandler?(cell, content, indexPath, error)
            }
        }) {
            prefetchOperations[indexPath] = operation
            prefetchOperationQueue.addOperation(operation)
        }
    }

    public func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            let item = self.item(at: indexPath)
            if let operation = prefetchHandler?(item, indexPath, { _, _ in }) {
                prefetchOperations[indexPath] = operation
                prefetchOperationQueue.addOperation(operation)
            }
        }
    }
    public func tableView(_ tableView: UITableView, cancelPrefetchingForRowsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            prefetchOperations[indexPath]?.cancel()
            prefetchOperations.removeValue(forKey: indexPath)
        }
    }
}
open class RSTArrayDataSource<ContentType, CellType: UIView & RSTCellContentCell, ViewType: UIScrollView, DataSourceType>: RSTCellContentDataSource<ContentType, CellType, ViewType, DataSourceType> {
    open var items: [ContentType] = [] {
        didSet {
            itemCount = items.count
            (contentView as? UICollectionView)?.reloadData()
            (contentView as? UITableView)?.reloadData()
        }
    }
    public init(items: [ContentType]) {
        self.items = items
        super.init()
        self.itemCount = items.count
    }
    public func setItems(_ items: [ContentType], with changes: [RSTCellContentChange]? = nil) {
        self.items = items
        self.itemCount = items.count
        (contentView as? UICollectionView)?.reloadData()
        (contentView as? UITableView)?.reloadData()
    }
    public override func item(at indexPath: IndexPath) -> ContentType { items[indexPath.item] }
    public override func numberOfSections(in contentView: ViewType) -> Int { 1 }
    public override func contentView(_ contentView: ViewType, numberOfItemsInSection section: Int) -> Int { items.count }
    public override func filterContent(with predicate: NSPredicate?) {}
}

open class RSTArrayCollectionViewDataSource<ContentType>: RSTArrayDataSource<ContentType, UICollectionViewCell, UICollectionView, UICollectionViewDataSource> {}
open class RSTArrayTableViewDataSource<ContentType>: RSTArrayDataSource<ContentType, UITableViewCell, UITableView, UITableViewDataSource> {}
open class RSTArrayCollectionViewPrefetchingDataSource<ContentType, PrefetchContentType>: RSTArrayCollectionViewDataSource<ContentType>, RSTCellContentPrefetchingDataSource, UICollectionViewDataSourcePrefetching {
    public var prefetchItemCache = NSCache<AnyObject, AnyObject>()
    public var prefetchHandler: ((ContentType, IndexPath, @escaping (PrefetchContentType?, Error?) -> Void) -> Operation?)?
    public var prefetchCompletionHandler: ((UICollectionViewCell, PrefetchContentType?, IndexPath, Error?) -> Void)?
    
    private var prefetchOperations: [IndexPath: Operation] = [:]
    private var prefetchOperationQueue = OperationQueue()

    public override func configureCell(_ cell: UICollectionViewCell, at indexPath: IndexPath) {
        super.configureCell(cell, at: indexPath)
        
        // Cancel existing operation for this index path if any
        prefetchOperations[indexPath]?.cancel()
        
        let item = self.item(at: indexPath)
        if let operation = prefetchHandler?(item, indexPath, { [weak self, weak cell] (content, error) in
            guard let self, let cell else { return }
            DispatchQueue.main.async {
                self.prefetchCompletionHandler?(cell, content, indexPath, error)
            }
        }) {
            prefetchOperations[indexPath] = operation
            prefetchOperationQueue.addOperation(operation)
        }
    }

    public func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            let item = self.item(at: indexPath)
            if let operation = prefetchHandler?(item, indexPath, { _, _ in }) {
                prefetchOperations[indexPath] = operation
                prefetchOperationQueue.addOperation(operation)
            }
        }
    }
    public func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            prefetchOperations[indexPath]?.cancel()
            prefetchOperations.removeValue(forKey: indexPath)
        }
    }
}
open class RSTArrayTableViewPrefetchingDataSource<ContentType, PrefetchContentType>: RSTArrayTableViewDataSource<ContentType>, RSTCellContentPrefetchingDataSource, UITableViewDataSourcePrefetching {
    public var prefetchItemCache = NSCache<AnyObject, AnyObject>()
    public var prefetchHandler: ((ContentType, IndexPath, @escaping (PrefetchContentType?, Error?) -> Void) -> Operation?)?
    public var prefetchCompletionHandler: ((UITableViewCell, PrefetchContentType?, IndexPath, Error?) -> Void)?
    
    private var prefetchOperations: [IndexPath: Operation] = [:]
    private var prefetchOperationQueue = OperationQueue()

    public override func configureCell(_ cell: UITableViewCell, at indexPath: IndexPath) {
        super.configureCell(cell, at: indexPath)
        
        // Cancel existing operation for this index path if any
        prefetchOperations[indexPath]?.cancel()
        
        let item = self.item(at: indexPath)
        if let operation = prefetchHandler?(item, indexPath, { [weak self, weak cell] (content, error) in
            guard let self, let cell else { return }
            DispatchQueue.main.async {
                self.prefetchCompletionHandler?(cell, content, indexPath, error)
            }
        }) {
            prefetchOperations[indexPath] = operation
            prefetchOperationQueue.addOperation(operation)
        }
    }

    public func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            let item = self.item(at: indexPath)
            if let operation = prefetchHandler?(item, indexPath, { _, _ in }) {
                prefetchOperations[indexPath] = operation
                prefetchOperationQueue.addOperation(operation)
            }
        }
    }
    public func tableView(_ tableView: UITableView, cancelPrefetchingForRowsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            prefetchOperations[indexPath]?.cancel()
            prefetchOperations.removeValue(forKey: indexPath)
        }
    }
}
open class RSTFetchedResultsDataSource<ContentType: NSManagedObject, CellType: UIView & RSTCellContentCell, ViewType: UIScrollView, DataSourceType>: RSTCellContentDataSource<ContentType, CellType, ViewType, DataSourceType>, NSFetchedResultsControllerDelegate {
    open var liveFetchLimit: Int = 0 {
        didSet {
            guard liveFetchLimit != oldValue else { return }
            refreshItemCount()
            reload()
        }
    }
    open var fetchedResultsController: NSFetchedResultsController<ContentType> {
        didSet { fetchedResultsController.delegate = self; reload() }
    }
    public init(fetchedResultsController: NSFetchedResultsController<ContentType>) {
        self.fetchedResultsController = fetchedResultsController
        super.init()
        self.fetchedResultsController.delegate = self
        refreshItemCount()
    }
    public convenience init(fetchRequest: NSFetchRequest<ContentType>, managedObjectContext: NSManagedObjectContext) {
        self.init(fetchedResultsController: NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: managedObjectContext, sectionNameKeyPath: nil, cacheName: nil))
    }
    private func performFetchIfNeeded() {
        guard fetchedResultsController.sections == nil else { return }
        try? fetchedResultsController.performFetch()
        refreshItemCount()
    }
    private func reload() { (contentView as? UICollectionView)?.reloadData(); (contentView as? UITableView)?.reloadData() }
    private func refreshItemCount() {
        guard let sections = fetchedResultsController.sections else {
            itemCount = 0
            return
        }
        
        let limit = liveFetchLimit > 0 ? liveFetchLimit : Int.max
        itemCount = sections.reduce(0) { partialResult, sectionInfo in
            partialResult + min(sectionInfo.numberOfObjects, limit)
        }
    }
    public override func numberOfSections(in contentView: ViewType) -> Int {
        performFetchIfNeeded()
        refreshItemCount()
        return fetchedResultsController.sections?.count ?? 0
    }
    public override func contentView(_ contentView: ViewType, numberOfItemsInSection section: Int) -> Int {
        performFetchIfNeeded()
        refreshItemCount()
        let count = fetchedResultsController.sections?[section].numberOfObjects ?? 0
        return liveFetchLimit > 0 ? min(count, liveFetchLimit) : count
    }
    public override func item(at indexPath: IndexPath) -> ContentType { fetchedResultsController.object(at: indexPath) }
    public override func filterContent(with predicate: NSPredicate?) {
        fetchedResultsController.fetchRequest.predicate = predicate
        try? fetchedResultsController.performFetch()
        refreshItemCount()
    }

        public func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {}
    public func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        refreshItemCount()
    }
    public func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        let changeType: RSTCellContentChange.ChangeType
        switch type {
        case .insert: changeType = .insert
        case .delete: changeType = .delete
        case .move: changeType = .move
        case .update: changeType = .update
        @unknown default: changeType = .update
        }
        addChange(RSTCellContentChange(type: changeType, currentIndexPath: indexPath, destinationIndexPath: newIndexPath))
    }
    public func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange sectionInfo: NSFetchedResultsSectionInfo, atSectionIndex sectionIndex: Int, for type: NSFetchedResultsChangeType) {
        let changeType: RSTCellContentChange.ChangeType
        switch type {
        case .insert: changeType = .insert
        case .delete: changeType = .delete
        case .move: changeType = .move
        case .update: changeType = .update
        @unknown default: changeType = .update
        }
        addChange(RSTCellContentChange(type: changeType, sectionIndex: sectionIndex))
    }
}

open class RSTFetchedResultsCollectionViewDataSource<ContentType: NSManagedObject>: RSTFetchedResultsDataSource<ContentType, UICollectionViewCell, UICollectionView, UICollectionViewDataSource> {}
open class RSTFetchedResultsTableViewDataSource<ContentType: NSManagedObject>: RSTFetchedResultsDataSource<ContentType, UITableViewCell, UITableView, UITableViewDataSource> {}
open class RSTFetchedResultsCollectionViewPrefetchingDataSource<ContentType: NSManagedObject, PrefetchContentType>: RSTFetchedResultsCollectionViewDataSource<ContentType>, RSTCellContentPrefetchingDataSource, UICollectionViewDataSourcePrefetching {
    public var prefetchItemCache = NSCache<AnyObject, AnyObject>()
    public var prefetchHandler: ((ContentType, IndexPath, @escaping (PrefetchContentType?, Error?) -> Void) -> Operation?)?
    public var prefetchCompletionHandler: ((UICollectionViewCell, PrefetchContentType?, IndexPath, Error?) -> Void)?
    
    private var prefetchOperations: [IndexPath: Operation] = [:]
    private var prefetchOperationQueue = OperationQueue()

    public override func configureCell(_ cell: UICollectionViewCell, at indexPath: IndexPath) {
        super.configureCell(cell, at: indexPath)
        
        // Cancel existing operation for this index path if any
        prefetchOperations[indexPath]?.cancel()
        
        let item = self.item(at: indexPath)
        if let operation = prefetchHandler?(item, indexPath, { [weak self, weak cell] (content, error) in
            guard let self, let cell else { return }
            DispatchQueue.main.async {
                self.prefetchCompletionHandler?(cell, content, indexPath, error)
            }
        }) {
            prefetchOperations[indexPath] = operation
            prefetchOperationQueue.addOperation(operation)
        }
    }

    public func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            let item = self.item(at: indexPath)
            if let operation = prefetchHandler?(item, indexPath, { _, _ in }) {
                prefetchOperations[indexPath] = operation
                prefetchOperationQueue.addOperation(operation)
            }
        }
    }
    public func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            prefetchOperations[indexPath]?.cancel()
            prefetchOperations.removeValue(forKey: indexPath)
        }
    }
}
open class RSTFetchedResultsTableViewPrefetchingDataSource<ContentType: NSManagedObject, PrefetchContentType>: RSTFetchedResultsTableViewDataSource<ContentType>, RSTCellContentPrefetchingDataSource, UITableViewDataSourcePrefetching {
    public var prefetchItemCache = NSCache<AnyObject, AnyObject>()
    public var prefetchHandler: ((ContentType, IndexPath, @escaping (PrefetchContentType?, Error?) -> Void) -> Operation?)?
    public var prefetchCompletionHandler: ((UITableViewCell, PrefetchContentType?, IndexPath, Error?) -> Void)?
    
    private var prefetchOperations: [IndexPath: Operation] = [:]
    private var prefetchOperationQueue = OperationQueue()

    public override func configureCell(_ cell: UITableViewCell, at indexPath: IndexPath) {
        super.configureCell(cell, at: indexPath)
        
        // Cancel existing operation for this index path if any
        prefetchOperations[indexPath]?.cancel()
        
        let item = self.item(at: indexPath)
        if let operation = prefetchHandler?(item, indexPath, { [weak self, weak cell] (content, error) in
            guard let self, let cell else { return }
            DispatchQueue.main.async {
                self.prefetchCompletionHandler?(cell, content, indexPath, error)
            }
        }) {
            prefetchOperations[indexPath] = operation
            prefetchOperationQueue.addOperation(operation)
        }
    }

    public func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            let item = self.item(at: indexPath)
            if let operation = prefetchHandler?(item, indexPath, { _, _ in }) {
                prefetchOperations[indexPath] = operation
                prefetchOperationQueue.addOperation(operation)
            }
        }
    }
    public func tableView(_ tableView: UITableView, cancelPrefetchingForRowsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            prefetchOperations[indexPath]?.cancel()
            prefetchOperations.removeValue(forKey: indexPath)
        }
    }
}
open class RSTCompositeDataSource<ContentType, CellType: UIView & RSTCellContentCell, ViewType: UIScrollView, DataSourceType>: RSTCellContentDataSource<ContentType, CellType, ViewType, DataSourceType> {
    open var dataSources: [AnyObject]
    open var shouldFlattenSections = false {
        didSet { (contentView as? UICollectionView)?.reloadData(); (contentView as? UITableView)?.reloadData() }
    }
    public init(dataSources: [AnyObject]) {
        self.dataSources = dataSources
        super.init()
        self.cellIdentifierHandler = { [weak self] indexPath in
            guard let self, let resolved = self.resolve(indexPath) else {
                return RSTCellContentGenericCellIdentifier
            }
            return resolved.dataSource.anyCellIdentifier(at: resolved.indexPath)
        }
        self.cellConfigurationHandler = { [weak self] cell, item, indexPath in
            guard let self, let resolved = self.resolve(indexPath) else { return }
            resolved.dataSource.configureAnyCell(cell, at: resolved.indexPath)
        }
    }

    private var typedDataSources: [RSTAnyCellContentDataSource] {
        dataSources.compactMap { $0 as? RSTAnyCellContentDataSource }
    }

    private func prepareChildren(for contentView: ViewType?) {
        for dataSource in typedDataSources {
            dataSource.setAnyContentView(contentView)
        }
    }

    private func sectionCount(for dataSource: RSTAnyCellContentDataSource) -> Int {
        dataSource.anyNumberOfSections()
    }

    private func itemCount(for dataSource: RSTAnyCellContentDataSource) -> Int {
        let sectionCount = dataSource.anyNumberOfSections()
        guard sectionCount > 0 else { return dataSource.anyItemCount }
        return (0..<sectionCount).reduce(0) { total, section in
            total + dataSource.anyNumberOfItems(in: section)
        }
    }

    private func localIndexPath(forFlattenedItem item: Int, in dataSource: RSTAnyCellContentDataSource) -> IndexPath {
        var remainingItem = item
        for section in 0..<dataSource.anyNumberOfSections() {
            let count = dataSource.anyNumberOfItems(in: section)
            if remainingItem < count {
                return IndexPath(item: remainingItem, section: section)
            }
            remainingItem -= count
        }
        return IndexPath(item: max(remainingItem, 0), section: 0)
    }

    private func resolve(_ indexPath: IndexPath) -> (dataSource: RSTAnyCellContentDataSource, indexPath: IndexPath)? {
        prepareChildren(for: contentView)

        if shouldFlattenSections {
            var itemOffset = 0
            for dataSource in typedDataSources {
                let count = itemCount(for: dataSource)
                if indexPath.item < itemOffset + count {
                    let localItem = indexPath.item - itemOffset
                    return (dataSource, localIndexPath(forFlattenedItem: localItem, in: dataSource))
                }
                itemOffset += count
            }
        } else {
            var sectionOffset = 0
            for dataSource in typedDataSources {
                let count = sectionCount(for: dataSource)
                if indexPath.section < sectionOffset + count {
                    return (dataSource, IndexPath(item: indexPath.item, section: indexPath.section - sectionOffset))
                }
                sectionOffset += count
            }
        }

        return nil
    }

    private func refreshItemCount() {
        itemCount = typedDataSources.reduce(0) { total, dataSource in
            total + itemCount(for: dataSource)
        }
    }

    open override func numberOfSections(in contentView: ViewType) -> Int {
        self.contentView = contentView
        prepareChildren(for: contentView)
        refreshItemCount()
        if shouldFlattenSections {
            return 1
        }
        return typedDataSources.reduce(0) { total, dataSource in
            total + dataSource.anyNumberOfSections()
        }
    }

    open override func contentView(_ contentView: ViewType, numberOfItemsInSection section: Int) -> Int {
        self.contentView = contentView
        prepareChildren(for: contentView)
        refreshItemCount()
        if shouldFlattenSections {
            return itemCount
        }
        guard let resolved = resolve(IndexPath(item: 0, section: section)) else {
            return 0
        }
        return resolved.dataSource.anyNumberOfItems(in: resolved.indexPath.section)
    }

    public override func item(at indexPath: IndexPath) -> ContentType {
        guard let resolved = resolve(indexPath) else { fatalError("Index path out of range.") }
        return resolved.dataSource.anyItem(at: resolved.indexPath) as! ContentType
    }

    public override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        contentView = collectionView as? ViewType
        guard let resolved = resolve(indexPath) else {
            return UICollectionViewCell()
        }

        let identifier = resolved.dataSource.anyCellIdentifier(at: resolved.indexPath)
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: identifier, for: indexPath)
        resolved.dataSource.configureAnyCell(cell, at: resolved.indexPath)
        return cell
    }

    public override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        contentView = tableView as? ViewType
        guard let resolved = resolve(indexPath) else {
            return UITableViewCell()
        }

        let identifier = resolved.dataSource.anyCellIdentifier(at: resolved.indexPath)
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier, for: indexPath)
        resolved.dataSource.configureAnyCell(cell, at: resolved.indexPath)
        return cell
    }
}

extension RSTCompositeDataSource: RSTAnyCompositeDataSource {
    fileprivate func compositeCollectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        contentView = collectionView as? ViewType
        guard let resolved = resolve(indexPath) else {
            return UICollectionViewCell()
        }

        let identifier = resolved.dataSource.anyCellIdentifier(at: resolved.indexPath)
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: identifier, for: indexPath)
        resolved.dataSource.configureAnyCell(cell, at: resolved.indexPath)
        return cell
    }

    fileprivate func compositeTableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        contentView = tableView as? ViewType
        guard let resolved = resolve(indexPath) else {
            return UITableViewCell()
        }

        let identifier = resolved.dataSource.anyCellIdentifier(at: resolved.indexPath)
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier, for: indexPath)
        resolved.dataSource.configureAnyCell(cell, at: resolved.indexPath)
        return cell
    }
}
open class RSTCompositeCollectionViewDataSource<ContentType>: RSTCompositeDataSource<ContentType, UICollectionViewCell, UICollectionView, UICollectionViewDataSource> {}
open class RSTCompositeTableViewDataSource<ContentType>: RSTCompositeDataSource<ContentType, UITableViewCell, UITableView, UITableViewDataSource> {}
open class RSTCompositeCollectionViewPrefetchingDataSource<ContentType, PrefetchContentType>: RSTCompositeCollectionViewDataSource<ContentType>, RSTCellContentPrefetchingDataSource, UICollectionViewDataSourcePrefetching {
    public var prefetchItemCache = NSCache<AnyObject, AnyObject>()
    public var prefetchHandler: ((ContentType, IndexPath, @escaping (PrefetchContentType?, Error?) -> Void) -> Operation?)?
    public var prefetchCompletionHandler: ((UICollectionViewCell, PrefetchContentType?, IndexPath, Error?) -> Void)?
    
    private var prefetchOperations: [IndexPath: Operation] = [:]
    private var prefetchOperationQueue = OperationQueue()

    public override func configureCell(_ cell: UICollectionViewCell, at indexPath: IndexPath) {
        super.configureCell(cell, at: indexPath)
        
        // Cancel existing operation for this index path if any
        prefetchOperations[indexPath]?.cancel()
        
        let item = self.item(at: indexPath)
        if let operation = prefetchHandler?(item, indexPath, { [weak self, weak cell] (content, error) in
            guard let self, let cell else { return }
            DispatchQueue.main.async {
                self.prefetchCompletionHandler?(cell, content, indexPath, error)
            }
        }) {
            prefetchOperations[indexPath] = operation
            prefetchOperationQueue.addOperation(operation)
        }
    }

    public func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            let item = self.item(at: indexPath)
            if let operation = prefetchHandler?(item, indexPath, { _, _ in }) {
                prefetchOperations[indexPath] = operation
                prefetchOperationQueue.addOperation(operation)
            }
        }
    }
    public func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            prefetchOperations[indexPath]?.cancel()
            prefetchOperations.removeValue(forKey: indexPath)
        }
    }
}
open class RSTCompositeTableViewPrefetchingDataSource<ContentType, PrefetchContentType>: RSTCompositeTableViewDataSource<ContentType>, RSTCellContentPrefetchingDataSource, UITableViewDataSourcePrefetching {
    public var prefetchItemCache = NSCache<AnyObject, AnyObject>()
    public var prefetchHandler: ((ContentType, IndexPath, @escaping (PrefetchContentType?, Error?) -> Void) -> Operation?)?
    public var prefetchCompletionHandler: ((UITableViewCell, PrefetchContentType?, IndexPath, Error?) -> Void)?
    
    private var prefetchOperations: [IndexPath: Operation] = [:]
    private var prefetchOperationQueue = OperationQueue()

    public override func configureCell(_ cell: UITableViewCell, at indexPath: IndexPath) {
        super.configureCell(cell, at: indexPath)
        
        // Cancel existing operation for this index path if any
        prefetchOperations[indexPath]?.cancel()
        
        let item = self.item(at: indexPath)
        if let operation = prefetchHandler?(item, indexPath, { [weak self, weak cell] (content, error) in
            guard let self, let cell else { return }
            DispatchQueue.main.async {
                self.prefetchCompletionHandler?(cell, content, indexPath, error)
            }
        }) {
            prefetchOperations[indexPath] = operation
            prefetchOperationQueue.addOperation(operation)
        }
    }

    public func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            let item = self.item(at: indexPath)
            if let operation = prefetchHandler?(item, indexPath, { _, _ in }) {
                prefetchOperations[indexPath] = operation
                prefetchOperationQueue.addOperation(operation)
            }
        }
    }
    public func tableView(_ tableView: UITableView, cancelPrefetchingForRowsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            prefetchOperations[indexPath]?.cancel()
            prefetchOperations.removeValue(forKey: indexPath)
        }
    }
}
public func RSTDegreesFromRadians(_ radians: CGFloat) -> CGFloat {
    return radians * (180.0 / .pi)
}

public func RSTRadiansFromDegrees(_ degrees: CGFloat) -> CGFloat {
    return (degrees * .pi) / 180.0
}

public func CGFloatEqualToFloat(_ float1: CGFloat, _ float2: CGFloat) -> Bool {
    if float1 == float2 {
        return true
    }
    if abs(float1 - float2) < .ulpOfOne {
        return true
    }
    return false
}

public func rst_dispatch_sync_on_main_thread(_ block: () -> Void) {
    if Thread.isMainThread {
        block()
    } else {
        DispatchQueue.main.sync(execute: block)
    }
}

private var sharedApplication: UIApplication? {
    let sharedSelector = NSSelectorFromString("sharedApplication")
    guard UIApplication.responds(to: sharedSelector) else { return nil }
    let shared = UIApplication.perform(sharedSelector)
    return shared?.takeUnretainedValue() as? UIApplication
}

public func RSTBeginBackgroundTask(name: String) -> UIBackgroundTaskIdentifier {
    var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    guard let app = sharedApplication else { return backgroundTask }
    backgroundTask = app.beginBackgroundTask(withName: name) {
        RSTEndBackgroundTask(&backgroundTask)
    }
    return backgroundTask
}

public func RSTEndBackgroundTask(_ backgroundTask: inout UIBackgroundTaskIdentifier) {
    guard let app = sharedApplication else { return }
    app.endBackgroundTask(backgroundTask)
    backgroundTask = .invalid
}

extension UITableViewCell: RSTCellContentCell {}
extension UICollectionViewCell: RSTCellContentCell {}

public protocol RSTCellContentUpdateableView: UIScrollView {
    func addChange(_ change: RSTCellContentChange)
}

extension UITableView: RSTCellContentUpdateableView {
    public func addChange(_ change: RSTCellContentChange) {
        // Simple fallback for table view, ideally use beginUpdates
        self.reloadData()
    }
}

extension UICollectionView: RSTCellContentUpdateableView {
    private struct AssociatedKeys {
        static var pendingChanges = "pendingChanges"
    }

    private var pendingChanges: [RSTCellContentChange] {
        get { objc_getAssociatedObject(self, &AssociatedKeys.pendingChanges) as? [RSTCellContentChange] ?? [] }
        set { objc_setAssociatedObject(self, &AssociatedKeys.pendingChanges, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    public func addChange(_ change: RSTCellContentChange) {
        var changes = pendingChanges
        changes.append(change)
        pendingChanges = changes
        
        // Dispatch performBatchUpdates
        DispatchQueue.main.async {
            let currentChanges = self.pendingChanges
            guard !currentChanges.isEmpty else { return }
            self.pendingChanges = []
            
            self.performBatchUpdates({
                for change in currentChanges {
                    if let sectionIndex = change.sectionIndex {
                        let indexSet = IndexSet(integer: sectionIndex)
                        switch change.type {
                        case .insert: self.insertSections(indexSet)
                        case .delete: self.deleteSections(indexSet)
                        case .update: self.reloadSections(indexSet)
                        default: break
                        }
                    } else {
                        switch change.type {
                        case .insert:
                            if let newIndexPath = change.destinationIndexPath { self.insertItems(at: [newIndexPath]) }
                        case .delete:
                            if let indexPath = change.currentIndexPath { self.deleteItems(at: [indexPath]) }
                        case .update:
                            if let indexPath = change.currentIndexPath { self.reloadItems(at: [indexPath]) }
                        case .move:
                            if let indexPath = change.currentIndexPath, let newIndexPath = change.destinationIndexPath {
                                self.moveItem(at: indexPath, to: newIndexPath)
                            }
                        default: break
                        }
                    }
                }
            }, completion: nil)
        }
    }
}


public extension UITableViewCell {
    class var nib: UINib {
        UINib(nibName: String(describing: self), bundle: nil)
    }

    class func instantiate(with nib: UINib) -> Self {
        nib.instantiate(withOwner: nil, options: nil).compactMap { $0 as? Self }.first ?? Self.init(style: .default, reuseIdentifier: nil)
    }
}

public extension UICollectionViewCell {
    class var nib: UINib {
        UINib(nibName: String(describing: self), bundle: nil)
    }

    class func instantiate(with nib: UINib) -> Self {
        nib.instantiate(withOwner: nil, options: nil).compactMap { $0 as? Self }.first ?? Self(frame: .zero)
    }
}

public extension UICollectionView {
    func add(_ change: RSTCellContentChange) {
        performBatchUpdates {
            switch change.type {
            case .insert:
                if let destinationIndexPath = change.destinationIndexPath {
                    insertItems(at: [destinationIndexPath])
                } else if let sectionIndex = change.sectionIndex {
                    insertSections(IndexSet(integer: sectionIndex))
                }
            case .delete:
                if let currentIndexPath = change.currentIndexPath {
                    deleteItems(at: [currentIndexPath])
                } else if let sectionIndex = change.sectionIndex {
                    deleteSections(IndexSet(integer: sectionIndex))
                }
            case .move:
                if let currentIndexPath = change.currentIndexPath, let destinationIndexPath = change.destinationIndexPath {
                    moveItem(at: currentIndexPath, to: destinationIndexPath)
                }
            case .update:
                if let currentIndexPath = change.currentIndexPath {
                    reloadItems(at: [currentIndexPath])
                }
            }
        }
    }
}
