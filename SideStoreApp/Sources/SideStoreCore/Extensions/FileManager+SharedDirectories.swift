//
//  FileManager+SharedDirectories.swift
//  AltStore
//
//  Created by Riley Testut on 5/14/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation


public extension FileManager {
    var altstoreSharedDirectory: URL? {
		#if SWIFT_PACKAGE
		guard let appGroup = Bundle.main.appGroups.first else { return nil }
		#else
		guard let appGroup = Bundle.main.appGroups.first else { return nil }
		#endif
        let sharedDirectoryURL = containerURL(forSecurityApplicationGroupIdentifier: appGroup)
        return sharedDirectoryURL
    }

    var appBackupsDirectory: URL? {
        let appBackupsDirectory = altstoreSharedDirectory?.appendingPathComponent("Backups", isDirectory: true)
        return appBackupsDirectory
    }

    func backupDirectoryURL(for app: InstalledApp) -> URL? {
        let backupDirectoryURL = appBackupsDirectory?.appendingPathComponent(app.bundleIdentifier, isDirectory: true)
        return backupDirectoryURL
    }
}
