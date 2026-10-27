//
//  InstallAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 6/19/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UserNotifications
import UIKit
import Foundation
import Network
import CoreData
import SideSign

final class InstallAppOperation: BasePipelineOperation<InstallAppOperationContext, InstalledApp>, @unchecked Sendable {
    let storeApp: StoreApp?
    
    init(context: InstallAppOperationContext, app: any AppProtocol) throws {
        self.storeApp = app as? StoreApp
        try super.init(context: context)
        self.progress.totalUnitCount = 100
    }
    
    override func execute(parentProgress: Progress?) async throws -> InstalledApp {
        let startTime = CFAbsoluteTimeGetCurrent()
        debugLog("[InstallAppOperation] execute() started")
        defer {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            debugLog("[InstallAppOperation] execute() took: \(String(format: "%.3fs", elapsed))")
        }
        try await super.executePreconditionCheck(parentProgress: parentProgress)
        
        defer {
            self.removeRefreshedIPA()
        }
        
        guard
            let certificate = context.targetSigningCertificate,
            let resignedAppBundle = context.resignedAppBundle,
            let provisioningProfiles = context.provisioningProfiles
        else {
            throw OperationError.invalidParameters(
                "InstallAppOperation.execute: self.context.targetSigningCertificate or self.context.resignedAppBundle or self.context.provisioningProfiles is nil"
            )
        }

        #if !targetEnvironment(simulator)
        guard resignedAppBundle.provisioningProfile != nil else {
            throw OperationError.missingProvisioningProfile(reason: "Resigned app bundle '\(resignedAppBundle.bundleIdentifier)' is missing its embedded provisioning profile.")
        }
        #endif

        @Managed var appVersion = context.appVersion
        let storeBuildVersion = $appVersion.buildVersion
        
        let backgroundContext = self.context.dbBackgroundContext
        
        self.setProgress(10)
        let authTeam = try await AuthManager.shared.getAuthenticatedTeam()
        do {
            let installedApp = try await installApp(
                in: backgroundContext,
                certificate: certificate,
                resignedAppBundle: resignedAppBundle,
                provisioningProfiles: provisioningProfiles,
                storeBuildVersion: storeBuildVersion,
                authTeam: authTeam
            )
            self.context.installedApp = installedApp
            await CellularRefreshManager.shared.turnOnDataIfNeeded()
            return installedApp
        } catch {
            await CellularRefreshManager.shared.turnOnDataIfNeeded()
            throw error
