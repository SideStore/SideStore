//
//  RSTDynamicDataSource.swift
//  AltStoreCore
//
//  Created by Magesh K on 6/17/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import UIKit
import CoreData
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
