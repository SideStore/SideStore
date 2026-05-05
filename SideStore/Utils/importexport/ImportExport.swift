//
//  ImportExport.swift
//  AltStore
//
//  Created by Magesh K on 07/01/25.
//  Copyright © 2025 SideStore. All rights reserved.
//


import UIKit
import AltStoreCore

class ImportExport {
    
    public static var documentPickerHandler: DocumentPickerHandler?
    
    public static func getPreviousBackupURL(_ backupURL: URL) -> URL {
        let backupParentDirectory = backupURL.deletingLastPathComponent()
        let backupName = backupURL.lastPathComponent
        let backupBakURL = backupParentDirectory.appendingPathComponent("\(backupName).bak")
        return backupBakURL
    }
    
    /// Renames the existing backup contents at `backupURL` to `<foldername>.bak`.
    private static func renameBackupContents(at backupURL: URL) throws {
        
        // rename backup to backup.bak dir only if backup dir exists
        guard FileManager.default.fileExists(atPath: backupURL.path) else { return }
        
        let backupBakURL = getPreviousBackupURL(backupURL)
        
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: backupBakURL.path) {
            try fileManager.removeItem(at: backupBakURL) // Remove any existing .bak directory
        }
        
        try fileManager.moveItem(at: backupURL, to: backupBakURL)
    }
    
    /// Handles importing new backup data into the designated backup directory.
    private static func importBackupContents(from documentPickerURL: URL, to backupURL: URL) throws {
        let fileManager = FileManager.default
        
        // Ensure the backup directory exists.
        if !fileManager.fileExists(atPath: backupURL.path) {
            try fileManager.createDirectory(at: backupURL, withIntermediateDirectories: true, attributes: nil)
        }
        
        print("Backup URL: \(backupURL)")
        print("Document Picker URL: \(documentPickerURL)")
        
        // Enumerate the contents of the selected directory and copy them to the backup directory.
        let selectedContents = try fileManager.contentsOfDirectory(
            at: documentPickerURL,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )
        for itemURL in selectedContents {
            let destinationURL = backupURL.appendingPathComponent(itemURL.lastPathComponent)
            
            // Remove the existing file if it exists at the destination.
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            
            // Copy the item.
            try fileManager.copyItem(at: itemURL, to: destinationURL)
        }
    }
    
    public static func importBackup(presentingViewController: UIViewController,
                                    for installedApp: InstalledApp,
                                    completionHandler: @escaping (Result<Void, Error>) -> Void){
        guard let backupURL = FileManager.default.backupDirectoryURL(for: installedApp) else {
            return completionHandler(.failure(OperationError.invalidParameters("Error: Backup directory URL not found.")))
        }
        
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        documentPicker.allowsMultipleSelection = false
                
        // Create a handler and set it as the delegate
        Self.documentPickerHandler = DocumentPickerHandler { selectedURL in
            guard let selectedURL = selectedURL else {
                return completionHandler(.failure( OperationError.cancelled))
            }
            
            // resolve symlinks if any, so that prefix match works
            let appUserDataDir = FileManager.default.documentsDirectory.resolvingSymlinksInPath()
            guard selectedURL.resolvingSymlinksInPath().path.hasPrefix(appUserDataDir.path) else {
                return completionHandler(.failure(
                    OperationError.forbidden(failureReason: "Selected backup data directory is not within the app's user data directory"))
                )
            }
            
            do {
                // Rename existing backup contents to `<foldername>.bak`.
                try Self.renameBackupContents(at: backupURL)
                
                // Import the contents of the selected folder into the backup directory.
                try Self.importBackupContents(from: selectedURL, to: backupURL)
                
                print("Backup imported successfully to:", backupURL.path)
                return completionHandler(.success(()))
            } catch {
                print("Backup Error:", error)
                return completionHandler(.failure( OperationError.invalidParameters(error.localizedDescription)))
            }
        }
        
        documentPicker.delegate = Self.documentPickerHandler
        // Present the picker
        presentingViewController.present(documentPicker, animated: true, completion: nil)
    }
}

private struct AssociatedKeys {
    static var documentPickerHandler = "documentPickerHandler"
}


class DocumentPickerHandler: NSObject, UIDocumentPickerDelegate {
    private let completion: (URL?) -> Void

    init(completion: @escaping (URL?) -> Void) {
        self.completion = completion
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        completion(urls.first)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        completion(nil)
    }
}
