//
//  RSTTintedImageView.swift
//  AltStoreCore
//
//  Created by Magesh K on 6/17/26.
//

import UIKit

@objc(RSTTintedImageView)
public class RSTTintedImageView: UIImageView {
    public override func awakeFromNib() {
        super.awakeFromNib()
        
        let originalTintColor = self.tintColor
        self.tintColor = nil
        self.tintColor = originalTintColor
    }
}
