//
//  NSLayoutConstraint+Edges.swift
//  AltStoreCore
//
//  Created by Magesh K on 6/17/26.
//

import UIKit

public extension NSLayoutConstraint {
    @objc(constraintsPinningEdgesOfView:toEdgesOfView:)
    static func constraintsPinningEdges(of view1: UIView, to view2: UIView) -> [NSLayoutConstraint] {
        return self.constraintsPinningEdges(of: view1, to: view2, withInsets: .zero)
    }
    
    @objc(constraintsPinningEdgesOfView:toEdgesOfView:withInsets:)
    static func constraintsPinningEdges(of view1: UIView, to view2: UIView, withInsets insets: UIEdgeInsets) -> [NSLayoutConstraint] {
        let topConstraint = view1.topAnchor.constraint(equalTo: view2.topAnchor, constant: insets.top)
        let bottomConstraint = view2.bottomAnchor.constraint(equalTo: view1.bottomAnchor, constant: insets.bottom)
        let leftConstraint = view1.leftAnchor.constraint(equalTo: view2.leftAnchor, constant: insets.left)
        let rightConstraint = view2.rightAnchor.constraint(equalTo: view1.rightAnchor, constant: insets.right)
        
        return [topConstraint, bottomConstraint, leftConstraint, rightConstraint]
    }
}

public extension UIView {
    @objc(addSubview:pinningEdgesWithInsets:)
    func addSubview(_ view: UIView, pinningEdgesWith insets: UIEdgeInsets) {
        view.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(view)
        
        let pinningConstraints = NSLayoutConstraint.constraintsPinningEdges(of: view, to: self, withInsets: insets)
        NSLayoutConstraint.activate(pinningConstraints)
    }
}
