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
open class RSTArrayTableViewPrefetchingDataSource<ContentType, PrefetchContentType>: RSTArrayTableViewDataSource<ContentType>, RSTCellContentPrefetchingDataSource, UITableViewDataSourcePrefetching {
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
