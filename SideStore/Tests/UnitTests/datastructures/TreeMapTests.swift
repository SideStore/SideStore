//
//  TreeMapTests.swift
//  SideStore
//
//  Created by Magesh K on 21/02/25.
//  Copyright © 2025 SideStore. All rights reserved.
//


import Foundation
import XCTest

class TreeMapTests: XCTestCase {
    
    func testInsertionAndRetrieval() {
        let map = TreeMap<Int, String>()
        XCTAssertNil(map[10])
        map[10] = "ten"
        XCTAssertEqual(map[10], "ten")
        
        map[5] = "five"
        map[15] = "fifteen"
        XCTAssertEqual(map.count, 3)
        XCTAssertEqual(map[5], "five")
        XCTAssertEqual(map[15], "fifteen")
    }
    
    func testUpdateValue() {
        let map = TreeMap<Int, String>()
        map[10] = "ten"
        let oldValue = map.insert(key: 10, value: "TEN")
        XCTAssertEqual(oldValue, "ten")
        XCTAssertEqual(map[10], "TEN")
        XCTAssertEqual(map.count, 1)
    }
    
    func testDeletion() {
        let map = TreeMap<Int, String>()
        // Setup: Inserting three nodes.
        map[20] = "twenty"
        map[10] = "ten"
        map[30] = "thirty"
        
        // Remove a leaf node.
        let removedLeaf = map.remove(key: 10)
        XCTAssertEqual(removedLeaf, "ten")
        XCTAssertNil(map[10])
        XCTAssertEqual(map.count, 2)
        
        // Setup additional nodes to create a one-child scenario.
        map[25] = "twenty-five"
        map[27] = "twenty-seven" // Right child for 25.
        // Remove a node with one child.
        let removedOneChild = map.remove(key: 25)
        XCTAssertEqual(removedOneChild, "twenty-five")
        XCTAssertNil(map[25])
        XCTAssertEqual(map.count, 3)
        
        // Setup for a node with two children.
        map[40] = "forty"
        map[35] = "thirty-five"
        map[45] = "forty-five"
        // Remove a node with two children.
        let removedTwoChildren = map.remove(key: 40)
        XCTAssertEqual(removedTwoChildren, "forty")
        XCTAssertNil(map[40])
        XCTAssertEqual(map.count, 5)
    }
    
    func testDeletionOfRoot() {
        let map = TreeMap<Int, String>()
        map[50] = "fifty"
        map[30] = "thirty"
        map[70] = "seventy"
        
        // Delete the root node.
        let removedRoot = map.remove(key: 50)
        XCTAssertEqual(removedRoot, "fifty")
        XCTAssertNil(map[50])
        // After deletion, remaining keys should be in sorted order.
        XCTAssertEqual(map.keys, [30, 70])
    }
    
    func testSortedIteration() {
        let map = TreeMap<Int, String>()
        let keys = [20, 10, 30, 5, 15, 25, 35]
        for key in keys {
            map[key] = "\(key)"
        }
        let sortedKeys = map.keys
        XCTAssertEqual(sortedKeys, keys.sorted())
        
        // Verify in-order traversal.
        var previous: Int? = nil
        for (key, value) in map {
            if let prev = previous {
                XCTAssertLessThanOrEqual(prev, key)
            }
            previous = key
            XCTAssertEqual(value, "\(key)")
        }
    }
    
    func testRemoveAll() {
        let map = TreeMap<Int, String>()
        for i in 0..<100 {
            map[i] = "\(i)"
        }
        XCTAssertEqual(map.count, 100)
        map.removeAll()
        XCTAssertEqual(map.count, 0)
        XCTAssertTrue(map.isEmpty)
    }
    
    func testBalancing() {
        let map = TreeMap<Int, Int>()
        // Insert elements in ascending order to challenge the balancing.
        for i in 1...1000 {
            map[i] = i
        }
        // Verify in-order traversal produces sorted order.
        var expected = 1
        for (key, value) in map {
            XCTAssertEqual(key, expected)
            XCTAssertEqual(value, expected)
            expected += 1
        }
        XCTAssertEqual(expected - 1, 1000)
        
        // Remove odd keys to force rebalancing.
        for i in stride(from: 1, through: 1000, by: 2) {
            _ = map.remove(key: i)
        }
        let expectedEvenKeys = (1...1000).filter { $0 % 2 == 0 }
        XCTAssertEqual(map.keys, expectedEvenKeys)
    }
    
    func testNonExistentDeletion() {
        let map = TreeMap<Int, String>()
        map[10] = "ten"
        let removed = map.remove(key: 20)
        XCTAssertNil(removed)
        XCTAssertEqual(map.count, 1)
    }
    
    func testDuplicateInsertion() {
        let map = TreeMap<String, String>()
        map["a"] = "first"
        XCTAssertEqual(map["a"], "first")
        let oldValue = map.insert(key: "a", value: "second")
        XCTAssertEqual(oldValue, "first")
        XCTAssertEqual(map["a"], "second")
        XCTAssertEqual(map.count, 1)
    }

    // MARK: - Deletion Regression Tests

    func testRemoveRootWithBlackSuccessorTerminates() {
        // Inserting 1...6 in ascending order leaves a root with two children whose
        // in-order successor is black. Removing that root used to hand the deletion
        // fix-up the wrong parent node, and the fix-up then looped forever.
        assertTerminates("remove the root of a 6 element map") {
            let map = TreeMap<Int, Int>()
            for i in 1...6 { map[i] = i }

            XCTAssertEqual(map.remove(key: 2), 2)
            XCTAssertNil(map[2])
            XCTAssertEqual(map.keys, [1, 3, 4, 5, 6])
            XCTAssertEqual(map.count, 5)
        }
    }

    func testEverySingleRemovalKeepsMapConsistent() {
        // Walks every (map size, removed key) pair for ascending inserts up to 40
        // elements, which covers all of the shapes the deletion fix-up has to handle.
        assertTerminates("remove each key of every map size", timeout: 60) {
            for size in 1...40 {
                for key in 1...size {
                    let map = TreeMap<Int, Int>()
                    for i in 1...size { map[i] = i * 10 }

                    let context = "size \(size), removed \(key)"
                    let expected = (1...size).filter { $0 != key }
                    XCTAssertEqual(map.remove(key: key), key * 10, context)
                    XCTAssertEqual(map.keys, expected, context)
                    XCTAssertEqual(map.values, expected.map { $0 * 10 }, context)
                    XCTAssertEqual(map.count, expected.count, context)
                }
            }
        }
    }

    func testRandomizedInsertAndRemoveMatchesDictionary() {
        // Interleaves inserts and removals and compares against a plain dictionary,
        // so any ordering, count or return value drift shows up.
        assertTerminates("randomized insert/remove", timeout: 60) {
            var generator = SeededGenerator(seed: 0x5EED)

            for round in 1...50 {
                let map = TreeMap<Int, Int>()
                var reference: [Int: Int] = [:]

                for _ in 0..<500 {
                    let key = Int.random(in: 0..<150, using: &generator)
                    if Bool.random(using: &generator) {
                        map[key] = key * 3
                        reference[key] = key * 3
                    } else {
                        XCTAssertEqual(map.remove(key: key), reference.removeValue(forKey: key), "round \(round)")
                    }
                }

                let expectedKeys = reference.keys.sorted()
                XCTAssertEqual(map.keys, expectedKeys, "round \(round)")
                XCTAssertEqual(map.values, expectedKeys.map { reference[$0]! }, "round \(round)")
                XCTAssertEqual(map.count, reference.count, "round \(round)")
            }
        }
    }

    // MARK: - Helpers

    /// Runs `work` on its own thread and reports a failure if it does not finish in time.
    /// A broken deletion fix-up spins forever rather than returning a wrong answer, so the
    /// test has to be able to give up on it instead of hanging the whole test run.
    private func assertTerminates(_ label: String,
                                  timeout: TimeInterval = 30,
                                  file: StaticString = #filePath,
                                  line: UInt = #line,
                                  work: @escaping @Sendable () -> Void) {
        let finished = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            work()
            finished.signal()
        }

        if finished.wait(timeout: .now() + timeout) == .timedOut {
            XCTFail("\(label) did not finish within \(Int(timeout))s, TreeMap is looping forever", file: file, line: line)
        }
    }
}

/// Seeded generator (splitmix64) so a failing randomized case is reproducible.
private struct SeededGenerator: RandomNumberGenerator {

    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
