//
//  OnDeviceAnisetteManager.swift
//  SideStore
//
//  Created by Magesh K on 18/08/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import AnisetteKit
import SideSign

public actor OnDeviceAnisetteManager {
    public static let shared = OnDeviceAnisetteManager()

    private let provider: AnisetteDataManager

    private init() {
        let baseDir: URL?
        if let sharedDir = FileManager.default.altstoreSharedDirectory {
            baseDir = sharedDir.appendingPathComponent(AppConstants.Anisette.hiddenBaseDirectoryName, isDirectory: true)
        } else {
            baseDir = FileManager.default.applicationSupportDirectory
                .appendingPathComponent(AppConstants.Anisette.appSupportSubdirectory, isDirectory: true)
                .appendingPathComponent(AppConstants.Anisette.hiddenBaseDirectoryName, isDirectory: true)
        }
        self.provider = AnisetteDataManager(baseDirectory: baseDir)
    }

    public nonisolated var baseAnisetteDirectory: URL? {
        provider.baseAnisetteDirectory
    }

    public nonisolated var librariesDirectory: URL? {
        provider.libsDir
    }

    public nonisolated var provisioningDirectory: URL? {
        provider.provisioningDir
    }

    public func isReady() async -> Bool {
        provider.isReady()
    }

    public func fetchAnisetteData() async throws -> ALTAnisetteData {
        debugLog("[OnDeviceAnisetteManager] [Fetch] Fetching on-device Anisette headers...")

        let identifierUUID = await AnisetteConfigManager.shared.resolveDeviceIdentifier()

        var existingAdiPbData: Data? = nil
        if let base64Blob = AnisetteConfigManager.shared.anisetteAdiBlob,
           let decoded = Data(base64Encoded: base64Blob, options: .ignoreUnknownCharacters),
           !decoded.isEmpty {
            existingAdiPbData = decoded
            debugLog("[OnDeviceAnisetteManager] [Fetch] Reusing existing adi.pb from Keychain (\(decoded.count) bytes)")
        } else {
            debugLog("[OnDeviceAnisetteManager] [Fetch] No existing adi.pb in Keychain -> local in-memory provisioning will be performed")
        }

        let headers = await AnisetteConfigManager.shared.makeRequestHeaders()

        let sourceURLString = UserDefaults.standard.menuAnisetteList.isEmpty ? AnisetteServersManager.defaultSource : UserDefaults.standard.menuAnisetteList
        let sourceURL = URL(string: sourceURLString) ?? AppConstants.Anisette.defaultODAMetadataURL
        let fallbackURL = AppConstants.Anisette.defaultODAMetadataURL

        let mode = AnisetteMode.remoteODA(sourceURL: sourceURL, fallbackURL: fallbackURL)

        let (anisetteData, newAdiPb) = try await provider.fetchAnisetteData(
            mode: mode,
            identifier: identifierUUID,
            existingAdiBlob: existingAdiPbData,
            headers: headers
        )

        if let freshBlob = newAdiPb {
            AnisetteConfigManager.shared.anisetteAdiBlob = freshBlob.base64EncodedString()
            debugLog("[OnDeviceAnisetteManager] [Fetch] Fresh local provisioning completed -> saved new adi.pb (\(freshBlob.count) bytes) to Keychain")
        }

        debugLog("[OnDeviceAnisetteManager] [Fetch] SUCCESS: AnisetteData generated successfully.")
        return anisetteData
    }
}
