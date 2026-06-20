//
//  UIViewController+TransitionState.swift
//  AltStoreCore
//
//  Created by Magesh K on 6/17/26.
//

import UIKit

extension UIViewController {
    @objc(isAppearing)
    public var isAppearing: Bool {
        guard let transitionCoordinator = self.transitionCoordinator else { return false }
        let toViewController = transitionCoordinator.viewController(forKey: .to)
        let fromViewController = transitionCoordinator.viewController(forKey: .from)
        
        let isAppearing = toViewController?.isEqualToViewControllerOrAncestor(self) ?? false
        return isAppearing && !(fromViewController is UIAlertController)
    }
    
    @objc(isDisappearing)
    public var isDisappearing: Bool {
        guard let transitionCoordinator = self.transitionCoordinator else { return false }
        let fromViewController = transitionCoordinator.viewController(forKey: .from)
        let toViewController = transitionCoordinator.viewController(forKey: .to)
        
        let isDisappearing = fromViewController?.isEqualToViewControllerOrAncestor(self) ?? false
        return isDisappearing && !(toViewController is UIAlertController)
    }
    
    private func isEqualToViewControllerOrAncestor(_ viewController: UIViewController) -> Bool {
        var current: UIViewController? = viewController
        while let vc = current {
            if self == vc {
                return true
            }
            current = vc.parent
        }
        return false
    }
}
