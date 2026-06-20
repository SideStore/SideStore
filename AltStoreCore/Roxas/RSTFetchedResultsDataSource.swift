//
//  RSTFetchedResultsDataSource.swift
//  AltStoreCore
//
//  Created by Magesh K on 6/17/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import UIKit
import CoreData
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
    private var _itemCount: Int = 0
    open override var itemCount: Int {
        get {
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

    public func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        if let window = contentView?.window, window != nil {
            (contentView as? RSTCellContentTransactionUpdateable)?.beginUpdates()
        }
    }

    public func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        refreshItemCount()
        if let window = contentView?.window, window != nil {
            (contentView as? RSTCellContentTransactionUpdateable)?.endUpdates()
        } else {
            (contentView as? UITableView)?.reloadData()
            (contentView as? UICollectionView)?.reloadData()
        }
    }

    public func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        guard contentView?.window != nil else { return }
        
        let changeType: RSTCellContentChange.ChangeType
        switch type {
        case .insert: changeType = .insert
        case .delete: changeType = .delete
        case .move: changeType = .move
        case .update: changeType = .update
        @unknown default: changeType = .update
        }
        
        var change: RSTCellContentChange? = nil
        if type == .update && indexPath != newIndexPath && indexPath != nil && newIndexPath != nil {
            change = RSTCellContentChange(type: .move, currentIndexPath: indexPath, destinationIndexPath: newIndexPath)
        } else {
            change = RSTCellContentChange(type: changeType, currentIndexPath: indexPath, destinationIndexPath: newIndexPath)
        }
        
        guard let actualChange = change else { return }
        actualChange.rowAnimation = self.rowAnimation
        
        var finalChange: RSTCellContentChange? = actualChange
        
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
                        let balancingChange = RSTCellContentChange(type: .insert, currentIndexPath: nil, destinationIndexPath: insertedIndexPath)
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
                    finalChange = RSTCellContentChange(type: .insert, currentIndexPath: nil, destinationIndexPath: newIP)
                    finalChange?.rowAnimation = self.rowAnimation
                    if destinationSectionCount >= self.liveFetchLimit {
                        let deletedIndexPath = IndexPath(item: self.liveFetchLimit - 1, section: newIP.section)
                        let balancingChange = RSTCellContentChange(type: .delete, currentIndexPath: deletedIndexPath, destinationIndexPath: nil)
                        balancingChange.rowAnimation = self.rowAnimation
                        self.addChange(balancingChange)
                    }
                } else if ip.item < self.liveFetchLimit && newIP.item >= self.liveFetchLimit {
                    finalChange = RSTCellContentChange(type: .delete, currentIndexPath: ip, destinationIndexPath: nil)
                    finalChange?.rowAnimation = self.rowAnimation
                    if currentSectionCount >= self.liveFetchLimit, (currentSection?.numberOfObjects ?? 0) > self.liveFetchLimit {
                        let insertedIndexPath = IndexPath(item: self.liveFetchLimit - 1, section: ip.section)
                        let balancingChange = RSTCellContentChange(type: .insert, currentIndexPath: nil, destinationIndexPath: insertedIndexPath)
                        balancingChange.rowAnimation = self.rowAnimation
                        self.addChange(balancingChange)
                    }
                } else if ip.section != newIP.section {
                    if currentSectionCount >= self.liveFetchLimit, (currentSection?.numberOfObjects ?? 0) > self.liveFetchLimit {
                        let insertedIndexPath = IndexPath(item: self.liveFetchLimit - 1, section: ip.section)
                        let balancingChange = RSTCellContentChange(type: .insert, currentIndexPath: nil, destinationIndexPath: insertedIndexPath)
                        balancingChange.rowAnimation = self.rowAnimation
                        self.addChange(balancingChange)
                    }
                    if destinationSectionCount >= self.liveFetchLimit {
                        let deletedIndexPath = IndexPath(item: self.liveFetchLimit - 1, section: newIP.section)
                        let balancingChange = RSTCellContentChange(type: .delete, currentIndexPath: deletedIndexPath, destinationIndexPath: nil)
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
        
        let changeType: RSTCellContentChange.ChangeType
        switch type {
        case .insert: changeType = .insert
        case .delete: changeType = .delete
        case .move: changeType = .move
        case .update: changeType = .update
        @unknown default: changeType = .update
        }
        let change = RSTCellContentChange(type: changeType, sectionIndex: sectionIndex)
        change.rowAnimation = self.rowAnimation
        addChange(change)
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
        
        prefetchOperations[indexPath]?.cancel()
        
        let item = self.item(at: indexPath)
        if let cached = prefetchItemCache.object(forKey: item as AnyObject) as? PrefetchContentType {
            self.prefetchCompletionHandler?(cell, cached, indexPath, nil)
            return
        }
        
        if let operation = prefetchHandler?(item, indexPath, { [weak self, weak cell] (content, error) in
            guard let self, let cell else { return }
            if let content {
                self.prefetchItemCache.setObject(content as AnyObject, forKey: item as AnyObject)
            }
            DispatchQueue.main.async {
                if let collectionView = self.contentView as? UICollectionView,
                   let cellIndexPath = collectionView.indexPath(for: cell) {
                    let localIndexPath = self.localIndexPath(for: cellIndexPath) ?? cellIndexPath
                    if self.isValidIndexPath(localIndexPath) {
                        let currentItem = self.item(at: localIndexPath)
                        if (currentItem as AnyObject) === (item as AnyObject) || localIndexPath == indexPath {
                            self.prefetchCompletionHandler?(cell, content, localIndexPath, error)
                        }
                    }
                } else {
                    self.prefetchCompletionHandler?(cell, content, indexPath, error)
                }
            }
        }) {
            prefetchOperations[indexPath] = operation
            prefetchOperationQueue.addOperation(operation)
        }
    }

    public func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            guard isValidIndexPath(indexPath) else { continue }
            let item = self.item(at: indexPath)
            if prefetchItemCache.object(forKey: item as AnyObject) != nil {
                continue
            }
            if let operation = prefetchHandler?(item, indexPath, { [weak self] (content, error) in
                guard let self else { return }
                if let content {
                    self.prefetchItemCache.setObject(content as AnyObject, forKey: item as AnyObject)
                }
            }) {
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
        
        prefetchOperations[indexPath]?.cancel()
        
        let item = self.item(at: indexPath)
        if let cached = prefetchItemCache.object(forKey: item as AnyObject) as? PrefetchContentType {
            self.prefetchCompletionHandler?(cell, cached, indexPath, nil)
            return
        }
        
        if let operation = prefetchHandler?(item, indexPath, { [weak self, weak cell] (content, error) in
            guard let self, let cell else { return }
            if let content {
                self.prefetchItemCache.setObject(content as AnyObject, forKey: item as AnyObject)
            }
            DispatchQueue.main.async {
                if let tableView = self.contentView as? UITableView,
                   let cellIndexPath = tableView.indexPath(for: cell) {
                    let localIndexPath = self.localIndexPath(for: cellIndexPath) ?? cellIndexPath
                    if self.isValidIndexPath(localIndexPath) {
                        let currentItem = self.item(at: localIndexPath)
                        if (currentItem as AnyObject) === (item as AnyObject) || localIndexPath == indexPath {
                            self.prefetchCompletionHandler?(cell, content, localIndexPath, error)
                        }
                    }
                } else {
                    self.prefetchCompletionHandler?(cell, content, indexPath, error)
                }
            }
        }) {
            prefetchOperations[indexPath] = operation
            prefetchOperationQueue.addOperation(operation)
        }
    }

    public func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            guard isValidIndexPath(indexPath) else { continue }
            let item = self.item(at: indexPath)
            if prefetchItemCache.object(forKey: item as AnyObject) != nil {
                continue
            }
            if let operation = prefetchHandler?(item, indexPath, { [weak self] (content, error) in
                guard let self else { return }
                if let content {
                    self.prefetchItemCache.setObject(content as AnyObject, forKey: item as AnyObject)
                }
            }) {
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
