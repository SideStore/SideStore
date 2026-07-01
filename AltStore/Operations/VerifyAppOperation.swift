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

import RegexBuilder

private extension ALTEntitlement {
    static var ignoredEntitlements: Set<ALTEntitlement> = [
        .applicationIdentifier,
        .teamIdentifier
    ]
}

extension VerifyAppOperation {
    enum PermissionReviewMode {
        case none
        case all
        case added
    }
}

@objc(VerifyAppOperation)
final class VerifyAppOperation: ResultOperation<Void> {
    let permissionsMode: PermissionReviewMode
    let context: InstallAppOperationContext
    var customBundleId: String?
    
    init(permissionsMode: PermissionReviewMode, context: InstallAppOperationContext, customBundleId: String? = nil) {
        self.permissionsMode = permissionsMode
        self.context = context
        self.customBundleId = customBundleId
        
        super.init()
    }
    
    override func main() {
        super.main()
        
        do {
            if let error = self.context.error {
                throw error
            }
            let appName = self.context.app?.name ?? NSLocalizedString("The app", comment: "")
            self.localizedFailure = String(format: NSLocalizedString("%@ could not be installed.", comment: ""), appName)
            
            guard let app = self.context.app else {
                throw OperationError.invalidParameters("VerifyAppOperation.main: self.context.app is nil")
            }
            
            if !["ny.litritt.ignited", "com.litritt.ignited"].contains(where: { $0 == app.bundleIdentifier }) {
                let bundleId = customBundleId ?? app.bundleIdentifier
                guard bundleId == self.context.bundleIdentifier else {
                    throw VerificationError.mismatchedBundleIdentifiers(sourceBundleID: self.context.bundleIdentifier, app: app)
                }
            }
            
            guard ProcessInfo.processInfo.isOperatingSystemAtLeast(app.minimumiOSVersion) else {
                throw VerificationError.iOSVersionNotSupported(app: app, requiredOSVersion: app.minimumiOSVersion)
            }
            
            guard let appVersion = self.context.appVersion else {
                return self.finish(.success(()))
            }
            
            Task  {
                do {
                    guard let ipaURL = self.context.ipaURL else { throw OperationError.appNotFound(name: app.name) }
                                        
                    try await self.verifyHash(of: app, at: ipaURL, matches: appVersion)
                    try await self.verifyDownloadedVersion(of: app, matches: appVersion)
                    
                    // process missing permissions check only if the source is V2 or later
                    if let source = appVersion.app?.source,
                       source.isSourceAtLeastV2 {
                        try await self.verifyPermissions(of: app, match: appVersion)
                    }
                    
                    self.finish(.success(()))
                } catch {
                    self.finish(.failure(error))
                }
            }
        } catch {
            self.finish(.failure(error))
        }
    }
    
    private func verifyHash(of app: ALTApplication, at ipaURL: URL, @AsyncManaged matches appVersion: AppVersion) async throws {
        // Do nothing if source doesn't provide hash.
        guard let expectedHash = await $appVersion.sha256 else { return }

        let data = try Data(contentsOf: ipaURL)
        let sha256Hash = SHA256.hash(data: data)
        let hashString = sha256Hash.compactMap { String(format: "%02x", $0) }.joined()
        
        verboseLog("Comparing app hash (\(hashString)) against expected hash (\(expectedHash))...")
        
        guard hashString == expectedHash else { throw VerificationError.mismatchedHash(hashString, expectedHash: expectedHash, app: app) }
    }
    
    private func verifyDownloadedVersion(of app: ALTApplication, @AsyncManaged matches appVersion: AppVersion) async throws {
        let (version, buildVersion) = await $appVersion.perform {
            ($0.version, $0.buildVersion)
        }
        
        // marketplace buildVersion validation
        if let buildVersion {
            guard buildVersion == app.buildVersion else {
                throw VerificationError.mismatchedBuildVersion(app.buildVersion, expectedVersion: buildVersion, app: app)
            }
        }
        
        if version != app.version {
            throw VerificationError.mismatchedVersion(version: app.version, expectedVersion: version, app: app)
        }
    }
    
    private func verifyPermissions(of app: ALTApplication, @AsyncManaged match appVersion: AppVersion) async throws {
        guard self.permissionsMode != .none else { return }
        guard let storeApp = await $appVersion.app else { throw OperationError.invalidParameters("verifyPermissions requires storeApp to be non-nil") }
        
        // Verify source permissions match first.
        let allPermissions = try await self.verifyPermissions(of: app, match: storeApp)
        
        guard #available(iOS 15, *) else {
            // Only review downloaded app permissions on iOS 15 and above.
            return
        }
        
        switch self.permissionsMode {
        case .none: break
        case .all:
            guard let presentingViewController = self.context.presentingViewController else { break } // Don't fail just because we can't show permissions.
            
            let allEntitlements = allPermissions.compactMap { $0 as? ALTEntitlement }
            if !allEntitlements.isEmpty {
                try await self.review(allEntitlements, for: app, mode: .all, presentingViewController: presentingViewController)
            }
            
        case .added:
            let installedAppURL = InstalledApp.fileURL(for: app)
            guard let previousApp = ALTApplication(fileURL: installedAppURL) else { throw OperationError.appNotFound(name: app.name) }
            
            var previousEntitlements = Set(previousApp.entitlements.keys)
            for appExtension in previousApp.appExtensions {
                previousEntitlements.formUnion(appExtension.entitlements.keys)
            }
            
            // Make sure all entitlements already exist in previousApp.
            let addedEntitlements = Array(allPermissions.lazy.compactMap { $0 as? ALTEntitlement }.filter { !previousEntitlements.contains($0) })
            if !addedEntitlements.isEmpty {
                // _DO_ throw error if there isn't a presentingViewController.
                guard let presentingViewController = self.context.presentingViewController else { throw VerificationError.addedPermissions(addedEntitlements, appVersion: appVersion) }
                
                try await self.review(addedEntitlements, for: app, mode: .added, presentingViewController: presentingViewController)
            }
        }
    }
    
    @discardableResult
    private func verifyPermissions(of app: ALTApplication, @AsyncManaged match storeApp: StoreApp) async throws -> [any ALTAppPermission] {
        let entitlements = self.entitlements(for: app)
        let privacyPermissions = self.privacyPermissions(for: app)
        let localPermissions: [any ALTAppPermission] = Array(entitlements) + privacyPermissions
        
        try await self.verifyPermissions(localPermissions: localPermissions, match: storeApp, app: app)
        
        return localPermissions
    }

    private func entitlements(for app: ALTApplication) -> Set<ALTEntitlement> {
        var allEntitlements = Set(app.entitlements.keys)
        for appExtension in app.appExtensions {
            allEntitlements.formUnion(appExtension.entitlements.keys)
        }
        
        allEntitlements = allEntitlements.filter { !ALTEntitlement.ignoredEntitlements.contains($0) }
        
        if let isDebuggable = app.entitlements[.getTaskAllow] as? Bool, !isDebuggable {
            allEntitlements.remove(.getTaskAllow)
        }
        
        return allEntitlements
    }

    private func privacyPermissions(for app: ALTApplication) -> [ALTAppPrivacyPermission] {
        return ([app] + app.appExtensions).flatMap { (app) in
            let permissions = app.bundle.infoDictionary?.keys.compactMap { key -> ALTAppPrivacyPermission? in
                if #available(iOS 16, *) {
                    guard key.wholeMatch(of: Regex.privacyPermission) != nil else { return nil }
                } else {
                    guard key.contains("UsageDescription") else { return nil }
                }
                
                return ALTAppPrivacyPermission(rawValue: key)
            } ?? []
            
            return permissions
        }
    }

    private func verifyPermissions(localPermissions: [any ALTAppPermission], @AsyncManaged match storeApp: StoreApp, app: ALTApplication) async throws {
        let sourcePermissions: Set<AnyHashable> = Set(await $storeApp.perform {
            $0.permissions.map { AnyHashable($0.permission) }
        })

        let missingPermissions: [any ALTAppPermission] = localPermissions.filter { permission in
            if sourcePermissions.contains(AnyHashable(permission)) {
                return false
            } else if permission.type == .privacy {
                guard #available(iOS 16, *) else {
                    return false
                }
                
                if let match = permission.rawValue.firstMatch(of: Regex.privacyPermission),
                   case let legacyPermission = ALTAppPrivacyPermission(rawValue: String(match.1)),
                   sourcePermissions.contains(AnyHashable(legacyPermission)) {
                    return false
                }
            }
            
            return true
        }
        
        do {
            guard missingPermissions.isEmpty else {
                throw VerificationError.undeclaredPermissions(missingPermissions, app: app)
            }
        } catch let error as VerificationError where error.code == .undeclaredPermissions {
            if let recommendedSources = UserDefaults.shared.recommendedSources, let (sourceID, sourceURL) = await $storeApp.perform({
                $0.source.map { ($0.identifier, $0.sourceURL) }
            }) {
                let normalizedSourceURL = try? sourceURL.normalized()
                
                let isRecommended = recommendedSources.contains { $0.identifier == sourceID || (try? $0.sourceURL?.normalized()) == normalizedSourceURL }
                guard !isRecommended else {
                    return
                }
            }
            
            throw error
        }
    }
    
    @MainActor @available(iOS 15, *)
    private func review(_ permissions: [ALTEntitlement], for app: AppProtocol, mode: PermissionReviewMode, presentingViewController: UIViewController) async throws {
        let reviewPermissionsViewController = ReviewPermissionsViewController(app: app, permissions: permissions, mode: mode)
        let navigationController = UINavigationController(rootViewController: reviewPermissionsViewController)
        
        defer {
            navigationController.dismiss(animated: true)
        }
        
        try await withCheckedThrowingContinuation { continuation in
            reviewPermissionsViewController.completionHandler = { result in
                continuation.resume(with: result)
            }
            
            presentingViewController.present(navigationController, animated: true)
        }
    }

    private func debugLog(_ text: String) {
        print(text)
    }

    private func verboseLog(_ text: String) {
        let isLoggingEnabled = OperationsLoggingControl.getFromDatabase(for: VerifyAppOperation.self)
        if isLoggingEnabled {
            print(text)
        }
    }
}
