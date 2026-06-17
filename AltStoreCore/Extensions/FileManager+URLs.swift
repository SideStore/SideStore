//
//  FileManager+URLs.swift
//  AltStoreCore
//
//  Created by Magesh K on 06/17/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation

public extension FileManager {
    var documentsDirectory: URL {
        return self.urls(for: .documentDirectory, in: .userDomainMask).first!
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
                print("[FileManager+URLs] Error removing temporary item: \(error)")
            }
        }
    }

    func copyItem(at sourceURL: URL, to destinationURL: URL, shouldReplace: Bool) throws {
        if !shouldReplace {
            try self.copyItem(at: sourceURL, to: destinationURL)
            return
        }

        let temporaryDirectory = try self.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: destinationURL, create: true)
        let temporaryURL = temporaryDirectory.appendingPathComponent(UUID().uuidString)
        
        let removeDirectory = {
            do {
                try self.removeItem(at: temporaryDirectory)
            } catch {
                print("[FileManager+URLs] Error removing temporary directory: \(error)")
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
}
