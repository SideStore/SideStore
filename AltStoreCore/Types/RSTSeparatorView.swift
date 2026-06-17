//
//  RSTSeparatorView.swift
//  AltStoreCore
//
//  Created by Magesh K on 6/17/26.
//

import UIKit

@IBDesignable
@objc(RSTSeparatorView)
public class RSTSeparatorView: UIView {
    private var _layoutMarginsDidChange = false
    private let separator = UIView()
    
    @IBInspectable
    public var lineWidth: CGFloat = 0.5 {
        didSet {
            guard lineWidth != oldValue else { return }
            invalidateIntrinsicContentSize()
        }
    }
    
    public override var tintColor: UIColor! {
        get { return super.tintColor }
        set {
            super.tintColor = newValue
            separator.backgroundColor = newValue
        }
    }
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        initialize()
    }
    
    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        initialize()
    }
    
    private func initialize() {
        self.isUserInteractionEnabled = false
        self.backgroundColor = nil
        
        separator.frame = self.bounds
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = self.tintColor
        self.addSubview(separator)
        
        if !_layoutMarginsDidChange {
            self.layoutMargins = .zero
        }
        
        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: self.layoutMarginsGuide.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: self.layoutMarginsGuide.trailingAnchor),
            separator.topAnchor.constraint(equalTo: self.layoutMarginsGuide.topAnchor),
            separator.bottomAnchor.constraint(equalTo: self.layoutMarginsGuide.bottomAnchor)
        ])
    }
    
    public override var intrinsicContentSize: CGSize {
        return CGSize(width: lineWidth, height: lineWidth)
    }
    
    public override func tintColorDidChange() {
        super.tintColorDidChange()
        separator.backgroundColor = self.tintColor
    }
    
    public override func layoutMarginsDidChange() {
        super.layoutMarginsDidChange()
        _layoutMarginsDidChange = true
    }
}
