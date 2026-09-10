//
//  ToastView.swift
//  AltStore
//
//  Created by Riley Testut on 7/19/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

@preconcurrency import UIKit

extension TimeInterval
{
    static let shortToastViewDuration = 4.0
    static let longToastViewDuration = 8.0
}

extension ToastView
{
    static let openErrorLogNotification = Notification.Name("ALTOpenErrorLogNotification")
    static let willShowNotification = Notification.Name("ToastViewWillShowNotification")
    static let didShowNotification = Notification.Name("ToastViewDidShowNotification")
    static let willDismissNotification = Notification.Name("ToastViewWillDismissNotification")
    static let didDismissNotification = Notification.Name("ToastViewDidDismissNotification")
    static let userInfoKeyPropertyAnimator = "ToastViewUserInfoKeyPropertyAnimator"

    public enum PresentationEdge: Int {
        case none
        case top
        case bottom
        case left
        case right
    }
}

class ToastView: UIControl
{
    public let textLabel = UILabel()
    public let detailTextLabel = UILabel()
    public let activityIndicatorView = UIActivityIndicatorView(style: .medium)

    var presentationEdge: PresentationEdge = .bottom {
        didSet {
            if presentationEdge == .none {
                presentationEdge = .bottom
            }
        }
    }

    var alignmentEdge: PresentationEdge = .none
    var edgeOffset = UIOffset(horizontal: 15, vertical: 15)

    private(set) var isShown = false
    var preferredDuration: TimeInterval
    var opensErrorLog: Bool = false

    private let dimmingView = UIView()
    private let stackView = UIStackView()
    private let labelsStackView = UIStackView()
    private var dismissTimer: Timer?

    private var axisConstraint: NSLayoutConstraint?
    private var hiddenAxisConstraint: NSLayoutConstraint?
    private var alignmentConstraint: NSLayoutConstraint?
    private var widthConstraint: NSLayoutConstraint?
    private var heightConstraint: NSLayoutConstraint?

    convenience init(text: String, detailText: String?, opensLog: Bool = false) {
        self.init(text: text, detailText: detailText)
        self.opensErrorLog = opensLog
    }

    init(text: String, detailText detailedText: String?)
    {
        if detailedText == nil
        {
            self.preferredDuration = .shortToastViewDuration
        }
        else
        {
            self.preferredDuration = .longToastViewDuration
        }

        super.init(frame: .zero)

        self.initialize()

        self.textLabel.text = text
        self.detailTextLabel.text = detailedText

        self.backgroundColor = .altPrimary
        self.textLabel.textColor = .white
        self.detailTextLabel.textColor = .white

        self.isAccessibilityElement = true

        self.layoutMargins = UIEdgeInsets(top: 8, left: 16, bottom: 10, right: 16)
        self.setNeedsLayout()

        self.labelsStackView.spacing = (detailedText != nil) ? 4.0 : 0.0
        self.labelsStackView.alignment = .leading

        self.addTarget(self, action: #selector(ToastView.showErrorLog), for: .touchUpInside)
    }

    public override init(frame: CGRect) {
        self.preferredDuration = .shortToastViewDuration
        super.init(frame: frame)
        self.initialize()
    }

    convenience init(error: Error, opensLog: Bool = false) {
        self.init(error: error)
        self.opensErrorLog = opensLog
    }

    enum InfoMode: String {
        case fullError
        case localizedDescription
    }

    convenience init(error: Error) {
        self.init(error: error, mode: .localizedDescription)
    }

    convenience init(error: Error, mode: InfoMode)
    {
        let error = error as NSError
        let mode = mode == .fullError ? ErrorProcessing.InfoMode.fullError : ErrorProcessing.InfoMode.localizedDescription

        let text = error.localizedTitle ?? NSLocalizedString("Operation Failed", comment: "")
        let detailText = ErrorProcessing(mode).getDescription(error: error)

        self.init(text: text, detailText: detailText)
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func initialize() {
        edgeOffset = UIOffset(horizontal: 15, vertical: 15)

        dimmingView.backgroundColor = .black
        dimmingView.alpha = 0.1
        dimmingView.isHidden = true
        dimmingView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(dimmingView)
        NSLayoutConstraint.activate([
            dimmingView.topAnchor.constraint(equalTo: self.topAnchor),
            dimmingView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            dimmingView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            dimmingView.trailingAnchor.constraint(equalTo: self.trailingAnchor)
        ])

        let detailTextLabelFontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .subheadline)
        let textLabelFontDescriptor = detailTextLabelFontDescriptor.withSymbolicTraits(.traitBold) ?? detailTextLabelFontDescriptor

        textLabel.font = UIFont(descriptor: textLabelFontDescriptor, size: 0)
        textLabel.textColor = .white
        textLabel.minimumScaleFactor = 0.75
        textLabel.numberOfLines = 0

        detailTextLabel.font = UIFont(descriptor: detailTextLabelFontDescriptor, size: 0)
        detailTextLabel.textColor = .white
        detailTextLabel.minimumScaleFactor = 0.75
        detailTextLabel.numberOfLines = 0

        activityIndicatorView.hidesWhenStopped = true

        labelsStackView.arrangedSubviews.forEach { labelsStackView.removeArrangedSubview($0) }
        labelsStackView.addArrangedSubview(textLabel)
        labelsStackView.addArrangedSubview(detailTextLabel)
        labelsStackView.axis = .vertical
        labelsStackView.alignment = .fill
        labelsStackView.spacing = 2.0

        stackView.arrangedSubviews.forEach { stackView.removeArrangedSubview($0) }
        stackView.addArrangedSubview(activityIndicatorView)
        stackView.addArrangedSubview(labelsStackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.isUserInteractionEnabled = false
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 8.0
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.insetsLayoutMarginsFromSafeArea = false
        self.addSubview(stackView)

        presentationEdge = .bottom
        alignmentEdge = .none

        let xAxis = UIInterpolatingMotionEffect(keyPath: "center.x", type: .tiltAlongHorizontalAxis)
        xAxis.minimumRelativeValue = -10
        xAxis.maximumRelativeValue = 10

        let yAxis = UIInterpolatingMotionEffect(keyPath: "center.y", type: .tiltAlongVerticalAxis)
        yAxis.minimumRelativeValue = -10
        yAxis.maximumRelativeValue = 10

        let group = UIMotionEffectGroup()
        group.motionEffects = [xAxis, yAxis]
        self.addMotionEffect(group)

        self.clipsToBounds = true
        self.translatesAutoresizingMaskIntoConstraints = false

        self.layoutMargins = UIEdgeInsets(top: 5, left: 10, bottom: 5, right: 10)
        self.preservesSuperviewLayoutMargins = false
        self.insetsLayoutMarginsFromSafeArea = false

        self.backgroundColor = UIColor(red: 61.0/255.0, green: 172.0/255.0, blue: 247.0/255.0, alpha: 1)

        NotificationCenter.default.addObserver(self, selector: #selector(toastViewWillShow(_:)), name: ToastView.willShowNotification, object: nil)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: self.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: self.trailingAnchor)
        ])
    }

    override var intrinsicContentSize: CGSize {
        if let superview = self.superview {
            let width = superview.bounds.width
            let preferredMaxLayoutWidth = width - (self.edgeOffset.horizontal * 2) - (self.layoutMargins.left + self.layoutMargins.right)
            textLabel.preferredMaxLayoutWidth = preferredMaxLayoutWidth
            detailTextLabel.preferredMaxLayoutWidth = preferredMaxLayoutWidth
        }
        return stackView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
    }

    override func layoutSubviews()
    {
        super.layoutSubviews()

        let minimumHeight = self.textLabel.font.lineHeight.rounded() + 18
        self.layer.cornerRadius = minimumHeight / 2

        if let superview = self.superview {
            let width = superview.bounds.width - superview.safeAreaInsets.left - superview.safeAreaInsets.right - (self.edgeOffset.horizontal * 2)
            textLabel.preferredMaxLayoutWidth = width
            detailTextLabel.preferredMaxLayoutWidth = width
        }

        invalidateIntrinsicContentSize()
    }

    override func updateConstraints() {
        if axisConstraint != nil || alignmentConstraint != nil {
            super.updateConstraints()
            return
        }

        guard let superview = self.superview else {
            super.updateConstraints()
            return
        }

        switch self.presentationEdge {
        case .left:
            axisConstraint = self.leftAnchor.constraint(equalTo: superview.safeAreaLayoutGuide.leftAnchor, constant: self.edgeOffset.horizontal)
            hiddenAxisConstraint = superview.leftAnchor.constraint(equalTo: self.rightAnchor)
        case .right:
            axisConstraint = superview.safeAreaLayoutGuide.rightAnchor.constraint(equalTo: self.rightAnchor, constant: self.edgeOffset.horizontal)
            hiddenAxisConstraint = self.leftAnchor.constraint(equalTo: superview.rightAnchor)
        case .top:
            axisConstraint = self.topAnchor.constraint(equalTo: superview.safeAreaLayoutGuide.topAnchor, constant: self.edgeOffset.vertical)
            hiddenAxisConstraint = superview.topAnchor.constraint(equalTo: self.bottomAnchor)
        case .bottom, .none:
            axisConstraint = superview.safeAreaLayoutGuide.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: self.edgeOffset.vertical)
            hiddenAxisConstraint = self.topAnchor.constraint(equalTo: superview.bottomAnchor)
        }

        switch self.presentationEdge {
        case .left, .right:
            switch self.alignmentEdge {
            case .top:
                alignmentConstraint = self.topAnchor.constraint(equalTo: superview.safeAreaLayoutGuide.topAnchor, constant: self.edgeOffset.vertical)
            case .bottom:
                alignmentConstraint = superview.safeAreaLayoutGuide.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: self.edgeOffset.vertical)
            default:
                alignmentConstraint = self.centerYAnchor.constraint(equalTo: superview.safeAreaLayoutGuide.centerYAnchor)
            }
        default:
            switch self.alignmentEdge {
            case .left:
                alignmentConstraint = self.leftAnchor.constraint(equalTo: superview.safeAreaLayoutGuide.leftAnchor, constant: self.edgeOffset.horizontal)
            case .right:
                alignmentConstraint = superview.safeAreaLayoutGuide.rightAnchor.constraint(equalTo: self.rightAnchor, constant: self.edgeOffset.horizontal)
            default:
                alignmentConstraint = self.centerXAnchor.constraint(equalTo: superview.safeAreaLayoutGuide.centerXAnchor)
            }
        }

        widthConstraint = self.widthAnchor.constraint(lessThanOrEqualTo: superview.safeAreaLayoutGuide.widthAnchor, constant: -(self.edgeOffset.horizontal * 2))
        heightConstraint = self.heightAnchor.constraint(lessThanOrEqualTo: superview.safeAreaLayoutGuide.heightAnchor, constant: -(self.edgeOffset.vertical * 2))

        if let hiddenConstraint = hiddenAxisConstraint, let alignConstraint = alignmentConstraint, let wConstraint = widthConstraint, let hConstraint = heightConstraint {
            NSLayoutConstraint.activate([hiddenConstraint, alignConstraint, wConstraint, hConstraint])
        }

        super.updateConstraints()
    }

    func show(in viewController: UIViewController)
    {
        self.show(in: viewController.navigationController?.view ?? viewController.view, duration: self.preferredDuration)
    }

    func show(in view: UIView, duration: TimeInterval)
    {
        dismissTimer?.invalidate()

        if duration > 0 {
            dismissTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                self?.dismiss()
            }
        } else {
            dismissTimer = nil
        }

        if isShown {
            return
        }

        isShown = true

        if opensErrorLog, case let configuration = UIImage.SymbolConfiguration(font: self.textLabel.font),
           let icon = UIImage(systemName: "chevron.right.circle", withConfiguration: configuration) {
            let tintedIcon = icon.withTintColor(.white, renderingMode: .alwaysOriginal)
            let moreIconImageView = UIImageView(image: tintedIcon)
            moreIconImageView.translatesAutoresizingMaskIntoConstraints = false
            self.addSubview(moreIconImageView)
            NSLayoutConstraint.activate([
                moreIconImageView.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -self.layoutMargins.right),
                moreIconImageView.centerYAnchor.constraint(equalTo: self.textLabel.centerYAnchor),
                moreIconImageView.leadingAnchor.constraint(greaterThanOrEqualToSystemSpacingAfter: self.textLabel.trailingAnchor, multiplier: 1.0)
            ])
        }

        textLabel.preferredMaxLayoutWidth = view.bounds.width
        detailTextLabel.preferredMaxLayoutWidth = view.bounds.width

        view.addSubview(self)
        view.layoutIfNeeded()

        hiddenAxisConstraint?.isActive = false
        axisConstraint?.isActive = true

        var distance: CGFloat = 0
        let overshoot: CGFloat = 10

        switch self.presentationEdge {
        case .left:
            distance = self.bounds.width + self.edgeOffset.horizontal + view.safeAreaInsets.left
        case .right:
            distance = self.bounds.width + self.edgeOffset.horizontal + view.safeAreaInsets.right
        case .top:
            distance = self.bounds.height + self.edgeOffset.vertical + view.safeAreaInsets.top
        default:
            distance = self.bounds.height + self.edgeOffset.vertical + view.safeAreaInsets.bottom
        }

        let percentOvershoot = overshoot / distance
        let dampingRatio = -log(percentOvershoot) / sqrt(pow(.pi, 2) + pow(log(percentOvershoot), 2))

        let timingParameters = UISpringTimingParameters(stiffness: 750.0, dampingRatio: dampingRatio)
        let animator = UIViewPropertyAnimator(springTimingParameters: timingParameters, animations: {
            view.layoutIfNeeded()
        })
        animator.addCompletion { [weak self] _ in
            guard let self = self else { return }
            NotificationCenter.default.post(name: ToastView.didShowNotification, object: self)
        }
        animator.startAnimation()

        NotificationCenter.default.post(name: ToastView.willShowNotification, object: self, userInfo: [ToastView.userInfoKeyPropertyAnimator: animator])

        let announcement = (self.textLabel.text ?? "") + ". " + (self.detailTextLabel.text ?? "")
        self.accessibilityLabel = announcement

        // Minimum 0.75 delay to prevent announcement being cut off by VoiceOver.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            UIAccessibility.post(notification: .announcement, argument: announcement)
        }
    }

    func show(in view: UIView)
    {
        self.show(in: view, duration: self.preferredDuration)
    }

    @objc func dismiss() {
        if !isShown {
            return
        }

        isShown = false

        if self.superview != nil {
            axisConstraint?.isActive = false
            hiddenAxisConstraint?.isActive = true
        }

        let timingParameters = UISpringTimingParameters(stiffness: 750.0, dampingRatio: 1.0)
        let animator = UIViewPropertyAnimator(springTimingParameters: timingParameters, animations: {
            self.superview?.layoutIfNeeded()
        })
        animator.addCompletion { [weak self] position in
            guard let self = self else { return }
            if position != .end { return }

            self.removeFromSuperview()

            self.axisConstraint = nil
            self.hiddenAxisConstraint = nil
            self.alignmentConstraint = nil

            NotificationCenter.default.post(name: ToastView.didDismissNotification, object: self)
        }
        animator.startAnimation()

        NotificationCenter.default.post(name: ToastView.willDismissNotification, object: self, userInfo: [ToastView.userInfoKeyPropertyAnimator: animator])
    }

    @objc private func toastViewWillShow(_ notification: Notification) {
        guard let toastView = notification.object as? ToastView, toastView != self else { return }
        if toastView.presentationEdge == self.presentationEdge {
            dismiss()
        }
    }

    override var isHighlighted: Bool {
        get { return super.isHighlighted }
        set {
            super.isHighlighted = newValue
            dimmingView.isHidden = !newValue
        }
    }

    override var layoutMargins: UIEdgeInsets {
        get { return super.layoutMargins }
        set {
            super.layoutMargins = newValue
            stackView.layoutMargins = newValue
        }
    }
}

private extension ToastView
{
    @objc func showErrorLog()
    {
        guard self.opensErrorLog else { return }

        NotificationCenter.default.post(name: ToastView.openErrorLogNotification, object: self)
    }
}
