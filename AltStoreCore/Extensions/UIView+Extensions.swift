//
//  UIView+Extensions.swift
//  AltStoreCore
//
//  Created by Magesh K on 06/17/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import UIKit

public extension UIView {
    func setHidden(_ hidden: Bool, animated: Bool) {
        guard animated else {
            self.isHidden = hidden
            return
        }
        
        guard self.isHidden != hidden else { return }
        
        let originalAlpha = self.alpha
        
        if hidden {
            UIView.animate(withDuration: 0.4, animations: {
                self.alpha = 0.0
            }, completion: { finished in
                if finished {
                    self.alpha = originalAlpha
                    self.isHidden = true
                }
            })
        } else {
            self.alpha = 0.0
            self.isHidden = false
            UIView.animate(withDuration: 0.4, animations: {
                self.alpha = originalAlpha
            })
        }
    }
}
