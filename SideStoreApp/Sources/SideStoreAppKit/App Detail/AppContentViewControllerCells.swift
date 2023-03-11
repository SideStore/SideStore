//
//  AppContentViewControllerCells.swift
//  AltStore
//
//  Created by Riley Testut on 7/24/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

@objc
final class PermissionCollectionViewCell: UICollectionViewCell {
    @IBOutlet var button: UIButton!
    @IBOutlet var textLabel: UILabel!

    override func layoutSubviews() {
        super.layoutSubviews()

        button.layer.cornerRadius = button.bounds.midY
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()

        button.backgroundColor = tintColor.withAlphaComponent(0.15)
        textLabel.textColor = tintColor
    }
}

@objc
final class AppContentTableViewCell: UITableViewCell {
    override func systemLayoutSizeFitting(_ targetSize: CGSize, withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority, verticalFittingPriority: UILayoutPriority) -> CGSize {
        // Ensure cell is laid out so it will report correct size.
        layoutIfNeeded()

        let size = super.systemLayoutSizeFitting(targetSize, withHorizontalFittingPriority: horizontalFittingPriority, verticalFittingPriority: verticalFittingPriority)

        return size
    }
}
