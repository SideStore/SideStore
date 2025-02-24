//
//  String+SideStore.swift
//  AltStoreCore
//
//  Created by nythepegasus on 5/9/24.
//

import Foundation

public extension String {
    init(formatted: String, comment: String? = nil, _ args: String...) {
        self.init(format: NSLocalizedString(formatted, comment: comment ?? ""), args)
    }
}
