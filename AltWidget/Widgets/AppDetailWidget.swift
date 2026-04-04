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

    @Environment(\.colorScheme)
    private var colorScheme

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

                                // widgetAccentedRenderingMode is iOS 18+ and must be the
                                // first modifier on Image (before any View-returning modifiers).
                                // .accentedDesaturated maps the icon's luminance to alpha and
                                // tints it with the user's chosen accent colour in tinted mode.
                                // .fullColor preserves the original icon in light/dark mode.
                                if #available(iOSApplicationExtension 18, *)
                                {
                                    AppIconView(
                                        icon: app.icon,
                                        imageHeight: imageHeight,
                                        isAccented: true // always pass true; mode switches internally
                                    )
                                }
                                else
                                {
                                    Image(uiImage: app.icon ?? UIImage())
                                        .resizable()
                                        .aspectRatio(CGSize(width: 1, height: 1), contentMode: .fit)
                                        .frame(height: imageHeight)
                                        .mask(RoundedRectangle(cornerRadius: imageHeight / 5.0, style: .continuous))
                                }
                                
                                Text(app.name.uppercased())
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            // Tint text in accented (tinted) mode
                            .widgetAccentable()
                            
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
                            // Tint the expiry text and countdown in accented mode
                            .widgetAccentable()
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
        .widgetBackground(
            backgroundView(
                icon: entry.apps.first?.icon,
                tintColor: entry.apps.first?.tintColor
            )
        )
    }
}

// Separate sub-view so we can gate the entire thing on iOS 18 without
// repeating the modifier chain. Only instantiated on iOS 18+.
@available(iOSApplicationExtension 18, *)
private struct AppIconView: View
{
    let icon: UIImage?
    let imageHeight: CGFloat
    let isAccented: Bool // unused here; rendering mode env drives the switch

    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        Image(uiImage: icon ?? UIImage())
            // Must be first modifier on Image — before any View-returning modifier.
            .widgetAccentedRenderingMode(renderingMode == .accented ? .accentedDesaturated : .fullColor)
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
        // Increase tint opacity in dark mode for contrast; reduce in light mode.
        let tintOpacity = colorScheme == .dark ? 0.60 : 0.45
        
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
            // Blurred icon background — desaturated further in dark mode so it
            // doesn't overpower the foreground content.
            GeometryReader { geometry in
                ZStack {
                    Image(uiImage: resizedIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: imageHeight, height: imageHeight, alignment: .center)
                        .saturation(colorScheme == .dark ? saturation * 0.6 : saturation)
                        .blur(radius: blurRadius, opaque: true)
                        .scaleEffect(geometry.size.width / imageHeight, anchor: .center)
                    
                    // In dark mode, overlay a dark scrim so text stays legible.
                    if colorScheme == .dark {
                        Color.black.opacity(0.35)
                    }
                    
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
