//
//  ClearAppCacheOperation.swift
//  AltStore
//
//  Created by Riley Testut on 9/27/22.
//  Copyright © 2022 Riley Testut. All rights reserved.
//

import Foundation
import AltStoreCore

import Nuke

struct BatchError: ALTLocalizedError {

    enum Code: Int, ALTErrorCode {
        typealias Error = BatchError
        
        case batchError
    }
    var code: Code = .batchError
    var underlyingErrors: [Error]
    
    var errorTitle: String?
    var errorFailure: String?
    
    init(errors: [Error]) {
        self.underlyingErrors = errors
    }
    
    var errorFailureReason: String {
        guard !self.underlyingErrors.isEmpty else { return NSLocalizedString("An unknown error occured.", comment: "") }
        
        let errorMessages = self.underlyingErrors.map { $0.localizedDescription }
        
        let message = errorMessages.joined(separator: "\n\n")
        return message
    }
}

@objc(ClearAppCacheOperation)
class ClearAppCacheOperation: ResultOperation<Void> {
    private let coordinator = NSFileCoordinator()
    private let coordinatorQueue = OperationQueue()
    
    override init() {
        self.coordinatorQueue.name = "AltStore - ClearAppCacheOperation Queue"
    }
    
    override func main() {
        super.main()
        
        self.clearNukeCache()
        
        Task { [weak self] in
            guard let self else { return }
            var allErrors = [Error]()
            
            do { try await self.clearTemporaryDirectory() }
            catch { allErrors.append(error) }
            
            do { try await self.removeUninstalledAppBackupDirectories() }
            catch { allErrors.append(error) }
            
            if allErrors.isEmpty {
                self.finish(.success(()))
            } else {
                self.finish(.failure(OperationError.cacheClearError(errors: allErrors.map { $0.localizedDescription })))
            }
        }
    }
    
    private func clearNukeCache() {
        guard let dataCache = ImagePipeline.shared.configuration.dataCache as? DataCache else { return }
        dataCache.removeAll()
    }
    
    private func clearTemporaryDirectory() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let intent = NSFileAccessIntent.writingIntent(with: FileManager.default.temporaryDirectory, options: [.forDeleting])
            self.coordinator.coordinate(with: [intent], queue: self.coordinatorQueue) { error in
                continuation.resume(with: Result { try self.clearTempDirItems(at: intent.url, coordinatorError: error) })
            }
        }
    }
    
    private func clearTempDirItems(at url: URL, coordinatorError: Error?) throws {
        if let coordinatorError { throw coordinatorError }
        
        let fileURLs = try FileManager.default.contentsOfDirectory(at: url,
                                                                   includingPropertiesForKeys: [],
                                                                   options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles])
        var errors = [Error]()
        for fileURL in fileURLs {
            do {
                self.verboseLog("Removing item from temporary directory: \(fileURL.lastPathComponent)")
                try FileManager.default.removeItem(at: fileURL)
            } catch {
                self.debugLog("Failed to remove \(fileURL.lastPathComponent) from temporary directory. \(error.localizedDescription)")
                errors.append(error)
            }
        }
        
        if !errors.isEmpty {
            throw OperationError.cacheClearError(errors: errors.map { $0.localizedDescription })
        }
    }
    
    private func removeUninstalledAppBackupDirectories() async throws {
        guard let backupsDirectory = FileManager.default.appBackupsDirectory else {
            throw OperationError.missingAppGroup
        }
        
        let installedAppBundleIDs = await DatabaseManager.shared.persistentContainer.performBackgroundTask { context in
            Set(InstalledApp.all(in: context).map { $0.bundleIdentifier })
        }
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let intent = NSFileAccessIntent.writingIntent(with: backupsDirectory, options: [.forDeleting])
            self.coordinator.coordinate(with: [intent], queue: self.coordinatorQueue) { error in
                continuation.resume(with: Result { try self.removeBackupDirItems(at: intent.url, installedBundleIDs: installedAppBundleIDs, coordinatorError: error) })
            }
        }
    }
    
    private func removeBackupDirItems(at url: URL, installedBundleIDs: Set<String>, coordinatorError: Error?) throws {
        if let coordinatorError { throw coordinatorError }
        
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return
        }
        
        let fileURLs = try FileManager.default.contentsOfDirectory(at: url,
                                                                   includingPropertiesForKeys: [.isDirectoryKey, .nameKey],
                                                                   options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles])
        var errors = [Error]()
        for backupDirectory in fileURLs {
            do {
                let resourceValues = try backupDirectory.resourceValues(forKeys: [.isDirectoryKey, .nameKey])
                guard let isDir = resourceValues.isDirectory, let bundleID = resourceValues.name else { continue }
                
                if isDir && !installedBundleIDs.contains(bundleID) && !AppManager.shared.isActivelyManagingApp(withBundleID: bundleID) {
                    self.verboseLog("Removing backup directory for uninstalled app: \(bundleID)")
                    try FileManager.default.removeItem(at: backupDirectory)
                }
            } catch {
                self.debugLog("Failed to remove app backup directory. \(error.localizedDescription)")
                errors.append(error)
            }
        }
        
        if !errors.isEmpty {
            throw OperationError.cacheClearError(errors: errors.map { $0.localizedDescription })
        }
    }

    private func debugLog(_ text: String) {
        print(text)
    }

    private func verboseLog(_ text: String) {
        let isLoggingEnabled = OperationsLoggingControl.getFromDatabase(for: ClearAppCacheOperation.self)
        if isLoggingEnabled {
            print(text)
        }
    }
}
