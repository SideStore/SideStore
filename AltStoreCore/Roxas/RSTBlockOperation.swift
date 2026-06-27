//
//  RSTBlockOperation.swift
//  AltStoreCore
//
//  Created by Magesh K on 6/17/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
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
