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
