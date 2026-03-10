//
//  VPNShortcuts.swift
//  SideStore
//
//  Ported from LocalDevVPN by se2crid.
//  App Intents for controlling LocalDevVPN from the Shortcuts app.
//
//  NOTE: All AppShortcut phrases MUST include \(.applicationName) — this is an
//  Apple requirement; without it the shortcut won't be registered with Siri.
//

import Foundation
import NetworkExtension

#if canImport(AppIntents)
import AppIntents

@available(iOS 16.0, *)
struct StartLocalDevVPNIntent: AppIntent {
    static var title: LocalizedStringResource = "Start LocalDevVPN"
    static var description = IntentDescription("Connects the local dev tunnel without opening the app.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        TunnelManager.shared.startVPN()
        return .result()
    }
}

@available(iOS 16.0, *)
struct StopLocalDevVPNIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop LocalDevVPN"
    static var description = IntentDescription("Disconnects the local dev tunnel without opening the app.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        TunnelManager.shared.stopVPN()
        return .result()
    }
}

@available(iOS 16.0, *)
struct LocalDevVPNActions: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartLocalDevVPNIntent(),
            phrases: [
                "Start \(.applicationName)",
                "Connect \(.applicationName)",
                "Enable \(.applicationName) tunnel",
            ],
            shortTitle: "Start LocalDevVPN",
            systemImageName: "checkmark.shield.fill"
        )
        AppShortcut(
            intent: StopLocalDevVPNIntent(),
            phrases: [
                "Stop \(.applicationName)",
                "Disconnect \(.applicationName)",
                "Disable \(.applicationName) tunnel",
            ],
            shortTitle: "Stop LocalDevVPN",
            systemImageName: "xmark.shield.fill"
        )
    }
}
#endif
