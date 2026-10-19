//
//  AnisetteProvider.swift
//  SideStore
//
//  Created by Magesh K on 8/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//
//  Temporary Apple ID fix (SideInstaller 1.5.2 / 1.5.3 parity):
//  GrandSlam is told we are a Windows PC (WINDOWS_CLIENT_INFO + akd UA).
//  Windows ADI anisette servers are preferred; Mac ADI hosts are last.
//  Mac-provisioned adi.pb is purged so Windows ADI can provision fresh.
//

import Foundation
import SideSign

enum AnisetteProvider {
    /// SideInstaller WINDOWS_CLIENT_INFO
    static let windowsClientInfo = "<PC> <Windows;6.2(0,0);9200> <com.apple.AuthKit/1 (com.apple.iTunes/12.12.4.1)>"
    /// SideInstaller AKD_USER_AGENT
    static let akdUserAgent = "akd/1.0 CFNetwork/808.1.4"

    /// SideInstaller STOCK_CLIENTS — anisette-v3 stock strings Apple rejects with 503
    private static let stockClientPrefixes = [
        "<MacBookPro13,2> <macOS;13.1;22C65>",
        "<MacBookPro15,1> <Mac OS X;10.15.2;19C57>"
    ]

    /// SideInstaller windowsADIHosts
    private static let windowsADIHosts: Set<String> = [
        "ani.jkcoxson.com",
        "win.ani.sidestore.io",
        "ani2.stikstore.app"
    ]

    /// SideInstaller macADIHosts — try last
    private static let macADIHosts: Set<String> = [
        "mac-ani.jkcoxson.com",
        "new.ani.sidestore.io"
    ]

    static func fetch(handler: AnisetteServerHandler? = nil) async throws -> ALTAnisetteData {
        // Temporary SideInstaller-style fix: on-device Mac identity is blocked by Apple
        if UserDefaults.standard.useOnDeviceAnisette {
            debugLog("[AnisetteProvider] On-device anisette forced off (Windows GSA temporary fix)")
            UserDefaults.standard.useOnDeviceAnisette = false
        }

        // Bump purge key so existing installs drop Mac-provisioned adi.pb once
        let migKey = "AnisetteWindowsADI.purgeAdi.v3"
        if !UserDefaults.standard.bool(forKey: migKey) {
            AnisetteConfigManager.shared.anisetteAdiBlob = nil
            UserDefaults.standard.set(true, forKey: migKey)
            debugLog("[AnisetteProvider] Purged stored adi.pb for Windows ADI re-provision (v3)")
        }

        // If the saved server is a known Mac ADI host, clear it so we start on Windows
        if let host = URL(string: UserDefaults.standard.menuAnisetteURL)?.host,
           macADIHosts.contains(host) {
            debugLog("[AnisetteProvider] Clearing Mac ADI server preference: \(host)")
            UserDefaults.standard.menuAnisetteURL = AppConstants.Anisette.Servers.defaultServerURL
            AnisetteConfigManager.shared.anisetteAdiBlob = nil
        }

        debugLog("[AnisetteProvider] Fetching anisette via remote server (Windows GSA path)...")
        return try await fetchRemote(handler: handler)
    }

    /// SideInstaller `client_info_to_use`.
    /// Temporary fix: always report Windows PC to GrandSlam (SideInstaller 1.5.2).
    static func clientInfoToUse(advertisedClientInfo: String?, advertisedUserAgent: String?) -> (clientInfo: String, userAgent: String) {
        _ = advertisedClientInfo
        _ = advertisedUserAgent
        return (windowsClientInfo, akdUserAgent)
    }

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

    /// SideInstaller order: Windows ADI first, then others, Mac ADI last.
    private static func orderServersWindowsFirst(_ servers: [URL]) -> [URL] {
        var windows: [URL] = []
        var middle: [URL] = []
        var macs: [URL] = []
        for url in servers {
            let host = url.host ?? ""
            if windowsADIHosts.contains(host) {
                windows.append(url)
            } else if macADIHosts.contains(host) {
                macs.append(url)
            } else {
                middle.append(url)
            }
        }
        let preferredOrder = ["ani.jkcoxson.com", "win.ani.sidestore.io", "ani2.stikstore.app"]
        windows.sort { a, b in
            let ia = preferredOrder.firstIndex(of: a.host ?? "") ?? 99
            let ib = preferredOrder.firstIndex(of: b.host ?? "") ?? 99
            return ia < ib
        }
        return windows + middle + macs
    }

    private static func fetchRemote(handler: AnisetteServerHandler? = nil) async throws -> ALTAnisetteData {
        let serverUrlStrings = await AnisetteServersManager.shared.getActiveServerURLs()
        let servers = serverUrlStrings.compactMap { URL(string: $0) }
        guard !servers.isEmpty else {
            throw AnisetteError.noServersConfigured
        }

        var ordered = orderServersWindowsFirst(servers)

        let fallbackWindows = [
            "https://ani.jkcoxson.com",
            "https://win.ani.sidestore.io",
            "https://ani2.stikstore.app"
        ].compactMap { URL(string: $0) }
        for fw in fallbackWindows.reversed() {
            if !ordered.contains(where: { $0.host == fw.host }) {
                ordered.insert(fw, at: 0)
            } else if let idx = ordered.firstIndex(where: { $0.host == fw.host }), idx > 0 {
                ordered.remove(at: idx)
                ordered.insert(fw, at: 0)
            }
        }

        let lastServer = UserDefaults.standard.menuAnisetteURL
        var startIndex = ordered.firstIndex(where: { $0.absoluteString == lastServer }) ?? 0
        if let host = URL(string: lastServer)?.host, macADIHosts.contains(host) {
            startIndex = 0
        }

        let activeServer = ordered[startIndex]
        let advertised = await fetchServerClientInfo(from: activeServer)
        let resolved = clientInfoToUse(advertisedClientInfo: advertised.clientInfo, advertisedUserAgent: advertised.userAgent)
        debugLog("[AnisetteProvider] Using clientInfo=\(resolved.clientInfo) ua=\(resolved.userAgent) server=\(activeServer.absoluteString)")

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
                if s.contains("-45061") || s.contains("not provisioned") || s.contains("-80045")
                    || s.contains("503") || s.contains("could not connect") {
                    debugLog("[AnisetteProvider] ADI/auth error — purging adi.pb")
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
        data.clientInfo = resolved.clientInfo
        return data
    }
}
