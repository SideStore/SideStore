//
//  View+AltWidget.swift
//  AltStore
//
//  Created by Riley Testut on 8/18/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import SwiftUI
import WidgetKit

extension View
{
    @ViewBuilder
    func widgetBackground(_ backgroundView: some View) -> some View
    {
        if #available(iOSApplicationExtension 17, *)
        {
            containerBackground(for: .widget) {
                backgroundView
            }
        }
        else
        {
            background(backgroundView)
        }
    }
    
    @ViewBuilder
    func invalidatableContentIfAvailable() -> some View
    {
        if #available(iOSApplicationExtension 17, *)
        {
            self.invalidatableContent()
        }
        else
        {
            self
        }
    }
    
    @ViewBuilder
    func activatesRefreshAllAppsIntent() -> some View
    {
        if #available(iOSApplicationExtension 17, *)
        {
            Button(intent: RefreshAllAppsWidgetIntent()) {
                self
            }
            .buttonStyle(.plain)
        }
        else
        {
            self
        }
    }

    @ViewBuilder
    func pageUpButton(_ widgetID: Int?, _ widgetKind: String) -> some View {
        if #available(iOSApplicationExtension 17, *) {
            Button(intent: PaginationIntent(widgetID, .up, widgetKind)){
                self
            }
            .buttonStyle(.plain)
        } else {
            self
        }
    }

    @ViewBuilder
    func pageDownButton(_ widgetID: Int?, _ widgetKind: String) -> some View {
        if #available(iOSApplicationExtension 17, *) {
            Button(intent: PaginationIntent(widgetID, .down, widgetKind)){
                self
            }
            .buttonStyle(.plain)
        } else {
            self
        }
    }

    /// Opts this view into the widget accent group on iOS 16+, which lets the system tint it with the user's chosen colour in tinted (accented) mode.
    /// Doesn't apply on older OS versions where the API does not exist.
    @ViewBuilder
    func widgetAccentableIfAvailable() -> some View
    {
        if #available(iOSApplicationExtension 16, *)
        {
            self.widgetAccentable()
        }
        else
        {
            self
        }
    }

    /// Applies `luminanceToAlpha()` only when the widget is rendering in accented (tinted) mode on iOS 16+. This converts the view's pixel brightness into opacity so the system can overlay the user's chosen tint colour correctly — without it, images appear as white rectangles in tinted mode.
    /// Doesn't apply in fullColor/dark/light mode and on older OS.
    @ViewBuilder
    func luminanceToAlphaInAccentedMode() -> some View
    {
        if #available(iOSApplicationExtension 16, *)
        {
            LuminanceToAlphaWrapper(content: self)
        }
        else
        {
            self
        }
    }

}

/// Helper view that reads widgetRenderingMode (iOS 16+) and conditionally applies luminanceToAlpha(). Kept separate so the environment read is cleanly scoped behind the @available gate.
@available(iOSApplicationExtension 16, *)
private struct LuminanceToAlphaWrapper<Content: View>: View
{
    let content: Content
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        if renderingMode == .accented
        {
            content.luminanceToAlpha()
        }
        else
        {
            content
        }
    }
}
