//
//  FetchProvisioningProfilesOperation.swift
//  AltStore
//
//  Created by Riley Testut on 2/27/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation
import AltStoreCore
import AltSign
import CoreData


@objc(FetchProvisioningProfilesOperation)
class FetchProvisioningProfilesOperation: ResultOperation<[String: ALTProvisioningProfile]> {
    let context: AppOperationContext
    
    var additionalEntitlements: [ALTEntitlement: Any]?
    
    // this class is abstract or shouldn't be instantiated outside, use the subclasses
    fileprivate init(context: AppOperationContext) {
        self.context = context
        
        super.init()
        
        self.progress.totalUnitCount = 1
    }
    
    override func main() {
        super.main()
        
        Task.detached { [weak self] in
            guard let self else { return }
            do {
                let profiles = try await self.execute()
                self.finish(.success(profiles))
            } catch {
                self.finish(.failure(error))
            }
        }
    }
    
    private func execute() async throws -> [String: ALTProvisioningProfile] {
        if let error = self.context.error {
            throw error
        }
        
        guard let team = self.context.team,
              let session = self.context.session else {
            throw OperationError.invalidParameters("FetchProvisioningProfilesOperation.main: self.context.team or self.context.session is nil")
        }
        
        guard let app = self.context.app else { throw OperationError.appNotFound(name: nil) }
        
        self.debugLog("Fetching provisioning profiles for app \(self.context.bundleIdentifier)...")
        
        self.progress.totalUnitCount = Int64(1 + app.appExtensions.count)
        let effectiveBundleId = self.context.bundleIdentifier

        let profile = try await self.prepareProvisioningProfile(for: app, parentApp: nil, team: team, session: session)
        self.progress.completedUnitCount += 1
        
        var profiles = [effectiveBundleId: profile]
        
        if !self.context.useMainProfile {
            try await withThrowingTaskGroup(of: (String, ALTProvisioningProfile).self) { group in
                for appExtension in app.appExtensions {
                    group.addTask {
                        let extProfile = try await self.prepareProvisioningProfile(for: appExtension, parentApp: app, team: team, session: session)
                        // Use customized bundle ID if applicable
                        let updatedExtensionBundleId = appExtension.bundleIdentifier.replacingOccurrences(of: app.bundleIdentifier, with: effectiveBundleId)
                        return (updatedExtensionBundleId, extProfile)
                    }
                }
                
                for try await (bundleId, extProfile) in group {
                    profiles[bundleId] = extProfile
                    self.progress.completedUnitCount += 1
                }
            }
        }
        
        return profiles
    }
    
    func process<T>(_ result: Result<T, Error>) -> T? {
        switch result {
        case .failure(let error):
            self.finish(.failure(error))
            return nil
            
        case .success(let value):
            guard !self.isCancelled else {
                self.finish(.failure(OperationError.cancelled))
                return nil
            }
            
            return value
        }
    }
    
    internal func fetchProvisioningProfile(for appID: ALTAppID, app: ALTApplication, team: ALTTeam, session: ALTAppleAPISession) async throws -> ALTProvisioningProfile {
        let profile = try await ALTAppleAPI.shared.fetchProvisioningProfile(for: appID, deviceType: .iphone, team: team, session: session)
        
        do {
            // Delete existing profile
            try await ALTAppleAPI.shared.delete(profile, for: team, session: session)
            
            self.debugLog("Generating new free provisioning profile for App ID \(appID.bundleIdentifier).")
            
            // Fetch new provisioning profile
            return try await ALTAppleAPI.shared.fetchProvisioningProfile(for: appID, deviceType: .iphone, team: team, session: session)
        } catch {
            // As of March 20, 2023, the free provisioning profile is re-generated each fetch, and you can no longer delete it.
            // So instead, we just return the fetched profile from above.
            return profile
        }
    }
    
    private func fetchPreferredBundleID(for app: ALTApplication, team: ALTTeam) async throws -> String? {
        try await DatabaseManager.shared.persistentContainer.performBackgroundTask { [weak self] (context) -> String? in
            guard let self else { return nil }
            return self.preferredBundleID(for: app, team: team, in: context)
        }
    }
    
    private func preferredBundleID(for app: ALTApplication, team: ALTTeam, in context: NSManagedObjectContext) -> String? {
        // Check if we have already installed this app with this team before.
        let predicate = NSPredicate(format: "%K == %@", #keyPath(InstalledApp.bundleIdentifier), app.bundleIdentifier)
        guard let installedApp = InstalledApp.first(satisfying: predicate, in: context) else { return nil }
        
        // Teams match if installedApp.team has same identifier as team,
        // or if installedApp.team is nil but resignedBundleIdentifier contains the team's identifier.
        let teamsMatch = installedApp.team?.identifier == team.identifier || (installedApp.team == nil && installedApp.resignedBundleIdentifier.contains(team.identifier))
        
        // TODO: @mahee96: Try to keep the debug build and release build operations similar, refactor later with proper reasoning
        //                 for now, restricted it to debug on simulator only
        #if DEBUG && targetEnvironment(simulator)

        if app.isAltStoreApp {
            // Use legacy bundle ID format for AltStore.
            return teamsMatch ? installedApp.resignedBundleIdentifier : nil
        } else {
            return teamsMatch ? installedApp.resignedBundleIdentifier : nil
        }

        #else
        
        if teamsMatch {
            // This app is already installed with the same team, so use the same resigned bundle identifier as before.
            // This way, if we change the identifier format (again), AltStore will continue to use
            // the old bundle identifier to prevent it from installing as a new app.
            return installedApp.resignedBundleIdentifier
        } else {
            return nil
        }
        
        #endif
    }
    
    private func prepareProvisioningProfile(for app: ALTApplication,
                                    parentApp: ALTApplication?,
                                    team: ALTTeam,
                                    session: ALTAppleAPISession) async throws -> ALTProvisioningProfile {
        let preferredBundleID = try await self.fetchPreferredBundleID(for: app, team: team)
        
        let bundleID: String
        
        if let preferredBundleID = preferredBundleID {
            bundleID = preferredBundleID
        } else {
            // This app isn't already installed, so create the resigned bundle identifier ourselves.
            // Or, if the app _is_ installed but with a different team, we need to create a new
            // bundle identifier anyway to prevent collisions with the previous team.
            let parentBundleID = parentApp?.bundleIdentifier ?? app.bundleIdentifier
            let effectiveParentBundleID = self.context.bundleIdentifier

            let updatedParentBundleID: String

            if app.isAltStoreApp {
                // Use legacy bundle ID format for AltStore (and its extensions).
                updatedParentBundleID = effectiveParentBundleID + "." + team.identifier // Append just team identifier to make it harder to track.
            } else {
                updatedParentBundleID = effectiveParentBundleID + "." + team.identifier // Append just team identifier to make it harder to track.
            }

            if let parentApp = parentApp,
               app.bundleIdentifier.hasPrefix(parentBundleID + ".") {
                let suffix = String(app.bundleIdentifier.dropFirst(parentBundleID.count))
                bundleID = updatedParentBundleID + suffix
            } else {
                bundleID = updatedParentBundleID
            }
        }
        
        let preferredName: String
        
        if let parentApp = parentApp {
            preferredName = parentApp.name + " " + app.name
        } else {
            preferredName = app.name
        }
        
        // Register
        let appID = try await self.registerAppID(for: app, name: preferredName, bundleIdentifier: bundleID, team: team, session: session)
        
        // Fetch Provisioning Profile
        return try await self.fetchProvisioningProfile(for: appID, app: app, team: team, session: session)
    }
    
    private func registerAppID(for application: ALTApplication,
                               name: String,
                               bundleIdentifier: String,
                               team: ALTTeam,
                               session: ALTAppleAPISession) async throws -> ALTAppID {
        let appIDs = try await ALTAppleAPI.shared.fetchAppIDs(for: team, session: session)
        
        if let appID = appIDs.first(where: { $0.bundleIdentifier.lowercased() == bundleIdentifier.lowercased() }) {
            self.verboseLog("Using existing App ID \(appID.bundleIdentifier)")
            return appID
        } else {
            let requiredAppIDs = 1 + application.appExtensions.count
            let availableAppIDs = max(0, Team.maximumFreeAppIDs - appIDs.count)
            
            let sortedExpirationDates = appIDs.compactMap { $0.expirationDate }.sorted(by: { $0 < $1 })
            
            if team.type == .free {
                if requiredAppIDs > availableAppIDs {
                    if let expirationDate = sortedExpirationDates.first {
                        throw OperationError.maximumAppIDLimitReached(appName: application.name, requiredAppIDs: requiredAppIDs, availableAppIDs: availableAppIDs, expirationDate: expirationDate)
                    } else {
                        throw ALTAppleAPIError(.maximumAppIDLimitReached)
                    }
                }
            }
            //App ID name must be ascii. If the name is not ascii, using bundleID instead
            let appIDName: String
            if !name.allSatisfy({ $0.isASCII }) {
                //Contains non ASCII (Such as Chinese/Japanese...), using bundleID
                appIDName = bundleIdentifier
            } else {
                //ASCII text, keep going as usual
                appIDName = name
            }
            
            do {
                let appID = try await ALTAppleAPI.shared.addAppID(withName: appIDName, bundleIdentifier: bundleIdentifier, team: team, session: session)
                self.debugLog("Registered new App ID \(appID.bundleIdentifier)")
                return appID
            } catch ALTAppleAPIError.maximumAppIDLimitReached {
                if let expirationDate = sortedExpirationDates.first {
                    throw OperationError.maximumAppIDLimitReached(appName: application.name, requiredAppIDs: requiredAppIDs, availableAppIDs: availableAppIDs, expirationDate: expirationDate)
                } else {
                    throw ALTAppleAPIError(.maximumAppIDLimitReached)
                }
            } catch ALTAppleAPIError.bundleIdentifierUnavailable {
                let appIDs = try await ALTAppleAPI.shared.fetchAppIDs(for: team, session: session)
                if let appID = appIDs.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
                    return appID
                } else {
                    throw ALTError(.unknown)
                }
            }
        }
    }

    func debugLog(_ text: String) {
        print(text)
    }

    func verboseLog(_ text: String) {
        let isLoggingEnabled = OperationsLoggingControl.getFromDatabase(for: type(of: self))
        if isLoggingEnabled {
            print(text)
        }
    }
}

class FetchProvisioningProfilesInstallOperation: FetchProvisioningProfilesOperation, @unchecked Sendable {
    override init(context: AppOperationContext) {
        super.init(context: context)
    }
    
    // modify Operations are allowed for the app groups and other stuffs
    override func fetchProvisioningProfile(for appID: ALTAppID,
                                    app: ALTApplication,
                                    team: ALTTeam,
                                    session: ALTAppleAPISession) async throws -> ALTProvisioningProfile {
        
        // Update features
        let updatedAppID = try await self.updateFeatures(for: appID, app: app, team: team, session: session)
        
        // Update app groups
        let groupAppID = try await self.updateAppGroups(for: updatedAppID, app: app, team: team, session: session)
        
        // Fetch Provisioning Profile
        return try await super.fetchProvisioningProfile(for: groupAppID, app: app, team: team, session: session)
    }
    
    private func updateFeatures(for appID: ALTAppID, app: ALTApplication, team: ALTTeam, session: ALTAppleAPISession) async throws -> ALTAppID {
        var entitlements = app.entitlements
        for (key, value) in additionalEntitlements ?? [:] {
            entitlements[key] = value
        }
        
        let requiredFeatures = entitlements.compactMap { (entitlement, value) -> (ALTFeature, Any)? in
            guard let feature = ALTFeature(entitlement: entitlement) else { return nil }
            return (feature, value)
        }
        
        var features = requiredFeatures.reduce(into: [ALTFeature: Any]()) { $0[$1.0] = $1.1 }
        
        if let applicationGroups = entitlements[.appGroups] as? [String], !applicationGroups.isEmpty {
            // App uses app groups, so assign `true` to enable the feature.
            features[.appGroups] = true
        } else {
            // App has no app groups, so assign `false` to disable the feature.
            features[.appGroups] = false
        }
        
        var updateFeatures = false
        
        // Determine whether the required features are already enabled for the AppID.
        for (feature, value) in features {
            if let appIDValue = appID.features[feature] as AnyObject?, (value as AnyObject).isEqual(appIDValue) {
                // AppID already has this feature enabled and the values are the same.
                continue
            } else if appID.features[feature] == nil, let shouldEnableFeature = value as? Bool, !shouldEnableFeature {
                // AppID doesn't already have this feature enabled, but we want it disabled anyway.
                continue
            } else {
                // AppID either doesn't have this feature enabled or the value has changed,
                // so we need to update it to reflect new values.
                updateFeatures = true
                break
            }
        }
        
        appID.entitlements = entitlements
        
        if updateFeatures || true {
            let appIDCopy = appID.copy() as! ALTAppID
            appIDCopy.features = features
            
            do {
                let updated = try await ALTAppleAPI.shared.update(appIDCopy, team: team, session: session)
                self.verboseLog("Updated features for App ID \(updated.bundleIdentifier).")
                return updated
            } catch {
                self.debugLog("Failed to update features for App ID \(appIDCopy.bundleIdentifier). \(error.localizedDescription)")
                throw error
            }
        } else {
            return appID
        }
    }
    
    private func updateAppGroups(for appID: ALTAppID, app: ALTApplication, team: ALTTeam, session: ALTAppleAPISession) async throws -> ALTAppID {
        var entitlements = app.entitlements
        for (key, value) in additionalEntitlements ?? [:] {
            entitlements[key] = value
        }
                
        guard var applicationGroups = entitlements[.appGroups] as? [String], !applicationGroups.isEmpty else {
            verboseLog("App ID \(appID.bundleIdentifier) has no app groups, skipping assignment.")
            // Assigning an App ID to an empty app group array fails,
            // so just do nothing if there are no app groups.
            return appID
        }
        
        if app.isAltStoreApp {
            verboseLog("Application groups before modifying for SideStore: \(applicationGroups)")
            
            // Remove app groups that contain AltStore since they can be problematic (cause SideStore to expire early)
            for (index, group) in applicationGroups.enumerated() {
                if group.contains("AltStore") {
                    verboseLog("Removing application group: \(group)")
                    applicationGroups.remove(at: index)
                }
            }
            
            // Make sure we add .AltWidget for the widget
            var altStoreAppGroupID = Bundle.baseAltStoreAppGroupID
            for (_, group) in applicationGroups.enumerated() {
                if group.contains("AltWidget") {
                    altStoreAppGroupID += ".AltWidget"
                    break
                }
            }
            
            // Potentially updating app groups for this specific AltStore.
            // Find the (unique) AltStore app group, then replace it
            // with the correct "base" app group ID.
            // Otherwise, we may append a duplicate team identifier to the end.
            if let index = applicationGroups.firstIndex(where: { $0.contains(Bundle.baseAltStoreAppGroupID) }) {
                applicationGroups[index] = altStoreAppGroupID
            } else {
                applicationGroups.append(altStoreAppGroupID)
            }
        }
        verboseLog("Application groups: \(applicationGroups)")
        
        return try await TaskChainSerializer.shared.serialize {
            // Ensure we're not concurrently fetching and updating app groups,
            // which can lead to race conditions such as adding an app group twice.
            do {
                let fetchedGroups = try await ALTAppleAPI.shared.fetchAppGroups(for: team, session: session)
                
                var groups = [ALTAppGroup]()
                
                for groupIdentifier in applicationGroups {
                    let adjustedGroupIdentifier = groupIdentifier + "." + team.identifier
                    
                    if let group = fetchedGroups.first(where: { $0.groupIdentifier == adjustedGroupIdentifier }) {
                        groups.append(group)
                    } else {
                        // Not all characters are allowed in group names, so we replace periods with spaces (like Apple does).
                        let name = "AltStore " + groupIdentifier.replacingOccurrences(of: ".", with: " ")
                        do {
                            let group = try await ALTAppleAPI.shared.addAppGroup(withName: name, groupIdentifier: adjustedGroupIdentifier, team: team, session: session)
                            self.verboseLog("Created new App Group \(group.groupIdentifier).")
                            groups.append(group)
                        } catch {
                            self.debugLog("Failed to create new App Group \(adjustedGroupIdentifier). \(error.localizedDescription)")
                            throw error
                        }
                    }
                }
                
                try await ALTAppleAPI.shared.assign(appID, to: Array(groups), team: team, session: session)
                let groupIDs = groups.map { $0.groupIdentifier }
                self.verboseLog("Assigned App ID \(appID.bundleIdentifier) to App Groups \(groupIDs.description).")
                
                return appID
            } catch {
                let groupIDs = applicationGroups.map { $0 + "." + team.identifier }
                self.debugLog("Failed to assign/create App Groups for App ID \(appID.bundleIdentifier): \(error.localizedDescription)")
                throw error
            }
        }
    }
}

// <TEST> : users were reporting that refresh (though seemed like it refreshed the app becomes no longer available)
//          possibly, this is caused since refesh was not updating appFeatures and AppGroups in the new profile? not sure.
//          for now we are reverting by keeping same operation that happens during fetch in install path to see if it fixes issue #893
// class FetchProvisioningProfilesRefreshOperation: FetchProvisioningProfilesOperation, @unchecked Sendable {
class FetchProvisioningProfilesRefreshOperation: FetchProvisioningProfilesInstallOperation, @unchecked Sendable {
    override init(context: AppOperationContext) {
        super.init(context: context)
    }
}

extension ALTAppleAPI {
    func fetchProvisioningProfile(for appID: ALTAppID, deviceType: ALTDeviceType, team: ALTTeam, session: ALTAppleAPISession) async throws -> ALTProvisioningProfile {
        try await withCheckedThrowingContinuation { continuation in
            self.fetchProvisioningProfile(for: appID, deviceType: deviceType, team: team, session: session) { (profile, error) in
                if let profile = profile {
                    continuation.resume(returning: profile)
                } else {
                    continuation.resume(throwing: error ?? OperationError.unknown())
                }
            }
        }
    }
    
    func delete(_ profile: ALTProvisioningProfile, for team: ALTTeam, session: ALTAppleAPISession) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.delete(profile, for: team, session: session) { (success, error) in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? OperationError.unknown())
                }
            }
        }
    }
    
    func fetchAppIDs(for team: ALTTeam, session: ALTAppleAPISession) async throws -> [ALTAppID] {
        try await withCheckedThrowingContinuation { continuation in
            self.fetchAppIDs(for: team, session: session) { (appIDs, error) in
                if let appIDs = appIDs {
                    continuation.resume(returning: appIDs)
                } else {
                    continuation.resume(throwing: error ?? OperationError.unknown())
                }
            }
        }
    }
    
    func addAppID(withName name: String, bundleIdentifier: String, team: ALTTeam, session: ALTAppleAPISession) async throws -> ALTAppID {
        try await withCheckedThrowingContinuation { continuation in
            self.addAppID(withName: name, bundleIdentifier: bundleIdentifier, team: team, session: session) { (appID, error) in
                if let appID = appID {
                    continuation.resume(returning: appID)
                } else {
                    continuation.resume(throwing: error ?? OperationError.unknown())
                }
            }
        }
    }
    
    func update(_ appID: ALTAppID, team: ALTTeam, session: ALTAppleAPISession) async throws -> ALTAppID {
        try await withCheckedThrowingContinuation { continuation in
            self.update(appID, team: team, session: session) { (updatedAppID, error) in
                if let updatedAppID = updatedAppID {
                    continuation.resume(returning: updatedAppID)
                } else {
                    continuation.resume(throwing: error ?? OperationError.unknown())
                }
            }
        }
    }
    
    func fetchAppGroups(for team: ALTTeam, session: ALTAppleAPISession) async throws -> [ALTAppGroup] {
        try await withCheckedThrowingContinuation { continuation in
            self.fetchAppGroups(for: team, session: session) { (groups, error) in
                if let groups = groups {
                    continuation.resume(returning: groups)
                } else {
                    continuation.resume(throwing: error ?? OperationError.unknown())
                }
            }
        }
    }
    
    func addAppGroup(withName name: String, groupIdentifier: String, team: ALTTeam, session: ALTAppleAPISession) async throws -> ALTAppGroup {
        try await withCheckedThrowingContinuation { continuation in
            self.addAppGroup(withName: name, groupIdentifier: groupIdentifier, team: team, session: session) { (group, error) in
                if let group = group {
                    continuation.resume(returning: group)
                } else {
                    continuation.resume(throwing: error ?? OperationError.unknown())
                }
            }
        }
    }
    
    func assign(_ appID: ALTAppID, to groups: [ALTAppGroup], team: ALTTeam, session: ALTAppleAPISession) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.assign(appID, to: groups, team: team, session: session) { (success, error) in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? OperationError.unknown())
                }
            }
        }
    }
}
