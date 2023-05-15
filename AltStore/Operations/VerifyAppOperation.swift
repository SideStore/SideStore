//
//  VerifyAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 5/2/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation
import CryptoKit

import AltStoreCore
import AltSign
import Roxas

extension VerificationError
{
    enum Code: Int, ALTErrorCode, CaseIterable {
        typealias Error = VerificationError

        case privateEntitlements
        case mismatchedBundleIdentifiers
        case iOSVersionNotSupported
    }

    static func privateEntitlements(_ entitlements: [String: Any], app: ALTApplication) -> VerificationError {
        VerificationError(code: .privateEntitlements, app: app, entitlements: entitlements)
    }

    static func mismatchedBundleIdentifiers(sourceBundleID: String, app: ALTApplication) -> VerificationError {
        VerificationError(code: .mismatchedBundleIdentifiers, app: app, sourceBundleID: sourceBundleID)
    }

    static func iOSVersionNotSupported(app: AppProtocol, osVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion, requiredOSVersion: OperatingSystemVersion?) -> VerificationError {
        VerificationError(code: .iOSVersionNotSupported, app: app)
    }
}

struct VerificationError: ALTLocalizedError {
    let code: Code

    var errorTitle: String?
    var errorFailure: String?
    @Managed var app: AppProtocol?
    var sourceBundleID: String?
    var deviceOSVersion: OperatingSystemVersion?
    var requiredOSVersion: OperatingSystemVersion?
    
    var errorDescription: String? {
        switch self.code {
        case .iOSVersionNotSupported:
            guard let deviceOSVersion else { return nil }

            var failureReason = self.errorFailureReason
            if self.app == nil {
                let firstLetter = failureReason.prefix(1).lowercased()
                failureReason = firstLetter + failureReason.dropFirst()
            }

            return String(formatted: "This device is running iOS %@, but %@", deviceOSVersion.stringValue, failureReason)
        default: return nil
        }
        
        return self.errorFailureReason
    }

    var errorFailureReason: String {
        switch self.code
        {
        case .privateEntitlements:
            let appName = self.$app.name ?? NSLocalizedString("The app", comment: "")
            return String(formatted: "“%@” requires private permissions.", appName)

        case .mismatchedBundleIdentifiers:
            if let appBundleID = self.$app.bundleIdentifier, let bundleID = self.sourceBundleID {
                return String(formatted: "The bundle ID '%@' does not match the one specified by the source ('%@').", appBundleID, bundleID)
            } else {
                return NSLocalizedString("The bundle ID does not match the one specified by the source.", comment: "")
            }

        case .iOSVersionNotSupported:
            let appName = self.$app.name ?? NSLocalizedString("The app", comment: "")
            let deviceOSVersion = self.deviceOSVersion ?? ProcessInfo.processInfo.operatingSystemVersion

            guard let requiredOSVersion else {
                return String(formatted: "%@ does not support iOS %@.", appName, deviceOSVersion.stringValue)
            }
            if deviceOSVersion > requiredOSVersion {
                return String(formatted: "%@ requires iOS %@ or earlier", appName, requiredOSVersion.stringValue)
            } else {
                return String(formatted: "%@ requires iOS %@ or later", appName, requiredOSVersion.stringValue)
            }
        }
    }
}

import RegexBuilder

private extension ALTEntitlement
{
    static var ignoredEntitlements: Set<ALTEntitlement> = [
        .applicationIdentifier,
        .teamIdentifier
    ]
}

extension VerifyAppOperation
{
    enum PermissionReviewMode
    {
        case none
        case all
        case added
    }
}

@objc(VerifyAppOperation)
final class VerifyAppOperation: ResultOperation<Void>
{
    let permissionsMode: PermissionReviewMode
    let context: InstallAppOperationContext
    
    init(permissionsMode: PermissionReviewMode, context: InstallAppOperationContext)
    {
        self.permissionsMode = permissionsMode
        self.context = context
        
        super.init()
    }
    
    override func main()
    {
        super.main()
        
        do
        {
            if let error = self.context.error
            {
                throw error
            }
            let appName = self.context.app?.name ?? NSLocalizedString("The app", comment: "")
            self.localizedFailure = String(format: NSLocalizedString("%@ could not be installed.", comment: ""), appName)
            
            guard let app = self.context.app else {
                throw OperationError.invalidParameters("VerifyAppOperation.main: self.context.app is nil")
            }
            
            if !["ny.litritt.ignited", "com.litritt.ignited"].contains(where: { $0 == app.bundleIdentifier }) {
                guard app.bundleIdentifier == self.context.bundleIdentifier else {
                    throw VerificationError.mismatchedBundleIdentifiers(sourceBundleID: self.context.bundleIdentifier, app: app)
                }
            }
            
            guard ProcessInfo.processInfo.isOperatingSystemAtLeast(app.minimumiOSVersion) else {
                throw VerificationError.iOSVersionNotSupported(app: app, requiredOSVersion: app.minimumiOSVersion)
            }
            
            guard let appVersion = self.context.appVersion else {
                return self.finish(.success(()))
            }
            
            Task<Void, Never>  {
                do
                {
                    guard let ipaURL = self.context.ipaURL else { throw OperationError.appNotFound(name: app.name) }
                    
                    try await self.verifyHash(of: app, at: ipaURL, matches: appVersion)
                    try await self.verifyDownloadedVersion(of: app, matches: appVersion)
                    try await self.verifyPermissions(of: app, match: appVersion)
                    
                    self.finish(.success(()))
                }
                catch
                {
                    self.finish(.failure(error))
                }
            }
        }
        catch
        {
            self.finish(.failure(error))
        }
    }
}

private extension VerifyAppOperation
{
    func verifyHash(of app: ALTApplication, at ipaURL: URL, @AsyncManaged matches appVersion: AppVersion) async throws
    {
        // Do nothing if source doesn't provide hash.
        guard let expectedHash = await $appVersion.sha256 else { return }

        let data = try Data(contentsOf: ipaURL)
        let sha256Hash = SHA256.hash(data: data)
        let hashString = sha256Hash.compactMap { String(format: "%02x", $0) }.joined()

        print("[ALTLog] Comparing app hash (\(hashString)) against expected hash (\(expectedHash))...")

        guard hashString == expectedHash else { throw VerificationError.mismatchedHash(hashString, expectedHash: expectedHash, app: app) }
    }
    
    func verifyDownloadedVersion(of app: ALTApplication, @AsyncManaged matches appVersion: AppVersion) async throws
    {
        let version = await $appVersion.version
        
        guard version == app.version else { throw VerificationError.mismatchedVersion(app.version, expectedVersion: version, app: app) }
    }
    
    func verifyPermissions(of app: ALTApplication, @AsyncManaged match appVersion: AppVersion) async throws
    {
        guard self.permissionsMode != .none else { return }
        guard let storeApp = await $appVersion.app else { throw OperationError.invalidParameters }
        
        // Verify source permissions match first.
        let allPermissions = try await self.verifyPermissions(of: app, match: storeApp)
        
        switch self.permissionsMode
        {
        case .none, .all: break
        case .added:
            let installedAppURL = InstalledApp.fileURL(for: app)
            guard let previousApp = ALTApplication(fileURL: installedAppURL) else { throw OperationError.appNotFound(name: app.name) }
            
            var previousEntitlements = Set(previousApp.entitlements.keys)
            for appExtension in previousApp.appExtensions
            {
                previousEntitlements.formUnion(appExtension.entitlements.keys)
            }
            
            // Make sure all entitlements already exist in previousApp.
            let addedEntitlements = Array(allPermissions.lazy.compactMap { $0 as? ALTEntitlement }.filter { !previousEntitlements.contains($0) })
            guard addedEntitlements.isEmpty else { throw VerificationError.addedPermissions(addedEntitlements, app: appVersion) }
        }
    }
    
    @discardableResult
    func verifyPermissions(of app: ALTApplication, @AsyncManaged match storeApp: StoreApp) async throws -> [any ALTAppPermission]
    {
        // Entitlements
        var allEntitlements = Set(app.entitlements.keys)
        for appExtension in app.appExtensions
        {
            allEntitlements.formUnion(appExtension.entitlements.keys)
        }
             
        // Filter out ignored entitlements.
        allEntitlements = allEntitlements.filter { !ALTEntitlement.ignoredEntitlements.contains($0) }
        
        
        // Background Modes
        // App extensions can't have background modes, so don't need to worry about them.
        let allBackgroundModes: Set<ALTAppBackgroundMode>
        if let backgroundModes = app.bundle.infoDictionary?[Bundle.Info.backgroundModes] as? [String]
        {
            let backgroundModes = backgroundModes.lazy.map { ALTAppBackgroundMode($0) }
            allBackgroundModes = Set(backgroundModes)
        }
        else
        {
            allBackgroundModes = []
        }
        
        
        // Privacy
        let allPrivacyPermissions: Set<ALTAppPrivacyPermission>
        if #available(iOS 16, *)
        {
            let regex = Regex {
                "NS"
                
                // Capture permission "name"
                Capture {
                    OneOrMore(.anyGraphemeCluster)
                }
                
                "UsageDescription"
                
                // Optional suffix
                Optionally(OneOrMore(.anyGraphemeCluster))
            }
            
            let privacyPermissions = ([app] + app.appExtensions).flatMap { (app) in
                let permissions = app.bundle.infoDictionary?.keys.compactMap { key -> ALTAppPrivacyPermission? in
                    guard let match = key.wholeMatch(of: regex) else { return nil }
                    
                    let permission = ALTAppPrivacyPermission(rawValue: String(match.1))
                    return permission
                } ?? []
                 
                return permissions
            }
            
            allPrivacyPermissions = Set(privacyPermissions)
        }
        else
        {
            allPrivacyPermissions = []
        }
        
        
        // Verify permissions.
        let sourcePermissions: Set<AnyHashable> = Set(await $storeApp.perform { $0.permissions.map { AnyHashable($0.permission) } })
        let localPermissions: [any ALTAppPermission] = Array(allEntitlements) + Array(allBackgroundModes) + Array(allPrivacyPermissions)
        
        // To pass: EVERY permission in localPermissions must also appear in sourcePermissions.
        // If there is a single missing permission, throw error.
        let missingPermissions: [any ALTAppPermission] = localPermissions.filter { !sourcePermissions.contains(AnyHashable($0)) }
        guard missingPermissions.isEmpty else { throw VerificationError.undeclaredPermissions(missingPermissions, app: app) }
        
        return localPermissions
    }
}
