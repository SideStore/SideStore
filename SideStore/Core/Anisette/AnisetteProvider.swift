//
//  AnisetteProvider.swift
//  SideStore
//
//  SideInstaller 1.6.1 exact Auto anisette parity.
//  candidates() / macADIOrder / library() match
//  FrizzleM/SideInstaller ios-app/AnisetteServers.swift
//

import Foundation
import SideSign

enum AnisetteProvider {

    // MARK: - SideInstaller ADI library classification (exact)

    enum ADILibrary {
        case mac, windows, android
    }

    /// SideInstaller client_info_to_use (exact from remote_v3/mod.rs).
    static func clientInfoToUse(advertisedClientInfo: String?, advertisedUserAgent: String?) -> (clientInfo: String, userAgent: String) {
        let advertised = (advertisedClientInfo ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let windows = "<PC> <Windows;6.2(0,0);9200> <com.apple.AuthKit/1 (com.apple.iTunes/12.12.4.1)>"
        let currentMac = "<MacBookPro18,3> <macOS;26.6;25F84> <com.apple.AuthKit/1 (com.apple.akd/1.0)>"
        let currentMacUA = "AuthKit/1 (Macintosh; OS X 26.6) (com.apple.akd/1.0)"
        let akdUA = "akd/1.0 CFNetwork/808.1.4"
        if advertised.isEmpty || advertised.contains("<Android;") {
            return (windows, akdUA)
        }
        // mac_version < 10.13 (servers name 10.12.6) → current Mac
        if advertised.contains("10.12") || advertised.contains("Mac OS X;10.11") || advertised.contains("Mac OS X;10.10") {
            return (currentMac, currentMacUA)
        }
        let ua = (advertisedUserAgent ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return (advertised, ua.isEmpty ? akdUA : ua)
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

    private static func fetchRemote(handler: AnisetteServerHandler? = nil) async throws -> ALTAnisetteData {
        let items = await AnisetteServersManager.shared.loadLocalServers()
        var serverUrlStrings = items.filter { !$0.isHidden }.map(\.address)
        var serverNames: [String: String] = [:]
        for item in items {
            serverNames[normalized(item.address)] = item.name
        }

        // Ensure SideInstaller Mac extras exist even if community list omits them
        let extras = [
            ("SideStore (New)", "https://new.ani.sidestore.io"),
            ("jkcoxson (Mac ADI)", "https://mac-ani.jkcoxson.com"),
            ("iLoader (Mac ADI)", "https://ani.iloader.app"),
            ("StikStore (Mac ADI)", "https://ani3.stikstore.app"),
            ("StikStore 2 (Mac ADI)", "https://ani2.stikstore.app"),
        ]
        for (name, addr) in extras {
            if !serverUrlStrings.contains(where: { normalized($0) == normalized(addr) }) {
                serverUrlStrings.append(addr)
                serverNames[normalized(addr)] = name
            }
        }

        guard !serverUrlStrings.isEmpty else {
            throw AnisetteError.noServersConfigured
        }

        let pick = UserDefaults.standard.menuAnisetteURL.isEmpty
            ? fallbackServerURL
            : UserDefaults.standard.menuAnisetteURL

        // SideInstaller Auto ON → candidates(); OFF → only the pick
        let orderedStrings: [String]
        if isAutoEnabled {
            orderedStrings = candidates(
                pick: pick,
                servers: serverUrlStrings,
                serverNames: serverNames,
                failing: RecentFailures.addresses()
            )
            // Allow trying the full Mac candidate list
            UserDefaults.standard.disableAnisetteRotation = false
        } else {
            orderedStrings = [pick]
        }

        let ordered = orderedStrings.compactMap { URL(string: $0) }
        guard !ordered.isEmpty else {
            throw AnisetteError.noServersConfigured
        }

        let startIndex = 0
        let activeServer = ordered[startIndex]
        debugLog("[AnisetteProvider] Auto=\(isAutoEnabled) ordered=\(ordered.map { $0.host ?? $0.absoluteString })")

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

        // SideSignHeaders.GrandSlam / AppleAuth only expose userAgent (not clientInfo).
        // Client-info goes on the anisette headers + ALTAnisetteData below.
        var gsConfig = await SideSignConfigManager.shared.loadConfig()
        if !resolved.userAgent.isEmpty {
            gsConfig.grandSlam.userAgent = resolved.userAgent
            gsConfig.appleAuth.userAgent = resolved.userAgent
        }
        DeveloperPortal.shared.customHeaders = SideSignConfigManager.sanitizeForGrandSlam(gsConfig)

        let (anisetteData, newAdiBlob) = try await provider.fetchAnisetteDataWithFailover(
            servers: isAutoEnabled ? ordered : [ordered[startIndex]],
            startIndex: startIndex,
            identifier: identifier,
            existingAdiBlob: existingBlob,
            headers: headers,
            onError: { error in
                let s = "\(error)"
                let lower = s.lowercased()
                RecentFailures.record(activeServer.absoluteString, error: s)
                if lower.contains("-45061") || lower.contains("not provisioned") || lower.contains("-80045")
                    || lower.contains("-80046") || lower.contains("503") || lower.contains("could not connect") {
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
                RecentFailures.clear(successfulServer.absoluteString)
                debugLog("[AnisetteProvider] Successfully fetched Anisette data from \(successfulServer.absoluteString)")
            }
        )

        if let freshBlob = newAdiBlob {
            AnisetteConfigManager.shared.anisetteAdiBlob = freshBlob.base64EncodedString()
        }

        var data = anisetteData
        data.clientInfo = resolved.clientInfo
        data.userAgent = resolved.userAgent
        return data
    }
}
