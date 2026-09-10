//
//  NibView.swift
//  AltStore
//
//  Created by Magesh K on 8/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import UIKit

open class NibView: UIView {
    public private(set) var contentView: UIView?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        initializeFromNib()
    }
    
    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        initializeFromNib()
    }
    
    private func initializeFromNib() {
        let name = String(describing: type(of: self))
        let nibName = name.components(separatedBy: ".").last ?? name
        
        let bundle = Bundle(for: type(of: self))
        
        let nib = UINib(nibName: nibName, bundle: bundle)
        guard let views = nib.instantiate(withOwner: self, options: nil) as? [UIView],
              let nibView = views.first else {
            assertionFailure("The nib for \(name) must contain a root UIView.")
            return
        }
        
        self.contentView = nibView
        nibView.preservesSuperviewLayoutMargins = true
        nibView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(nibView)
        NSLayoutConstraint.activate([
            nibView.topAnchor.constraint(equalTo: self.topAnchor),
            nibView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            nibView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            nibView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
        ])
    }
}
