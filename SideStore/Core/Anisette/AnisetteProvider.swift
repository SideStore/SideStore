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

    /// SideInstaller `macADIOrder` — Auto tries these hosts first.
    static let macADIOrder: [String] = [
        "ani.jkcoxson.com",
        "mac-ani.jkcoxson.com",
        "new.ani.sidestore.io",
        "ani.iloader.app",
        "ani3.stikstore.app",
        "ani2.stikstore.app",
    ]
    static let macADIHosts: Set<String> = Set(macADIOrder)
    static let windowsADIHosts: Set<String> = ["win.ani.sidestore.io"]

    /// SideInstaller `MAC_CLIENT_INFO` (grandslam.rs) — current Mac, not server's 10.12.
    static let macClientInfo = "<Mac15,7> <macOS;27.0;26A5378j> <com.apple.AuthKit/1 (com.apple.akd/1.0)>"
    static let macUserAgent  = "akd/1.0 CFNetwork/808.1.4"

    /// SideInstaller `AnisetteServer.fallback`
    static let fallbackServerURL = "https://ani.jkcoxson.com"

    /// SideInstaller Auto default (Engine.anisetteAuto defaults to true)
    static var isAutoEnabled: Bool {
        if UserDefaults.standard.object(forKey: "anisetteServerAuto") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "anisetteServerAuto")
    }

    static func setAutoEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "anisetteServerAuto")
        if enabled {
            UserDefaults.standard.useOnDeviceAnisette = false
            // Auto tries multiple servers — allow rotation across Mac candidates
            UserDefaults.standard.disableAnisetteRotation = false
            if UserDefaults.standard.menuAnisetteURL.isEmpty {
                UserDefaults.standard.menuAnisetteURL = fallbackServerURL
            }
        }
    }

    static func normalized(_ address: String) -> String {
        var a = address.trimmingCharacters(in: .whitespacesAndNewlines)
        while a.hasSuffix("/") { a.removeLast() }
        return a.lowercased()
    }

    /// SideInstaller `library(of:in:)`
    static func library(of address: String, serverNames: [String: String] = [:]) -> ADILibrary {
        let key = normalized(address)
        if let host = URL(string: key)?.host?.lowercased() {
            if macADIHosts.contains(host) { return .mac }
            if windowsADIHosts.contains(host) { return .windows }
        }
        let name = (serverNames[key] ?? "").lowercased()
        if name.contains("mac adi") { return .mac }
        if name.contains("windows") { return .windows }
        return .android
    }

    /// SideInstaller `AnisetteServer.candidates(pick:servers:failing:)` — exact algorithm.
    static func candidates(pick: String, servers: [String], serverNames: [String: String] = [:], failing: Set<String> = []) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        func add(_ group: [String]) {
            var failed: [String] = []
            for address in group {
                let a = address.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !a.isEmpty, seen.insert(normalized(a)).inserted else { continue }
                if failing.contains(normalized(a)) {
                    failed.append(a)
                } else {
                    out.append(a)
                }
            }
            out += failed
        }
        let addresses = servers
        let macServers = addresses.filter { library(of: $0, serverNames: serverNames) == .mac }
        let mac = macADIOrder.compactMap { host in
            macServers.first { URL(string: normalized($0))?.host?.lowercased() == host }
        } + macServers
        let windows = addresses.filter { library(of: $0, serverNames: serverNames) == .windows }
        switch library(of: pick, serverNames: serverNames) {
        case .mac:     add([pick] + mac)
        case .windows: add([pick] + windows)
        case .android: add([pick])  // alone — Android ends in -80046 for new login
        }
        add(mac)
        add(windows)
        return out
    }

    // MARK: - RecentFailures (SideInstaller, 12h window)

    enum RecentFailures {
        static let key = "anisetteServerFailures"
        static let window: TimeInterval = 12 * 60 * 60

        static func addresses(now: Date = Date()) -> Set<String> {
            Set(stored().filter { now.timeIntervalSince1970 - $0.value < window }.keys)
        }

        static func record(_ address: String, error: String, now: Date = Date()) {
            let e = error.lowercased()
            // Only hold back real anisette-server faults
            guard e.contains("anisette") || e.contains("timeout") || e.contains("502") || e.contains("503") else { return }
            var failures = stored().filter { now.timeIntervalSince1970 - $0.value < window }
            failures[normalized(address)] = now.timeIntervalSince1970
            UserDefaults.standard.set(failures, forKey: key)
        }

        static func clear(_ address: String) {
            var failures = stored()
            guard failures.removeValue(forKey: normalized(address)) != nil else { return }
            UserDefaults.standard.set(failures, forKey: key)
        }

        private static func stored() -> [String: Double] {
            UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
        }
    }

    // MARK: - Fetch

    static func fetch(handler: AnisetteServerHandler? = nil) async throws -> ALTAnisetteData {
        // SideInstaller post-install parity for SideStore: ODA always off
        if UserDefaults.standard.useOnDeviceAnisette {
            debugLog("[AnisetteProvider] On-device anisette forced off (SideInstaller 1.6.1)")
            UserDefaults.standard.useOnDeviceAnisette = false
        }

        // One-time purge so Mac ADI can create a fresh identity
        let migKey = "AnisetteMacADI.purgeAdi.v1"
        if !UserDefaults.standard.bool(forKey: migKey) {
            AnisetteConfigManager.shared.anisetteAdiBlob = nil
            UserDefaults.standard.set(true, forKey: migKey)
            debugLog("[AnisetteProvider] Purged stored adi.pb for Mac ADI re-provision")
        }

        // Default Auto ON + SideStore (New) when unset
        if UserDefaults.standard.object(forKey: "anisetteServerAuto") == nil {
            UserDefaults.standard.set(true, forKey: "anisetteServerAuto")
        }
        if UserDefaults.standard.menuAnisetteURL.isEmpty ||
            windowsADIHosts.contains(URL(string: UserDefaults.standard.menuAnisetteURL)?.host ?? "") {
            UserDefaults.standard.menuAnisetteURL = fallbackServerURL
        }

        debugLog("[AnisetteProvider] Fetching anisette (SideInstaller Auto=\(isAutoEnabled))...")
        return try await fetchRemote(handler: handler)
    }

    /// Always report SideInstaller current Mac (not server's macOS 10.12).
    static func clientInfoToUse(advertisedClientInfo: String?, advertisedUserAgent: String?) -> (clientInfo: String, userAgent: String) {
        let ua = (advertisedUserAgent?.isEmpty == false) ? advertisedUserAgent! : macUserAgent
        return (macClientInfo, ua.isEmpty ? macUserAgent : ua)
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
