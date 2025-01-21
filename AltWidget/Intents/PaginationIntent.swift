//
//  PaginationIntent.swift
//  AltStore
//
//  Created by Magesh K on 08/01/25.
//  Copyright © 2025 SideStore. All rights reserved.
//

import AppIntents
import Intents
import WidgetKit

public enum Direction: String, Sendable{
    case up
    case down
}

public struct NavigationEvent {
    let direction: Direction?
    var consumed: Bool = false
    var dataHolder: PaginationDataHolder?
}

@available(iOS 17, *)
class PaginationIntent: AppIntent, @unchecked Sendable {
        
    static var title: LocalizedStringResource = "Page Navigation Intent"
    static var isDiscoverable: Bool = false
    
    @Parameter(title: "widgetID")
    var widgetID: Int

    @Parameter(title: "Direction")
    var direction: String

    @Parameter(title: "widgetKind")
    var widgetKind: String

    required init(){}
    
    // NOTE: widgetID here means the configurable value using edit widget button
    //       but widgetKind is the kind set in when instantiating the widget configuration
    init(_ widgetID: Int?, _ direction: Direction,  _ widgetKind: String){
        // if id was not passed in, then we assume the widget isn't customized yet
        // hence we use the common ID, if this is not present in registry of PageInfoManager
        // then it will return nil, triggering to show first page in the provider
        self.widgetID = widgetID ?? WidgetUpdateIntent.COMMON_WIDGET_ID
        self.direction = direction.rawValue
        self.widgetKind = widgetKind
    }
    
    func perform() async throws -> some IntentResult {
        // Post the navigation event into the shared db (Dictionary) and ask to reload
        DispatchQueue(label: String(widgetID)).sync {
            self.postThisNavigationEvent()
            WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
        }
        return .result()
    }
    
    private func postThisNavigationEvent(){
        // re-use an existing event if available and update only required parts
        let navEvent = PageInfoManager.shared.getPageInfo(forWidgetKind: widgetKind, forWidgetID: widgetID)
        let navigationEvent = NavigationEvent(
            direction: Direction(rawValue: direction),
            consumed: false,    // event is never consumed at origin :D
            dataHolder: navEvent?.dataHolder ?? nil
        )
        PageInfoManager.shared.setPageInfo(forWidgetKind: widgetKind, forWidgetID: widgetID, value: navigationEvent)
    }
}
