//
//  WidgetUpdateIntent.swift
//  AltStore
//
//  Created by Magesh K on 10/01/25.
//  Copyright © 2025 SideStore. All rights reserved.
//

import AppIntents

@available(iOS 17, *)
final class WidgetUpdateIntent: WidgetConfigurationIntent, @unchecked Sendable {
    public static let COMMON_WIDGET_ID = 1
    
    static var title: LocalizedStringResource { "Widget ID update Intent" }
    static var isDiscoverable: Bool { false }
    
    @Parameter(title: "ID", description: "Provide a numeric ID to identify the widget", default: 1)
    var ID: Int?
}
