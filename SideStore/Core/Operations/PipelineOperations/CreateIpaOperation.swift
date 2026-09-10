//
//  CreateIpaOperation.swift
//  SideStore
//
//  Created by Magesh K on 9/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import SideSign

final class CreateIpaOperation: BasePipelineOperation<InstallAppOperationContext, URL?>, @unchecked Sendable {

    override func execute(parentProgress: Progress?) async throws -> URL? {
        let startTime = CFAbsoluteTimeGetCurrent()
        debugLog("[CreateIpaOperation] execute() started")
        defer {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            debugLog("[CreateIpaOperation] execute() took: \(String(format: "%.3fs", elapsed))")
        }
        try await super.executePreconditionCheck(parentProgress: parentProgress)
        self.setProgress(10)

        guard UserDefaults.standard.preferResignedIPA || UserDefaults.standard.isExportResignedAppEnabled else {
            debugLog("[CreateIpaOperation] Skipping: preferResignedIPA and isExportResignedAppEnabled are disabled")
            self.setProgress(100)
            return nil
        }

        guard let resignedAppBundle = self.context.resignedAppBundle else {
            throw OperationError.invalidParameters("CreateIpaOperation: context.resignedAppBundle is nil")
        }

        let appURL = resignedAppBundle.fileURL
        debugLog("[CreateIpaOperation] Packaging app bundle at \(appURL.path)...")
        self.setProgress(30)

        let ipaURL = try FileManager.default.zipAppBundle(at: appURL, compressionLevel: .none)
        self.context.ipaURL = ipaURL
        self.setProgress(100)
        debugLog("[CreateIpaOperation] Packaged IPA created at \(ipaURL.path)")
        return ipaURL
    }
}
