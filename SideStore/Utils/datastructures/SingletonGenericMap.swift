//
//  SingletonGenericMap.swift
//  SideStore
//
//  Created by Magesh K on 10/01/25.
//  Copyright © 2025 SideStore. All rights reserved.
//

class SingletonGenericMap{
    static var shared = SingletonGenericMap()
    private var pageInfoMap: [AnyHashable: Any] = [:]
    
    private init() {}
    
    func setPageInfo<T: Hashable, U>(for key: T, value: U?) {
        pageInfoMap[key] = value
    }
    
    func getPageInfo<T: Hashable, U>(for key: T) -> U? {
       return pageInfoMap[key] as? U
    }

    func popPageInfo<T: Hashable, U>(for key: T) -> U? {
        return pageInfoMap.removeValue(forKey: key) as? U
    }

    func clearAll() {
        pageInfoMap.removeAll()
    }
}
