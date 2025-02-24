//
//  PageInfoManager.swift
//  AltStore
//
//  Created by Magesh K on 11/01/25.
//  Copyright © 2025 SideStore. All rights reserved.
//

import Foundation

// TODO: See if we can persist these values instead of keeping in memory to prevent memory leaks
//       Possible ways: Userdefaults.standard - set/get ?
class PageInfoManager {
    static var shared = PageInfoManager()
    private var pageInfoMap: [String: NavigationEvent] = [:]
    
    private init() {}
    
    private func getKey(forWidgetKind kind: String, forWidgetID id: Int) -> String{
        return "\(kind)@\(id)"
    }
    
    func setPageInfo(forWidgetKind kind: String, forWidgetID id: Int, value: NavigationEvent?) {
        let key = getKey(forWidgetKind: kind, forWidgetID: id)
//        UserDefaults.standard.set(value, forKey: key)
        pageInfoMap[key] = value
    }
    
    func getPageInfo(forWidgetKind kind: String, forWidgetID id: Int) -> NavigationEvent? {
        let key = getKey(forWidgetKind: kind, forWidgetID: id)
//        return UserDefaults.standard.value(forKey: key)
        return pageInfoMap[key]
   
    }

    func popPageInfo(forWidgetKind kind: String, forWidgetID id: Int) -> NavigationEvent? {
        let key = getKey(forWidgetKind: kind, forWidgetID: id)
        return pageInfoMap.removeValue(forKey: key)
    }

    func clearAll() {
        pageInfoMap.removeAll()
    }
}
