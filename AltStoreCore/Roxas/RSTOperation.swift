//
//  RSTOperation.swift
//  AltStoreCore
//
//  Created by Magesh K on 6/17/26.
//  Copyright © 2026 SideStore. All rights reserved.
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
