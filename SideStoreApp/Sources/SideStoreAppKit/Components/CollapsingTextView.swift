//
//  CollapsingTextView.swift
//  AltStore
//
//  Created by Riley Testut on 7/23/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

final class CollapsingTextView: UITextView {
    var isCollapsed = true {
        didSet {
            setNeedsLayout()
        }
    }

    var maximumNumberOfLines = 2 {
        didSet {
            setNeedsLayout()
        }
    }

    var lineSpacing: CGFloat = 2 {
        didSet {
            setNeedsLayout()
        }
    }

    let moreButton = UIButton(type: .system)

    override func awakeFromNib() {
        super.awakeFromNib()

        layoutManager.delegate = self

        textContainerInset = .zero
        textContainer.lineFragmentPadding = 0
        textContainer.lineBreakMode = .byTruncatingTail
        textContainer.heightTracksTextView = true
        textContainer.widthTracksTextView = true

        moreButton.setTitle(NSLocalizedString("More", comment: ""), for: .normal)
        moreButton.addTarget(self, action: #selector(CollapsingTextView.toggleCollapsed(_:)), for: .primaryActionTriggered)
        addSubview(moreButton)

        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        guard let font = font else { return }

        let buttonFont = UIFont.systemFont(ofSize: font.pointSize, weight: .medium)
        moreButton.titleLabel?.font = buttonFont

        let buttonY = (font.lineHeight + lineSpacing) * CGFloat(maximumNumberOfLines - 1)
        let size = moreButton.sizeThatFits(CGSize(width: 1000, height: 1000))

        let moreButtonFrame = CGRect(x: bounds.width - moreButton.bounds.width,
                                     y: buttonY,
                                     width: size.width,
                                     height: font.lineHeight)
        moreButton.frame = moreButtonFrame

        if isCollapsed {
            textContainer.maximumNumberOfLines = maximumNumberOfLines

            let boundingSize = attributedText.boundingRect(with: CGSize(width: textContainer.size.width, height: .infinity), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            let maximumCollapsedHeight = font.lineHeight * Double(maximumNumberOfLines)

            if boundingSize.height.rounded() > maximumCollapsedHeight.rounded() {
                var exclusionFrame = moreButtonFrame
                exclusionFrame.origin.y += moreButton.bounds.midY
                exclusionFrame.size.width = bounds.width // Extra wide to make sure it wraps to next line.
                textContainer.exclusionPaths = [UIBezierPath(rect: exclusionFrame)]

                moreButton.isHidden = false
            } else {
                textContainer.exclusionPaths = []

                moreButton.isHidden = true
            }
        } else {
            textContainer.maximumNumberOfLines = 0
            textContainer.exclusionPaths = []

            moreButton.isHidden = true
        }

        invalidateIntrinsicContentSize()
    }
}

private extension CollapsingTextView {
    @objc func toggleCollapsed(_: UIButton) {
        isCollapsed.toggle()
    }
}

extension CollapsingTextView: NSLayoutManagerDelegate {
    func layoutManager(_: NSLayoutManager, lineSpacingAfterGlyphAt _: Int, withProposedLineFragmentRect _: CGRect) -> CGFloat {
        lineSpacing
    }
}
