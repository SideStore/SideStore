//
//  AppShortcuts.swift
//  AltStore
//
//  Created by Riley Testut on 8/23/22.
//  Copyright © 2022 Riley Testut. All rights reserved.
//

import AppIntents

@available(iOS 17, *)
public struct ShortcutsProvider: AppShortcutsProvider
{
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RefreshAllAppsIntent(),
                    phrases: [
                        "Refresh \(.applicationName)",
                        "Refresh \(.applicationName) apps",
                        "Refresh my \(.applicationName) apps",
                        "Refresh apps with \(.applicationName)",
                    ],
                    shortTitle: "Refresh All Apps",
                    systemImageName: "arrow.triangle.2.circlepath")
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

    public static var shortcutTileColor: ShortcutTileColor {
        return .teal
    }
}
