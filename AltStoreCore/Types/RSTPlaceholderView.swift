//
//  RSTPlaceholderView.swift
//  AltStoreCore
//
//  Created by Magesh K on 6/17/26.
//

import UIKit

@IBDesignable
@objc(RSTPlaceholderView)
public class RSTPlaceholderView: RSTNibView {
    @IBOutlet public var textLabel: UILabel!
    @IBOutlet public var detailTextLabel: UILabel!
    @IBOutlet public var activityIndicatorView: UIActivityIndicatorView!
    @IBOutlet public var imageView: UIImageView!
    @IBOutlet public var stackView: UIStackView!
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        initialize()
    }
    
    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        initialize()
    }
    
    private func initialize() {
        self.activityIndicatorView.isHidden = true
        self.imageView.isHidden = true
        
        if UIDevice.current.userInterfaceIdiom == .tv {
            self.stackView.spacing = 15
            self.detailTextLabel.font = UIFont.preferredFont(forTextStyle: .headline)
        }
    }
}
