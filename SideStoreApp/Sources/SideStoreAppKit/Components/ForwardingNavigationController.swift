//
//  ForwardingNavigationController.swift
//  AltStore
//
//  Created by Riley Testut on 10/24/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

final class ForwardingNavigationController: UINavigationController {
    override var childForStatusBarStyle: UIViewController? {
        self.topViewController
    }

    override var childForStatusBarHidden: UIViewController? {
        topViewController
    }
}
