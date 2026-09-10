//
//  FileManager+URLs.swift
//  AltStore
//
//  Created by Magesh K on 8/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation

public extension FileManager {
    var documentsDirectory: URL {
        #if os(tvOS)
        return self.cachesDirectory
        #else
        return self.urls(for: .documentDirectory, in: .userDomainMask).first!
        #endif
    }

    var libraryDirectory: URL {
        return self.urls(for: .libraryDirectory, in: .userDomainMask).first!
    }

    var applicationSupportDirectory: URL {
        return self.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    }

    var cachesDirectory: URL {
        return self.urls(for: .cachesDirectory, in: .userDomainMask).first!
    }

    func uniqueTemporaryURL() -> URL {
        let temporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let uniqueIdentifier = ProcessInfo.processInfo.globallyUniqueString
        return temporaryDirectoryURL.appendingPathComponent(uniqueIdentifier)
    }

    func prepareTemporaryURL(_ fileHandlingBlock: (URL) -> Void) {
        let temporaryURL = self.uniqueTemporaryURL()
        fileHandlingBlock(temporaryURL)
        do {
            try self.removeItem(at: temporaryURL)
        } catch {
            let nsError = error as NSError
            if nsError.domain != NSCocoaErrorDomain || nsError.code != NSFileNoSuchFileError {
                debugLog("[FileManager+URLs] Error removing temporary item: \(error)")
            }
        }
    }

    func copyItem(at sourceURL: URL, to destinationURL: URL, shouldReplace: Bool) throws {
        let destinationExists = self.fileExists(atPath: destinationURL.path)
        if !shouldReplace || !destinationExists {
            let parentDirectory = destinationURL.deletingLastPathComponent()
            if !self.fileExists(atPath: parentDirectory.path) {
                try self.createDirectory(at: parentDirectory, withIntermediateDirectories: true, attributes: nil)
            }
            try self.copyItem(at: sourceURL, to: destinationURL)
            return
        }

        let temporaryDirectory = try self.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: destinationURL, create: true)
        let temporaryURL = temporaryDirectory.appendingPathComponent(UUID().uuidString)
        
        let removeDirectory = {
            do {
                try self.removeItem(at: temporaryDirectory)
            } catch {
                debugLog("[FileManager+URLs] Error removing temporary directory: \(error)")
            }
        }

        do {
            try self.copyItem(at: sourceURL, to: temporaryURL)
            _ = try self.replaceItemAt(destinationURL, withItemAt: temporaryURL, backupItemName: nil, options: [])
            removeDirectory()
        } catch {
            removeDirectory()
            throw error
        }
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL, shouldReplace: Bool) throws {
        let destinationExists = self.fileExists(atPath: destinationURL.path)
        if destinationExists {
            if shouldReplace {
                try self.removeItem(at: destinationURL)
            } else {
                return
            }
        }
        let parentDirectory = destinationURL.deletingLastPathComponent()
        if !self.fileExists(atPath: parentDirectory.path) {
            try self.createDirectory(at: parentDirectory, withIntermediateDirectories: true, attributes: nil)
        }
        try self.moveItem(at: sourceURL, to: destinationURL)
    }
}
