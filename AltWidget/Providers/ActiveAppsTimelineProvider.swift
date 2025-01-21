//
//  ActiveAppsTimelineProvider.swift
//  AltStore
//
//  Created by Magesh K on 10/01/25.
//  Copyright © 2025 SideStore. All rights reserved.
//

import WidgetKit

protocol WidgetInfo{
    var ID: Int? { get }
}

@available(iOS 17, *)
class ActiveAppsTimelineProvider<T:  WidgetInfo>: AppsTimelineProviderBase<WidgetInfo> {
    public struct WidgetData: WidgetInfo {
        let ID: Int?
    }

    private let defaultDataHolder = PaginationDataHolder(
        itemsPerPage: ActiveAppsWidget.Constants.MAX_ROWS_PER_PAGE
    )
    
    let widgetKind: String
    
    init(widgetKind: String){
        self.widgetKind = widgetKind
    }
    
    deinit{
        // if this provider goes out of scope, clear all entries
        PageInfoManager.shared.clearAll()
    }
    
    override func getUpdatedData(_ apps: [AppSnapshot], _ context: WidgetInfo?) -> [AppSnapshot] {
        var apps = apps
        
        // if simulator, get the 10 simulated entries based on first entry
        #if targetEnvironment(simulator)
        apps = getSimulatedData(apps: apps)
        #endif
        
        // always start with first page since defaultDataHolder is never updated
        var currentPageApps = defaultDataHolder.currentPage(inItems: apps)
        
        if  let widgetInfo = context,
            let widgetID = widgetInfo.ID {
            
            var navEvent = getPageInfo(widgetID: widgetID)
            if  let event = navEvent,
                let direction = event.direction
            {
                let dataHolder = event.dataHolder!
                currentPageApps = dataHolder.currentPage(inItems: apps)
                
                // process navigation request only if event wasn't consumed yet
                if !event.consumed {
                    switch (direction){
                        case Direction.up:
                            currentPageApps = dataHolder.prevPage(inItems: apps, whenUnavailable: .current)!
                        case Direction.down:
                            currentPageApps = dataHolder.nextPage(inItems: apps, whenUnavailable: .current)!
                    }
                    // mark the event as consumed
                    // this prevents duplicate getUpdatedData() requests for same navigation event
                    navEvent!.consumed = true
                }
            }else{
                // construct fresh/replace existing
                navEvent = NavigationEvent(direction: nil, consumed: true, dataHolder: PaginationDataHolder(other: defaultDataHolder))
            }
            // put back the data
            updatePageInfo(widgetID: widgetID, navEvent: navEvent)
        }
             
        return currentPageApps
    }
    
    
    private func getPageInfo(widgetID: Int) -> NavigationEvent?{
        return PageInfoManager.shared.getPageInfo(forWidgetKind: widgetKind, forWidgetID: widgetID)
    }

    private func updatePageInfo(widgetID: Int, navEvent: NavigationEvent?) {
        PageInfoManager.shared.setPageInfo(forWidgetKind: widgetKind, forWidgetID: widgetID, value: navEvent)
    }
}

/// TimelineProvider for WidgetAppIntentConfiguration widget type
@available(iOS 17, *)
extension ActiveAppsTimelineProvider: AppIntentTimelineProvider {
    
    typealias Intent = WidgetUpdateIntent

    func snapshot(for intent: Intent, in context: Context) async -> AppsEntry<WidgetInfo> {
        // system retains the previously configured ID value and posts the same here
        let widgetData = WidgetData(ID: intent.ID)
        
        let bundleIDs = await super.fetchActiveAppBundleIDs()
        let snapshot = await self.snapshot(for: bundleIDs, in: widgetData)
        
        return snapshot
    }
    
    func timeline(for intent: Intent, in context: Context) async -> Timeline<AppsEntry<WidgetInfo>> {
        // system retains the previously configured ID value and posts the same here
        let widgetData = WidgetData(ID: intent.ID)

        let bundleIDs = await self.fetchActiveAppBundleIDs()
        let timeline = await self.timeline(for: bundleIDs, in: widgetData)

        return timeline
    }
}
