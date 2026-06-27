//
//  RSTOperationQueue.swift
//  AltStoreCore
//
//  Created by Magesh K on 6/17/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
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
