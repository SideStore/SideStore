//
//  CoreDataHelper.swift
//  AltStore
//
//  Created by Magesh K on 02/01/25.
//  Copyright © 2025 SideStore. All rights reserved.
//


import Foundation
import CoreData
import System

import AltStoreCore

class CoreDataHelper{
    
    private static let STORE_XCMODELD_NAME = "AltStore"
    private static let COREDATA_BUNDLE_ID = "com.SideStore.SideStore.AltStoreCore"
    
    // Create a serial dispatch queue to lock access to the Core Data store
    private static let datastoreQueue = DispatchQueue(label: "com.SideStore.AltStore.datastoreQueue")
    
    public static func exportCoreDataStore() async throws -> URL {

        // Locate the bundle containing the Core Data model
        guard let bundle = Bundle(identifier: COREDATA_BUNDLE_ID) else {
            let errorDescription = "AltStoreCore bundle not found"
            throw getCoreDataError(code: 1, localizedDescription: errorDescription)
        }
        
        // Load the model from the bundle
        guard let modelURL = bundle.url(forResource: STORE_XCMODELD_NAME, withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: modelURL) else {
            
            let errorDescription = "Failed to load model \(STORE_XCMODELD_NAME) from AltStoreCore bundle"
            throw getCoreDataError(code: 2, localizedDescription: errorDescription)
        }
        
//        let container = NSPersistentContainer(name: STORE_XCMODELD_NAME)
//        let container = NSPersistentContainer(name: STORE_XCMODELD_NAME, managedObjectModel: model)
        let container = DatabaseManager.shared.persistentContainer

        // bridge callback into async-await pattern
//        return try await withCheckedThrowingContinuation{ (continuation: CheckedContinuation<URL, Error>) in
            
            // async callback processing
//            container.loadPersistentStores { description, error in
                // perform actual backup in sync manner
//                do{
//                    let exportedURL = try backupCoreDataStore(container: container, loadError: error)
//                    let exportedURL = try backupCoreDataStore(container: container)
                    return try backupCoreDataStore(container: container)
//                    continuation.resume(returning: exportedURL)
//                }catch{
//                    continuation.resume(throwing: error)
//                }
//            }
//        }
    }
    
    private static func lockSQLiteFile(at url: URL) -> FileDescriptor? {
        // Open the SQLite file for locking
        let fileDescriptor = open(url.path, O_RDWR)
        guard fileDescriptor >= 0 else {
            print("Failed to open SQLite file for locking.")
            return nil
        }

        // Lock the file using flock (exclusive lock)
        let lockResult = flock(fileDescriptor, LOCK_EX)
        guard lockResult == 0 else {
            print("Failed to lock SQLite file.")
            close(fileDescriptor)
            return nil
        }

        return FileDescriptor(rawValue: fileDescriptor)
    }

    private static func unlockSQLiteFile(fileDescriptor: FileDescriptor) {
        let fileDescriptor = fileDescriptor.rawValue
        // Unlock the file after backup
        flock(fileDescriptor, LOCK_UN)
        close(fileDescriptor)
    }
    
    private static func getCoreDataError(code: Int, localizedDescription: String) -> Error {
        return NSError(domain: "CoreDataExport", code: code, userInfo: [NSLocalizedDescriptionKey: localizedDescription])
    }
    
    
    private static func backupCoreDataStore(container: NSPersistentContainer, loadError: Error? = nil) throws -> URL
    {
        
        // Check for load errors
        if let error = loadError {
            let errorDescription = "Failed to load persistent store: \(error.localizedDescription)"
            throw getCoreDataError(code: 3, localizedDescription: errorDescription)
        }
                
        guard let storeURL = container.persistentStoreCoordinator.persistentStores.first?.url else {
            let errorDescription = "Persistent store URL not found"
            throw getCoreDataError(code: 4, localizedDescription: errorDescription)
        }

        // TODO: we can't lock on the sqlite file for serialization coz coredata might be holding
        //       active database connection handle to the sqlite
        
//        // Lock the SQLite file
//        guard let fileDescriptor = lockSQLiteFile(at: storeURL) else {
//            throw getCoreDataError(code: 5, localizedDescription: "Failed to lock SQLite file")
//        }
//        
//        defer {
//            // Ensure that the file is unlocked when the backup completes or fails
//            unlockSQLiteFile(fileDescriptor: fileDescriptor)
//        }
        
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let exportedDir = documentsURL.appendingPathComponent("ExportedCoreDataStores", isDirectory: true)
        
        let currentDateTime = Date()
        let currentTimeStamp = DateTimeUtil.getDateInTimeStamp(date: currentDateTime)
        
        func getFileName(extn fileExtension: String) -> String {
            let fileNamePrefix = storeURL.deletingPathExtension().lastPathComponent
            let fileName = DateTimeUtil.getTimeStampSuffixedFileName(
                fileName: fileNamePrefix,
                timestamp: currentTimeStamp,
                extn: "." + fileExtension
            )
            return fileName
        }
        
        let fileName = getFileName(extn: storeURL.pathExtension)
        let destinationURL = exportedDir.appendingPathComponent(fileName)
        
        let directoryURL = storeURL.deletingLastPathComponent()
        if let files = try? FileManager.default.contentsOfDirectory(atPath: directoryURL.path) {
            print("Files in Database Dir: \(directoryURL), \(files)")
        } else {
            print("Failed to list directory contents.")
        }
        
        let parentDirectory = destinationURL.deletingLastPathComponent()
        
        // TODO: CLOSE Store such that WAL and SHM are flushed and take backup of single sqlite store
        
        do {
            // create intermediate dirs as required
            try FileManager.default.createDirectory(at: parentDirectory,
                                                    withIntermediateDirectories: true,
                                                    attributes: nil)
            
            // Copy main SQLite file
            try fileManager.copyItem(at: storeURL, to: destinationURL)
            print("Core Data store exported to: \(destinationURL.path)")

            // Copy -shm and -wal files if they exist
            let additionalFiles = ["-shm", "-wal"].compactMap {
                storeURL.deletingPathExtension().appendingPathExtension(destinationURL.pathExtension + $0)
            }
            
            for file in additionalFiles where fileManager.fileExists(atPath: file.path) {
                let destination = destinationURL.deletingPathExtension() .appendingPathExtension(file.pathExtension)
                try fileManager.copyItem(at: file, to: destination)
                print("Core Data store exported to: \(destination.path)")
            }
            
            return destinationURL
            
        } catch {
            let errorDescription = "Failed to copy Core Data files: \(error.localizedDescription)"
            throw getCoreDataError(code: 6, localizedDescription: errorDescription)
        }
    }
}
