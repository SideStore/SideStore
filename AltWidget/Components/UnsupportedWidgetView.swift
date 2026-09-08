//
//  UnsupportedWidgetView.swift
//  AltWidget
//
//  Created by Magesh K on 8/8/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import WidgetKit

struct UnsupportedEntry: TimelineEntry {
    let date: Date = Date()
}

struct UnsupportedTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> UnsupportedEntry {
        UnsupportedEntry()
    }

    func getSnapshot(in context: Context, completion: @escaping (UnsupportedEntry) -> Void) {
        completion(UnsupportedEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UnsupportedEntry>) -> Void) {
        let timeline = Timeline(entries: [UnsupportedEntry()], policy: .never)
        completion(timeline)
    }
}

struct UnsupportedWidgetView: View {
    let requiredVersion: String

    var body: some View {
        VStack(spacing: 4) {
            Text("Unsupported iOS")
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(.white)
            Text(String(format: NSLocalizedString("Requires %@ or later", comment: ""), requiredVersion))
                .font(.system(.caption2, design: .rounded))
                .foregroundColor(Color.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .padding(8)
    }
}
