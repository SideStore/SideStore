//
//  SendAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 6/7/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

@preconcurrency import UIKit
import Foundation
import Network
import SideSign

final class SendAppOperation: BasePipelineOperation<InstallAppOperationContext, ALTApplication>, @unchecked Sendable {
    
    override func execute(parentProgress: Progress?) async throws -> ALTApplication {
        let startTime = CFAbsoluteTimeGetCurrent()
        debugLog("[SendAppOperation] execute() started")
        defer {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            debugLog("[SendAppOperation] execute() took: \(String(format: "%.3fs", elapsed))")
        }
        try await super.executePreconditionCheck(parentProgress: parentProgress)
        self.setProgress(10)

        guard let resignedAppBundle = self.context.resignedAppBundle else {
            throw OperationError.invalidParameters("SendAppOperation.main: self.resignedAppBundle is nil")
        }

        let bundleIdentifier = self.context.targetBundleIdentifier
        let appURL = resignedAppBundle.fileURL
        verboseLog("[SendAppOperation] AFC App Bundle `fileURL`: \(appURL.absoluteString)")

        do {
            await CellularRefreshManager.shared.turnOffDataIfNeeded()
            
            if UserDefaults.standard.preferResignedIPA, let ipaURL = self.context.ipaURL {
                debugLog("[SendAppOperation] Sending IPA at \(ipaURL.path) via AFC...")
                let rawBytes = try Data(contentsOf: ipaURL, options: .mappedIfSafe)
                try await sendIpaAfc(bundleIdentifier, rawBytes)
            } else {
                debugLog("[SendAppOperation] Sending App Bundle at \(appURL.path) via AFC...")
                try await sendAppBundleAfc(bundleIdentifier, at: appURL)
            }
            self.setProgress(100)
        } catch {
            await CellularRefreshManager.shared.turnOnDataIfNeeded()

            debugLog("[SendAppOperation] Failed to send app at \(self.context.ipaURL?.path ?? appURL.path): \(error)")
            throw OperationError.appNotFound(name: bundleIdentifier)
        }
        return resignedAppBundle
    }
}
