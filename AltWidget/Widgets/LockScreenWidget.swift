//
//  LockScreenWidget.swift
//  AltWidget
//
//  Created by Riley Testut on 7/7/22.
//  Copyright © 2022 Riley Testut. All rights reserved.
//

import SwiftUI
import WidgetKit

struct TextLockScreenWidget: Widget
{
    private let kind: String = "TextLockAppDetail"
    
    init() {
        debugLog("[TextLockScreenWidget] Initialized widget kind: TextLockAppDetail")
    }
    
    public var body: some WidgetConfiguration {
        if #available(iOSApplicationExtension 16, *)
        {
            return IntentConfiguration(kind: kind,
                                       intent: ViewAppIntent.self,
                                       provider: AppsTimelineProvider()) { (entry) in
                ComplicationView(apps: entry.apps, date: entry.date, isPlaceholder: entry.isPlaceholder, style: .text)
            }
            .supportedFamilies([.accessoryCircular])
            .configurationDisplayName("AltWidget (Text)")
            .description("View remaining days until SideStore expires.")
        }
        else
        {
            return StaticConfiguration(kind: kind, provider: UnsupportedTimelineProvider()) { _ in
                UnsupportedWidgetView(requiredVersion: "iOS 16")
            }
            .supportedFamilies([.systemSmall])
            .configurationDisplayName("AltWidget (Text)")
            .description("Requires iOS 16 or later.")
        }
    }
}

struct IconLockScreenWidget: Widget
{
    private let kind: String = "IconLockAppDetail"
    
    init() {
        debugLog("[IconLockScreenWidget] Initialized widget kind: IconLockAppDetail")
    }
    
    public var body: some WidgetConfiguration {
        if #available(iOSApplicationExtension 16, *)
        {
            return IntentConfiguration(kind: kind,
                                       intent: ViewAppIntent.self,
                                       provider: AppsTimelineProvider()) { (entry) in
                ComplicationView(apps: entry.apps, date: entry.date, isPlaceholder: entry.isPlaceholder, style: .icon)
            }
            .supportedFamilies([.accessoryCircular])
            .configurationDisplayName("AltWidget (Icon)")
            .description("View remaining days until SideStore expires.")
        }
        else
        {
            return StaticConfiguration(kind: kind, provider: UnsupportedTimelineProvider()) { _ in
                UnsupportedWidgetView(requiredVersion: "iOS 16")
            }
            .supportedFamilies([.systemSmall])
            .configurationDisplayName("AltWidget (Icon)")
            .description("Requires iOS 16 or later.")
        }
    }
}

@available(iOS 16, *)
extension ComplicationView
{
    fileprivate enum Style
    {
        case text
        case icon
    }
}

@available(iOS 16, *)
private struct ComplicationView: View
{
    let apps: [AppSnapshot]
    let date: Date
    let isPlaceholder: Bool
    let style: Style
    
    var body: some View {
        let refreshedDate = self.apps.first?.refreshedDate ?? .now
        let expirationDate = self.apps.first?.expirationDate ?? .now
        
        let totalDays = expirationDate.numberOfCalendarDays(since: refreshedDate)
        let daysRemaining = expirationDate.numberOfCalendarDays(since: self.date)
        
        let progress = totalDays > 0 ? Double(daysRemaining) / Double(totalDays) : 0.0
        
        // TODO: Gauge initialized with an out-of-bounds progress amount. The amount will be clamped to the nearest bound.
        Gauge(value: progress) {
            if self.apps.isEmpty
            {
                switch self.style
                {
                case .text:
                    VStack(spacing: -1) {
                        Text("-")
                            .font(.system(size: 20.0, weight: .bold, design: .rounded))
                        
                        Text("DAYS")
                            .font(.caption)
                    }
                    .fixedSize()
                    .offset(y: -1)
                    
                case .icon:
                    ZStack {
                        Image("SmallIcon")
                            .resizable()
                            .aspectRatio(1.0, contentMode: .fill)
                            .scaleEffect(x: 0.8, y: 0.8)
                        
                        Text("-")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(Color.black)
                            .blendMode(.destinationOut)
                    }
                }
            }
            else if daysRemaining < 0
            {
                Text("Expired")
                    .font(.system(size: 10, weight: .bold))
            }
            else
            {
                switch self.style
                {
                case .text:
                    VStack(spacing: -1) {
                        let fontSize = daysRemaining > 99 ? 18.0 : 20.0
                        Text(String(format: NSLocalizedString("%d", comment: ""), daysRemaining))
                            .font(.system(size: fontSize, weight: .bold, design: .rounded))
                        
                        Text(daysRemaining == 1 ? NSLocalizedString("DAY", comment: "") : NSLocalizedString("DAYS", comment: ""))
                            .font(.caption)
                    }
                    .fixedSize()
                    .offset(y: -1)
                    
                case .icon:
                    ZStack {
                        // Destination
                        Image("SmallIcon")
                            .resizable()
                            .aspectRatio(1.0, contentMode: .fill)
                            .scaleEffect(x: 0.8, y: 0.8)
                        
                        // Source
                        (
                            daysRemaining > 7 ?
                            Text("7+")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .kerning(-2) :
                                
                            Text(String(format: NSLocalizedString("%d", comment: ""), daysRemaining))
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                         )
                        .foregroundColor(Color.black)
                        .blendMode(.destinationOut) // Clip text out of image.
                    }
                }
            }
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .unredacted()
        .widgetBackground(Color.clear)
        .onAppear {
            debugLog("[ComplicationView] onAppear: style=\(style), isPlaceholder=\(isPlaceholder), appsCount=\(apps.count)")
        }
    }
}

private let widgetFamily = if #available(iOS 16, *) { WidgetFamily.accessoryCircular } else { WidgetFamily.systemSmall }

@available(iOS 17, *)
#Preview("Text", as: widgetFamily) {
    TextLockScreenWidget()
} timeline: {
    let expiredDate = Date().addingTimeInterval(1 * 60 * 60 * 24 * 7)
    let (altstore, _, _, longAltStore, _, _) = AppSnapshot.makePreviewSnapshots()
    
    AppsEntry<Void>(date: Date(), apps: [altstore])
    AppsEntry<Void>(date: Date(), apps: [longAltStore])
    
    AppsEntry<Void>(date: expiredDate, apps: [altstore])
}

@available(iOS 17, *)
#Preview("Icon", as: widgetFamily) {
    IconLockScreenWidget()
} timeline: {
    let expiredDate = Date().addingTimeInterval(1 * 60 * 60 * 24 * 7)
    let (altstore, _, _, longAltStore, _, _) = AppSnapshot.makePreviewSnapshots()
    
    AppsEntry<Void>(date: Date(), apps: [altstore])
    AppsEntry<Void>(date: Date(), apps: [longAltStore])
    
    AppsEntry<Void>(date: expiredDate, apps: [altstore])
}
