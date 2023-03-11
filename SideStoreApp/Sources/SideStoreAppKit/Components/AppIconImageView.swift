//
//  AppIconImageView.swift
//  AltStore
//
//  Created by Riley Testut on 5/9/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

final class AppIconImageView: UIImageView {
    override func awakeFromNib() {
        super.awakeFromNib()

        contentMode = .scaleAspectFill
        clipsToBounds = true

        backgroundColor = .white

        if #available(iOS 13, *) {
            self.layer.cornerCurve = .continuous
        } else {
            if layer.responds(to: Selector(("continuousCorners"))) {
                layer.setValue(true, forKey: "continuousCorners")
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // Based off of 60pt icon having 12pt radius.
        let radius = bounds.height / 5
        layer.cornerRadius = radius
    }
}
