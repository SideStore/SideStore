//
//  UpdateCollectionViewCell.swift
//  AltStore
//
//  Created by Riley Testut on 7/16/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

extension UpdateCollectionViewCell {
    enum Mode {
        case collapsed
        case expanded
    }
}

@objc final class UpdateCollectionViewCell: UICollectionViewCell {
    var mode: Mode = .expanded {
        didSet {
            update()
        }
    }

    @IBOutlet var bannerView: AppBannerView!
    @IBOutlet var versionDescriptionTitleLabel: UILabel!
    @IBOutlet var versionDescriptionTextView: CollapsingTextView!

    @IBOutlet private var blurView: UIVisualEffectView!

    private var originalTintColor: UIColor?

    override func awakeFromNib() {
        super.awakeFromNib()

        // Prevent temporary unsatisfiable constraint errors due to UIView-Encapsulated-Layout constraints.
        contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.preservesSuperviewLayoutMargins = true

        bannerView.backgroundEffectView.isHidden = true
        bannerView.button.setTitle(NSLocalizedString("UPDATE", comment: ""), for: .normal)

        blurView.layer.cornerRadius = 20
        blurView.layer.masksToBounds = true

        update()
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()

        if tintAdjustmentMode != .dimmed {
            originalTintColor = tintColor
        }

        update()
    }

    override func apply(_: UICollectionViewLayoutAttributes) {
        // Animates transition to new attributes.
        let animator = UIViewPropertyAnimator(springTimingParameters: UISpringTimingParameters()) {
            self.layoutIfNeeded()
        }
        animator.startAnimation()
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)

        if view == versionDescriptionTextView {
            // Forward touches on the text view (but not on the nested "more" button)
            // so cell selection works as expected.
            return self
        } else {
            return view
        }
    }
}

private extension UpdateCollectionViewCell {
    func update() {
        switch mode {
        case .collapsed: versionDescriptionTextView.isCollapsed = true
        case .expanded: versionDescriptionTextView.isCollapsed = false
        }

        versionDescriptionTitleLabel.textColor = originalTintColor ?? tintColor
        blurView.backgroundColor = originalTintColor ?? tintColor
        bannerView.button.progressTintColor = originalTintColor ?? tintColor

        setNeedsLayout()
        layoutIfNeeded()
    }
}
