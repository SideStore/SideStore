//
//  TaskChainSerializer.swift
//  AltStore
//
//  Created by Magesh K on 7/2/26.
//

import Foundation

/*
 A serializer that queues tasks sequentially by chaining Task references.
 
 **Pros:**
 - Deadlock-free: Execution is managed inside a closure block, avoiding manual lock/unlock pairs. Even if the closure throws an error, the next task automatically runs.
 - Task cancellation support: Naturally propagates Swift Concurrency cancellations down the chain.
 - Simple API: Clean wrapper pattern (`try await serialize { ... }`). 
 */
actor TaskChainSerializer {
    static let shared = TaskChainSerializer()
    private var previousTask: Task<Void, Never>?
    
    func serialize<T>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        let localPreviousTask = previousTask
        let newTask = Task {
            // await/block until prev task was cancelled or completed
            _ = await localPreviousTask?.result
            // check once to see if caller task was already cancelled 
            // to not waste time in dispatching
            try Task.checkCancellation()
            // do the actual operation
            return try await operation()
        }
        // preserve the task with a wrapper task 
        // so that any cancellation errors are ignored when we wait
        // NOTE: the result we don't care here coz newTask.value below 
        //       is the one to return result if task completed without cancellation
        previousTask = Task { _ = await newTask.result }

        return try await withTaskCancellationHandler {
            try await newTask.value     // task result when completed are returned here
        } onCancel: {
            newTask.cancel()
        }
    }
}
