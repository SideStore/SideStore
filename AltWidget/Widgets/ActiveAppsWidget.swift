//
//  ActiveAppsWidget.swift
//  AltWidgetExtension
//
//  Created by Riley Testut on 8/16/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import SwiftUI
import WidgetKit

import AltStoreCore

import GameplayKit

private extension Color
{
    static let altGradientLight = Color.init(.displayP3, red: 123.0/255.0, green: 200.0/255.0, blue: 176.0/255.0)
    static let altGradientDark = Color.init(.displayP3, red: 0.0/255.0, green: 128.0/255.0, blue: 132.0/255.0)
    
    static let altGradientExtraDark = Color.init(.displayP3, red: 2.0/255.0, green: 82.0/255.0, blue: 103.0/255.0)
}

struct WidgetTag: WidgetInfo{
    let ID: Int?
}

//@available(iOS 17, *)
struct ActiveAppsWidget: Widget
{
    struct Constants{
        static let MAX_ROWS_PER_PAGE: UInt = 3
    }
    
    public var body: some WidgetConfiguration {
        if #available(iOS 17, *)
        {
            let widgetID = "ActiveApps - \(UUID().uuidString)"

            let widgetConfig = AppIntentConfiguration(
                kind: widgetID,
                intent: WidgetUpdateIntent.self,
                provider: ActiveAppsTimelineProvider<WidgetTag>(kind: widgetID)
            ) { entry in
                ActiveAppsWidgetView(entry: entry)
            }
            .supportedFamilies([.systemMedium])
            .configurationDisplayName("Active Apps")
            .description("View remaining days until your active apps expire. Tap the countdown timers to refresh them in the background.")
            
            return widgetConfig
        }
        else
        {
            // Can't mark ActiveAppsWidget as requiring iOS 17 directly without causing crash on older versions.
            // So instead we just return EmptyWidgetConfiguration pre-iOS 17.
            return EmptyWidgetConfiguration()
        }
    }
}

@available(iOS 17, *)
private struct ActiveAppsWidgetView: View
{
    var entry: AppsEntry<WidgetInfo>
    
    @Environment(\.colorScheme)
    private var colorScheme
        
    var body: some View {
        Group {
            if entry.apps.isEmpty
            {
                placeholder
            }
            else
            {
                content
            }
        }
        .foregroundStyle(.white)
        .containerBackground(for: .widget) {
            if colorScheme == .dark
            {
                LinearGradient(colors: [.altGradientDark, .altGradientExtraDark], startPoint: .top, endPoint: .bottom)
            }
            else
            {
                LinearGradient(colors: [.altGradientLight, .altGradientDark], startPoint: .top, endPoint: .bottom)
            }
        }
    }
    
    private var content: some View {
        GeometryReader { (geometry) in
            HStack(alignment: .center) {
                
                appsListView(reader: geometry)
                
                Spacer(minLength: 16)
                
                navigationBarView()
                
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    private func appsListView(reader: GeometryProxy) -> some View {
        let itemsPerPage = ActiveAppsWidget.Constants.MAX_ROWS_PER_PAGE
        
        let preferredRowHeight = (reader.size.height / Double(itemsPerPage)) - 8
        let rowHeight = min(preferredRowHeight, reader.size.height / 2)

        return LazyVStack(spacing: 12) {
            ForEach(Array(entry.apps.enumerated()), id: \.offset) { index, app in
            
                appEntryRowView(app: app, rowHeight: rowHeight)
            
            }
        }
    }
    
    
    private func appEntryRowView(app: AppSnapshot, rowHeight: Double) -> some View {
        let icon: UIImage = app.icon ?? UIImage(named: "SideStore")!
        
        // 1024x1024 images are not supported by previews but supported by device
        // so we scale the image to 97% so as to reduce its actual size but not too much
        // to somewhere below value, acceptable by previews ie < 1042x948
        let scalingFactor = 0.97
        
        let resizedSize = CGSize(
            width:  icon.size.width * scalingFactor,
            height: icon.size.height * scalingFactor
        )
        
        let resizedIcon = icon.resizing(to: resizedSize)!
        let cornerRadius = rowHeight / 5.0
        
        return HStack(spacing: 10) {
            Image(uiImage: resizedIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .cornerRadius(cornerRadius)
            
            appDetailsView(app)
            
            Spacer()
            
            countDownView(app)
            
        }
        .frame(height: rowHeight)
    }
    
    
    private func appDetailsView(_ app: AppSnapshot) -> some View {
        let daysRemaining = app.expirationDate.numberOfCalendarDays(since: entry.date)

        return VStack(alignment: .leading, spacing: 1) {
            Text(app.name)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            
            let text = if entry.date > app.expirationDate
            {
                Text("Expired")
            }
            else
            {
                Text("Expires in \(daysRemaining) ") + (daysRemaining == 1 ? Text("day") : Text("days"))
            }
            
            text
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
    
    private func countDownView(_ app: AppSnapshot) -> some View {
        Countdown(startDate: app.refreshedDate,
                  endDate: app.expirationDate,
                  currentDate: entry.date,
                  strokeWidth: 3.0) // Slightly thinner circle stroke width
        .background {
            Color.black.opacity(0.1)
                .mask(Capsule())
                .padding(.all, -5)
        }
        .font(.system(size: 16, weight: .semibold, design: .rounded))
        // this modifier invalidates the view (disables user interaction and shows a blinking effect)
        .invalidatableContent()
        .activatesRefreshAllAppsIntent()

    }
    
    private func navigationBarView() -> some View {
        let buttonWidth: CGFloat = 16
        let widgetID = entry.context?.ID
        
        return VStack {
            Image(systemName: "arrow.up")
                .resizable()
                .frame(width: buttonWidth, height: buttonWidth)
                .opacity(0.3)
                // .mask(Capsule())
                .pageUpButton(widgetID)
            
            Spacer()
            
            Image(systemName: "arrow.down")
                .resizable()
                .frame(width: buttonWidth, height: buttonWidth)
                .opacity(0.3)
                // .mask(Capsule())
                .pageDownButton(widgetID)
        }
        .padding(.vertical)
    }
    
    private var placeholder: some View {
        Text("App Not Found")
            .font(.system(.body, design: .rounded))
            .fontWeight(.semibold)
            .foregroundColor(Color.white.opacity(0.4))
    }
}

@available(iOS 17, *)
#Preview(as: .systemMedium) {
    return ActiveAppsWidget()
} timeline: {
    let expiredDate = Date().addingTimeInterval(1 * 60 * 60 * 24 * 7)
    let (altstore, delta, clip, longAltStore, longDelta, longClip) = AppSnapshot.makePreviewSnapshots()
    
    AppsEntry<Any>(date: Date(), apps: [altstore, delta, clip])
    AppsEntry<Any>(date: Date(), apps: [longAltStore, longDelta, longClip])
    
    AppsEntry<Any>(date: expiredDate, apps: [altstore, delta, clip])
    
    AppsEntry<Any>(date: Date(), apps: [altstore, delta])
    AppsEntry<Any>(date: Date(), apps: [altstore])
    
    AppsEntry<Any>(date: Date(), apps: [])
    AppsEntry<Any>(date: Date(), apps: [], isPlaceholder: true)
}
