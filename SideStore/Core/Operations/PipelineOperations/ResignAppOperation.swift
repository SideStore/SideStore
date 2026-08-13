//
//  ResignAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 6/7/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

@preconcurrency import UIKit
import Foundation
@preconcurrency import AltSign

final class ResignAppOperation: BasePipelineOperation<InstallAppOperationContext, ALTApplication>, @unchecked Sendable {
    
    override func execute(parentProgress: Progress?) async throws -> ALTApplication {
        debugLog("[ResignAppOperation] execute() started")
        defer { debugLog("[ResignAppOperation] execute() completed") }
        try await super.executePreconditionCheck(parentProgress: parentProgress)
        
        guard
            let appBundle = self.context.targetAppBundle,
            let profiles = self.context.provisioningProfiles,
            let team = self.context.authenticatedContext.team,
            let certificate = self.context.overrideCertificate ?? self.context.authenticatedContext.signingCertificate
        else {
            throw OperationError.invalidParameters("ResignAppOperation.main: " +
                                                   "self.context.authenticatedContext.team or " +
                                                   "self.context.provisioningProfiles or " +
                                                   "self.context.authenticatedContext.signingCertificate is nil")
        }
        
        debugLog("[ResignAppOperation] Resigning app \(self.context.bundleIdentifier)...")
        
        self.setProgress(5)
        
        let effectiveBundleId = self.context.targetBundleIdentifier
        
        let appBundleURL = try await self.prepareAppBundle(for: appBundle, profiles: profiles, appexBundleIds: context.appexBundleIds ?? [:])
        
        self.setProgress(40)
        
        let resignedURL = try await self.resignAppBundle(at: appBundleURL, team: team, certificate: certificate, profiles: Array(profiles.values))
        
        let updatedApp = AnyApp(
            name: appBundle.name,
            bundleIdentifier: effectiveBundleId,
            url: appBundle.fileURL,
            storeApp: appBundle.storeApp
        )
        let destinationURL = InstalledApp.refreshedIPAURL(for: updatedApp)
        try FileManager.default.copyItem(at: resignedURL, to: destinationURL, shouldReplace: true)
        self.debugLog("[ResignAppOperation] Successfully resigned app to \(destinationURL.absoluteString)")
        
        // Use appBundleURL since we need an app bundle, not .ipa.
        guard let resignedAppBundle = ALTApplication(fileURL: appBundleURL) else { throw OperationError.invalidApp }
        
        self.debugLog("[ResignAppOperation] Resigned app \(self.context.bundleIdentifier) to \(resignedAppBundle.bundleIdentifier).")
        
        self.setProgress(100)
        
        return resignedAppBundle
    }

    
    private func prepareAppBundle(for targetAppBundle: ALTApplication, profiles: [String: ALTProvisioningProfile], appexBundleIds: [String: String]) async throws -> URL {

        let bundleIdentifier = context.targetBundleIdentifier
        let finalBundleIdentifier: String
        if let profile = context.useMainProfile ? profiles.values.first : profiles[bundleIdentifier] {
            finalBundleIdentifier = profile.bundleIdentifier
        } else {
            finalBundleIdentifier = bundleIdentifier
        }
        
        // Use customized bundle ID if applicable
        let openURL = InstalledApp.openAppURL(for: AnyApp(from: targetAppBundle, bundleId: finalBundleIdentifier))
        let fileURL = targetAppBundle.fileURL

        let appBundleURL = self.context.temporaryDirectory.appendingPathComponent("App.app")
        if fileURL.path != appBundleURL.path {
            if FileManager.default.fileExists(atPath: appBundleURL.path) {
                try FileManager.default.removeItem(at: appBundleURL)
            }
            try FileManager.default.copyItem(at: fileURL, to: appBundleURL)
        }
        
        guard let appBundle = Bundle(url: appBundleURL) else { throw ALTError(.missingAppBundle) }
        guard let infoDictionary = appBundle.completeInfoDictionary else { throw ALTError(.missingInfoPlist) }
        
        // replace scheme targets to match the bundle suffix so multiple instances can be correctly routed for helper apps like SideBackup
        var allURLSchemes = infoDictionary[Bundle.Info.urlTypes] as? [[String: Any]] ?? []
        allURLSchemes.removeAll { urlType in
            guard let schemes = urlType["CFBundleURLSchemes"] as? [String] else { return false }
            return schemes.contains { $0.hasPrefix("sidestore-") }
        }
        
        let altstoreURLScheme = ["CFBundleTypeRole": "Editor",
                                 "CFBundleURLName": finalBundleIdentifier,
                                 "CFBundleURLSchemes": [openURL.scheme!]] as [String : Any]
        allURLSchemes.append(altstoreURLScheme)
        
        var additionalValues: [String: Any] = [Bundle.Info.urlTypes: allURLSchemes]

        if targetAppBundle.isAltStoreApp {
            guard let udid = try await fetchUDID() else { throw OperationError.unknownUDID }
            guard Bundle.main.object(forInfoDictionaryKey: Bundle.Info.devicePairingString) is String else { throw OperationError.unknownUDID }
            additionalValues[Bundle.Info.devicePairingString] = "<insert pairing file here>"
            additionalValues[Bundle.Info.deviceID] = udid
            additionalValues[Bundle.Info.serverID] = UserDefaults.standard.preferredServerID
            
            if let activeCert = CertificateManager.shared.activeCertificate {
                additionalValues[Bundle.Info.certificateID] = activeCert.serialNumber
                try activeCert.p12Data.write(to: appBundle.certificateURL, options: .atomic)
            } else {
                self.verboseLog("[ResignAppOperation] No activeCertificate found in CertificateManager. Embedded certificate + certificate identifier in app bundle will not be updated.")
            }
        } else if infoDictionary.keys.contains(Bundle.Info.deviceID), let udid = try await fetchUDID() {
            // There is an ALTDeviceID entry, so assume the app is using AltKit and replace it with the device's UDID.
            additionalValues[Bundle.Info.deviceID] = udid
            additionalValues[Bundle.Info.serverID] = UserDefaults.standard.preferredServerID
        }
        
        // Prepare app
        try self.prepare(appBundle, bundleID: bundleIdentifier, additionalInfoDictionaryValues: additionalValues, profiles: profiles, appexBundleIds: appexBundleIds)
        try self.removeMissingAppExtensionReferences(from: appBundle)
        
        if let directory = appBundle.builtInPlugInsURL, let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil, options: [.skipsSubdirectoryDescendants]) {
            for case let fileURL as URL in enumerator {
                // Only strip SideStore's own debug test products. Imported XCTest runners need their .xctest bundle at runtime.
                #if DEBUG
                let isOwnTestArtifact = targetAppBundle.isAltStoreApp && fileURL.pathExtension.lowercased() == "xctest"
                if isOwnTestArtifact {
                    // Remove embedded XCTest (+ dSYM) bundle from copied app bundle.
                    try FileManager.default.removeItem(at: fileURL)
                    continue
                }
                #endif
                
                guard let appExtension = Bundle(url: fileURL) else { throw ALTError(.missingAppBundle) }
                let updatedAppExBundleId = appExtension.bundleIdentifier?.replacingOccurrences(of: targetAppBundle.bundleIdentifier, with: bundleIdentifier)
                try self.prepare(appExtension, bundleID: updatedAppExBundleId, profiles: profiles, appexBundleIds: appexBundleIds)
            }
        }
        
        return appBundleURL
    }
    
    private func prepare(_ bundle: Bundle, bundleID identifier: String?, additionalInfoDictionaryValues: [String: Any] = [:], profiles: [String: ALTProvisioningProfile], appexBundleIds: [String: String]) throws {
        guard let identifier else {
            throw ALTError(.missingAppBundle)
        }
        guard let profile = context.useMainProfile ? profiles.values.first : profiles[identifier] else {
            throw ALTError(.missingProvisioningProfile)
        }
        guard var infoDictionary = bundle.completeInfoDictionary else {
            throw ALTError(.missingInfoPlist)
        }
        
        if let forcedBundleIdentifier = appexBundleIds[identifier] {
            infoDictionary[kCFBundleIdentifierKey as String] = forcedBundleIdentifier
        } else {
            infoDictionary[kCFBundleIdentifierKey as String] = profile.bundleIdentifier
        }

        infoDictionary[Bundle.Info.altBundleID] = identifier
        infoDictionary[Bundle.Info.devicePairingString] = "<insert pairing file here>"
        infoDictionary.removeValue(forKey: "DTXcode")
        infoDictionary.removeValue(forKey: "DTXcodeBuild")

        for (key, value) in additionalInfoDictionaryValues {
            infoDictionary[key] = value
        }

        if let appGroups = profile.entitlements[.appGroups] as? [String] {
            infoDictionary[Bundle.Info.appGroups] = appGroups

            // To keep file providers working, remap the NSExtensionFileProviderDocumentGroup, if there is one.
            if var extensionInfo = infoDictionary["NSExtension"] as? [String: Any],
                let appGroup = extensionInfo["NSExtensionFileProviderDocumentGroup"] as? String,
                let localAppGroup = appGroups.filter({ $0.contains(appGroup) }).min(by: { $0.count < $1.count }) {
                extensionInfo["NSExtensionFileProviderDocumentGroup"] = localAppGroup
                infoDictionary["NSExtension"] = extensionInfo
            }
        }
        
        // Add app-specific exported UTI so we can check later if this app (extension) is installed or not.
        let installedAppUTI = ["UTTypeConformsTo": [],
                               "UTTypeDescription": "AltStore Installed App",
                               "UTTypeIconFiles": [],
                               "UTTypeIdentifier": InstalledApp.installedAppUTI(forBundleIdentifier: profile.bundleIdentifier),
                               "UTTypeTagSpecification": [:]] as [String : Any]
        
        var exportedUTIs = infoDictionary[Bundle.Info.exportedUTIs] as? [[String: Any]] ?? []
        exportedUTIs.append(installedAppUTI)
        infoDictionary[Bundle.Info.exportedUTIs] = exportedUTIs
        
        try (infoDictionary as NSDictionary).write(to: bundle.infoPlistURL)
        
        // Remove _CodeSignature folder (if it exists) because it will be added when resigning and it may have files that aren't overwritten when resigning
        // These files might be the cause of some ApplicationVerificationFailed errors
        let codeSignaturePath = bundle.bundleURL.appendingPathComponent("_CodeSignature").absoluteString.replacingOccurrences(of: "file://", with: "")
        if FileManager.default.fileExists(atPath: codeSignaturePath) {
            try FileManager.default.removeItem(atPath: codeSignaturePath)
            self.verboseLog("[ResignAppOperation] Removed _CodeSignature folder at \(codeSignaturePath)")
        }
    }
    
    private func resignAppBundle(at fileURL: URL, team: ALTTeam, certificate: ALTCertificate, profiles: [ALTProvisioningProfile]) async throws -> URL {
        let signer = ALTSigner(team: team, certificate: certificate)
        try await signer.signApp(at: fileURL, provisioningProfiles: profiles, parentProgress: self.progress)
        return try FileManager.default.zipAppBundle(at: fileURL)
    }
    
    private func removeMissingAppExtensionReferences(from bundle: Bundle) throws {
        // If app extensions have been removed from an app (either by AltStore or the developer),
        // we must remove all references to them from SC_Info/Manifest.plist (if it exists).
        
        let scInfoURL = bundle.bundleURL.appendingPathComponent("SC_Info")
        let manifestPlistURL = scInfoURL.appendingPathComponent("Manifest.plist")
        
        guard let manifestPlist = NSMutableDictionary(contentsOf: manifestPlistURL), let sinfReplicationPaths = manifestPlist["SinfReplicationPaths"] as? [String] else { return }
        
        // Remove references to missing files.
        let filteredReplicationPaths = sinfReplicationPaths.filter { path in
            guard let fileURL = URL(string: path, relativeTo: bundle.bundleURL) else { return false }
            
            let fileExists = FileManager.default.fileExists(atPath: fileURL.path)
            return fileExists
        }
        
        manifestPlist["SinfReplicationPaths"] = filteredReplicationPaths
        
        // Save updated Manifest.plist to disk.
        try manifestPlist.write(to: manifestPlistURL)
    }
}

extension ALTSigner {
    func signApp(at fileURL: URL, provisioningProfiles: [ALTProvisioningProfile], parentProgress: Progress) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let progress = self.signApp(at: fileURL, provisioningProfiles: provisioningProfiles) { (success, error) in
                if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: error ?? OperationError.unknown())
                }
            }
            parentProgress.addChild(progress, withPendingUnitCount: 50)
        }
    }
}
