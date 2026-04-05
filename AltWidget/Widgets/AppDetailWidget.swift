//
//  AppDetailWidget.swift
//  AltWidgetExtension
//
//  Created by Riley Testut on 9/14/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import WidgetKit
import SwiftUI
import AltStoreCore

struct AppDetailWidget: Widget
{
    private let kind: String = "AppDetail"
    
    public var body: some WidgetConfiguration {
        // On iOS 16+ use AppIntentConfiguration — it correctly supports
        // containerBackground and contentMarginsDisabled(), unlike the legacy
        // IntentConfiguration which breaks on iOS 17+ with the
        // "Please adopt containerBackground" error.
        if #available(iOSApplicationExtension 16, *)
        {
            return AppIntentConfiguration(
                kind: kind,
                intent: SelectAppIntent.self,
                provider: SelectAppTimelineProvider()
            ) { entry in
                AppDetailWidgetView(apps: entry.apps, date: entry.date, isPlaceholder: entry.isPlaceholder)
            }
            .supportedFamilies([.systemSmall])
            .configurationDisplayName("App Status")
            .description("View remaining days until your sideloaded apps expire. Tap the countdown timer to refresh them in the background.")
            .contentMarginsDisabled()
        }
        else
        {
            // Legacy path for iOS 15.
            return IntentConfiguration(
                kind: kind,
                intent: ViewAppIntent.self,
                provider: AppsTimelineProvider()
            ) { entry in
                AppDetailWidgetView(apps: entry.apps, date: entry.date, isPlaceholder: entry.isPlaceholder)
            }
            .supportedFamilies([.systemSmall])
            .configurationDisplayName("App Status")
            .description("View remaining days until your sideloaded apps expire. Tap the countdown timer to refresh them in the background.")
        }
    }
}

private struct AppDetailWidgetView: View
{
    let apps: [AppSnapshot]
    let date: Date
    let isPlaceholder: Bool
    
    var body: some View {
        Group {
            if let app = apps.first
            {
                let daysRemaining = app.expirationDate.numberOfCalendarDays(since: date)
                    
                GeometryReader { (geometry) in
                    Group {
                        VStack(alignment: .leading) {
                            VStack(alignment: .leading, spacing: 5) {
                                let imageHeight = geometry.size.height * 0.4
                                
                                AppIconView(icon: app.icon, imageHeight: imageHeight)
                                
                                Text(app.name.uppercased())
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            .widgetAccentableIfAvailable()
                            
                            Spacer(minLength: 0)
                            
                            HStack(alignment: .center) {
                                let expirationText: Text = {
                                    switch daysRemaining
                                    {
                                    case ..<0: return Text("Expired")
                                    case 1: return Text("1 day")
                                    default: return Text("\(daysRemaining) days")
                                    }
                                }()
                                
                                (
                                    Text("Expires in\n")
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .foregroundColor(Color.white.opacity(0.45)) +
                                    
                                    expirationText
                                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                                        .foregroundColor(.white)
                                )
                                .lineLimit(2)
                                .lineSpacing(1.0)
                                .minimumScaleFactor(0.5)
                                
                                Spacer()
                                
                                if daysRemaining >= 0
                                {
                                    Countdown(startDate: app.refreshedDate,
                                              endDate: app.expirationDate,
                                              currentDate: date)
                                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                                        .foregroundColor(Color.white)
                                        .opacity(0.8)
                                        .fixedSize(horizontal: true, vertical: false)
                                        .offset(x: 5)
                                        .invalidatableContentIfAvailable()
                                }
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            .activatesRefreshAllAppsIntent()
                            .widgetAccentableIfAvailable()
                        }
                        .padding()
                    }
                }
            }
            else
            {
                VStack {
                    // Put conditional inside VStack, or else an empty view will be returned
                    // if isPlaceholder == false, which messes up layout.
                    if !isPlaceholder
                    {
                        Text("App Not Found")
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundColor(Color.white.opacity(0.4))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .widgetBackground(
            backgroundView(
                icon: apps.first?.icon,
                tintColor: apps.first?.tintColor
            )
        )
    }

    func backgroundView(icon: UIImage? = nil, tintColor: UIColor? = nil) -> some View
    {
        let icon = icon ?? UIImage(named: "SideStore")!
        let tintColor = tintColor ?? .gray
        
        let imageHeight = 60 as CGFloat
        let saturation = 1.8
        let blurRadius = 5 as CGFloat
        let tintOpacity = 0.45
        
        // 1024x1024 images are not supported by previews but supported by device
        // so we scale the image to 97% so as to reduce its actual size but not too much
        // to somewhere below value, acceptable by previews ie < 1042x948
        let scalingFactor = 0.97
        
        let resizedSize = CGSize(
            width:  icon.size.width * scalingFactor,
            height: icon.size.height * scalingFactor
        )
            
        let resizedIcon = icon.resizing(to: resizedSize)!
        
        return ZStack(alignment: .topTrailing) {
            // Blurred Image
            GeometryReader { geometry in
                ZStack {
                    Image(uiImage: resizedIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: imageHeight, height: imageHeight, alignment: .center)
                        .saturation(saturation)
                        .blur(radius: blurRadius, opaque: true)
                        .scaleEffect(geometry.size.width / imageHeight, anchor: .center)
                    
                    Color(tintColor)
                        .opacity(tintOpacity)
                }
            }
            
            Image("Badge")
                .resizable()
                .frame(width: 26, height: 26)
                .padding()
        }
    }
}

// Tinted-mode icon: widgetAccentable lets the system tint correctly.
private struct AppIconView: View
{
    let icon: UIImage?
    let imageHeight: CGFloat

    var body: some View {
        Image(uiImage: icon ?? UIImage())
            .resizable()
            .aspectRatio(CGSize(width: 1, height: 1), contentMode: .fit)
            .frame(height: imageHeight)
            .mask(RoundedRectangle(cornerRadius: imageHeight / 5.0, style: .continuous))
            .widgetAccentableIfAvailable()
    }
}

@available(iOS 17, *)
#Preview(as: .systemSmall) {
    AppDetailWidget()
} timeline: {
    let expiredDate = Date().addingTimeInterval(1 * 60 * 60 * 24 * 7)
    let (altstore, _, _, longAltStore, _, _) = AppSnapshot.makePreviewSnapshots()
    AppsEntry<Any>(date: Date(), apps: [altstore])
    AppsEntry<Any>(date: Date(), apps: [longAltStore])
    
    AppsEntry<Any>(date: expiredDate, apps: [altstore])
    
    AppsEntry<Any>(date: Date(), apps: [])
    AppsEntry<Any>(date: Date(), apps: [], isPlaceholder: true)
}
