//
//  NavigationBar.swift
//  AltStore
//
//  Created by Riley Testut on 7/15/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

import RoxasUIKit

@objc
final class NavigationBar: UINavigationBar {
	@objc
    @IBInspectable var automaticallyAdjustsItemPositions: Bool = true

    private let backgroundColorView = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)

        initialize()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)

        initialize()
    }

    private func initialize() {
        if #available(iOS 13, *) {
            let standardAppearance = UINavigationBarAppearance()
            standardAppearance.configureWithDefaultBackground()
            standardAppearance.shadowColor = nil

            let edgeAppearance = UINavigationBarAppearance()
            edgeAppearance.configureWithOpaqueBackground()
            edgeAppearance.backgroundColor = self.barTintColor
            edgeAppearance.shadowColor = nil

            if let tintColor = self.barTintColor {
                let textAttributes = [NSAttributedString.Key.foregroundColor: UIColor.white]

                standardAppearance.backgroundColor = tintColor
                standardAppearance.titleTextAttributes = textAttributes
                standardAppearance.largeTitleTextAttributes = textAttributes

                edgeAppearance.titleTextAttributes = textAttributes
                edgeAppearance.largeTitleTextAttributes = textAttributes
            } else {
                standardAppearance.backgroundColor = nil
            }

            self.scrollEdgeAppearance = edgeAppearance
            self.standardAppearance = standardAppearance
        } else {
            shadowImage = UIImage()

            if let tintColor = barTintColor {
                backgroundColorView.backgroundColor = tintColor

                // Top = -50 to cover status bar area above navigation bar on any device.
                // Bottom = -1 to prevent a flickering gray line from appearing.
                addSubview(backgroundColorView, pinningEdgesWith: UIEdgeInsets(top: -50, left: 0, bottom: -1, right: 0))
            } else {
                barTintColor = .white
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        if backgroundColorView.superview != nil {
            insertSubview(backgroundColorView, at: 1)
        }

        if automaticallyAdjustsItemPositions {
            // We can't easily shift just the back button up, so we shift the entire content view slightly.
            for contentView in subviews {
                guard NSStringFromClass(type(of: contentView)).contains("ContentView") else { continue }
                contentView.center.y -= 2
            }
        }
    }
}
