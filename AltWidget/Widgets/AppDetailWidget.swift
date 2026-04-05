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
        let configuration = IntentConfiguration(kind: kind,
                                   intent: ViewAppIntent.self,
                                   provider: AppsTimelineProvider()) { (entry) in
            AppDetailWidgetView(entry: entry)
        }
        .supportedFamilies([.systemSmall])
        .configurationDisplayName("App Status")
        .description("View remaining days until your sideloaded apps expire. Tap the countdown timer to refresh them in the background.")
        
        if #available(iOS 17, *)
        {
            return configuration
                .contentMarginsDisabled()
        }
        else
        {
            return configuration
        }
    }
}

private struct AppDetailWidgetView: View
{
    var entry: AppsEntry<Intent>
    
    var body: some View {
        Group {
            if let app = self.entry.apps.first
            {
                let daysRemaining = app.expirationDate.numberOfCalendarDays(since: self.entry.date)
                    
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
                                              currentDate: self.entry.date)
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
                        }
                        .padding()
                    }
                }
            }
            else
            {
                VStack {
                    if !entry.isPlaceholder
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
        // On iOS 17+ with contentMarginsDisabled(), containerBackground is still
        // required — it must be applied as a modifier on the foreground content,
        // with the background view passed as the closure body.
        // The widgetBackground helper does exactly this correctly.
        .widgetBackground(
            backgroundView(
                icon: entry.apps.first?.icon,
                tintColor: entry.apps.first?.tintColor
            )
        )
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
    }
}

private extension AppDetailWidgetView
{
    func backgroundView(icon: UIImage? = nil, tintColor: UIColor? = nil) -> some View
    {
        let icon = icon ?? UIImage(named: "SideStore")!
        let tintColor = tintColor ?? .gray
        
        let imageHeight = 60 as CGFloat
        let saturation = 1.8
        let blurRadius = 5 as CGFloat
        let tintOpacity = 0.45
        
        let scalingFactor = 0.97
        
        let resizedSize = CGSize(
            width:  icon.size.width * scalingFactor,
            height: icon.size.height * scalingFactor
        )
            
        let resizedIcon = icon.resizing(to: resizedSize)!
        
        return ZStack(alignment: .topTrailing) {
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
