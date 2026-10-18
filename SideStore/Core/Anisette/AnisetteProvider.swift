//
//  AnisetteProvider.swift
//  SideStore
//
//  Created by Magesh K on 8/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import SideSign

enum AnisetteProvider {
    static func fetch(handler: AnisetteServerHandler? = nil) async throws -> ALTAnisetteData {
        // Temporary SideInstaller-style fix: on-device Mac identity is blocked by Apple
        // (-80045 / "could not connect to iCloud"). Always use remote Windows ADI servers.
        // Users can still change the anisette server URL in Settings.
        if UserDefaults.standard.useOnDeviceAnisette {
            debugLog("[AnisetteProvider] On-device anisette requested but forced remote (temporary Windows auth fix)")
            UserDefaults.standard.useOnDeviceAnisette = false
        }
        debugLog("[AnisetteProvider] Fetching anisette via remote server...")
        return try await fetchRemote(handler: handler)
    }

    private static func fetchRemote(handler: AnisetteServerHandler? = nil) async throws -> ALTAnisetteData {
        let serverUrlStrings = await AnisetteServersManager.shared.getActiveServerURLs()
        let servers = serverUrlStrings.compactMap { URL(string: $0) }
        guard !servers.isEmpty else {
            throw AnisetteError.noServersConfigured
        }

        // Prefer Windows ADI servers first (SideInstaller default: ani.jkcoxson.com)
        let preferredWindows = ["https://ani.jkcoxson.com", "https://win.ani.sidestore.io", "https://ani2.stikstore.app"]
        var ordered = servers
        if let pref = preferredWindows.compactMap({ u in servers.first(where: { $0.absoluteString.hasPrefix(u) }) }).first,
           let idx = ordered.firstIndex(of: pref) {
            ordered.remove(at: idx)
            ordered.insert(pref, at: 0)
        }
        let lastServer = UserDefaults.standard.menuAnisetteURL
        let startIndex = ordered.firstIndex(where: { $0.absoluteString == lastServer }) ?? 0

        let provider = SideSign.AnisetteDataManager.shared
        let existingBlob = AnisetteConfigManager.shared.anisetteAdiBlob.flatMap { Data(base64Encoded: $0) }
        let identifier = await AnisetteConfigManager.shared.resolveDeviceIdentifier()
        // SideInstaller-style: force Windows client-info + UA on every request
        var headers = await AnisetteConfigManager.shared.makeRequestHeaders()
        headers.clientInfo = "<PC> <Windows;6.2(0,0);9200> <com.apple.AuthKit/1 (com.apple.iTunes/12.12.4.1)>"
        headers.userAgent = "akd/1.0 CFNetwork/808.1.4"

        let (anisetteData, newAdiBlob) = try await provider.fetchAnisetteDataWithFailover(
            servers: UserDefaults.standard.disableAnisetteRotation ? [ordered[startIndex]] : ordered,
            startIndex: startIndex,
            identifier: identifier,
            existingAdiBlob: existingBlob,
            headers: headers,
            onError: { error in
                if let anisetteError = error as? SideSign.AnisetteError,
                   case .outdatedV1Server(let serverURL, _) = anisetteError {
                    if UserDefaults.standard.defaultServerURL == serverURL.absoluteString {
                        return true
                    }
                    if let handler = handler {
                        let shouldContinue = try await handler.warnOutdatedAnisetteServer()
                        if shouldContinue {
                            UserDefaults.standard.defaultServerURL = serverURL.absoluteString
                        }
                        return shouldContinue
                    }
                }
                return false
            },
            onSuccess: { successfulServer in
                UserDefaults.standard.menuAnisetteURL = successfulServer.absoluteString
                debugLog("[AnisetteProvider] Successfully fetched Anisette data from \(successfulServer.absoluteString)")
            }
        )

        if let freshBlob = newAdiBlob {
            AnisetteConfigManager.shared.anisetteAdiBlob = freshBlob.base64EncodedString()
        }

        return anisetteData
    }
}
