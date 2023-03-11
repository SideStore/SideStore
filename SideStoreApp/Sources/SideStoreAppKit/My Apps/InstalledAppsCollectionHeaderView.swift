//
//  InstalledAppsCollectionHeaderView.swift
//  AltStore
//
//  Created by Riley Testut on 3/9/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import UIKit

final class InstalledAppsCollectionHeaderView: UICollectionReusableView {
    let textLabel: UILabel
    let button: UIButton

    override init(frame: CGRect) {
        textLabel = UILabel()
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.font = UIFont.systemFont(ofSize: 24, weight: .bold)
        textLabel.accessibilityTraits.insert(.header)

        button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)

        super.init(frame: frame)

        addSubview(textLabel)
        addSubview(button)

        NSLayoutConstraint.activate([textLabel.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
                                     textLabel.bottomAnchor.constraint(equalTo: bottomAnchor)])

        NSLayoutConstraint.activate([button.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
                                     button.firstBaselineAnchor.constraint(equalTo: textLabel.firstBaselineAnchor)])

        preservesSuperviewLayoutMargins = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
