//
//  FetchedResultsDataSource.swift
//  AltStore
//
//  Created by Magesh K on 8/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

@preconcurrency import UIKit
import CoreData

internal final class ProxyPredicate: NSCompoundPredicate {
    convenience init(predicate: NSPredicate?, externalPredicate: NSPredicate?) {
        var subpredicates = [NSPredicate]()
        if let externalPredicate = externalPredicate {
            subpredicates.append(externalPredicate)
        }
        if let predicate = predicate {
            subpredicates.append(predicate)
        }
        self.init(type: .and, subpredicates: subpredicates)
    }
    
    override init(type: NSCompoundPredicate.LogicalType, subpredicates: [NSPredicate]) {
        super.init(type: type, subpredicates: subpredicates)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
}

open class FetchedResultsDataSource<ContentType: NSManagedObject, CellType: UIView & CellContentCell, ViewType: UIScrollView, DataSourceType>: CellContentDataSource<ContentType, CellType, ViewType, DataSourceType>, NSFetchedResultsControllerDelegate {
    open var liveFetchLimit: Int = 0 {
        didSet {
            guard liveFetchLimit != oldValue else { return }
            refreshItemCount()
            reload()
        }
    }
    
    open var externalPredicate: NSPredicate?
    private var isObservingPredicate = false
    
    private func setupPredicateObservation() {
        guard !isObservingPredicate else { return }
        fetchedResultsController.fetchRequest.addObserver(self, forKeyPath: "predicate", options: .new, context: nil)
        isObservingPredicate = true
    }
    
    private func teardownPredicateObservation() {
        guard isObservingPredicate else { return }
        fetchedResultsController.fetchRequest.removeObserver(self, forKeyPath: "predicate")
        isObservingPredicate = false
    }
    
    open override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "predicate", let fetchRequest = object as? NSFetchRequest<ContentType> {
            let newPredicate = change?[.newKey] as? NSPredicate
            if !(newPredicate is ProxyPredicate) {
                self.externalPredicate = newPredicate
                let proxyPredicate = ProxyPredicate(predicate: self.predicate, externalPredicate: self.externalPredicate)
                fetchRequest.predicate = proxyPredicate
            }
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }
    
    deinit {
        teardownPredicateObservation()
    }
    
    open var fetchedResultsController: NSFetchedResultsController<ContentType> {
        willSet {
            teardownPredicateObservation()
            fetchedResultsController.fetchRequest.predicate = self.externalPredicate
            self.externalPredicate = nil
        }
        didSet {
            if fetchedResultsController.delegate == nil {
                fetchedResultsController.delegate = self
            }
            
            self.externalPredicate = fetchedResultsController.fetchRequest.predicate
            let proxyPredicate = ProxyPredicate(predicate: self.predicate, externalPredicate: self.externalPredicate)
            fetchedResultsController.fetchRequest.predicate = proxyPredicate
            
            setupPredicateObservation()
            reload()
        }
    }
    private var _itemCount: Int = 0
    open override var itemCount: Int {
        get {
            performFetchIfNeeded()
            guard let sections = fetchedResultsController.sections else {
                return 0
            }
            let limit = liveFetchLimit > 0 ? liveFetchLimit : Int.max
            return sections.reduce(0) { partialResult, sectionInfo in
                partialResult + min(sectionInfo.numberOfObjects, limit)
            }
        }
        set {
            _backingItemCount = newValue
        }
    }
    private var _backingItemCount: Int = 0
    
    open override var contentView: ViewType? {
        didSet {
            performFetchIfNeeded()
        }
    }

    public init(fetchedResultsController: NSFetchedResultsController<ContentType>) {
        self.fetchedResultsController = fetchedResultsController
        super.init()
        if fetchedResultsController.delegate == nil {
            fetchedResultsController.delegate = self
        }
        
        self.externalPredicate = fetchedResultsController.fetchRequest.predicate
        let proxyPredicate = ProxyPredicate(predicate: self.predicate, externalPredicate: self.externalPredicate)
        fetchedResultsController.fetchRequest.predicate = proxyPredicate
        
        setupPredicateObservation()
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
        let proxyPredicate = ProxyPredicate(predicate: predicate, externalPredicate: self.externalPredicate)
        fetchedResultsController.fetchRequest.predicate = proxyPredicate
        try? fetchedResultsController.performFetch()
        refreshItemCount()
    }

    public func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        if (contentView?.window) != nil {
            (contentView as? CellContentTransactionUpdateable)?.beginUpdates()
        }
    }

    public func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        refreshItemCount()
        if (contentView?.window) != nil {
            (contentView as? CellContentTransactionUpdateable)?.endUpdates()
        } else {
            (contentView as? UITableView)?.reloadData()
            (contentView as? UICollectionView)?.reloadData()
        }
    }

    public func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        guard contentView?.window != nil else { return }
        
        let changeType: CellContentChange.ChangeType
        switch type {
        case .insert: changeType = .insert
        case .delete: changeType = .delete
        case .move: changeType = .move
        case .update: changeType = .update
        @unknown default: changeType = .update
        }
        
        var change: CellContentChange? = nil
        if type == .update && indexPath != newIndexPath && indexPath != nil && newIndexPath != nil {
            change = CellContentChange(type: .move, currentIndexPath: indexPath, destinationIndexPath: newIndexPath)
        } else {
            change = CellContentChange(type: changeType, currentIndexPath: indexPath, destinationIndexPath: newIndexPath)
        }
        
        guard let actualChange = change else { return }
        actualChange.rowAnimation = self.rowAnimation
        
        var finalChange: CellContentChange? = actualChange
        
        if self.liveFetchLimit > 0 {
            // Reflects _previous_ section counts.
            var currentSectionCount = -1
            var destinationSectionCount = -1
            
            var currentSection: NSFetchedResultsSectionInfo? = nil
            if let ip = indexPath, ip.section < self.fetchedResultsController.sections?.count ?? 0 {
                currentSection = self.fetchedResultsController.sections?[ip.section]
            }
            
            if let ip = indexPath {
                let globalIndexPath = indexPathTranslator?.dataSource(self, globalIndexPathForLocalIndexPath: ip) ?? ip
                if let tableView = contentView as? UITableView {
                    currentSectionCount = tableView.numberOfRows(inSection: globalIndexPath.section)
                } else if let collectionView = contentView as? UICollectionView {
                    currentSectionCount = collectionView.numberOfItems(inSection: globalIndexPath.section)
                }
            }
            
            if let newIP = newIndexPath {
                let globalIndexPath = indexPathTranslator?.dataSource(self, globalIndexPathForLocalIndexPath: newIP) ?? newIP
                let numberOfSections: Int
                if let tableView = contentView as? UITableView {
                    numberOfSections = tableView.numberOfSections
                } else if let collectionView = contentView as? UICollectionView {
                    numberOfSections = collectionView.numberOfSections
                } else {
                    numberOfSections = 0
                }
                
                if globalIndexPath.section < numberOfSections {
                    if let tableView = contentView as? UITableView {
                        destinationSectionCount = tableView.numberOfRows(inSection: globalIndexPath.section)
                    } else if let collectionView = contentView as? UICollectionView {
                        destinationSectionCount = collectionView.numberOfItems(inSection: globalIndexPath.section)
                    }
                } else {
                    destinationSectionCount = 0
                }
            }
            
            switch actualChange.type {
            case .insert:
                if let newIP = newIndexPath, newIP.item >= self.liveFetchLimit {
                    return
                }
            case .delete:
                if let ip = indexPath, ip.item >= self.liveFetchLimit {
                    return
                }
                if currentSectionCount >= self.liveFetchLimit, let ip = indexPath {
                    let insertedIndexPath = IndexPath(item: self.liveFetchLimit - 1, section: ip.section)
                    if isValidIndexPath(insertedIndexPath) {
                        let balancingChange = CellContentChange(type: .insert, currentIndexPath: nil, destinationIndexPath: insertedIndexPath)
                        balancingChange.rowAnimation = self.rowAnimation
                        self.addChange(balancingChange)
                    }
                }
            case .update:
                if let ip = indexPath, ip.item >= self.liveFetchLimit {
                    return
                }
            case .move:
                guard let ip = indexPath, let newIP = newIndexPath else { break }
                if ip.item >= self.liveFetchLimit && newIP.item >= self.liveFetchLimit {
                    return
                } else if ip.item >= self.liveFetchLimit && newIP.item < self.liveFetchLimit {
                    finalChange = CellContentChange(type: .insert, currentIndexPath: nil, destinationIndexPath: newIP)
                    finalChange?.rowAnimation = self.rowAnimation
                    if destinationSectionCount >= self.liveFetchLimit {
                        let deletedIndexPath = IndexPath(item: self.liveFetchLimit - 1, section: newIP.section)
                        let balancingChange = CellContentChange(type: .delete, currentIndexPath: deletedIndexPath, destinationIndexPath: nil)
                        balancingChange.rowAnimation = self.rowAnimation
                        self.addChange(balancingChange)
                    }
                } else if ip.item < self.liveFetchLimit && newIP.item >= self.liveFetchLimit {
                    finalChange = CellContentChange(type: .delete, currentIndexPath: ip, destinationIndexPath: nil)
                    finalChange?.rowAnimation = self.rowAnimation
                    if currentSectionCount >= self.liveFetchLimit, (currentSection?.numberOfObjects ?? 0) > self.liveFetchLimit {
                        let insertedIndexPath = IndexPath(item: self.liveFetchLimit - 1, section: ip.section)
                        let balancingChange = CellContentChange(type: .insert, currentIndexPath: nil, destinationIndexPath: insertedIndexPath)
                        balancingChange.rowAnimation = self.rowAnimation
                        self.addChange(balancingChange)
                    }
                } else if ip.section != newIP.section {
                    if currentSectionCount >= self.liveFetchLimit, (currentSection?.numberOfObjects ?? 0) > self.liveFetchLimit {
                        let insertedIndexPath = IndexPath(item: self.liveFetchLimit - 1, section: ip.section)
                        let balancingChange = CellContentChange(type: .insert, currentIndexPath: nil, destinationIndexPath: insertedIndexPath)
                        balancingChange.rowAnimation = self.rowAnimation
                        self.addChange(balancingChange)
                    }
                    if destinationSectionCount >= self.liveFetchLimit {
                        let deletedIndexPath = IndexPath(item: self.liveFetchLimit - 1, section: newIP.section)
                        let balancingChange = CellContentChange(type: .delete, currentIndexPath: deletedIndexPath, destinationIndexPath: nil)
                        balancingChange.rowAnimation = self.rowAnimation
                        self.addChange(balancingChange)
                    }
                }
            }
        }
        
        if let changeToDispatch = finalChange {
            addChange(changeToDispatch)
        }
    }

    public func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange sectionInfo: NSFetchedResultsSectionInfo, atSectionIndex sectionIndex: Int, for type: NSFetchedResultsChangeType) {
        guard contentView?.window != nil else { return }
        
        let changeType: CellContentChange.ChangeType
        switch type {
        case .insert: changeType = .insert
        case .delete: changeType = .delete
        case .move: changeType = .move
        case .update: changeType = .update
        @unknown default: changeType = .update
        }
        let change = CellContentChange(type: changeType, sectionIndex: sectionIndex)
        change.rowAnimation = self.rowAnimation
        addChange(change)
    }
}

open class FetchedResultsCollectionViewDataSource<ContentType: NSManagedObject>: FetchedResultsDataSource<ContentType, UICollectionViewCell, UICollectionView, UICollectionViewDataSource> {}
open class FetchedResultsTableViewDataSource<ContentType: NSManagedObject>: FetchedResultsDataSource<ContentType, UITableViewCell, UITableView, UITableViewDataSource> {}
open class FetchedResultsCollectionViewPrefetchingDataSource<ContentType: NSManagedObject, PrefetchContentType>: FetchedResultsCollectionViewDataSource<ContentType>, CellContentPrefetchingDataSource, UICollectionViewDataSourcePrefetching {
    public var prefetchItemCache = NSCache<AnyObject, AnyObject>()
    public var prefetchHandler: ((ContentType, IndexPath) async throws -> PrefetchContentType?)?
    public var prefetchCompletionHandler: ((UICollectionViewCell, PrefetchContentType?, IndexPath, Error?) -> Void)?
    
    private var prefetchTasks: [IndexPath: Task<Void, Never>] = [:]

    public override func configureCell(_ cell: UICollectionViewCell, at indexPath: IndexPath) {
        super.configureCell(cell, at: indexPath)
        
        prefetchTasks[indexPath]?.cancel()
        
        let item = self.item(at: indexPath)
        if let cached = prefetchItemCache.object(forKey: item as AnyObject) as? PrefetchContentType {
            self.prefetchCompletionHandler?(cell, cached, indexPath, nil)
            return
        }
        
        guard let prefetchHandler else { return }
        
        prefetchTasks[indexPath] = Task { @MainActor [weak self, weak cell] in
            defer { self?.prefetchTasks.removeValue(forKey: indexPath) }
            do {
                guard let content = try await prefetchHandler(item, indexPath) else { return }
                guard !Task.isCancelled else { return }
                
                self?.prefetchItemCache.setObject(content as AnyObject, forKey: item as AnyObject)
                
                guard let self, let cell else { return }
                if let collectionView = self.contentView,
                   let cellIndexPath = collectionView.indexPath(for: cell) {
                    let localIndexPath = self.localIndexPath(for: cellIndexPath) ?? cellIndexPath
                    if self.isValidIndexPath(localIndexPath) {
                        let currentItem = self.item(at: localIndexPath)
                        if (currentItem as AnyObject) === (item as AnyObject) || localIndexPath == indexPath {
                            self.prefetchCompletionHandler?(cell, content, localIndexPath, nil)
                        }
                    }
                } else {
                    self.prefetchCompletionHandler?(cell, content, indexPath, nil)
                }
            } catch {
                guard !Task.isCancelled else { return }
                guard let self, let cell else { return }
                self.prefetchCompletionHandler?(cell, nil, indexPath, error)
            }
        }
    }

    public func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        guard let prefetchHandler else { return }
        for indexPath in indexPaths {
            guard isValidIndexPath(indexPath) else { continue }
            let item = self.item(at: indexPath)
            if prefetchItemCache.object(forKey: item as AnyObject) != nil {
                continue
            }
            guard prefetchTasks[indexPath] == nil else { continue }
            
            prefetchTasks[indexPath] = Task { [weak self] in
                defer { self?.prefetchTasks.removeValue(forKey: indexPath) }
                guard let content = try? await prefetchHandler(item, indexPath) else { return }
                guard !Task.isCancelled else { return }
                self?.prefetchItemCache.setObject(content as AnyObject, forKey: item as AnyObject)
            }
        }
    }
    public func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            prefetchTasks[indexPath]?.cancel()
            prefetchTasks.removeValue(forKey: indexPath)
        }
    }
}

open class FetchedResultsTableViewPrefetchingDataSource<ContentType: NSManagedObject, PrefetchContentType>: FetchedResultsTableViewDataSource<ContentType>, CellContentPrefetchingDataSource, UITableViewDataSourcePrefetching {
    public var prefetchItemCache = NSCache<AnyObject, AnyObject>()
    public var prefetchHandler: ((ContentType, IndexPath) async throws -> PrefetchContentType?)?
    public var prefetchCompletionHandler: ((UITableViewCell, PrefetchContentType?, IndexPath, Error?) -> Void)?
    
    private var prefetchTasks: [IndexPath: Task<Void, Never>] = [:]

    public override func configureCell(_ cell: UITableViewCell, at indexPath: IndexPath) {
        super.configureCell(cell, at: indexPath)
        
        prefetchTasks[indexPath]?.cancel()
        
        let item = self.item(at: indexPath)
        if let cached = prefetchItemCache.object(forKey: item as AnyObject) as? PrefetchContentType {
            self.prefetchCompletionHandler?(cell, cached, indexPath, nil)
            return
        }
        
        guard let prefetchHandler else { return }
        
        prefetchTasks[indexPath] = Task { @MainActor [weak self, weak cell] in
            defer { self?.prefetchTasks.removeValue(forKey: indexPath) }
            do {
                guard let content = try await prefetchHandler(item, indexPath) else { return }
                guard !Task.isCancelled else { return }
                
                self?.prefetchItemCache.setObject(content as AnyObject, forKey: item as AnyObject)
                
                guard let self, let cell else { return }
                if let tableView = self.contentView,
                   let cellIndexPath = tableView.indexPath(for: cell) {
                    let localIndexPath = self.localIndexPath(for: cellIndexPath) ?? cellIndexPath
                    if self.isValidIndexPath(localIndexPath) {
                        let currentItem = self.item(at: localIndexPath)
                        if (currentItem as AnyObject) === (item as AnyObject) || localIndexPath == indexPath {
                            self.prefetchCompletionHandler?(cell, content, localIndexPath, nil)
                        }
                    }
                } else {
                    self.prefetchCompletionHandler?(cell, content, indexPath, nil)
                }
            } catch {
                guard !Task.isCancelled else { return }
                guard let self, let cell else { return }
                self.prefetchCompletionHandler?(cell, nil, indexPath, error)
            }
        }
    }

    public func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {
        guard let prefetchHandler else { return }
        for indexPath in indexPaths {
            guard isValidIndexPath(indexPath) else { continue }
            let item = self.item(at: indexPath)
            if prefetchItemCache.object(forKey: item as AnyObject) != nil {
                continue
            }
            guard prefetchTasks[indexPath] == nil else { continue }
            
            prefetchTasks[indexPath] = Task { [weak self] in
                defer { self?.prefetchTasks.removeValue(forKey: indexPath) }
                guard let content = try? await prefetchHandler(item, indexPath) else { return }
                guard !Task.isCancelled else { return }
                self?.prefetchItemCache.setObject(content as AnyObject, forKey: item as AnyObject)
            }
        }
    }
    public func tableView(_ tableView: UITableView, cancelPrefetchingForRowsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            prefetchTasks[indexPath]?.cancel()
            prefetchTasks.removeValue(forKey: indexPath)
        }
    }
}
