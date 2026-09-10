//
//  String+Localization.swift
//  AltStore
//
//  Created by Magesh K on 8/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import UIKit

public extension String {
    init(formatted: String, comment: String? = nil, _ args: String...) {
        self.init(format: NSLocalizedString(formatted, comment: comment ?? ""), args)
    }
}

public func systemLocalizedString(_ string: String) -> String {
    let bundle = Bundle(for: UIApplication.self)
    let localizedString = bundle.localizedString(forKey: string, value: "com.sidestore.SystemLocalizedStringNotFound", table: nil)
    if localizedString == "com.sidestore.SystemLocalizedStringNotFound" {
        return NSLocalizedString(string, comment: "")
    }
    return localizedString
}
