//
//  DynamicDataSource.swift
//  AltStore
//
//  Created by Magesh K on 8/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

@preconcurrency import UIKit
import CoreData

open class DynamicDataSource<ContentType, CellType: UIView & CellContentCell, ViewType: UIScrollView, DataSourceType>: CellContentDataSource<ContentType, CellType, ViewType, DataSourceType> {
    open var numberOfSectionsHandler: (() -> Int) = { 0 }
    open var numberOfItemsHandler: ((Int) -> Int) = { _ in 0 }
    open var dynamicCellConfigurationHandler: ((CellType, IndexPath) -> Void) = { _, _ in }
    
    open override var isDynamic: Bool { true }

    public override func numberOfSections(in contentView: ViewType) -> Int { numberOfSectionsHandler() }
    public override func contentView(_ contentView: ViewType, numberOfItemsInSection section: Int) -> Int { numberOfItemsHandler(section) }
    
    public override func item(at indexPath: IndexPath) -> ContentType {
        fatalError("item(at:) should not be called on DynamicDataSource")
    }

    public override func configureCell(_ cell: CellType, at indexPath: IndexPath) {
        dynamicCellConfigurationHandler(cell, indexPath)
    }
}

open class DynamicCollectionViewDataSource<ContentType>: DynamicDataSource<ContentType, UICollectionViewCell, UICollectionView, UICollectionViewDataSource> {}
open class DynamicTableViewDataSource<ContentType>: DynamicDataSource<ContentType, UITableViewCell, UITableView, UITableViewDataSource> {}

open class DynamicCollectionViewPrefetchingDataSource<ContentType, PrefetchContentType>: DynamicCollectionViewDataSource<ContentType>, CellContentPrefetchingDataSource, UICollectionViewDataSourcePrefetching {
    public var prefetchItemCache = NSCache<AnyObject, AnyObject>()
    public var prefetchHandler: ((ContentType, IndexPath) async throws -> PrefetchContentType?)?
    public var prefetchCompletionHandler: ((UICollectionViewCell, PrefetchContentType?, IndexPath, Error?) -> Void)?

    public override func configureCell(_ cell: UICollectionViewCell, at indexPath: IndexPath) {
        super.configureCell(cell, at: indexPath)
    }

    public func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {}
    public func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {}
}

open class DynamicTableViewPrefetchingDataSource<ContentType, PrefetchContentType>: DynamicTableViewDataSource<ContentType>, CellContentPrefetchingDataSource, UITableViewDataSourcePrefetching {
    public var prefetchItemCache = NSCache<AnyObject, AnyObject>()
    public var prefetchHandler: ((ContentType, IndexPath) async throws -> PrefetchContentType?)?
    public var prefetchCompletionHandler: ((UITableViewCell, PrefetchContentType?, IndexPath, Error?) -> Void)?

    public override func configureCell(_ cell: UITableViewCell, at indexPath: IndexPath) {
        super.configureCell(cell, at: indexPath)
    }

    public func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {}
    public func tableView(_ tableView: UITableView, cancelPrefetchingForRowsAt indexPaths: [IndexPath]) {}
}
