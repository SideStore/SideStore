//
//  TaskMutexSerializer.swift
//  AltStore
//
//  Created by Magesh K on 7/2/26.
//

import Foundation

/*
 An asynchronous mutex lock utilizing CheckedContinuations to suspend queue tasks.
 
 **Pros:**
 - Standard lock/unlock pairs like traditional mutexes (e.g. NSLock).
 
 **Cons:**
 - Deadlock risk: Requires manual lock() and unlock() pairs. If a task throws an error or exits early without calling unlock(), it will permanently deadlock.
 - Cancellation leaks: Continuations do not clean up automatically on task cancellation, potentially leaking memory or causing hangs.
 */
actor TaskMutexSerializer {
    static let shared = TaskMutexSerializer()
    private var isLocked = false
    private var suspensionQueue: [CheckedContinuation<Void, Never>] = []
    
    func lock() async {
        if isLocked {
            await withCheckedContinuation { continuation in
                suspensionQueue.append(continuation)
            }
        } else {
            isLocked = true
        }
    }
    
    func unlock() {
        if !suspensionQueue.isEmpty {
            let next = suspensionQueue.removeFirst()
            next.resume()
        } else {
            isLocked = false
        }
    }
}
