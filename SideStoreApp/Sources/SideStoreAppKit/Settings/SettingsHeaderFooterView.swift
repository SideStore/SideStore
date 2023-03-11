//
//  SettingsHeaderFooterView.swift
//  AltStore
//
//  Created by Riley Testut on 8/31/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

import RoxasUIKit

final class SettingsHeaderFooterView: UITableViewHeaderFooterView {
    @IBOutlet var primaryLabel: UILabel!
    @IBOutlet var secondaryLabel: UILabel!
    @IBOutlet var button: UIButton!

    @IBOutlet private var stackView: UIStackView!

    override func awakeFromNib() {
        super.awakeFromNib()

        contentView.layoutMargins = .zero
        contentView.preservesSuperviewLayoutMargins = true

        stackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stackView)

        NSLayoutConstraint.activate([stackView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
                                     stackView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
                                     stackView.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
                                     stackView.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor)])
    }
}
