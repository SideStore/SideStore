//
//  LinkedHashMapTests.swift
//  SideStore
//
//  Created by Magesh K on 21/02/25.
//  Copyright © 2025 SideStore. All rights reserved.
//

import XCTest

// A helper class that signals when it is deallocated.
class LeakTester {
    let id: Int
    var onDeinit: (() -> Void)?
    init(id: Int, onDeinit: (() -> Void)? = nil) {
        self.id = id
        self.onDeinit = onDeinit
    }
    deinit {
        onDeinit?()
    }
}

final class LinkedHashMapTests: XCTestCase {
    
    // Test that insertion preserves order and that iteration returns items in insertion order.
    func testInsertionAndOrder() {
        let map = LinkedHashMap<String, Int>()
        map.put(key: "one", value: 1)
        map.put(key: "two", value: 2)
        map.put(key: "three", value: 3)
        
        XCTAssertEqual(map.count, 3)
        XCTAssertEqual(map.keys, ["one", "two", "three"], "Insertion order should be preserved")
        
        var iteratedKeys = [String]()
        for (key, _) in map {
            iteratedKeys.append(key)
        }
        XCTAssertEqual(iteratedKeys, ["one", "two", "three"], "Iterator should follow insertion order")
    }
    
    // Test that updating a key does not change its order.
    func testUpdateDoesNotChangeOrder() {
        let map = LinkedHashMap<String, Int>()
        map.put(key: "a", value: 1)
        map.put(key: "b", value: 2)
        map.put(key: "c", value: 3)
        // Update key "b"
        map.put(key: "b", value: 20)
        XCTAssertEqual(map.get(key: "b"), 20)
        
        XCTAssertEqual(map.keys, ["a", "b", "c"], "Order should not change on update")
    }
    
    // Test removal functionality and behavior when removing a non-existent key.
    func testRemoval() {
        let map = LinkedHashMap<Int, String>()
        map.put(key: 1, value: "one")
        map.put(key: 2, value: "two")
        map.put(key: 3, value: "three")
        
        let removed = map.remove(key: 2)
        XCTAssertEqual(removed, "two")
        XCTAssertEqual(map.count, 2)
        XCTAssertEqual(map.keys, [1, 3])
        
        // Removing a key that doesn't exist should return nil.
        let removedNil = map.remove(key: 4)
        XCTAssertNil(removedNil)
    }
    
    // Test clearing the map.
    func testClear() {
        let map = LinkedHashMap<String, Int>()
        map.put(key: "x", value: 100)
        map.put(key: "y", value: 200)
        XCTAssertEqual(map.count, 2)
        
        map.clear()
        XCTAssertEqual(map.count, 0)
        XCTAssertTrue(map.isEmpty)
        XCTAssertEqual(map.keys, [])
        XCTAssertEqual(map.values, [])
    }
    
    // Test subscript access for getting, updating, and removal.
    func testSubscript() {
        let map = LinkedHashMap<String, Int>()
        map["alpha"] = 10
        XCTAssertEqual(map["alpha"], 10)
        
        map["alpha"] = 20
        XCTAssertEqual(map["alpha"], 20)
        
        // Setting a key to nil should remove the mapping.
        map["alpha"] = nil
        XCTAssertNil(map["alpha"])
    }
    
    // Test containsKey and containsValue.
    func testContains() {
        let map = LinkedHashMap<String, Int>()
        map.put(key: "key1", value: 1)
        map.put(key: "key2", value: 2)
        
        XCTAssertTrue(map.containsKey("key1"))
        XCTAssertFalse(map.containsKey("key3"))
        
        XCTAssertTrue(map.containsValue(1))
        XCTAssertFalse(map.containsValue(99))
    }
    
    // Test initialization from a dictionary.
    func testInitializationFromDictionary() {
        // Note: Swift dictionaries preserve insertion order for literals.
        let dictionary: [String: Int] = ["a": 1, "b": 2, "c": 3]
        let map = LinkedHashMap(dictionary)
        XCTAssertEqual(map.count, 3)
        // Order may differ since Dictionary order is not strictly defined – here we verify membership.
        XCTAssertEqual(Set(map.keys), Set(["a", "b", "c"]))
    }
    
    // Revised test that iterates over the map and compares key-value pairs element by element.
    func testIteration() {
        let map = LinkedHashMap<Int, String>()
        let pairs = [(1, "one"), (2, "two"), (3, "three")]
        for (key, value) in pairs {
            map.put(key: key, value: value)
        }
        
        var iteratedPairs = [(Int, String)]()
        for (key, value) in map {
            iteratedPairs.append((key, value))
        }
        
        XCTAssertEqual(iteratedPairs.count, pairs.count, "Iterated count should match inserted count")
        for (iter, expected) in zip(iteratedPairs, pairs) {
            XCTAssertEqual(iter.0, expected.0, "Keys should match in order")
            XCTAssertEqual(iter.1, expected.1, "Values should match in order")
        }
    }
    
    // Test that the values stored in the map are deallocated when the map is deallocated.
    func testMemoryLeak() {
        weak var weakMap: LinkedHashMap<Int, LeakTester>?
        var deinitCalled = false
        
        do {
            let map = LinkedHashMap<Int, LeakTester>()
            let tester = LeakTester(id: 1) { deinitCalled = true }
            map.put(key: 1, value: tester)
            weakMap = map
            XCTAssertNotNil(map.get(key: 1))
        }
        // At this point the map (and its stored objects) should be deallocated.
        XCTAssertNil(weakMap, "LinkedHashMap should be deallocated when out of scope")
        XCTAssertTrue(deinitCalled, "LeakTester should be deallocated, indicating no memory leak")
    }
    
    // Test that removal from the map correctly frees stored objects.
    func testMemoryLeakOnRemoval() {
        var deinitCalledForTester1 = false
        var deinitCalledForTester2 = false
        
        let map = LinkedHashMap<Int, LeakTester>()
        autoreleasepool {
            let tester1 = LeakTester(id: 1) { deinitCalledForTester1 = true }
            let tester2 = LeakTester(id: 2) { deinitCalledForTester2 = true }
            map.put(key: 1, value: tester1)
            map.put(key: 2, value: tester2)
            
            XCTAssertNotNil(map.get(key: 1))
            XCTAssertNotNil(map.get(key: 2))
            
            // Remove tester1; it should be deallocated if no retain cycle exists.
            _ = map.remove(key: 1)
        }
        // tester1 should be deallocated immediately after removal.
        XCTAssertTrue(deinitCalledForTester1, "Tester1 should be deallocated after removal")
        // tester2 is still in the map.
        XCTAssertNotNil(map.get(key: 2))
        
        // Clear the map and tester2 should be deallocated.
        map.clear()
        XCTAssertTrue(deinitCalledForTester2, "Tester2 should be deallocated after clearing the map")
    }
    
    func testDefaultSubscriptExtension() {
            // Create an instance of LinkedHashMap with String keys and Bool values.
            let map = LinkedHashMap<String, Bool>()
            
            // Verify that accessing a non-existent key returns the default value (false).
            XCTAssertEqual(map["testKey", default: false], false)
            
            // Use the default subscript setter to assign 'true' for the key.
            map["testKey", default: false] = true
            XCTAssertEqual(map["testKey", default: false], true)
            
            // Simulate in-place toggle: read the value, toggle it, then write it back.
            var current = map["testKey", default: false]
            current.toggle() // now false
            map["testKey", default: false] = current
            XCTAssertEqual(map["testKey", default: false], false)
        }
}
