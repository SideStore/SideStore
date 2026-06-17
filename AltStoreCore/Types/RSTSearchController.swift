//
//  RSTSearchController.swift
//  AltStoreCore
//
//  Created by Magesh K on 6/17/26.
//

import UIKit

@objc(RSTSearchValue)
public final class RSTSearchValue: NSObject, NSCopying {
    @objc public let text: String
    @objc public let predicate: NSPredicate
    
    @objc(initWithText:predicate:)
    public init(text: String, predicate: NSPredicate) {
        self.text = text
        self.predicate = predicate
        super.init()
    }
    
    public func copy(with zone: NSZone? = nil) -> Any {
        return RSTSearchValue(text: self.text, predicate: self.predicate)
    }
    
    public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? RSTSearchValue else { return false }
        return self.text == other.text
    }
    
    public override var hash: Int {
        return self.text.hash
    }
}

@objc(RSTSearchController)
open class RSTSearchController: UISearchController, UISearchResultsUpdating {
    @objc open var searchableKeyPaths: Set<String> = ["self"]
    
    @objc open var searchHandler: ((RSTSearchValue, RSTSearchValue?) -> Operation?)?
    
    private let searchOperationQueue: RSTOperationQueue = {
        let queue = RSTOperationQueue()
        queue.qualityOfService = .userInitiated
        return queue
    }()
    
    private var previousSearchValue: RSTSearchValue?
    
    @objc(initWithSearchResultsController:)
    public override init(searchResultsController: UIViewController?) {
        super.init(searchResultsController: searchResultsController)
        self.searchResultsUpdater = self
        self.obscuresBackgroundDuringPresentation = false
    }
    
    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.searchResultsUpdater = self
        self.obscuresBackgroundDuringPresentation = false
    }
    
    public func updateSearchResults(for searchController: UISearchController) {
        let searchText = searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let searchPredicate = NSPredicate.forSearching(forText: searchText, inValuesForKeyPaths: self.searchableKeyPaths)
        
        let searchValue = RSTSearchValue(text: searchText, predicate: searchPredicate)
        
        if let previous = previousSearchValue, let previousOperation = self.searchOperationQueue.operation(forKey: previous) {
            previousOperation.cancel()
        }
        
        if let handler = self.searchHandler {
            if let searchOperation = handler(searchValue, previousSearchValue) {
                self.searchOperationQueue.addOperation(searchOperation, forKey: searchValue)
            }
        }
        
        self.previousSearchValue = searchValue
    }
}
