//
//  NSString+Localization.swift
//  AltStoreCore
//
//  Created by Magesh K on 6/17/26.
//

import UIKit

public extension String {
    init(formatted: String, comment: String? = nil, _ args: String...) {
        self.init(format: NSLocalizedString(formatted, comment: comment ?? ""), args)
    }
}

public func RSTSystemLocalizedString(_ string: String) -> String {
    let bundle = Bundle(for: UIApplication.self)
    let localizedString = bundle.localizedString(forKey: string, value: "com.rileytestut.RSTSystemLocalizedStringNotFound", table: nil)
    if localizedString == "com.rileytestut.RSTSystemLocalizedStringNotFound" {
        return string
    }
    return localizedString
}
