//
//  Button.swift
//  AltStore
//
//  Created by Riley Testut on 5/9/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

final class Button: UIButton {
    override var intrinsicContentSize: CGSize {
        var size = super.intrinsicContentSize
        size.width += 20
        size.height += 10
        return size
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        setTitleColor(.white, for: .normal)

        layer.masksToBounds = true
        layer.cornerRadius = 8

        update()
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()

        update()
    }

    override var isHighlighted: Bool {
        didSet {
            self.update()
        }
    }

    override var isEnabled: Bool {
        didSet {
            update()
        }
    }
}

private extension Button {
    func update() {
        if isEnabled {
            backgroundColor = tintColor
        } else {
            backgroundColor = .lightGray
        }
    }
}
