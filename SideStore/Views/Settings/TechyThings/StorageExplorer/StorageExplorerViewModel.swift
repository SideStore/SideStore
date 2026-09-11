//
//  StorageExplorerViewModel.swift
//  SideStore
//
//  Created by Magesh K on 3/8/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import Combine

// MARK: - Clipboard Singleton

@MainActor
public final class StorageExplorerClipboard: ObservableObject {
    public static let shared = StorageExplorerClipboard()
    
    @Published public var copiedURLs: [URL] = []
    
    private init() {}
    
    public var hasCopiedItems: Bool {
        !copiedURLs.isEmpty
    }
    
    public var pasteLabelText: String {
        if copiedURLs.count == 1, let first = copiedURLs.first {
            return String(format: NSLocalizedString("Paste “%@”", comment: ""), first.lastPathComponent)
        } else if copiedURLs.count > 1 {
            return String(format: NSLocalizedString("Paste %d Items", comment: ""), copiedURLs.count)
        }
        return NSLocalizedString("Paste", comment: "")
    }
    
    public func setCopied(urls: [URL]) {
        self.copiedURLs = urls
    }
    
    public func clear() {
        self.copiedURLs.removeAll()
    }
}

// MARK: - Paste Conflict Model

public struct PasteConflict: Identifiable {
    public var id: String { sourceURL.path }
    public let sourceURL: URL
    public let destinationDirectory: URL
    public let existingName: String
}

// MARK: - Storage Location Model

public struct StorageLocation: Identifiable, Hashable {
    public var id: String { url.path }
    public let name: String
    public let subtitle: String
    public let iconName: String
    public let url: URL
}

// MARK: - Storage Explorer Item Model

public struct StorageExplorerItem: Identifiable, Hashable {
    public var id: URL { url }
    public let url: URL
    public let name: String
    public let isDirectory: Bool
    public var size: Int64
    public var itemCount: Int
    public let modificationDate: Date
    
    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    
    public var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: modificationDate)
    }
}

// MARK: - Sorting & Grouping Enums

public enum StorageSortOption: String, CaseIterable, Identifiable {
    case name = "Name"
    case date = "Date Modified"
    case size = "Size"
    case type = "Type"
    
    public var id: String { rawValue }
}

// MARK: - Directory Explorer ViewModel

@MainActor
public final class StorageExplorerViewModel: ObservableObject {
    public let currentURL: URL
    
    @Published public var items: [StorageExplorerItem] = []
    @Published public var searchText: String = ""
    @Published public var sortOption: StorageSortOption = .name
    @Published public var sortAscending: Bool = true
    @Published public var groupFoldersFirst: Bool = true
    @Published public var isTextWrapEnabled: Bool = true
    @Published public var isLoading: Bool = false
    
    @Published public var isSelectionMode: Bool = false
    @Published public var selectedURLs: Set<URL> = []
    
    @Published public var currentFolderSize: Int64 = 0
    @Published public var freeDiskSpaceString: String = ""
    
    @Published public var activeAlert: ActiveAlert? = nil
    @Published public var itemToRename: StorageExplorerItem? = nil
    @Published public var renameInput: String = ""
    @Published public var shareURL: URL? = nil
    
    @Published public var pendingConflicts: [PasteConflict] = []
    @Published public var currentConflict: PasteConflict? = nil
    @Published public var conflictNewNameInput: String = ""
    
    public enum ActiveAlert: Identifiable {
        case confirmSingleDelete(StorageExplorerItem)
        case confirmBulkDelete
        case rename(StorageExplorerItem)
        case bulkRename
        case pasteConflict(PasteConflict)
        case error(String)
        
        public var id: String {
            switch self {
            case .confirmSingleDelete(let item): return "singleDelete-\(item.url.path)"
            case .confirmBulkDelete: return "bulkDelete"
            case .rename(let item): return "rename-\(item.url.path)"
            case .bulkRename: return "bulkRename"
            case .pasteConflict(let c): return "conflict-\(c.sourceURL.path)"
            case .error(let msg): return "error-\(msg)"
            }
        }
    }
    
    public init(url: URL) {
        self.currentURL = url
        self.loadContents()
        self.loadDiskSpace()
    }
    
    public func loadDiskSpace() {
        Task.detached {
            let space = await Self.getFreeDiskSpaceString()
            Task { @MainActor in
                self.freeDiskSpaceString = space
            }
        }
    }
    
    private static func getFreeDiskSpaceString() -> String {
        do {
            #if !os(tvOS)
            let values = try FileManager.default.temporaryDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
            if let free = values.volumeAvailableCapacityForImportantUsage {
                return ByteCountFormatter.string(fromByteCount: free, countStyle: .file)
            } else if let free = values.volumeAvailableCapacity {
                return ByteCountFormatter.string(fromByteCount: Int64(free), countStyle: .file)
            }
            #else
            let values = try FileManager.default.temporaryDirectory.resourceValues(forKeys: [.volumeAvailableCapacityKey])
            if let free = values.volumeAvailableCapacity {
                return ByteCountFormatter.string(fromByteCount: Int64(free), countStyle: .file)
            }
            #endif
        } catch {}
        return "Unknown"
    }
    
    private var loadTask: Task<Void, Never>?
    
    deinit {
        loadTask?.cancel()
    }
    
    public func cancelLoading() {
        loadTask?.cancel()
        loadTask = nil
    }
    
    public static func calculateDirectorySize(url: URL) -> Int64 {
        let fileManager = FileManager.default
        var total: Int64 = 0
        if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator {
                if Task.isCancelled { break }
                if let vals = try? fileURL.resourceValues(forKeys: [.fileSizeKey]), let size = vals.fileSize {
                    total += Int64(size)
                }
            }
        }
        return total
    }
    
    public func loadContents() {
        verboseLog("[StorageExplorerViewModel] loadContents requested for: \(currentURL.path)")
        loadTask?.cancel()
        self.isLoading = true
        let targetURL = self.currentURL
        
        loadTask = Task.detached {
            let start = Date()
            verboseLog("[StorageExplorerViewModel] loadContents background task starting for: \(targetURL.path)")
            var loadedItems: [StorageExplorerItem] = []
            var folderTotalSize: Int64 = 0
            
            do {
                let fileManager = FileManager.default
                let contents = try fileManager.contentsOfDirectory(at: targetURL, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey], options: [.skipsHiddenFiles])
                
                for itemURL in contents {
                    if Task.isCancelled {
                        verboseLog("[StorageExplorerViewModel] loadContents cancelled during directory iteration for: \(targetURL.path)")
                        return
                    }
                    let resourceValues = try? itemURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
                    let isDir = resourceValues?.isDirectory ?? false
                    let modDate = resourceValues?.contentModificationDate ?? Date()
                    var size: Int64 = Int64(resourceValues?.fileSize ?? 0)
                    var itemCount: Int = 0
                    
                    if isDir {
                        size = await Self.calculateDirectorySize(url: itemURL)
                        if Task.isCancelled {
                            verboseLog("[StorageExplorerViewModel] loadContents cancelled during subfolder size calculation for: \(itemURL.path)")
                            return
                        }
                        if let subContents = try? fileManager.contentsOfDirectory(at: itemURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                            itemCount = subContents.count
                        }
                    }
                    
                    folderTotalSize += size
                    loadedItems.append(StorageExplorerItem(
                        url: itemURL,
                        name: itemURL.lastPathComponent,
                        isDirectory: isDir,
                        size: size,
                        itemCount: itemCount,
                        modificationDate: modDate
                    ))
                }
            } catch {
                debugLog("[StorageExplorerViewModel] Error reading directory \(targetURL.path): \(error)")
            }
            
            if Task.isCancelled {
                verboseLog("[StorageExplorerViewModel] loadContents cancelled before MainActor dispatch for: \(targetURL.path)")
                return
            }
            let duration = Date().timeIntervalSince(start)
            let totalFolderSize = folderTotalSize
            verboseLog("[StorageExplorerViewModel] loadContents completed for: \(targetURL.path) -> \(loadedItems.count) items, totalSize: \(totalFolderSize) bytes (\(String(format: "%.3f", duration))s)")
            
            Task { @MainActor in
                self.items = loadedItems
                self.currentFolderSize = totalFolderSize
                self.isLoading = false
            }
        }
    }
    
    public var filteredAndSortedItems: [StorageExplorerItem] {
        var result = items
        
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let query = searchText.lowercased()
            result = result.filter { $0.name.lowercased().contains(query) }
        }
        
        result.sort { item1, item2 in
            if groupFoldersFirst && item1.isDirectory != item2.isDirectory {
                return item1.isDirectory && !item2.isDirectory
            }
            
            switch sortOption {
            case .name:
                let comp = item1.name.localizedStandardCompare(item2.name) == .orderedAscending
                return sortAscending ? comp : !comp
            case .date:
                let comp = item1.modificationDate < item2.modificationDate
                return sortAscending ? comp : !comp
            case .size:
                let comp = item1.size < item2.size
                return sortAscending ? comp : !comp
            case .type:
                let ext1 = item1.url.pathExtension
                let ext2 = item2.url.pathExtension
                let comp = ext1.localizedStandardCompare(ext2) == .orderedAscending
                return sortAscending ? comp : !comp
            }
        }
        
        return result
    }
    
    public func delete(item: StorageExplorerItem) {
        Task.detached {
            do {
                try FileManager.default.removeItem(at: item.url)
                Task { @MainActor in
                    self.loadContents()
                }
            } catch {
                Task { @MainActor in
                    self.activeAlert = .error("Failed to delete \(item.name): \(error.localizedDescription)")
                }
            }
        }
    }
    
    public func bulkDeleteSelected() {
        let targets = items.filter { selectedURLs.contains($0.url) }
        Task.detached {
            var errors: [String] = []
            for item in targets {
                do {
                    try FileManager.default.removeItem(at: item.url)
                } catch {
                    errors.append("\(item.name): \(error.localizedDescription)")
                }
            }
            Task { @MainActor in
                self.selectedURLs.removeAll()
                self.isSelectionMode = false
                self.loadContents()
                if !errors.isEmpty {
                    self.activeAlert = .error("Errors deleting items:\n" + errors.joined(separator: "\n"))
                }
            }
        }
    }
    
    public func rename(item: StorageExplorerItem, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != item.name else { return }
        let destinationURL = item.url.deletingLastPathComponent().appendingPathComponent(trimmed)
        Task.detached {
            do {
                try FileManager.default.moveItem(at: item.url, to: destinationURL)
                Task { @MainActor in
                    self.loadContents()
                }
            } catch {
                Task { @MainActor in
                    self.activeAlert = .error("Failed to rename \(item.name): \(error.localizedDescription)")
                }
            }
        }
    }
    
    public func bulkRenameSelected(to newBaseName: String) {
        let trimmed = newBaseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let targets = items.filter { selectedURLs.contains($0.url) }
        guard !targets.isEmpty else { return }
        
        if targets.count == 1, let item = targets.first {
            rename(item: item, to: trimmed)
            self.selectedURLs.removeAll()
            self.isSelectionMode = false
            return
        }
        
        Task.detached {
            var errors: [String] = []
            var index = 1
            
            for item in targets {
                let ext = item.url.pathExtension
                let nameWithoutExt = ext.isEmpty ? "\(trimmed)_\(index)" : "\(trimmed)_\(index).\(ext)"
                let destinationURL = item.url.deletingLastPathComponent().appendingPathComponent(nameWithoutExt)
                
                do {
                    try FileManager.default.moveItem(at: item.url, to: destinationURL)
                } catch {
                    errors.append("\(item.name): \(error.localizedDescription)")
                }
                index += 1
            }
            
            Task { @MainActor in
                self.selectedURLs.removeAll()
                self.isSelectionMode = false
                self.loadContents()
                if !errors.isEmpty {
                    self.activeAlert = .error("Errors renaming items:\n" + errors.joined(separator: "\n"))
                }
            }
        }
    }
    
    public func copyToClipboard(item: StorageExplorerItem) {
        StorageExplorerClipboard.shared.setCopied(urls: [item.url])
    }
    
    public func copySelectedToClipboard() {
        let selected = items.filter { selectedURLs.contains($0.url) }.map { $0.url }
        if !selected.isEmpty {
            StorageExplorerClipboard.shared.setCopied(urls: selected)
            self.isSelectionMode = false
            self.selectedURLs.removeAll()
        }
    }
    
    public func pasteCopiedItems() {
        let sources = StorageExplorerClipboard.shared.copiedURLs
        guard !sources.isEmpty else { return }
        let currentTargetURL = self.currentURL
        
        Task.detached {
            var conflicts: [PasteConflict] = []
            var copyErrors: [String] = []
            let fileManager = FileManager.default
            
            for sourceURL in sources {
                guard fileManager.fileExists(atPath: sourceURL.path) else { continue }
                let destURL = currentTargetURL.appendingPathComponent(sourceURL.lastPathComponent)
                
                if fileManager.fileExists(atPath: destURL.path) {
                    conflicts.append(PasteConflict(sourceURL: sourceURL, destinationDirectory: currentTargetURL, existingName: sourceURL.lastPathComponent))
                } else {
                    do {
                        try fileManager.copyItem(at: sourceURL, to: destURL)
                    } catch {
                        copyErrors.append("\(sourceURL.lastPathComponent): \(error.localizedDescription)")
                    }
                }
            }
            
            Task { @MainActor in
                self.loadContents()
                if !conflicts.isEmpty {
                    self.pendingConflicts = conflicts
                    self.presentNextConflict()
                } else if !copyErrors.isEmpty {
                    self.activeAlert = .error("Errors copying items:\n" + copyErrors.joined(separator: "\n"))
                }
            }
        }
    }
    
    private func presentNextConflict() {
        guard let next = pendingConflicts.first else {
            self.currentConflict = nil
            self.loadContents()
            return
        }
        self.currentConflict = next
        self.conflictNewNameInput = next.existingName
        self.activeAlert = .pasteConflict(next)
    }
    
    public func resolveConflictWithNewName() {
        guard let conflict = currentConflict else { return }
        let trimmed = conflictNewNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmed.isEmpty else { return }
        
        let destURL = conflict.destinationDirectory.appendingPathComponent(trimmed)
        if FileManager.default.fileExists(atPath: destURL.path) {
            // Name still conflicts!
            self.activeAlert = .error("A file named “\(trimmed)” already exists in this folder. Please choose a different name.")
            return
        }
        
        do {
            try FileManager.default.copyItem(at: conflict.sourceURL, to: destURL)
        } catch {
            debugLog("Error copying conflict item: \(error)")
        }
        
        if !pendingConflicts.isEmpty {
            pendingConflicts.removeFirst()
        }
        self.presentNextConflict()
    }
    
    public func cancelRemainingConflicts() {
        self.pendingConflicts.removeAll()
        self.currentConflict = nil
        self.loadContents()
    }
}
