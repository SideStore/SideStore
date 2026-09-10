//
//  UIView+Pinning.swift
//  AltStore
//
//  Created by Magesh K on 8/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

@preconcurrency import UIKit

public extension NSLayoutConstraint {
    static func constraintsPinningEdges(of view1: UIView, to view2: UIView) -> [NSLayoutConstraint] {
        return self.constraintsPinningEdges(of: view1, to: view2, withInsets: .zero)
    }
    
    static func constraintsPinningEdges(of view1: UIView, to view2: UIView, withInsets insets: UIEdgeInsets) -> [NSLayoutConstraint] {
        let topConstraint = view1.topAnchor.constraint(equalTo: view2.topAnchor, constant: insets.top)
        let bottomConstraint = view2.bottomAnchor.constraint(equalTo: view1.bottomAnchor, constant: insets.bottom)
        let leftConstraint = view1.leftAnchor.constraint(equalTo: view2.leftAnchor, constant: insets.left)
        let rightConstraint = view2.rightAnchor.constraint(equalTo: view1.rightAnchor, constant: insets.right)
        
        return [topConstraint, bottomConstraint, leftConstraint, rightConstraint]
    }
}

public extension UIView {
    func addSubview(_ view: UIView, pinningEdgesWith insets: UIEdgeInsets) {
        view.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(view)
        
        let pinningConstraints = NSLayoutConstraint.constraintsPinningEdges(of: view, to: self, withInsets: insets)
        NSLayoutConstraint.activate(pinningConstraints)
    }
}
