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
                        "刷新 \(.applicationName)",
                        "刷新 \(.applicationName) 应用",
                        "刷新我的 \(.applicationName) 应用",
                        "使用 \(.applicationName) 刷新应用",
                    ],
                    shortTitle: "刷新所有应用",
                    systemImageName: "arrow.triangle.2.circlepath")
    }
    
    public static var shortcutTileColor: ShortcutTileColor {
        return .teal
    }
}
