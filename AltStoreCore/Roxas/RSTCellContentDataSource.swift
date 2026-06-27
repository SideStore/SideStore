//
//  RSTCellContentDataSource.swift
//  AltStoreCore
//
//  Created by Magesh K on 6/17/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import UIKit
import CoreData

public let RSTCellContentGenericCellIdentifier = "Cell"

@objc(RSTCellContentIndexPathTranslating)
public protocol RSTCellContentIndexPathTranslating: AnyObject {
    @objc func dataSource(_ dataSource: AnyObject, globalIndexPathForLocalIndexPath localIndexPath: IndexPath) -> IndexPath?
    @objc func dataSource(_ dataSource: AnyObject, localIndexPathForGlobalIndexPath globalIndexPath: IndexPath) -> IndexPath?
}

protocol RSTAnyCellContentDataSource: AnyObject {
    var anyItemCount: Int { get }
    func setAnyContentView(_ contentView: UIScrollView?)
    func anyNumberOfSections() -> Int
    func anyNumberOfItems(in section: Int) -> Int
    func anyItem(at indexPath: IndexPath) -> Any
    func anyCellIdentifier(at indexPath: IndexPath) -> String
    func configureAnyCell(_ cell: UIView, at indexPath: IndexPath)
    var anyIndexPathTranslator: RSTCellContentIndexPathTranslating? { get set }
    var anyIsDynamic: Bool { get }
}

open class RSTCellContentDataSource<ContentType, CellType: UIView & RSTCellContentCell, ViewType: UIScrollView, DataSourceType>: NSObject, UITableViewDataSource, UICollectionViewDataSource {
    open weak var contentView: ViewType?
    open weak var proxy: AnyObject?
    open var cellIdentifierHandler: ((IndexPath) -> String) = { _ in RSTCellContentGenericCellIdentifier }
    open var cellConfigurationHandler: ((CellType, ContentType, IndexPath) -> Void) = { _, _, _ in }
    private var _predicate: NSPredicate?
    open var predicate: NSPredicate? {
        get { return _predicate }
        set { setPredicate(newValue, refreshContent: true) }
    }
    open weak var indexPathTranslator: RSTCellContentIndexPathTranslating?
    open var isDynamic: Bool { false }
    
    public func localIndexPath(for globalIndexPath: IndexPath) -> IndexPath? {
        if let translator = indexPathTranslator {
            return translator.dataSource(self, localIndexPathForGlobalIndexPath: globalIndexPath)
        }
        return globalIndexPath
    }

    public func globalIndexPath(for localIndexPath: IndexPath) -> IndexPath? {
        if let translator = indexPathTranslator {
            return translator.dataSource(self, globalIndexPathForLocalIndexPath: localIndexPath)
        }
        return localIndexPath
    }

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
    open var itemCount: Int = 0

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
        _predicate = predicate
        filterContent(with: predicate)
        if refreshContent { (contentView as? UICollectionView)?.reloadData(); (contentView as? UITableView)?.reloadData() }
    }

    open func isValidIndexPath(_ indexPath: IndexPath) -> Bool {
        guard let contentView else { return false }
        if indexPath.section >= numberOfSections(in: contentView) {
            return false
        }
        if indexPath.item >= self.contentView(contentView, numberOfItemsInSection: indexPath.section) {
            return false
        }
        return true
    }

    open func addChange(_ change: RSTCellContentChange) {
        let transformedChange: RSTCellContentChange
        
        if change.sectionIndex != RSTUnknownSectionIndex {
            let sectionIndexPath = IndexPath(item: 0, section: change.sectionIndex)
            let globalIndexPath = indexPathTranslator?.dataSource(self, globalIndexPathForLocalIndexPath: sectionIndexPath) ?? sectionIndexPath
            transformedChange = RSTCellContentChange(type: change.type, sectionIndex: globalIndexPath.section)
        } else {
            let currentIndexPath = change.currentIndexPath.flatMap { indexPathTranslator?.dataSource(self, globalIndexPathForLocalIndexPath: $0) ?? $0 }
            let destinationIndexPath = change.destinationIndexPath.flatMap { indexPathTranslator?.dataSource(self, globalIndexPathForLocalIndexPath: $0) ?? $0 }
            transformedChange = RSTCellContentChange(type: change.type, currentIndexPath: currentIndexPath, destinationIndexPath: destinationIndexPath)
        }
        transformedChange.rowAnimation = change.rowAnimation
        
        if change.sectionIndex == RSTUnknownSectionIndex {
            var indexPathForRemovingFromCache: IndexPath? = nil
            switch change.type {
            case .update:
                indexPathForRemovingFromCache = change.currentIndexPath
            case .move:
                indexPathForRemovingFromCache = change.destinationIndexPath
            default:
                break
            }
            if let cachePath = indexPathForRemovingFromCache {
                let item = self.item(at: cachePath)
                if let prefetchSelf = self as? any RSTCellContentPrefetchingDataSource {
                    prefetchSelf.prefetchItemCache.removeObject(forKey: item as AnyObject)
                }
            }
        }
        
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

    private func isDataSourceSelector(_ aSelector: Selector!) -> Bool {
        for protocolName in ["UITableViewDataSource", "UICollectionViewDataSource", "UITableViewDataSourcePrefetching", "UICollectionViewDataSourcePrefetching"] {
            if let proto = objc_getProtocol(protocolName) {
                var desc = protocol_getMethodDescription(proto, aSelector, false, true)
                if desc.name != nil {
                    return true
                }
                desc = protocol_getMethodDescription(proto, aSelector, true, true)
                if desc.name != nil {
                    return true
                }
            }
        }
        return false
    }
    
    open override func responds(to aSelector: Selector!) -> Bool {
        if super.responds(to: aSelector) {
            return true
        }
        if let proxy = self.proxy, isDataSourceSelector(aSelector) {
            return proxy.responds(to: aSelector)
        }
        return false
    }
    
    open override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if let proxy = self.proxy, isDataSourceSelector(aSelector) {
            return proxy
        }
        return super.forwardingTarget(for: aSelector)
    }
}

extension RSTCellContentDataSource: RSTAnyCellContentDataSource {
    var anyItemCount: Int { itemCount }

    func setAnyContentView(_ contentView: UIScrollView?) {
        self.contentView = contentView as? ViewType
    }

    func anyNumberOfSections() -> Int {
        guard let contentView else { return 0 }
        return numberOfSections(in: contentView)
    }

    func anyNumberOfItems(in section: Int) -> Int {
        guard let contentView else { return 0 }
        return self.contentView(contentView, numberOfItemsInSection: section)
    }

    func anyItem(at indexPath: IndexPath) -> Any {
        item(at: indexPath)
    }

    func anyCellIdentifier(at indexPath: IndexPath) -> String {
        cellIdentifierHandler(indexPath)
    }

    func configureAnyCell(_ cell: UIView, at indexPath: IndexPath) {
        guard let cell = cell as? CellType else { return }
        configureCell(cell, at: indexPath)
    }

    var anyIndexPathTranslator: RSTCellContentIndexPathTranslating? {
        get { self.indexPathTranslator }
        set { self.indexPathTranslator = newValue }
    }

    var anyIsDynamic: Bool { isDynamic }
}
