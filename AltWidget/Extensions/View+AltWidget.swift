//
//  View+AltWidget.swift
//  AltStore
//
//  Created by Riley Testut on 8/18/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import SwiftUI

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

}

// Added for iOS 18+ tinted widget icon fix.
// `widgetAccentedRenderingMode` is an Image-only modifier that returns Image,
// so this must extend Image and return Image to keep the modifier chain intact
// (e.g. so .resizable() can still follow it).
extension Image {
    /// Applies `.widgetAccentedRenderingMode(.fullColor)` on iOS 18+ so app icons
    /// retain their original colours in tinted (accented) widget mode instead of
    /// being rendered as white silhouettes. No-op on older OS versions.
    func widgetAccentedFullColor() -> Image
    {
        if #available(iOSApplicationExtension 18, *)
        {
            return self.widgetAccentedRenderingMode(.fullColor)
        }
        else
        {
            return self
        }
    }
}
