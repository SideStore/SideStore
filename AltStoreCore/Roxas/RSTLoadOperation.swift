//
//  RSTLoadOperation.swift
//  AltStoreCore
//
//  Created by Magesh K on 6/17/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
@objc(RSTLoadOperation)
open class RSTLoadOperation: RSTOperation {
    @objc open var cacheKey: AnyObject?
    @objc open var resultHandler: ((Any?, Error?) -> Void)?
    
    @objc open var resultsCache: NSCache<AnyObject, AnyObject>? {
        didSet {
            guard let cache = resultsCache, let key = cacheKey else { return }
            if cache.object(forKey: key) != nil {
                self.isImmediate = true
            }
        }
    }
    
    private var result: Any?
    private var error: Error?
    
    @objc(initWithCacheKey:)
    public init(cacheKey: AnyObject?) {
        self.cacheKey = cacheKey
        super.init()
    }
    
    open override func main() {
        var cachedResult: AnyObject?
        if let key = cacheKey {
            cachedResult = resultsCache?.object(forKey: key)
        }
        
        if let cachedResult = cachedResult {
            self.result = cachedResult
            if isAsynchronous {
                finish()
            }
            return
        }
        
        loadResult { [weak self] result, error in
            guard let self = self else { return }
            if self.isCancelled {
                return
            }
            
            self.result = result
            self.error = error
            
            if let result = result as AnyObject?, let key = self.cacheKey {
                self.resultsCache?.setObject(result, forKey: key)
            }
            
            if self.isAsynchronous {
                self.finish()
            }
        }
    }
    
    @objc open func loadResult(completion: @escaping (Any?, Error?) -> Void) {
        completion(nil, nil)
    }
    
    open override func finish() {
        super.finish()
        resultHandler?(result, error)
    }
}
