//
//  StorageExplorerView.swift
//  SideStore
//
//  Created by Magesh K on 1/8/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import Combine

// MARK: - Root Storage Explorer View

public struct StorageExplorerView: View {
    private static var hasCompletedInitialStatsScan: Bool = false
    private static var cachedAppStorageUsed: String = ""
    private static var cachedFreeSpace: String = ""
    private static var cachedTotalSpace: String = ""
    
    public static func clearCache() {
        verboseLog("[StorageExplorerView] Static cache cleared")
        hasCompletedInitialStatsScan = false
        cachedAppStorageUsed = ""
        cachedFreeSpace = ""
        cachedTotalSpace = ""
    }
    
    @State private var locations: [StorageLocation] = []
    @State private var totalHardwareSpaceString: String = StorageExplorerView.cachedTotalSpace
    @State private var freeHardwareSpaceString: String = StorageExplorerView.cachedFreeSpace
    @State private var appStorageUsedString: String = StorageExplorerView.cachedAppStorageUsed
    @State private var statsTask: Task<Void, Never>? = nil
    
    public var onSelectFolder: ((URL) -> Void)?
    
    public init(onSelectFolder: ((URL) -> Void)? = nil) {
        self.onSelectFolder = onSelectFolder
    }
    
    public var body: some View {
        List {
            Section(
                header: Text("App Storage Containers"),
                footer: StorageExplorerFooterView(
                    appStorageUsedString: appStorageUsedString.isEmpty ? "Calculating..." : appStorageUsedString,
                    freeHardwareSpaceString: freeHardwareSpaceString,
                    totalHardwareSpaceString: totalHardwareSpaceString
                )
            ) {
                ForEach(locations) { location in
                    StorageLocationRowView(location: location, onSelectFolder: onSelectFolder)
                }
            }
        }
        #if !os(tvOS)
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
        #else
        .listStyle(.grouped)
        #endif
        .navigationTitle("Storage Explorer")
        .onAppear {
            verboseLog("[StorageExplorerView] onAppear triggered")
            self.loadLocations()
            if !StorageExplorerView.hasCompletedInitialStatsScan {
                verboseLog("[StorageExplorerView] Initial load -> starting loadStorageStats immediately")
                self.loadStorageStats(delayMs: 0)
            } else {
                verboseLog("[StorageExplorerView] Returning from folder -> displaying cached stats and scheduling 500ms reconciliation task")
                self.totalHardwareSpaceString = StorageExplorerView.cachedTotalSpace
                self.freeHardwareSpaceString = StorageExplorerView.cachedFreeSpace
                self.appStorageUsedString = StorageExplorerView.cachedAppStorageUsed
                self.loadStorageStats(delayMs: 500)
            }
        }
        .onDisappear {
            verboseLog("[StorageExplorerView] onDisappear triggered - cancelling statsTask")
            self.statsTask?.cancel()
            self.statsTask = nil
        }
    }
    
    private func loadLocations() {
        Task.detached {
            var locs: [StorageLocation] = []
            let fileManager = FileManager.default
            
            // 1. Private Documents
            if let docsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
                locs.append(StorageLocation(
                    name: NSLocalizedString("Private Documents", comment: ""),
                    subtitle: docsURL.path,
                    iconName: "folder.badge.gearshape",
                    url: docsURL
                ))
            }
            
            // 2. App Group Containers
            var seenGroupPaths = Set<String>()
            for groupID in Bundle.main.appGroups {
                if let groupURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: groupID),
                   !seenGroupPaths.contains(groupURL.path) {
                    seenGroupPaths.insert(groupURL.path)
                    locs.append(StorageLocation(
                        name: String(format: NSLocalizedString("App Group Container (%@)", comment: ""), groupID),
                        subtitle: groupURL.path,
                        iconName: "shippingbox",
                        url: groupURL
                    ))
                }
            }
            
            // 3. App Backups Directory
            if let backupsURL = fileManager.appBackupsDirectory {
                locs.append(StorageLocation(
                    name: NSLocalizedString("App Backups Directory", comment: ""),
                    subtitle: backupsURL.path,
                    iconName: "archivebox",
                    url: backupsURL
                ))
            }
            
            // 4. Temporary Directory
            let tmpURL = fileManager.temporaryDirectory
            locs.append(StorageLocation(
                name: NSLocalizedString("Temporary Directory (tmp)", comment: ""),
                subtitle: tmpURL.path,
                iconName: "trash.circle",
                url: tmpURL
            ))
            
            Task { @MainActor in
                self.locations = locs
            }
        }
    }
    
    private func loadStorageStats(delayMs: Int = 0) {
        verboseLog("[StorageExplorerView] loadStorageStats requested (delayMs: \(delayMs))")
        statsTask?.cancel()
        
        statsTask = Task.detached {
            if delayMs > 0 {
                verboseLog("[StorageExplorerView] statsTask waiting \(delayMs)ms before scanning...")
                try? await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
            }
            if Task.isCancelled {
                verboseLog("[StorageExplorerView] statsTask cancelled during initial delay")
                return
            }
            
            verboseLog("[StorageExplorerView] statsTask starting container scan on background thread")
            let fileManager = FileManager.default
            var totalAppSize: Int64 = 0
            
            var containerURLs: [URL] = []
            if let docsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
                containerURLs.append(docsURL)
            }
            for groupID in Bundle.main.appGroups {
                if let groupURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: groupID) {
                    containerURLs.append(groupURL)
                }
            }
            if let backupsURL = fileManager.appBackupsDirectory {
                containerURLs.append(backupsURL)
            }
            containerURLs.append(fileManager.temporaryDirectory)
            
            var seenPaths = Set<String>()
            for containerURL in containerURLs {
                if Task.isCancelled {
                    verboseLog("[StorageExplorerView] statsTask cancelled during container scan loop")
                    return
                }
                if !seenPaths.contains(containerURL.path) {
                    seenPaths.insert(containerURL.path)
                    let start = Date()
                    let size = await StorageExplorerViewModel.calculateDirectorySize(url: containerURL)
                    let duration = Date().timeIntervalSince(start)
                    verboseLog("[StorageExplorerView] Scanned container: \(containerURL.path) -> Size: \(size) bytes (\(String(format: "%.3f", duration))s)")
                    totalAppSize += size
                }
            }
            
            if Task.isCancelled {
                verboseLog("[StorageExplorerView] statsTask cancelled before HW space query")
                return
            }
            
            var hwTotalStr = "Unknown"
            var hwFreeStr = "Unknown"
            #if !os(tvOS)
            do {
                let values = try fileManager.temporaryDirectory.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
                if let total = values.volumeTotalCapacity {
                    hwTotalStr = ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file)
                }
                if let free = values.volumeAvailableCapacityForImportantUsage {
                    hwFreeStr = ByteCountFormatter.string(fromByteCount: free, countStyle: .file)
                } else if let free = values.volumeAvailableCapacity {
                    hwFreeStr = ByteCountFormatter.string(fromByteCount: Int64(free), countStyle: .file)
                }
            } catch {}
            #else
            do {
                let values = try fileManager.temporaryDirectory.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey])
                if let total = values.volumeTotalCapacity {
                    hwTotalStr = ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file)
                }
                if let free = values.volumeAvailableCapacity {
                    hwFreeStr = ByteCountFormatter.string(fromByteCount: Int64(free), countStyle: .file)
                }
            } catch {}
            #endif
            
            let appSizeStr = ByteCountFormatter.string(fromByteCount: totalAppSize, countStyle: .file)
            verboseLog("[StorageExplorerView] statsTask completed successfully. totalAppSize: \(appSizeStr), freeSpace: \(hwFreeStr)")
            
            if Task.isCancelled { return }
            
            Task { @MainActor in
                StorageExplorerView.hasCompletedInitialStatsScan = true
                StorageExplorerView.cachedTotalSpace = hwTotalStr
                StorageExplorerView.cachedFreeSpace = hwFreeStr
                StorageExplorerView.cachedAppStorageUsed = appSizeStr
                
                self.totalHardwareSpaceString = hwTotalStr
                self.freeHardwareSpaceString = hwFreeStr
                self.appStorageUsedString = appSizeStr
            }
        }
    }
}

private struct StorageLocationRowView: View {
    let location: StorageLocation
    let onSelectFolder: ((URL) -> Void)?
    
    private var rowContent: some View {
        HStack(spacing: 12) {
            Image(systemName: location.iconName)
                .font(.title2)
                .foregroundColor(.accentColor)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(location.name)
                    .font(.headline)
                Text(location.subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color.secondary.opacity(0.4))
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
    
    var body: some View {
        #if !os(tvOS)
        rowContent
            .onTapGesture {
                verboseLog("[StorageLocationRowView] Tapped container location: \(location.name) (\(location.url.path))")
                onSelectFolder?(location.url)
            }
        #else
        SwiftUI.Button {
            verboseLog("[StorageLocationRowView] Tapped container location: \(location.name) (\(location.url.path))")
            onSelectFolder?(location.url)
        } label: {
            rowContent
        }
        .buttonStyle(PlainButtonStyle())
        #endif
    }
}

private struct StorageExplorerFooterView: View {
    let appStorageUsedString: String
    let freeHardwareSpaceString: String
    let totalHardwareSpaceString: String
    
    var body: some View {
        VStack(alignment: .center, spacing: 5) {
            if !appStorageUsedString.isEmpty {
                HStack(spacing: 4) {
                    Text("App Storage Used:")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.secondary)
                    Text(appStorageUsedString)
                        .font(.footnote.weight(.medium))
                        .foregroundColor(.secondary)
                }
            }
            if !freeHardwareSpaceString.isEmpty {
                HStack(spacing: 4) {
                    Text("Available Space:")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.secondary)
                    Text(freeHardwareSpaceString)
                        .font(.footnote.weight(.medium))
                        .foregroundColor(.secondary)
                }
            }
            if !totalHardwareSpaceString.isEmpty {
                HStack(spacing: 4) {
                    Text("Total Space:")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.secondary)
                    Text(totalHardwareSpaceString)
                        .font(.footnote.weight(.medium))
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}
