//
//  RSTNibView.swift
//  AltStoreCore
//
//  Created by Magesh K on 6/17/26.
//

import UIKit

@objc(RSTNibView)
open class RSTNibView: UIView {
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
        
        nibView.preservesSuperviewLayoutMargins = true
        self.addSubview(nibView, pinningEdgesWith: .zero)
    }
}
