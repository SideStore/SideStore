//
//  VPNShortcuts.swift
//  SideStore
//
//  Ported from LocalDevVPN by se2crid.
//  App Intents for controlling LocalDevVPN from Shortcuts.
//

import Foundation
import NetworkExtension

#if canImport(AppIntents)
import AppIntents

@available(iOS 16.0, *)
struct StartLocalDevVPNIntent: AppIntent {
    static var title: LocalizedStringResource = "Start LocalDevVPN"
    static var description = IntentDescription("Connects LocalDevVPN without launching the app.")
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
    static var description = IntentDescription("Disconnects LocalDevVPN without launching the app.")
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
                "Start LocalDevVPN",
                "Connect LocalDevVPN",
                "Enable LocalDevVPN"
            ],
            shortTitle: "Start LocalDevVPN",
            systemImageName: "checkmark.shield.fill"
        )
        AppShortcut(
            intent: StopLocalDevVPNIntent(),
            phrases: [
                "Stop LocalDevVPN",
                "Disconnect LocalDevVPN",
                "Disable LocalDevVPN"
            ],
            shortTitle: "Stop LocalDevVPN",
            systemImageName: "xmark.shield.fill"
        )
    }
}
#endif
