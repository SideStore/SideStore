//
//  ArrayDataSource.swift
//  AltStore
//
//  Created by Magesh K on 8/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

@preconcurrency import UIKit
import CoreData

open class ArrayDataSource<ContentType, CellType: UIView & CellContentCell, ViewType: UIScrollView, DataSourceType>: CellContentDataSource<ContentType, CellType, ViewType, DataSourceType> {
    private var isApplyingBatchChanges = false

    open var items: [ContentType] = [] {
        didSet {
            itemCount = items.count
            if !isApplyingBatchChanges {
                (contentView as? UICollectionView)?.reloadData()
                (contentView as? UITableView)?.reloadData()
            }
        }
    }
    public init(items: [ContentType]) {
        self.items = items
        super.init()
        self.itemCount = items.count
    }
    public func setItems(_ items: [ContentType], with changes: [CellContentChange]? = nil) {
        self.isApplyingBatchChanges = true
        self.items = items
        self.itemCount = items.count
        self.isApplyingBatchChanges = false
        
        if let changes = changes {
            if !changes.isEmpty, let contentView = self.contentView {
                (contentView as? CellContentTransactionUpdateable)?.beginUpdates()
                for change in changes {
                    self.addChange(change)
                }
                (contentView as? CellContentTransactionUpdateable)?.endUpdates()
            }
        } else {
            (contentView as? UICollectionView)?.reloadData()
            (contentView as? UITableView)?.reloadData()
        }
    }
    public override func item(at indexPath: IndexPath) -> ContentType { items[indexPath.item] }
    public override func numberOfSections(in contentView: ViewType) -> Int { 1 }
    public override func contentView(_ contentView: ViewType, numberOfItemsInSection section: Int) -> Int { items.count }
    public override func filterContent(with predicate: NSPredicate?) {}
}

open class ArrayCollectionViewDataSource<ContentType>: ArrayDataSource<ContentType, UICollectionViewCell, UICollectionView, UICollectionViewDataSource> {}
open class ArrayTableViewDataSource<ContentType>: ArrayDataSource<ContentType, UITableViewCell, UITableView, UITableViewDataSource> {}

open class ArrayCollectionViewPrefetchingDataSource<ContentType, PrefetchContentType>: ArrayCollectionViewDataSource<ContentType>, CellContentPrefetchingDataSource, UICollectionViewDataSourcePrefetching {
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

open class ArrayTableViewPrefetchingDataSource<ContentType, PrefetchContentType>: ArrayTableViewDataSource<ContentType>, CellContentPrefetchingDataSource, UITableViewDataSourcePrefetching {
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
