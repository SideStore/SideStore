//
//  PaginationDataHolder.swift
//  AltStore
//
//  Created by Magesh K on 09/01/25.
//  Copyright © 2025 SideStore. All rights reserved.
//

import Foundation

public class PaginationDataHolder {
    
    public let itemsPerPage: UInt
    public private(set) var currentPageindex: UInt

    init(itemsPerPage: UInt, startPageIndex: UInt = 0) {
        self.itemsPerPage = itemsPerPage
        self.currentPageindex = startPageIndex
    }
    
    init(other: PaginationDataHolder) {
        self.itemsPerPage = other.itemsPerPage
        self.currentPageindex = other.currentPageindex
    }
    
    public enum PageLimitResult{
        case null
        case empty
        case current
    }
    
    private func updatePageIndexForDirection(_ direction: Direction, itemsCount: Int) -> Bool {

        var targetPageIndex = Int(currentPageindex)
        let availablePages = UInt(ceil(Double(itemsCount) / Double(itemsPerPage)))

        switch(direction){
        case .up:
            targetPageIndex -= 1
        case .down:
            targetPageIndex += 1
        }
        
        let isUpdateValid = (targetPageIndex >= 0 && targetPageIndex < availablePages)

        if isUpdateValid{
            self.currentPageindex = UInt(targetPageIndex)
        }
        
        return isUpdateValid
    }

    public func nextPage<T>(inItems: [T], whenUnavailable: PageLimitResult = .current) -> [T]? {
        return targetPage(for: .down, inItems: inItems, whenUnavailable: whenUnavailable)
    }

    public func prevPage<T>(inItems: [T], whenUnavailable: PageLimitResult = .current) -> [T]? {
        return targetPage(for: .up, inItems: inItems, whenUnavailable: whenUnavailable)
    }

    public func targetPage<T>(for direction: Direction, inItems: [T], whenUnavailable: PageLimitResult = .current) -> [T]? {
        if updatePageIndexForDirection(direction, itemsCount: inItems.count){
            return currentPage(inItems: inItems)
        }
        
        switch whenUnavailable {
            case .null:
                return nil                              // null was requested
            case .empty:
                return []                               // empty list was requested
            case .current:
                return currentPage(inItems: inItems)    // Stay on the current page and return the same items
        }
    }

    public func currentPage<T>(inItems items: [T]) -> [T] {
        let count = UInt(items.count)
        
        if(count == 0) { return items }
        
        // since we operate on any input items list at any time,
        // we set currentPageIndex as last availablePage if out of bounds
        let availablePages = UInt(ceil(Double(count) / Double(itemsPerPage)))
        
        self.currentPageindex = min(availablePages-1, currentPageindex)

        let startIndex = currentPageindex * itemsPerPage
        let estimatedEndIndex = startIndex + (itemsPerPage-1)
        let endIndex: UInt = min(count-1, estimatedEndIndex)
        let currentPageEntries = items[Int(startIndex) ... Int(endIndex)]
        return Array(currentPageEntries)
    }
}
