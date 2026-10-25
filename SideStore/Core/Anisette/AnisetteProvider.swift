//
//  AnisetteProvider.swift
//  SideStore
//
//  Created by Magesh K on 8/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//
//  Temporary Apple ID fix (SideInstaller 1.6.1 parity):
//  Apple rejects Windows/Android anisette after the verification code with -80046.
//  Sign in through Mac anisette servers first, report a current Mac via the
//  server's /v3/client_info, force On-Device Anisette off, and purge stale adi.pb.
//

import Foundation
import SideSign

enum AnisetteProvider {
    /// SideInstaller 1.6.1 macADIHosts — try these first
    private static let macADIHosts: Set<String> = [
        "new.ani.sidestore.io",      // SideStore (New) — SideInstaller 1.6.1 first
        "mac-ani.jkcoxson.com",
        "ani.iloader.app",
        "ani3.stikstore.app",
        "ani2.stikstore.app",
        "ani.sidestore.io",
        "ani.jkcoxson.com",
    ]

    /// Former Windows ADI hosts — try only after Mac servers
    private static let windowsADIHosts: Set<String> = [
        "win.ani.sidestore.io"
    ]

    /// Preferred Mac server order (SideInstaller starts with SideStore (New))
    private static let preferredMacOrder = [
        "new.ani.sidestore.io",      // SideInstaller macADIOrder[0]
        "mac-ani.jkcoxson.com",
        "ani.iloader.app",
        "ani3.stikstore.app",
        "ani2.stikstore.app",
        "ani.sidestore.io",
        "ani.jkcoxson.com",
    ]

    static func fetch(handler: AnisetteServerHandler? = nil) async throws -> ALTAnisetteData {
        // SideInstaller 1.6.1: On-Device Anisette ends in -80046 → force off
        if UserDefaults.standard.useOnDeviceAnisette {
            debugLog("[AnisetteProvider] On-device anisette forced off (SideInstaller 1.6.1 Mac fix)")
            UserDefaults.standard.useOnDeviceAnisette = false
        }

        // Prefer auto-rotation off so we stay on a working Mac server
        if !UserDefaults.standard.disableAnisetteRotation {
            // Do not force-write every launch; only ensure a sensible default once
            let key = "AnisetteMacADI.defaultedRotationOff.v1"
            if !UserDefaults.standard.bool(forKey: key) {
                UserDefaults.standard.disableAnisetteRotation = true
                UserDefaults.standard.set(true, forKey: key)
                debugLog("[AnisetteProvider] Defaulted auto-rotation OFF (SideInstaller 1.6.1)")
            }
        }

        // One-time purge of Windows/Android-provisioned adi.pb so Mac ADI can create a fresh identity
        let migKey = "AnisetteMacADI.purgeAdi.v1"
        if !UserDefaults.standard.bool(forKey: migKey) {
            AnisetteConfigManager.shared.anisetteAdiBlob = nil
            UserDefaults.standard.set(true, forKey: migKey)
            debugLog("[AnisetteProvider] Purged stored adi.pb for Mac ADI re-provision (v1)")
        }

        // If the saved server is a known Windows-only host, clear it so we start on Mac
        if let host = URL(string: UserDefaults.standard.menuAnisetteURL)?.host,
           windowsADIHosts.contains(host) {
            debugLog("[AnisetteProvider] Clearing Windows ADI server preference: \(host)")
            UserDefaults.standard.menuAnisetteURL = AppConstants.Anisette.Servers.defaultServerURL
            AnisetteConfigManager.shared.anisetteAdiBlob = nil
        }

        debugLog("[AnisetteProvider] Fetching anisette via remote server (Mac GSA path)...")
        return try await fetchRemote(handler: handler)
    }

    /// SideInstaller 1.6.1: use the client_info the Mac server advertises (current Mac).
    /// Fall back only if the server returns nothing useful.
    /// SideInstaller 1.6.1: ALWAYS report a current Mac for GrandSlam.
    /// Servers still *name* macOS 10.12; Apple rejects that after the code (-80046 / -23782).
    static func clientInfoToUse(advertisedClientInfo: String?, advertisedUserAgent: String?) -> (clientInfo: String, userAgent: String) {
        let ci = AppConstants.Anisette.Servers.macClientInfo
        var ua = (advertisedUserAgent?.isEmpty == false) ? advertisedUserAgent! : AppConstants.Anisette.Servers.macUserAgent
        if ua.isEmpty { ua = AppConstants.Anisette.Servers.macUserAgent }
        return (ci, ua)
    }

    /// Fetch /v3/client_info (SideInstaller RemoteV3)
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

    /// SideInstaller 1.6.1 order: Mac ADI first, then others, Windows ADI last.
    private static func orderServersMacFirst(_ servers: [URL]) -> [URL] {
        var macs: [URL] = []
        var middle: [URL] = []
        var windows: [URL] = []
        for url in servers {
            let host = url.host ?? ""
            if macADIHosts.contains(host) {
                macs.append(url)
            } else if windowsADIHosts.contains(host) {
                windows.append(url)
            } else {
                middle.append(url)
            }
        }
        macs.sort { a, b in
            let ia = preferredMacOrder.firstIndex(of: a.host ?? "") ?? 99
            let ib = preferredMacOrder.firstIndex(of: b.host ?? "") ?? 99
            return ia < ib
        }
        return macs + middle + windows
    }

    private static func fetchRemote(handler: AnisetteServerHandler? = nil) async throws -> ALTAnisetteData {
        let serverUrlStrings = await AnisetteServersManager.shared.getActiveServerURLs()
        let servers = serverUrlStrings.compactMap { URL(string: $0) }
        guard !servers.isEmpty else {
            throw AnisetteError.noServersConfigured
        }

        var ordered = orderServersMacFirst(servers)

        // Ensure preferred Mac servers are tried first even if missing from remote list
        let fallbackMac = [
            "https://new.ani.sidestore.io",   // SideStore (New) first
            "https://mac-ani.jkcoxson.com",
            "https://ani.iloader.app",
            "https://ani3.stikstore.app",
            "https://ani2.stikstore.app",
            "https://ani.sidestore.io",
        ].compactMap { URL(string: $0) }
        for fm in fallbackMac.reversed() {
            if !ordered.contains(where: { $0.host == fm.host }) {
                ordered.insert(fm, at: 0)
            } else if let idx = ordered.firstIndex(where: { $0.host == fm.host }), idx > 0 {
                ordered.remove(at: idx)
                ordered.insert(fm, at: 0)
            }
        }

        let lastServer = UserDefaults.standard.menuAnisetteURL
        var startIndex = ordered.firstIndex(where: { $0.absoluteString == lastServer }) ?? 0
        // If last server was Windows-only, start at Mac instead
        if let host = URL(string: lastServer)?.host, windowsADIHosts.contains(host) {
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
        if !resolved.clientInfo.isEmpty {
            headers.clientInfo = resolved.clientInfo
        }
        if !resolved.userAgent.isEmpty {
            headers.userAgent = resolved.userAgent
        }

        // Align GrandSlam UA with the Mac identity the server gave us
        var gsConfig = await SideSignConfigManager.shared.loadConfig()
        if !resolved.userAgent.isEmpty {
            gsConfig.grandSlam.userAgent = resolved.userAgent
            gsConfig.appleAuth.userAgent = resolved.userAgent
        }
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
                    || s.contains("-80046") || s.contains("503") || s.contains("could not connect") {
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
        // Prefer the Mac identity the server advertised (SideInstaller one-client rule for Mac path)
        if !resolved.clientInfo.isEmpty {
            data.clientInfo = resolved.clientInfo
        }
        if !resolved.userAgent.isEmpty {
            data.userAgent = resolved.userAgent
        }
        return data
    }
}
