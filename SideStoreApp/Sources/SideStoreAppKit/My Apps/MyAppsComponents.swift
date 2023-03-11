//
//  MyAppsComponents.swift
//  AltStore
//
//  Created by Riley Testut on 7/17/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import RoxasUIKit
import UIKit

@objc
final class InstalledAppCollectionViewCell: UICollectionViewCell {
    private(set) var deactivateBadge: UIView?

    @IBOutlet var bannerView: AppBannerView!

    override func awakeFromNib() {
        super.awakeFromNib()

        contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.preservesSuperviewLayoutMargins = true

        if #available(iOS 13.0, *) {
            let deactivateBadge = UIView()
            deactivateBadge.translatesAutoresizingMaskIntoConstraints = false
            deactivateBadge.isHidden = true
            self.addSubview(deactivateBadge)

            // Solid background to make the X opaque white.
            let backgroundView = UIView()
            backgroundView.translatesAutoresizingMaskIntoConstraints = false
            backgroundView.backgroundColor = .white
            deactivateBadge.addSubview(backgroundView)

            let badgeView = UIImageView(image: UIImage(systemName: "xmark.circle.fill"))
            badgeView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(scale: .large)
            badgeView.tintColor = .systemRed
            deactivateBadge.addSubview(badgeView, pinningEdgesWith: .zero)

            NSLayoutConstraint.activate([
                deactivateBadge.centerXAnchor.constraint(equalTo: self.bannerView.iconImageView.trailingAnchor),
                deactivateBadge.centerYAnchor.constraint(equalTo: self.bannerView.iconImageView.topAnchor),

                backgroundView.centerXAnchor.constraint(equalTo: badgeView.centerXAnchor),
                backgroundView.centerYAnchor.constraint(equalTo: badgeView.centerYAnchor),
                backgroundView.widthAnchor.constraint(equalTo: badgeView.widthAnchor, multiplier: 0.5),
                backgroundView.heightAnchor.constraint(equalTo: badgeView.heightAnchor, multiplier: 0.5)
            ])

            self.deactivateBadge = deactivateBadge
        }
    }
}

@objc
final class InstalledAppsCollectionFooterView: UICollectionReusableView {
    @IBOutlet var textLabel: UILabel!
    @IBOutlet var button: UIButton!
}

@objc
final class NoUpdatesCollectionViewCell: UICollectionViewCell {
    @IBOutlet var blurView: UIVisualEffectView!

    override func awakeFromNib() {
        super.awakeFromNib()

        contentView.preservesSuperviewLayoutMargins = true
    }
}

@objc
final class UpdatesCollectionHeaderView: UICollectionReusableView {
    let button = PillButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)

        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(">", for: .normal)
        addSubview(button)

        NSLayoutConstraint.activate([button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
                                     button.topAnchor.constraint(equalTo: topAnchor),
                                     button.widthAnchor.constraint(equalToConstant: 50),
                                     button.heightAnchor.constraint(equalToConstant: 26)])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
