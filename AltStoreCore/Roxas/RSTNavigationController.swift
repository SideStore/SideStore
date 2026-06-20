//
//  RSTNavigationController.swift
//  AltStoreCore
//
//  Created by Magesh K on 6/17/26.
//

import UIKit

@objc(RSTNavigationController)
public class RSTNavigationController: UINavigationController {
    open override var shouldAutorotate: Bool {
        return self.topViewController?.shouldAutorotate ?? super.shouldAutorotate
    }
    
    open override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return self.topViewController?.supportedInterfaceOrientations ?? super.supportedInterfaceOrientations
    }
    
    open override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        return self.topViewController?.preferredInterfaceOrientationForPresentation ?? super.preferredInterfaceOrientationForPresentation
    }
}

public func RSTContainInNavigationController(_ viewController: UIViewController) -> RSTNavigationController {
    return RSTNavigationController(rootViewController: viewController)
}
