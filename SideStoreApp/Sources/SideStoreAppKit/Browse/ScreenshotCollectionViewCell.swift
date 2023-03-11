//
//  ScreenshotCollectionViewCell.swift
//  AltStore
//
//  Created by Riley Testut on 7/15/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

import RoxasUIKit

@objc(ScreenshotCollectionViewCell)
class ScreenshotCollectionViewCell: UICollectionViewCell {
    let imageView = UIImageView(image: nil)

    override init(frame: CGRect) {
        super.init(frame: frame)

        initialize()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)

        initialize()
    }

    private func initialize() {
        imageView.layer.masksToBounds = true
        addSubview(imageView, pinningEdgesWith: .zero)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        imageView.layer.cornerRadius = 4
    }
}
