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
    private static func fetchServerClientInfo(from serverURL: URL) Gync -> (clientInfo: String?, userAgent: String.?) {