//
//  AppBannerView.swift
//  AltStore
//
//  Created by Riley Testut on 8/29/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

import SideStoreCore
import RoxasUIKit

class AppBannerView: RSTNibView {
    override var accessibilityLabel: String? {
        get { self.accessibilityView?.accessibilityLabel }
        set { self.accessibilityView?.accessibilityLabel = newValue }
    }

    override open var accessibilityAttributedLabel: NSAttributedString? {
        get { self.accessibilityView?.accessibilityAttributedLabel }
        set { self.accessibilityView?.accessibilityAttributedLabel = newValue }
    }

    override var accessibilityValue: String? {
        get { self.accessibilityView?.accessibilityValue }
        set { self.accessibilityView?.accessibilityValue = newValue }
    }

    override open var accessibilityAttributedValue: NSAttributedString? {
        get { self.accessibilityView?.accessibilityAttributedValue }
        set { self.accessibilityView?.accessibilityAttributedValue = newValue }
    }

    override open var accessibilityTraits: UIAccessibilityTraits {
        get { accessibilityView?.accessibilityTraits ?? [] }
        set { accessibilityView?.accessibilityTraits = newValue }
    }

    private var originalTintColor: UIColor?

    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var subtitleLabel: UILabel!
    @IBOutlet var iconImageView: AppIconImageView!
    @IBOutlet var button: PillButton!
    @IBOutlet var buttonLabel: UILabel!
    @IBOutlet var betaBadgeView: UIView!

    @IBOutlet var backgroundEffectView: UIVisualEffectView!

    @IBOutlet private var vibrancyView: UIVisualEffectView!
    @IBOutlet private var accessibilityView: UIView!

    override init(frame: CGRect) {
        super.init(frame: frame)

        initialize()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)

        initialize()
    }

    private func initialize() {
        accessibilityView.accessibilityTraits.formUnion(.button)

        isAccessibilityElement = false
        accessibilityElements = [accessibilityView, button].compactMap { $0 }

        betaBadgeView.isHidden = true
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()

        if tintAdjustmentMode != .dimmed {
            originalTintColor = tintColor
        }

        update()
    }
}

extension AppBannerView {
    func configure(for app: AppProtocol) {
        struct AppValues {
            var name: String
            var developerName: String?
            var isBeta: Bool = false

            init(app: AppProtocol) {
                name = app.name

                guard let storeApp = (app as? StoreApp) ?? (app as? InstalledApp)?.storeApp else { return }
                developerName = storeApp.developerName

                if storeApp.isBeta {
                    name = String(format: NSLocalizedString("%@ beta", comment: ""), app.name)
                    isBeta = true
                }
            }
        }

        let values = AppValues(app: app)
        titleLabel.text = app.name // Don't use values.name since that already includes "beta".
        betaBadgeView.isHidden = !values.isBeta

        if let developerName = values.developerName {
            subtitleLabel.text = developerName
            accessibilityLabel = String(format: NSLocalizedString("%@ by %@", comment: ""), values.name, developerName)
        } else {
            subtitleLabel.text = NSLocalizedString("Sideloaded", comment: "")
            accessibilityLabel = values.name
        }
    }
}

private extension AppBannerView {
    func update() {
        clipsToBounds = true
        layer.cornerRadius = 22

        subtitleLabel.textColor = originalTintColor ?? tintColor
        backgroundEffectView.backgroundColor = originalTintColor ?? tintColor
    }
}
