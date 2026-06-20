//
//  RSTCompositeDataSource.swift
//  AltStoreCore
//
//  Created by Magesh K on 6/17/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import UIKit
import CoreData
private protocol RSTAnyCompositeDataSource: AnyObject {
    func compositeCollectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell
    func compositeTableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell
}

open class RSTCompositeDataSource<ContentType, CellType: UIView & RSTCellContentCell, ViewType: UIScrollView, DataSourceType>: RSTCellContentDataSource<ContentType, CellType, ViewType, DataSourceType> {
    open var dataSources: [AnyObject]
    open var shouldFlattenSections = false {
        didSet { (contentView as? UICollectionView)?.reloadData(); (contentView as? UITableView)?.reloadData() }
    }
    public init(dataSources: [AnyObject]) {
        self.dataSources = dataSources
        super.init()
        for dataSource in dataSources {
            if let anyDataSource = dataSource as? RSTAnyCellContentDataSource {
                anyDataSource.anyIndexPathTranslator = self
            }
        }
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

extension RSTCompositeDataSource: RSTCellContentIndexPathTranslating {
    public func dataSource(_ dataSource: AnyObject, globalIndexPathForLocalIndexPath localIndexPath: IndexPath) -> IndexPath? {
        guard let anyDataSource = dataSource as? RSTAnyCellContentDataSource else { return nil }
        
        guard let dataSourceIndex = typedDataSources.firstIndex(where: { $0 === anyDataSource }) else {
            return nil
        }
        
        let globalIndexPath: IndexPath
        if shouldFlattenSections {
            var itemOffset = 0
            for i in 0..<dataSourceIndex {
                itemOffset += itemCount(for: typedDataSources[i])
            }
            globalIndexPath = IndexPath(item: localIndexPath.item + itemOffset, section: 0)
        } else {
            var sectionOffset = 0
            for i in 0..<dataSourceIndex {
                sectionOffset += sectionCount(for: typedDataSources[i])
            }
            globalIndexPath = IndexPath(item: localIndexPath.item, section: localIndexPath.section + sectionOffset)
        }
        
        if let parentTranslator = self.indexPathTranslator {
            return parentTranslator.dataSource(self, globalIndexPathForLocalIndexPath: globalIndexPath)
        }
        
        return globalIndexPath
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
