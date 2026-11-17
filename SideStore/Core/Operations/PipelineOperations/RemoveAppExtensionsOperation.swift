//
//  RemoveAppExtensionsOperation.swift
//  AltStore
//
//  Created by Riley Testut on 2/27/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//


import Foundation
import SideSign

public enum AppExtensionCustomization: String, CaseIterable, Identifiable, Sendable {
    case promptUser     = "prompt-user"
    case removeAll      = "remove-all"
    case keepAll        = "keep-all"
    case useMainProfile = "use-main-profile"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .promptUser:
            return "Prompt User"
        case .removeAll:
            return "Remove All"
        case .keepAll:
            return "Keep All"
        case .useMainProfile:
            return "Use Main Profile"
        }
    }

    var fixedDecision: ExtensionRemovalDecision? {
        switch self {
        case .promptUser:
            return nil
        case .removeAll:
            return .removeAll
        case .keepAll:
            return .keepAll(useMainProfile: false)
        case .useMainProfile:
            return .keepAll(useMainProfile: true)
        }
    }
}


final class RemoveAppExtensionsOperation: BasePipelineOperation<InstallAppOperationContext, ALTApplication>, @unchecked Sendable {
    let localAppExtensions: Set<ALTApplication>?
    
    init(context: InstallAppOperationContext, localAppExtensions: Set<ALTApplication>?) throws {
        self.localAppExtensions = localAppExtensions
        try super.init(context: context)
    }
    
    override func execute(parentProgress: Progress?) async throws -> ALTApplication {
        let startTime = CFAbsoluteTimeGetCurrent()
        debugLog("[RemoveAppExtensionsOperation] execute() started")
        defer {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            debugLog("[RemoveAppExtensionsOperation] execute() took: \(String(format: "%.3fs", elapsed))")
        }
        try await super.executePreconditionCheck(parentProgress: parentProgress)
        self.setProgress(10)
        
        guard let targetAppBundle = context.targetAppBundle else {
            throw OperationError.invalidParameters("RemoveAppExtensionsOperation: context.appBundle is nil")
        }
        
        // target App Bundle doesn't contain extensions so don't bother
        guard !targetAppBundle.appExtensions.isEmpty else {
            self.setProgress(100)
            return targetAppBundle
        }
        
        self.setProgress(30)
        let excessExtensions = processExtensionsInfo(from: targetAppBundle, localAppExtensions: localAppExtensions)
        
        let handler = self.context.handler.extensionRemovalHandler
        let decision: ExtensionRemovalDecision
        if let preset = UserDefaults.standard.customizeAppExtensions.fixedDecision {
            decision = preset
        } else {
            self.setProgress(50)
            decision = try await handler.selectAppExtensionsToRemove(
                appBundle: targetAppBundle,
                localAppExtensions: Array(localAppExtensions ?? []),
                excessExtensions: excessExtensions
            )
        }

        switch decision {
            case .cancel:
                throw OperationError.cancelled

            case .keepAll(let useMainProfile):
                self.context.useMainProfile = useMainProfile
                self.setProgress(100)

            case .removeAll:
                try self.removeExtensions(from: targetAppBundle.appExtensions, endPercent: 85)
                try self.updateManifest()
                self.setProgress(100)

            case .removeSelected(let selection):
                try self.removeExtensions(from: selection, endPercent: 100)
                self.setProgress(100)
        }
        
        return targetAppBundle
    }
    
    private func removeExtensions(from extensions: Set<ALTApplication>, endPercent: Int64) throws {
        let isLoggingEnabled = OperationsLoggingControl.isLoggingEnabled(for: RemoveAppExtensionsOperation.self)
        let startProgress = self.progress.completedUnitCount
        let range = endPercent - startProgress
        guard !extensions.isEmpty else {
            self.setProgress(endPercent)
            return
        }
        let array = Array(extensions)
        let count = array.count
        for (index, appExtension) in array.enumerated() {
            if range > 0 {
                let percent = startProgress + Int64(Double(index + 1) / Double(count) * Double(range))
                self.setProgress(percent)
            }
            if isLoggingEnabled {
                debugLog("Deleting extension \(appExtension.bundleIdentifier)")
            }
            try FileManager.default.removeItem(at: appExtension.fileURL)
        }
    }

    private func updateManifest() throws {
        guard let appBundle = context.targetAppBundle else {
            return
        }
        
        let scInfoURL = appBundle.fileURL.appendingPathComponent("SC_Info")
        let manifestPlistURL = scInfoURL.appendingPathComponent("Manifest.plist")
        
        if let manifestPlist = NSMutableDictionary(contentsOf: manifestPlistURL),
           let sinfReplicationPaths = manifestPlist["SinfReplicationPaths"] as? [String] {
            let replacementPaths = sinfReplicationPaths.filter { !$0.starts(with: "PlugIns/") && !$0.starts(with: "Extensions/") } // Filter out app extension paths.
            manifestPlist["SinfReplicationPaths"] = replacementPaths
            try manifestPlist.write(to: manifestPlistURL)
        }
    }
    
    struct ExtensionsInfo {
        let excessInTarget: Set<ALTApplication>
        let necessaryInExisting: Set<ALTApplication>
    }
    
    private func processExtensionsInfo(from targetAppBundle: ALTApplication,
                                       localAppExtensions: Set<ALTApplication>?) -> Set<ALTApplication> {
        //App-Extensions: Ensure existing app's extensions in DB and currently installing app bundle's extensions must match
        let targetAppEx: Set<ALTApplication> = targetAppBundle.appExtensions
        let targetAppExNames  = targetAppEx.map { appEx in appEx.bundleIdentifier }

        guard let extensionsInExistingApp = localAppExtensions else {
            let diagnosticsMsg = "RemoveAppExtensionsOperation: ExistingApp is nil, Hence keeping all app extensions from targetAppBundle"
                               + "RemoveAppExtensionsOperation: ExistingAppEx: nil; targetAppBundleEx: \(targetAppExNames)"
            verboseLog(diagnosticsMsg)
            return Set()    // nothing is excess since we are keeping all, so returning empty
        }
        
        let existingAppEx: Set<ALTApplication> = extensionsInExistingApp
        let existingAppExNames = existingAppEx.map { appEx in appEx.bundleIdentifier }
        
        let excessExtensionsInTargetApp = targetAppEx.filter {
            !(existingAppExNames.contains($0.bundleIdentifier))
        }
    
        let isMatching = (targetAppEx.count == existingAppEx.count) && excessExtensionsInTargetApp.isEmpty
        let diagnosticsMsg = "RemoveAppExtensionsOperation: App Extensions in localAppBundle and targetAppBundle are matching: \(isMatching)\n"
                            + "RemoveAppExtensionsOperation: \nlocalAppBundleEx: \(existingAppExNames); \ntargetAppBundleEx: \(String(describing: targetAppExNames))\n"
        verboseLog(diagnosticsMsg)

        return excessExtensionsInTargetApp
    }
}
