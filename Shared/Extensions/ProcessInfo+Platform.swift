//
//  ProcessInfo+Platform.swift
//  SideStore
//
//  Created by SternXD on 9/13/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation

public extension ProcessInfo {
    var machineModel: String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        if size > 0 {
            var machine = [CChar](repeating: 0, count: size)
            if sysctlbyname("hw.machine", &machine, &size, nil, 0) == 0 {
                return String(cString: machine)
            }
        }
        return ""
    }

    var platformName: String {
        #if os(tvOS)
            return "tvOS"
        #else
            if machineModel.hasPrefix("iPad") {
                return "iPadOS"
            }
            return "iOS"
        #endif
    }
}
