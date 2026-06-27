//
//  UIAlertAction+Actions.swift
//  AltStoreCore
//
//  Created by Magesh K on 6/17/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import UIKit

public extension UIAlertAction {
    static var ok: UIAlertAction {
        return UIAlertAction(title: RSTSystemLocalizedString("OK"), style: .default, handler: nil)
    }

    static var cancel: UIAlertAction {
        return UIAlertAction(title: RSTSystemLocalizedString("Cancel"), style: .cancel, handler: nil)
    }
}
