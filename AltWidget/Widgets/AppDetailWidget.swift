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

// ViewModifier that reads widgetRenderingMode (iOS 16+) and injects
// an `isAccented` Bool into the environment so pre-iOS-16 code stays clean.
@available(iOS 16, *)
private struct RenderingModeModifier: ViewModifier
{
    @Environment(\.widgetRenderingMode) private var renderingMode

    func body(content: Content) -> some View {
        content
            .environment(\.isAccentedWidget, renderingMode == .accented)
    }
}

// Custom environment key so we can pass the accented flag down without
// requiring iOS 16 at every call site.
private struct IsAccentedWidgetKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

private extension EnvironmentValues {
    var isAccentedWidget: Bool {
        get { self[IsAccentedWidgetKey.self] }
        set { self[IsAccentedWidgetKey.self] = newValue }
    }
}


private struct AppDetailWidgetView: View
{
    var entry: AppsEntry<Intent>

    @Environment(\.colorScheme)
    private var colorScheme

    // Populated by RenderingModeModifier on iOS 16+; false on older OS.
    @Environment(\.isAccentedWidget)
    private var isAccented

    var body: some View {
        // Attach the iOS-16 rendering-mode reader only when available.
        if #available(iOS 16, *)
        {
            innerBody.modifier(RenderingModeModifier())
        }
        else
        {
            innerBody
        }
    }

    @ViewBuilder
    private var innerBody: some View {
        Group {
            if let app = self.entry.apps.first
            {
                let daysRemaining = app.expirationDate.numberOfCalendarDays(since: self.entry.date)
                    
                GeometryReader { (geometry) in
                    Group {
                        VStack(alignment: .leading) {
                            VStack(alignment: .leading, spacing: 5) {
                                let imageHeight = geometry.size.height * 0.4
                                
                                Image(uiImage: app.icon ?? UIImage())
                                    // Preserve the original app icon colours in tinted (accented)
                                    // mode on iOS 18+. Without this the system renders the icon white.
                                    // Must be applied directly on Image before any View-returning modifiers.
                                    .widgetAccentedFullColor()
                                    .resizable()
                                    .aspectRatio(CGSize(width: 1, height: 1), contentMode: .fit)
                                    .frame(height: imageHeight)
                                    .mask(RoundedRectangle(cornerRadius: imageHeight / 5.0, style: .continuous))
                                
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
                tintColor: entry.apps.first?.tintColor,
                isAccented: isAccented,
                colorScheme: colorScheme
            )
        )
    }
}

private extension AppDetailWidgetView
{
    func backgroundView(icon: UIImage? = nil, tintColor: UIColor? = nil, isAccented: Bool = false, colorScheme: ColorScheme = .light) -> some View
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
        
        // In tinted (accented) mode the system overlays its own accent colour;
        // return a simple neutral background so it reads clearly.
        if isAccented {
            return AnyView(Color.gray.opacity(0.3))
        }
        
        return AnyView(ZStack(alignment: .topTrailing) {
            // Blurred Image background — desaturated further in dark mode so the
            // blurred icon doesn't overpower the foreground content.
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
        })
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
