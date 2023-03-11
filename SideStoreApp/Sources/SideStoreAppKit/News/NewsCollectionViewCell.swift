//
//  NewsCollectionViewCell.swift
//  AltStore
//
//  Created by Riley Testut on 8/29/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

@objc
final class NewsCollectionViewCell: UICollectionViewCell {
    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var captionLabel: UILabel!
    @IBOutlet var imageView: UIImageView!
    @IBOutlet var contentBackgroundView: UIView!

    override func awakeFromNib() {
        super.awakeFromNib()

        contentView.preservesSuperviewLayoutMargins = true

        contentBackgroundView.layer.cornerRadius = 30
        contentBackgroundView.clipsToBounds = true

        imageView.layer.cornerRadius = 30
        imageView.clipsToBounds = true
    }
}
