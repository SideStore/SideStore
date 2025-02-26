//
//  LinkedHashMap.swift
//  SideStore
//
//  Created by Magesh K on 21/02/25.
//  Copyright © 2025 SideStore. All rights reserved.
//


/// A generic LinkedHashMap implementation in Swift.
/// It provides constant-time lookup along with predictable (insertion) ordering.
public final class LinkedHashMap<Key: Hashable, Value>: Sequence {
    
    /// Internal doubly-linked list node
    fileprivate final class Node {
        let key: Key
        var value: Value
        var next: Node?
        weak var prev: Node?  // weak to avoid strong reference cycle
        
        init(key: Key, value: Value) {
            self.key = key
            self.value = value
        }
    }
    
    // MARK: - Storage
    
    /// Dictionary for fast lookup from key to node.
    private var dict: [Key: Node] = [:]
    
    /// Head and tail of the doubly-linked list to maintain order.
    private var head: Node?
    private var tail: Node?
    
    // MARK: - Initialization
    
    /// Creates an empty LinkedHashMap.
    public init() { }
    
    /// Creates a LinkedHashMap from a standard dictionary.
    public init(_ dictionary: [Key: Value]) {
        for (key, value) in dictionary {
            _ = self.put(key: key, value: value)
        }
    }
    
    // MARK: - Public API
    
    /// The number of key-value pairs in the map.
    public var count: Int {
        return dict.count
    }
    
    /// A Boolean value indicating whether the map is empty.
    public var isEmpty: Bool {
        return dict.isEmpty
    }
    
    /// Returns the value for the given key, or `nil` if the key is not found.
    public func get(key: Key) -> Value? {
        return dict[key]?.value
    }
    
    /// Inserts or updates the value for the given key.
    /// - Returns: The previous value for the key if it existed; otherwise, `nil`.
    @discardableResult
    public func put(key: Key, value: Value) -> Value? {
        if let node = dict[key] {
            let oldValue = node.value
            node.value = value
            return oldValue
        } else {
            let newNode = Node(key: key, value: value)
            dict[key] = newNode
            appendNode(newNode)
            return nil
        }
    }
    
    /// Removes the value for the given key.
    /// - Returns: The removed value if it existed; otherwise, `nil`.
    @discardableResult
    public func remove(key: Key) -> Value? {
        guard let node = dict.removeValue(forKey: key) else { return nil }
        removeNode(node)
        return node.value
    }
    
    /// Removes all key-value pairs from the map.
    public func clear() {
        dict.removeAll()
        head = nil
        tail = nil
    }
    
    /// Determines whether the map contains the given key.
    public func containsKey(_ key: Key) -> Bool {
        return dict[key] != nil
    }
    
    /// Determines whether the map contains the given value.
    /// Note: This method requires that Value conforms to Equatable.
    public func containsValue(_ value: Value) -> Bool where Value: Equatable {
        var current = head
        while let node = current {
            if node.value == value {
                return true
            }
            current = node.next
        }
        return false
    }
    
    /// Returns all keys in insertion order.
    public var keys: [Key] {
        var result = [Key]()
        var current = head
        while let node = current {
            result.append(node.key)
            current = node.next
        }
        return result
    }
    
    /// Returns all values in insertion order.
    public var values: [Value] {
        var result = [Value]()
        var current = head
        while let node = current {
            result.append(node.value)
            current = node.next
        }
        return result
    }
    
    /// Subscript for getting and setting values.
    public subscript(key: Key) -> Value? {
        get {
            return get(key: key)
        }
        set {
            if let newValue = newValue {
                _ = put(key: key, value: newValue)
            } else {
                _ = remove(key: key)
            }
        }
    }
    
    // MARK: - Sequence Conformance
    
    /// Iterator that yields key-value pairs in insertion order.
    public struct Iterator: IteratorProtocol {
        private var current: Node?
        
        fileprivate init(start: Node?) {
            self.current = start
        }
        
        public mutating func next() -> (key: Key, value: Value)? {
            guard let node = current else { return nil }
            current = node.next
            return (node.key, node.value)
        }
    }
    
    public func makeIterator() -> Iterator {
        return Iterator(start: head)
    }
    
    // MARK: - Private Helpers
    
    /// Appends a new node to the end of the linked list.
    private func appendNode(_ node: Node) {
        if let tailNode = tail {
            tailNode.next = node
            node.prev = tailNode
            tail = node
        } else {
            head = node
            tail = node
        }
    }
    
    /// Removes the given node from the linked list.
    private func removeNode(_ node: Node) {
        let prevNode = node.prev
        let nextNode = node.next
        
        if let prevNode = prevNode {
            prevNode.next = nextNode
        } else {
            head = nextNode
        }
        
        if let nextNode = nextNode {
            nextNode.prev = prevNode
        } else {
            tail = prevNode
        }
        
        // Disconnect node's pointers.
        node.prev = nil
        node.next = nil
    }
    
    public func removeValue(forKey key: Key) -> Value? {
        return remove(key: key)
    }
}

extension LinkedHashMap {
    public subscript(key: Key, default defaultValue: @autoclosure () -> Value) -> Value {
        get {
            if let value = self[key] {
                return value
            } else {
                return defaultValue()
            }
        }
        set {
            self[key] = newValue
        }
    }
}
