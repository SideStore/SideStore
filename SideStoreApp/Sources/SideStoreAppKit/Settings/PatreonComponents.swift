//
//  PatreonComponents.swift
//  AltStore
//
//  Created by Riley Testut on 9/5/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

@objc
final class PatronCollectionViewCell: UICollectionViewCell {
    @IBOutlet var textLabel: UILabel!
}

final class PatronsHeaderView: UICollectionReusableView {
    let textLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)

        textLabel.font = UIFont.boldSystemFont(ofSize: 17)
        textLabel.textColor = .white
        addSubview(textLabel, pinningEdgesWith: UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20))
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class PatronsFooterView: UICollectionReusableView {
    let button = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)

        button.translatesAutoresizingMaskIntoConstraints = false
        button.activityIndicatorView.style = .medium
        button.titleLabel?.textColor = .white
        addSubview(button)

        NSLayoutConstraint.activate([button.centerXAnchor.constraint(equalTo: centerXAnchor),
                                     button.centerYAnchor.constraint(equalTo: centerYAnchor)])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class AboutPatreonHeaderView: UICollectionReusableView {
    @IBOutlet var supportButton: UIButton!
    @IBOutlet var accountButton: UIButton!
    @IBOutlet var textView: UITextView!

    @IBOutlet private var rileyLabel: UILabel!
    @IBOutlet private var shaneLabel: UILabel!

    @IBOutlet private var rileyImageView: UIImageView!
    @IBOutlet private var shaneImageView: UIImageView!

    override func awakeFromNib() {
        super.awakeFromNib()

        textView.clipsToBounds = true
        textView.layer.cornerRadius = 20
        textView.textContainer.lineFragmentPadding = 0

        for imageView in [rileyImageView, shaneImageView].compactMap({ $0 }) {
            imageView.clipsToBounds = true
            imageView.layer.cornerRadius = imageView.bounds.midY
        }

        for button in [supportButton, accountButton].compactMap({ $0 }) {
            button.clipsToBounds = true
            button.layer.cornerRadius = 16
        }
    }

    override func layoutMarginsDidChange() {
        super.layoutMarginsDidChange()

        textView.textContainerInset = UIEdgeInsets(top: layoutMargins.left, left: layoutMargins.left, bottom: layoutMargins.right, right: layoutMargins.right)
    }
}
