//
//  FileManager+SharedDirectories.swift
//  AltStore
//
//  Created by Riley Testut on 5/14/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation

public extension FileManager
{
    var altstoreSharedDirectory: URL? {
        // Prefer the app group read from the bundle's ALTAppGroups Info.plist key.
        // In the widget extension process on iOS 27+ Bundle.main refers to the
        // extension bundle, and the ALTAppGroups lookup can return nil if the
        // extension Info.plist hasn't been parsed yet or the entitlement resolver
        // is stricter. Fall back to constructing the well-known group ID directly
        // so the CoreData store URL is always resolved correctly.
        let appGroup = Bundle.main.altstoreAppGroup ?? Bundle.baseAltStoreAppGroupID
        
        let sharedDirectoryURL = self.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
        return sharedDirectoryURL
    }
    
    var appBackupsDirectory: URL? {
        let appBackupsDirectory = self.altstoreSharedDirectory?.appendingPathComponent("Backups", isDirectory: true)
        return appBackupsDirectory
    }
    
    func backupDirectoryURL(for app: InstalledApp) -> URL?
    {
        let backupDirectoryURL = self.appBackupsDirectory?.appendingPathComponent(app.bundleIdentifier, isDirectory: true)
        return backupDirectoryURL
    }
}
