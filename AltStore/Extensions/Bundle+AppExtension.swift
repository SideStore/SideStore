//
//  Bundle+AppExtension.swift
//  AltStore
//
//  Created by Magesh K on 8/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation

public extension Bundle {
    static func isAppExtension() -> Bool {
        return Bundle.main.executablePath?.contains(".appex/") ?? false
    }
}
