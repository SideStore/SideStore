//
//  RSTToastView.swift
//  AltStoreCore
//
//  Created by Magesh K on 6/17/26.
//

import UIKit

@objc(RSTViewEdge)
public enum RSTViewEdge: Int {
    case none
    case top
    case bottom
    case left
    case right
}

extension RSTToastView {
    @objc(willShowNotification)
    public static let willShowNotification = Notification.Name("RSTToastViewWillShowNotification")
    
    @objc(didShowNotification)
    public static let didShowNotification = Notification.Name("RSTToastViewDidShowNotification")
    
    @objc(willDismissNotification)
    public static let willDismissNotification = Notification.Name("RSTToastViewWillDismissNotification")
    
    @objc(didDismissNotification)
    public static let didDismissNotification = Notification.Name("RSTToastViewDidDismissNotification")
    
    @objc(RSTToastViewUserInfoKeyPropertyAnimator)
    public static let userInfoKeyPropertyAnimator = "RSTToastViewUserInfoKeyPropertyAnimator"
}

private var toastViewContext = 0

@objc(RSTToastView)
open class RSTToastView: UIControl {
    @objc open override var tintColor: UIColor! {
        get { return super.tintColor }
        set {
            super.tintColor = newValue
            self.backgroundColor = newValue
        }
    }
    
    @objc public let textLabel = UILabel()
    @objc public let detailTextLabel = UILabel()
    @objc public let activityIndicatorView = UIActivityIndicatorView(style: .white)
    
    @objc open var presentationEdge: RSTViewEdge = .bottom {
        didSet {
            if presentationEdge == .none {
                presentationEdge = .bottom
            }
        }
    }
    
    @objc open var alignmentEdge: RSTViewEdge = .none
    @objc open var edgeOffset = UIOffset(horizontal: 15, vertical: 15)
    
    @objc open private(set) var isShown = false
    
    private let dimmingView = UIView()
    private let stackView = UIStackView()
    private var dismissTimer: Timer?
    
    private var axisConstraint: NSLayoutConstraint?
    private var hiddenAxisConstraint: NSLayoutConstraint?
    private var alignmentConstraint: NSLayoutConstraint?
    private var widthConstraint: NSLayoutConstraint?
    private var heightConstraint: NSLayoutConstraint?
    
    @objc(initWithText:detailText:)
    public init(text: String, detailText: String?) {
        super.init(frame: .zero)
        initialize()
        textLabel.text = text
        detailTextLabel.text = detailText
    }
    
    @objc(initWithError:)
    public convenience init(error: Error) {
        let nsError = error as NSError
        self.init(text: nsError.localizedDescription, detailText: nsError.localizedFailureReason)
    }
    
    public override init(frame: CGRect) {
        super.init(frame: .zero)
        initialize()
    }
    
    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        initialize()
    }
    
    deinit {
        textLabel.removeObserver(self, forKeyPath: "text", context: &toastViewContext)
        detailTextLabel.removeObserver(self, forKeyPath: "text", context: &toastViewContext)
    }
    
    private func initialize() {
        edgeOffset = UIOffset(horizontal: 15, vertical: 15)
        
        dimmingView.backgroundColor = .black
        dimmingView.alpha = 0.1
        dimmingView.isHidden = true
        self.addSubview(dimmingView, pinningEdgesWith: .zero)
        
        let detailTextLabelFontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .subheadline)
        let textLabelFontDescriptor = detailTextLabelFontDescriptor.withSymbolicTraits(.traitBold) ?? detailTextLabelFontDescriptor
        
        textLabel.font = UIFont(descriptor: textLabelFontDescriptor, size: 0)
        textLabel.textColor = .white
        textLabel.minimumScaleFactor = 0.75
        textLabel.numberOfLines = 0
        textLabel.addObserver(self, forKeyPath: "text", options: .old, context: &toastViewContext)
        
        detailTextLabel.font = UIFont(descriptor: detailTextLabelFontDescriptor, size: 0)
        detailTextLabel.textColor = .white
        detailTextLabel.minimumScaleFactor = 0.75
        detailTextLabel.numberOfLines = 0
        detailTextLabel.addObserver(self, forKeyPath: "text", options: .old, context: &toastViewContext)
        
        activityIndicatorView.hidesWhenStopped = true
        
        let labelsStackView = UIStackView(arrangedSubviews: [textLabel, detailTextLabel])
        labelsStackView.axis = .vertical
        labelsStackView.alignment = .fill
        labelsStackView.spacing = 2.0
        
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
        
        self.addTarget(self, action: #selector(dismiss), for: .touchUpInside)
        
        NotificationCenter.default.addObserver(self, selector: #selector(toastViewWillShow(_:)), name: RSTToastView.willShowNotification, object: nil)
        
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: self.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: self.trailingAnchor)
        ])
    }
    
    open override var intrinsicContentSize: CGSize {
        if let superview = self.superview {
            let width = superview.bounds.width
            let preferredMaxLayoutWidth = width - (self.edgeOffset.horizontal * 2) - (self.layoutMargins.left + self.layoutMargins.right)
            textLabel.preferredMaxLayoutWidth = preferredMaxLayoutWidth
            detailTextLabel.preferredMaxLayoutWidth = preferredMaxLayoutWidth
        }
        return stackView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
    }
    
    open override func layoutSubviews() {
        super.layoutSubviews()
        
        let cornerRadius = min(10.0, self.bounds.midY)
        self.layer.cornerRadius = cornerRadius
        
        if let superview = self.superview {
            let width = superview.bounds.width - superview.safeAreaInsets.left - superview.safeAreaInsets.right - (self.edgeOffset.horizontal * 2)
            textLabel.preferredMaxLayoutWidth = width
            detailTextLabel.preferredMaxLayoutWidth = width
        }
        
        invalidateIntrinsicContentSize()
    }
    
    open override func updateConstraints() {
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
    
    open override func tintColorDidChange() {
        super.tintColorDidChange()
        self.backgroundColor = self.tintColor
    }
    
    @objc(showInView:)
    open func show(in view: UIView) {
        show(in: view, duration: 0)
    }
    
    @objc(showInView:duration:)
    open func show(in view: UIView, duration: TimeInterval) {
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
        animator.addCompletion { [weak self] position in
            guard let self = self else { return }
            NotificationCenter.default.post(name: RSTToastView.didShowNotification, object: self)
        }
        animator.startAnimation()
        
        NotificationCenter.default.post(name: RSTToastView.willShowNotification, object: self, userInfo: [RSTToastView.userInfoKeyPropertyAnimator: animator])
    }
    
    @objc open func dismiss() {
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
            
            NotificationCenter.default.post(name: RSTToastView.didDismissNotification, object: self)
        }
        animator.startAnimation()
        
        NotificationCenter.default.post(name: RSTToastView.willDismissNotification, object: self, userInfo: [RSTToastView.userInfoKeyPropertyAnimator: animator])
    }
    
    open override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if context == &toastViewContext {
            invalidateIntrinsicContentSize()
            
            guard let label = object as? UILabel, let previousText = change?[.oldKey] as? String else { return }
            
            if self.superview != nil {
                var initialAlpha: CGFloat = 1.0
                var finalAlpha: CGFloat = 1.0
                
                if previousText.isEmpty && !(label.text?.isEmpty ?? true) {
                    initialAlpha = 0.0
                    finalAlpha = 1.0
                } else if !previousText.isEmpty && (label.text?.isEmpty ?? true) {
                    initialAlpha = 1.0
                    finalAlpha = 0.0
                }
                
                label.alpha = initialAlpha
                
                let animator = UIViewPropertyAnimator(springTimingParameters: UISpringTimingParameters(), animations: {
                    label.alpha = finalAlpha
                    self.superview?.layoutIfNeeded()
                })
                animator.startAnimation()
            }
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }
    
    @objc private func toastViewWillShow(_ notification: Notification) {
        guard let toastView = notification.object as? RSTToastView, toastView != self else { return }
        if toastView.presentationEdge == self.presentationEdge {
            dismiss()
        }
    }
    
    open override var isHighlighted: Bool {
        get { return super.isHighlighted }
        set {
            super.isHighlighted = newValue
            dimmingView.isHidden = !newValue
        }
    }
    
    open override var layoutMargins: UIEdgeInsets {
        get { return super.layoutMargins }
        set {
            super.layoutMargins = newValue
            stackView.layoutMargins = newValue
        }
    }
}
