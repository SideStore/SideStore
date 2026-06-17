//
//  Bundle+Extensions.swift
//  AltStoreCore
//
//  Created by Magesh K on 06/17/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation

public extension Bundle {
    static func isAppExtension() -> Bool {
        return Bundle.main.executablePath?.contains(".appex/") ?? false
    }
}
