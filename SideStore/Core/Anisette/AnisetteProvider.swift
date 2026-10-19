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
    /// SideInstaller WINDOWS_CLIENT_INFO / AKD_USER_AGENT
    static let windowsClientInfo = "<PC> <Windows;6.2(0,0);9200> <com.apple.AuthKit/1 (com.apple.iTunes/12.12.4.1)>"
    static let akdUserAgent = "akd/1.0 CFNetwork/808.1.4"

    /// Stock Mac strings anisette-v3 servers advertise that Apple rejects (SideInstaller STOCK_CLIENTS)
    private static let stockClientPrefixes = [
        "<MacBookPro13,2> <macOS;13.1;22C65>",
        "<MacBookPro15,1> <Mac OS X;10.15.2;19C57>"
    ]

    static func fetch(handler: AnisetteServerHandler? = nil) async throws -> ALTAnisetteData {
        // Temporary SideInstaller-style fix: on-device Mac identity is blocked by Apple
        if UserDefaults.standard.useOnDeviceAnisette {
            debugLog("[AnisetteProvider] On-device anisette requested but forced remote (temporary Windows auth fix)")
            UserDefaults.standard.useOnDeviceAnisette = false
        }
        // One-shot: drop Mac-provisioned adi.pb so Windows ADI can provision fresh
        let migKey = "AnisetteWindowsADI.purgeAdi.v2"
        if !UserDefaults.standard.bool(forKey: migKey) {
            AnisetteConfigManager.shared.anisetteAdiBlob = nil
            UserDefaults.standard.set(true, forKey: migKey)
            debugLog("[AnisetteProvider] Purged stored adi.pb for Windows ADI re-provision")
        }
        debugLog("[AnisetteProvider] Fetching anisette via remote server...")
        return try await fetchRemote(handler: handler)
    }

    /// SideInstaller `client_info_to_use`: prefer server /v3/client_info unless stock Mac / Android.
    static func clientInfoToUse(advertisedClientInfo: String?, advertisedUserAgent: String?) -> (clientInfo: String, userAgent: String) {
        let client = (advertisedClientInfo ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let stock = stockClientPrefixes.contains { client.hasPrefix($0) }
        if client.isEmpty || stock || client.contains("<Android;") {
            return (windowsClientInfo, akdUserAgent)
        }
        let ua = (advertisedUserAgent ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return (client, ua.isEmpty ? akdUserAgent : ua)
    }

    /// Fetch /v3/client_info from the anisette server (SideInstaller RemoteV3).
    private static func fetchServerClientInfo(from serverURL: URL) async -> (clientInfo: String?, userAgent: String?) {
        guard var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false) else {
            return (nil, nil)
        }
        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        if path.hasSuffix("/v3/get_headers") {
            path = String(path.dropLast("/v3/get_headers".count))
        }
        components.path = path + "/v3/client_info"
        components.query = nil
        guard let url = components.url else { return (nil, nil) }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return (nil, nil)
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return (nil, nil)
            }
            let ci = json["client_info"] as? String
            let ua = json["user_agent"] as? String
            debugLog("[AnisetteProvider] Server client_info: \(ci ?? "nil"), ua: \(ua ?? "nil")")
            return (ci, ua)
        } catch {
            debugLog("[AnisetteProvider] /v3/client_info failed: \(error)")
            return (nil, nil)
        }
    }

    private static func fetchRemote(handler: AnisetteServerHandler? = nil) async throws -> ALTAnisetteData {
        let serverUrlStrings = await AnisetteServersManager.shared.getActiveServerURLs()
        let servers = serverUrlStrings.compactMap { URL(string: $0) }
        guard !servers.isEmpty else {
            throw AnisetteError.noServersConfigured
        }

        let preferredWindows = ["https://ani.jkcoxson.com", "https://win.ani.sidestore.io", "https://ani2.stikstore.app"]
        var ordered = servers
        if let pref = preferredWindows.compactMap({ u in servers.first(where: { $0.absoluteString.hasPrefix(u) }) }).first,
           let idx = ordered.firstIndex(of: pref) {
            ordered.remove(at: idx)
            ordered.insert(pref, at: 0)
        }
        let lastServer = UserDefaults.standard.menuAnisetteURL
        let startIndex = ordered.firstIndex(where: { $0.absoluteString == lastServer }) ?? 0

        let activeServer = ordered[startIndex]
        let advertised = await fetchServerClientInfo(from: activeServer)
        let resolved = clientInfoToUse(advertisedClientInfo: advertised.clientInfo, advertisedUserAgent: advertised.userAgent)
        debugLog("[AnisetteProvider] Using clientInfo=\(resolved.clientInfo) ua=\(resolved.userAgent)")

        let provider = SideSign.AnisetteDataManager.shared
        let existingBlob = AnisetteConfigManager.shared.anisetteAdiBlob.flatMap { Data(base64Encoded: $0) }
        let identifier = await AnisetteConfigManager.shared.resolveDeviceIdentifier()
        var headers = await AnisetteConfigManager.shared.makeRequestHeaders()
        headers.clientInfo = resolved.clientInfo
        headers.userAgent = resolved.userAgent

        var gsConfig = await SideSignConfigManager.shared.loadConfig()
        gsConfig.grandSlam.userAgent = resolved.userAgent
        gsConfig.appleAuth.userAgent = resolved.userAgent
        DeveloperPortal.shared.customHeaders = SideSignConfigManager.sanitizeForGrandSlam(gsConfig)

        let (anisetteData, newAdiBlob) = try await provider.fetchAnisetteDataWithFailover(
            servers: UserDefaults.standard.disableAnisetteRotation ? [ordered[startIndex]] : ordered,
            startIndex: startIndex,
            identifier: identifier,
            existingAdiBlob: existingBlob,
            headers: headers,
            onError: { error in
                let s = "\(error)".lowercased()
                if s.contains("-45061") || s.contains("not provisioned") || s.contains("-80045") {
                    debugLog("[AnisetteProvider] ADI error — purging adi.pb")
                    AnisetteConfigManager.shared.anisetteAdiBlob = nil
                }
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

        var data = anisetteData
        // Force X-MMe-Client-Info identity into GSA (SideInstaller one-client rule)
        if data.clientInfo != resolved.clientInfo {
            data.clientInfo = resolved.clientInfo
        }
        return data
    }
}
