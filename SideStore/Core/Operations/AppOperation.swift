//
//  AppOperation.swift
//  SideStore
//
//  Created by Magesh K on 7/30/26.
//  Copyright © 2026 SideStore. All rights reserved.
//


import Foundation
import CoreData

enum AppOperation: CustomStringConvertible
{
    case install(AppProtocol, customBundleIdentifier: String? = nil)
    case update(AppProtocol, customBundleIdentifier: String? = nil)
    case refresh(InstalledApp)
    case activate(InstalledApp)
    case deactivate(InstalledApp)
    case deleteApp(InstalledApp)
    case backup(InstalledApp)
    case restore(InstalledApp)
    case resign(InstalledApp, alternateIconMode: AlternateIconMode = .preserve)
    case removeApp(InstalledApp)
    case removeDeactivatedApp(InstalledApp)
    
    var rawValue: String {
        switch self
        {
        case .install:              return "install"
        case .update:               return "update"
        case .refresh:              return "refresh"
        case .activate:             return "activate"
        case .deactivate:           return "deactivate"
        case .deleteApp:            return "deleteApp"
        case .backup:               return "backup"
        case .restore:              return "restore"
        case .resign:               return "resign"
        case .removeApp:            return "removeApp"
        case .removeDeactivatedApp: return "removeDeactivatedApp"
        }
    }
    
    var description: String {
        return self.rawValue
    }
    
    func logSummary(status: String, elapsed: Double, error: Error? = nil) {
        logOperationSummary(
            operation: self.rawValue,
            target: self.bundleIdentifier,
            status: status,
            elapsed: elapsed,
            error: error
        )
    }
    
    var app: AppProtocol {
        switch self
        {
        case .install(let app, _), .update(let app, _):
            return app
        case .refresh(let app), .activate(let app), .deactivate(let app), .deleteApp(let app),
             .backup(let app),  .restore(let app),  .resign(let app, _),
             .removeApp(let app), .removeDeactivatedApp(let app):
            return app
        }
    }
    
    var bundleIdentifier: String {
        var bundleIdentifier: String!
        
        if let context = (self.app as? NSManagedObject)?.managedObjectContext
        {
            context.performAndWait { bundleIdentifier = self.app.bundleIdentifier }
        }
        else
        {
            bundleIdentifier = self.app.bundleIdentifier
        }
        
        return bundleIdentifier
    }

    var loggedErrorOperation: LoggedError.Operation {
        switch self
        {
        case .install: return .install
        case .update: return .update
        case .refresh: return .refresh
        case .activate: return .activate
        case .deactivate: return .deactivate
        case .deleteApp: return .deactivate
        case .backup: return .backup
        case .restore: return .restore
        case .resign: return .resign
        case .removeApp, .removeDeactivatedApp: return .remove
        }
    }
}
