//
//  CacheViewModel.swift
//  AltStore
//
//  Created by Magesh K on 2026-06-29.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import CoreData
import AltStoreCore
import AltSign

struct CacheItem: Identifiable, Equatable {
    let id: String
    let name: String
    let bundleIdentifier: String?
    let sizeString: String
    let sizeInBytes: Int64
    let url: URL
    let isDirectory: Bool
    let image: UIImage?
}

@MainActor
class CacheViewModel: ObservableObject {
    @Published var internalApps: [CacheItem] = []
    @Published var resignedApps: [CacheItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String? = nil {
        didSet {
            showErrorAlert = errorMessage != nil
        }
    }
    @Published var showErrorAlert = false
    
    // Deletion states
    @Published var itemToDelete: CacheItem? = nil {
        didSet {
            showDeleteAlert = itemToDelete != nil
        }
    }
    @Published var showDeleteAlert = false
    
    // Export/Share states
    @Published var activeExportURL: URL? = nil
    
    private let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter
    }()
    
    func loadCacheItems() {
        self.isLoading = true
        
        let internalAppURLs = CacheService.shared.fetchInternalApps()
        let resignedAppURLs = CacheService.shared.fetchResignedApps()
        
        // Fetch all database apps to map display names & icons
        let context = DatabaseManager.shared.viewContext
        var dbAppsMap: [String: (name: String, fileURL: URL, alternateIconURL: URL, hasAlternateIcon: Bool)] = [:]
        
        context.performAndWait {
            let apps = InstalledApp.all(in: context)
            for app in apps {
                dbAppsMap[app.bundleIdentifier] = (
                    name: app.name,
                    fileURL: app.fileURL,
                    alternateIconURL: app.alternateIconURL,
                    hasAlternateIcon: app.hasAlternateIcon
                )
            }
        }
        
        // Process on background queue
        DispatchQueue.global(qos: .userInitiated).async {
            var internalItems: [CacheItem] = []
            var resignedItems: [CacheItem] = []
            
            // 1. Process Internal Cache Items
            for url in internalAppURLs {
                let bundleID = url.lastPathComponent
                let size = CacheService.shared.calculateSize(of: url)
                let sizeStr = self.byteFormatter.string(fromByteCount: size)
                
                var displayName = bundleID
                var iconImage: UIImage? = nil
                
                if let dbInfo = dbAppsMap[bundleID] {
                    displayName = dbInfo.name
                    
                    if dbInfo.hasAlternateIcon,
                       let data = try? Data(contentsOf: dbInfo.alternateIconURL) {
                        iconImage = UIImage(data: data)
                    } else if let appIcon = ALTApplication(fileURL: dbInfo.fileURL)?.icon {
                        iconImage = appIcon
                    }
                }
                
                let item = CacheItem(
                    id: bundleID,
                    name: displayName,
                    bundleIdentifier: bundleID,
                    sizeString: sizeStr,
                    sizeInBytes: size,
                    url: url,
                    isDirectory: true,
                    image: iconImage
                )
                internalItems.append(item)
            }
            
            // 2. Process Resigned App Items
            for url in resignedAppURLs {
                let filename = url.lastPathComponent
                let size = CacheService.shared.calculateSize(of: url)
                let sizeStr = self.byteFormatter.string(fromByteCount: size)
                
                let displayName = filename.replacingOccurrences(of: ".app", with: "")
                                          .replacingOccurrences(of: ".ipa", with: "")
                
                var iconImage: UIImage? = nil
                if let appIcon = ALTApplication(fileURL: url)?.icon {
                    iconImage = appIcon
                }
                
                let item = CacheItem(
                    id: filename,
                    name: displayName,
                    bundleIdentifier: nil,
                    sizeString: sizeStr,
                    sizeInBytes: size,
                    url: url,
                    isDirectory: url.hasDirectoryPath,
                    image: iconImage
                )
                resignedItems.append(item)
            }
            
            // Sort by size descending
            internalItems.sort { $0.sizeInBytes > $1.sizeInBytes }
            resignedItems.sort { $0.sizeInBytes > $1.sizeInBytes }
            
            DispatchQueue.main.async {
                self.internalApps = internalItems
                self.resignedApps = resignedItems
                self.isLoading = false
            }
        }
    }
    
    func deleteItem(_ item: CacheItem) {
        self.isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try CacheService.shared.delete(at: item.url)
                DispatchQueue.main.async {
                    self.loadCacheItems()
                }
            } catch {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}
