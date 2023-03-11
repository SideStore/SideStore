//
//  InsetGroupTableViewCell.swift
//  AltStore
//
//  Created by Riley Testut on 8/31/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

extension InsetGroupTableViewCell {
    @objc enum Style: Int {
        case single
        case top
        case middle
        case bottom
    }
}

final class InsetGroupTableViewCell: UITableViewCell {
    #if !TARGET_INTERFACE_BUILDER
        @IBInspectable var style: Style = .single {
            didSet {
                self.update()
            }
        }
    #else
        @IBInspectable var style: Int = 0
    #endif

    @IBInspectable var isSelectable: Bool = false

    private let separatorView = UIView()
    private let insetView = UIView()

    override func awakeFromNib() {
        super.awakeFromNib()

        selectionStyle = .none

        separatorView.translatesAutoresizingMaskIntoConstraints = false
        separatorView.backgroundColor = UIColor.white.withAlphaComponent(0.25)
        addSubview(separatorView)

        insetView.layer.masksToBounds = true
        insetView.layer.cornerRadius = 16

        // Get the preferred background color from Interface Builder.
        insetView.backgroundColor = backgroundColor
        backgroundColor = nil

        addSubview(insetView, pinningEdgesWith: UIEdgeInsets(top: 0, left: 15, bottom: 0, right: 15))
        sendSubviewToBack(insetView)

        NSLayoutConstraint.activate([separatorView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 30),
                                     separatorView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -30),
                                     separatorView.bottomAnchor.constraint(equalTo: bottomAnchor),
                                     separatorView.heightAnchor.constraint(equalToConstant: 1)])

        update()
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        if animated {
            UIView.animate(withDuration: 0.4) {
                self.update()
            }
        } else {
            update()
        }
    }

    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)

        if animated {
            UIView.animate(withDuration: 0.4) {
                self.update()
            }
        } else {
            update()
        }
    }
}

private extension InsetGroupTableViewCell {
    func update() {
        switch style {
        case .single:
            insetView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            separatorView.isHidden = true

        case .top:
            insetView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            separatorView.isHidden = false

        case .middle:
            insetView.layer.maskedCorners = []
            separatorView.isHidden = false

        case .bottom:
            insetView.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            separatorView.isHidden = true
        }

        if isSelectable && (isHighlighted || isSelected) {
            insetView.backgroundColor = UIColor.white.withAlphaComponent(0.55)
        } else {
            insetView.backgroundColor = UIColor.white.withAlphaComponent(0.25)
        }
    }
}
