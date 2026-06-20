//
//  RSTArrayDataSource.swift
//  AltStoreCore
//
//  Created by Magesh K on 6/17/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import UIKit
import CoreData
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
