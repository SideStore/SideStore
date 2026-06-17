//
//  Operations.swift
//  AltStoreCore
//
//  Created by Magesh K on 6/17/26.
//

import Foundation

@objc(RSTOperation)
open class RSTOperation: Operation {
    private var _isExecuting = false
    private var _isFinished = false
    
    @objc open var isImmediate = false {
        didSet {
            guard isImmediate != oldValue else { return }
            if isImmediate {
                self.qualityOfService = .userInitiated
                self.queuePriority = .high
            } else {
                self.qualityOfService = .default
                self.queuePriority = .normal
            }
        }
    }
    
    open override var isExecuting: Bool {
        if !isAsynchronous {
            return super.isExecuting
        }
        return _isExecuting
    }
    
    open override var isFinished: Bool {
        if !isAsynchronous {
            return super.isFinished
        }
        return _isFinished
    }
    
    private var kvoContext = 0
    
    open override func start() {
        if !isAsynchronous {
            self.addObserver(self, forKeyPath: "isFinished", options: .new, context: &kvoContext)
            super.start()
            return
        }
        
        if isFinished {
            return
        }
        
        if isCancelled {
            finish()
        } else {
            willChangeValue(forKey: "isExecuting")
            _isExecuting = true
            didChangeValue(forKey: "isExecuting")
            
            main()
        }
    }
    
    @objc open func finish() {
        guard isAsynchronous else { return }
        
        willChangeValue(forKey: "isFinished")
        willChangeValue(forKey: "isExecuting")
        
        _isExecuting = false
        _isFinished = true
        
        didChangeValue(forKey: "isExecuting")
        didChangeValue(forKey: "isFinished")
    }
    
    open override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if context == &kvoContext {
            if let newValue = change?[.newKey] as? Bool, newValue {
                finish()
                self.removeObserver(self, forKeyPath: "isFinished", context: &kvoContext)
            }
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }
}

@objc(RSTOperationQueue)
open class RSTOperationQueue: OperationQueue {
    private let operationsMapTable = NSMapTable<AnyObject, Operation>.strongToWeakObjects()
    
    open override func addOperation(_ op: Operation) {
        super.addOperation(op)
        
        if let rstOp = op as? RSTOperation, rstOp.isImmediate {
            let completionBlock = op.completionBlock
            op.completionBlock = nil
            
            op.waitUntilFinished()
            
            completionBlock?()
        }
    }
    
    @objc(addOperation:forKey:)
    open func addOperation(_ op: Operation, forKey key: AnyObject) {
        let previousOperation = operation(forKey: key)
        previousOperation?.cancel()
        
        operationsMapTable.setObject(op, forKey: key)
        addOperation(op)
    }
    
    @objc(operationForKey:)
    open func operation(forKey key: AnyObject) -> Operation? {
        return operationsMapTable.object(forKey: key)
    }
    
    @objc open subscript(key: Any) -> Operation? {
        return operation(forKey: key as AnyObject)
    }
}

@objc(RSTBlockOperation)
open class RSTBlockOperation: RSTOperation {
    @objc public let executionBlock: (RSTBlockOperation) -> Void
    @objc open var cancellationBlock: (() -> Void)?
    
    @objc(initWithExecutionBlock:)
    public required init(executionBlock: @escaping (RSTBlockOperation) -> Void) {
        self.executionBlock = executionBlock
        super.init()
    }
    
    @objc(blockOperationWithExecutionBlock:)
    public class func blockOperation(withExecutionBlock executionBlock: @escaping (RSTBlockOperation) -> Void) -> Self {
        return self.init(executionBlock: executionBlock)
    }
    
    open override func main() {
        executionBlock(self)
    }
    
    open override func cancel() {
        super.cancel()
        cancellationBlock?()
    }
}

@objc(RSTAsyncBlockOperation)
open class RSTAsyncBlockOperation: RSTBlockOperation {
    open override var isAsynchronous: Bool {
        return true
    }
}

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
