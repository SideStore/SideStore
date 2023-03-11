//
//  PillButton.swift
//  AltStore
//
//  Created by Riley Testut on 7/15/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

final class PillButton: UIButton {
    override var accessibilityValue: String? {
        get {
            guard progress != nil else { return super.accessibilityValue }
            return progressView.accessibilityValue
        }
        set { super.accessibilityValue = newValue }
    }

    var progress: Progress? {
        didSet {
            progressView.progress = Float(progress?.fractionCompleted ?? 0)
            progressView.observedProgress = progress

            let isUserInteractionEnabled = self.isUserInteractionEnabled
            isIndicatingActivity = (progress != nil)
            self.isUserInteractionEnabled = isUserInteractionEnabled

            update()
        }
    }

    var progressTintColor: UIColor? {
        get {
            progressView.progressTintColor
        }
        set {
            progressView.progressTintColor = newValue
        }
    }

    var countdownDate: Date? {
        didSet {
            isEnabled = (countdownDate == nil)
            displayLink.isPaused = (countdownDate == nil)

            if countdownDate == nil {
                setTitle(nil, for: .disabled)
            }
        }
    }

    private let progressView = UIProgressView(progressViewStyle: .default)

    private lazy var displayLink: CADisplayLink = {
        let displayLink = CADisplayLink(target: self, selector: #selector(PillButton.updateCountdown))
        displayLink.preferredFramesPerSecond = 15
        displayLink.isPaused = true
        displayLink.add(to: .main, forMode: .common)
        return displayLink
    }()

    private let dateComponentsFormatter: DateComponentsFormatter = {
        let dateComponentsFormatter = DateComponentsFormatter()
        dateComponentsFormatter.zeroFormattingBehavior = [.pad]
        dateComponentsFormatter.collapsesLargestUnit = false
        return dateComponentsFormatter
    }()

    override var intrinsicContentSize: CGSize {
        var size = super.intrinsicContentSize
        size.width += 26
        size.height += 3
        return size
    }

    deinit {
        self.displayLink.remove(from: .main, forMode: RunLoop.Mode.default)
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        layer.masksToBounds = true
        accessibilityTraits.formUnion([.updatesFrequently, .button])

        activityIndicatorView.style = .medium
        activityIndicatorView.isUserInteractionEnabled = false

        progressView.progress = 0
        progressView.trackImage = UIImage()
        progressView.isUserInteractionEnabled = false
        addSubview(progressView)

        update()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        progressView.bounds.size.width = bounds.width

        let scale = bounds.height / progressView.bounds.height

        progressView.transform = CGAffineTransform.identity.scaledBy(x: 1, y: scale)
        progressView.center = CGPoint(x: bounds.midX, y: bounds.midY)

        layer.cornerRadius = bounds.midY
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()

        update()
    }
}

private extension PillButton {
    func update() {
        if progress == nil {
            setTitleColor(.white, for: .normal)
            backgroundColor = tintColor
        } else {
            setTitleColor(tintColor, for: .normal)
            backgroundColor = tintColor.withAlphaComponent(0.15)
        }

        progressView.progressTintColor = tintColor
    }

    @objc func updateCountdown() {
        guard let endDate = countdownDate else { return }

        let startDate = Date()

        let interval = endDate.timeIntervalSince(startDate)
        guard interval > 0 else {
            isEnabled = true
            return
        }

        let text: String?

        if interval < (1 * 60 * 60) {
            dateComponentsFormatter.unitsStyle = .positional
            dateComponentsFormatter.allowedUnits = [.minute, .second]

            text = dateComponentsFormatter.string(from: startDate, to: endDate)
        } else if interval < (2 * 24 * 60 * 60) {
            dateComponentsFormatter.unitsStyle = .positional
            dateComponentsFormatter.allowedUnits = [.hour, .minute, .second]

            text = dateComponentsFormatter.string(from: startDate, to: endDate)
        } else {
            dateComponentsFormatter.unitsStyle = .full
            dateComponentsFormatter.allowedUnits = [.day]

            let numberOfDays = endDate.numberOfCalendarDays(since: startDate)
            text = String(format: NSLocalizedString("%@ DAYS", comment: ""), NSNumber(value: numberOfDays))
        }

        if let text = text {
            UIView.performWithoutAnimation {
                self.isEnabled = false
                self.setTitle(text, for: .disabled)
                self.layoutIfNeeded()
            }
        } else {
            isEnabled = true
        }
    }
}
