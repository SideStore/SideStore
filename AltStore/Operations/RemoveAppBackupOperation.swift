//
//  RemoveAppBackupOperation.swift
//  AltStore
//
//  Created by Riley Testut on 5/13/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation
import AltStoreCore

@objc(RemoveAppBackupOperation)
final class RemoveAppBackupOperation: ResultOperation<Void>
{
    let context: InstallAppOperationContext
    
    private let coordinator = NSFileCoordinator()
    private let coordinatorQueue = OperationQueue()
    
    init(context: InstallAppOperationContext)
    {
        self.context = context
        
        super.init()
        
        self.coordinatorQueue.name = "AltStore - RemoveAppBackupOperation Queue"
    }
    
    override func main()
    {
        super.main()
        
        if let error = self.context.error
        {
            self.finish(.failure(error))
            return
        }
        
        guard let installedApp = self.context.installedApp else {
            return self.finish(.failure(OperationError.invalidParameters("RemoveAppBackupOperation.main: self.context.installedApp is nil")))
        }
        
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.removeBackup(for: installedApp)
                self.finish(.success(()))
            } catch {
                self.finish(.failure(error))
            }
        }
    }
    
    private func removeBackup(for installedApp: InstalledApp) async throws {
        let backupDirectoryURL: URL? = await installedApp.managedObjectContext?.perform {
            self.backupDirectoryURL(for: installedApp)
        }
        guard let backupDirectoryURL else {
            throw OperationError.missingAppGroup
        }
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let intent = NSFileAccessIntent.writingIntent(with: backupDirectoryURL, options: [.forDeleting])
            self.coordinator.coordinate(with: [intent], queue: self.coordinatorQueue) { error in
                continuation.resume(with: Result { try self.removeBackupItem(at: intent.url, backupDirectoryURL: backupDirectoryURL, coordinatorError: error) })
            }
        }
    }
    
    private func backupDirectoryURL(for installedApp: InstalledApp) -> URL? {
        FileManager.default.backupDirectoryURL(for: installedApp)
    }
    
    private func removeBackupItem(at url: URL, backupDirectoryURL: URL, coordinatorError: Error?) throws {
        if let coordinatorError { throw coordinatorError }
        do {
            try FileManager.default.removeItem(at: url)
        } catch let error as CocoaError where error.code == CocoaError.Code.fileNoSuchFile {
            // TODO: @mahee96: Find out why should in debug builds the app-groups is not expected to match
//                    #if DEBUG
//                    
//                    // When debugging, it's expected that app groups don't match, so ignore.
//                    self.finish(.success(()))
//                    
//                    #else
            debugLog("Failed to remove app backup directory \(backupDirectoryURL.lastPathComponent). \(error.localizedDescription)")
            throw error
//                    #endif
        } catch {
            debugLog("Failed to remove app backup directory \(backupDirectoryURL.lastPathComponent). \(error.localizedDescription)")
            throw error
        }
    }

    private func debugLog(_ text: String) {
        print(text)
    }

    private func verboseLog(_ text: String) {
        let isLoggingEnabled = OperationsLoggingControl.getFromDatabase(for: RemoveAppBackupOperation.self)
        if isLoggingEnabled {
            print(text)
        }
    }
}

