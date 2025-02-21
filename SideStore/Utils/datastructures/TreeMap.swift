//
//  TreeMap.swift
//  SideStore
//
//  Created by Magesh K on 21/02/25.
//  Copyright © 2025 SideStore. All rights reserved.
//

public class TreeMap<Key: Comparable, Value>: Sequence {
    
    // MARK: - Node and Color Definitions
    
    fileprivate enum Color {
        case red
        case black
    }
    
    fileprivate class Node {
        var key: Key
        var value: Value
        var left: Node?
        var right: Node?
        weak var parent: Node?
        var color: Color
        
        init(key: Key, value: Value, color: Color = .red, parent: Node? = nil) {
            self.key = key
            self.value = value
            self.color = color
            self.parent = parent
        }
    }
    
    // MARK: - TreeMap Properties and Initializer
    
    private var root: Node?
    public private(set) var count: Int = 0
    
    public init() {}
    
    // MARK: - Public Dictionary-like API
    
    /// Subscript: Get or set value for a given key.
    public subscript(key: Key) -> Value? {
        get { return get(key: key) }
        set {
            if let newValue = newValue {
                _ = insert(key: key, value: newValue)
            } else {
                _ = remove(key: key)
            }
        }
    }
    
    /// Returns the value associated with the given key.
    public func get(key: Key) -> Value? {
        guard let node = getNode(forKey: key) else { return nil }
        return node.value
    }
    
    /// Inserts (or updates) the key with the given value.
    /// Returns the old value if the key was already present.
    @discardableResult
    public func insert(key: Key, value: Value) -> Value? {
        if let node = getNode(forKey: key) {
            let oldValue = node.value
            node.value = value
            return oldValue
        }
        // Create new node
        let newNode = Node(key: key, value: value)
        var parent: Node? = nil
        var current = root
        while let cur = current {
            parent = cur
            if newNode.key < cur.key {
                current = cur.left
            } else {
                current = cur.right
            }
        }
        newNode.parent = parent
        if parent == nil {
            root = newNode
        } else if newNode.key < parent!.key {
            parent!.left = newNode
        } else {
            parent!.right = newNode
        }
        count += 1
        fixAfterInsertion(newNode)
        return nil
    }
    
    /// Removes the node with the given key.
    /// Returns the removed value if it existed.
    @discardableResult
    public func remove(key: Key) -> Value? {
        guard let node = getNode(forKey: key) else { return nil }
        let removedValue = node.value
        deleteNode(node)
        count -= 1
        return removedValue
    }
    
    /// Returns true if the map is empty.
    public var isEmpty: Bool {
        return count == 0
    }
    
    /// Returns all keys in sorted order.
    public var keys: [Key] {
        var result = [Key]()
        for (k, _) in self { result.append(k) }
        return result
    }
    
    /// Returns all values in order of their keys.
    public var values: [Value] {
        var result = [Value]()
        for (_, v) in self { result.append(v) }
        return result
    }
    
    /// Removes all entries.
    public func removeAll() {
        root = nil
        count = 0
    }
    
    // MARK: - Internal Helper Methods
    
    /// Standard BST search for a node matching the key.
    private func getNode(forKey key: Key) -> Node? {
        var current = root
        while let node = current {
            if key == node.key {
                return node
            } else if key < node.key {
                current = node.left
            } else {
                current = node.right
            }
        }
        return nil
    }
    
    /// Returns the minimum node in the subtree rooted at `node`.
    private func minimum(_ node: Node) -> Node {
        var current = node
        while let next = current.left {
            current = next
        }
        return current
    }
    
    // MARK: - Rotation Methods
    
    private func rotateLeft(_ x: Node) {
        guard let y = x.right else { return }
        x.right = y.left
        if let leftChild = y.left {
            leftChild.parent = x
        }
        y.parent = x.parent
        if x.parent == nil {
            root = y
        } else if x === x.parent?.left {
            x.parent?.left = y
        } else {
            x.parent?.right = y
        }
        y.left = x
        x.parent = y
    }
    
    private func rotateRight(_ x: Node) {
        guard let y = x.left else { return }
        x.left = y.right
        if let rightChild = y.right {
            rightChild.parent = x
        }
        y.parent = x.parent
        if x.parent == nil {
            root = y
        } else if x === x.parent?.right {
            x.parent?.right = y
        } else {
            x.parent?.left = y
        }
        y.right = x
        x.parent = y
    }
    
    // MARK: - Insertion Fix-Up
    
    /// Restores red–black properties after insertion.
    private func fixAfterInsertion(_ x: Node) {
        var node = x
        node.color = .red
        while node !== root, let parent = node.parent, parent.color == .red {
            if parent === parent.parent?.left {
                if let uncle = parent.parent?.right, uncle.color == .red {
                    parent.color = .black
                    uncle.color = .black
                    parent.parent?.color = .red
                    if let grandparent = parent.parent {
                        node = grandparent
                    }
                } else {
                    if node === parent.right {
                        node = parent
                        rotateLeft(node)
                    }
                    node.parent?.color = .black
                    node.parent?.parent?.color = .red
                    if let grandparent = node.parent?.parent {
                        rotateRight(grandparent)
                    }
                }
            } else {
                if let uncle = parent.parent?.left, uncle.color == .red {
                    parent.color = .black
                    uncle.color = .black
                    parent.parent?.color = .red
                    if let grandparent = parent.parent {
                        node = grandparent
                    }
                } else {
                    if node === parent.left {
                        node = parent
                        rotateRight(node)
                    }
                    node.parent?.color = .black
                    node.parent?.parent?.color = .red
                    if let grandparent = node.parent?.parent {
                        rotateLeft(grandparent)
                    }
                }
            }
        }
        root?.color = .black
    }
    
    // MARK: - Deletion Helpers
    
    /// Replaces subtree rooted at u with subtree rooted at v.
    private func transplant(_ u: Node, _ v: Node?) {
        if u.parent == nil {
            root = v
        } else if u === u.parent?.left {
            u.parent?.left = v
        } else {
            u.parent?.right = v
        }
        if let vNode = v {
            vNode.parent = u.parent
        }
    }
    
    /// Deletes node z and fixes red–black properties.
    private func deleteNode(_ z: Node) {
        var y = z
        let originalColor = y.color
        var x: Node?
        
        if z.left == nil {
            x = z.right
            transplant(z, z.right)
        } else if z.right == nil {
            x = z.left
            transplant(z, z.left)
        } else {
            y = minimum(z.right!)
            let yOriginalColor = y.color
            x = y.right
            if y.parent === z {
                if x != nil { x!.parent = y }
            } else {
                transplant(y, y.right)
                y.right = z.right
                y.right?.parent = y
            }
            transplant(z, y)
            y.left = z.left
            y.left?.parent = y
            y.color = z.color
            if yOriginalColor == .black {
                fixAfterDeletion(x, parent: y.parent)
            }
            return
        }
        if originalColor == .black {
            fixAfterDeletion(x, parent: z.parent)
        }
    }
    
    /// Restores red–black properties after deletion.
    private func fixAfterDeletion(_ x: Node?, parent: Node?) {
        var x = x
        var parent = parent
        while (x == nil || x!.color == .black) && (x !== root) {
            if x === parent?.left {
                var w = parent?.right
                if w?.color == .red {
                    w?.color = .black
                    parent?.color = .red
                    rotateLeft(parent!)
                    w = parent?.right
                }
                if (w?.left == nil || w?.left?.color == .black) &&
                   (w?.right == nil || w?.right?.color == .black) {
                    w?.color = .red
                    x = parent
                    parent = x?.parent
                } else {
                    if w?.right == nil || w?.right?.color == .black {
                        w?.left?.color = .black
                        w?.color = .red
                        if let wUnwrapped = w { rotateRight(wUnwrapped) }
                        w = parent?.right
                    }
                    w?.color = parent?.color ?? .black
                    parent?.color = .black
                    w?.right?.color = .black
                    rotateLeft(parent!)
                    x = root
                    parent = nil
                }
            } else {
                var w = parent?.left
                if w?.color == .red {
                    w?.color = .black
                    parent?.color = .red
                    rotateRight(parent!)
                    w = parent?.left
                }
                if (w?.left == nil || w?.left?.color == .black) &&
                   (w?.right == nil || w?.right?.color == .black) {
                    w?.color = .red
                    x = parent
                    parent = x?.parent
                } else {
                    if w?.left == nil || w?.left?.color == .black {
                        w?.right?.color = .black
                        w?.color = .red
                        if let wUnwrapped = w { rotateLeft(wUnwrapped) }
                        w = parent?.left
                    }
                    w?.color = parent?.color ?? .black
                    parent?.color = .black
                    w?.left?.color = .black
                    rotateRight(parent!)
                    x = root
                    parent = nil
                }
            }
        }
        x?.color = .black
    }
    
    // Convenience overload if parent is not separately tracked.
    private func fixAfterDeletion(_ x: Node?) {
        fixAfterDeletion(x, parent: x?.parent)
    }
    
    // MARK: - Sequence Conformance (In-Order Traversal)
    
    public struct Iterator: IteratorProtocol {
        private var stack: [Node] = []
        
        // Marked as private because Node is a private type.
        fileprivate init(root: Node?) {
            var current = root
            while let node = current {
                stack.append(node)
                current = node.left
            }
        }
        
        public mutating func next() -> (Key, Value)? {
            if stack.isEmpty { return nil }
            let node = stack.removeLast()
            let result = (node.key, node.value)
            var current = node.right
            while let n = current {
                stack.append(n)
                current = n.left
            }
            return result
        }
    }
    
    public func makeIterator() -> Iterator {
        return Iterator(root: root)
    }
}
