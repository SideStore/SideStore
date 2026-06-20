//
//  UIKit+ActivityIndicating.swift
//  AltStoreCore
//
//  Created by Magesh K on 6/17/26.
//

import UIKit
import ObjectiveC

@objc(RSTActivityIndicating)
public protocol RSTActivityIndicating: AnyObject {
    @objc var isIndicatingActivity: Bool { get set }
    @objc var activityCount: Int { get }
    
    @objc func incrementActivityCount()
    @objc func decrementActivityCount()
}

private var activityIndicatingHelperKey: UInt8 = 0

internal final class ActivityIndicatingHelper: NSObject, RSTActivityIndicating {
    weak var indicatingObject: AnyObject?
    
    private let queue = DispatchQueue(label: "com.rileytestut.Roxas.activityCountQueue")
    private var _activityCount: Int = 0
    private var _isIndicatingActivity = false
    
    var userInfo = [String: Any]()
    
    private var _activityIndicatorView: UIActivityIndicatorView?
    var activityIndicatorView: UIActivityIndicatorView {
        if let view = _activityIndicatorView {
            return view
        }
        let view = UIActivityIndicatorView(style: .medium)
        view.translatesAutoresizingMaskIntoConstraints = false
        _activityIndicatorView = view
        return view
    }
    
    init(indicatingObject: AnyObject) {
        self.indicatingObject = indicatingObject
        super.init()
    }
    
    var activityCount: Int {
        return queue.sync { _activityCount }
    }
    
    var isIndicatingActivity: Bool {
        get { return queue.sync { _isIndicatingActivity } }
        set {
            if newValue {
                activityIndicatorView.startAnimating()
            } else {
                activityIndicatorView.stopAnimating()
            }
            
            queue.sync {
                guard _isIndicatingActivity != newValue else { return }
                _isIndicatingActivity = newValue
            }
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if newValue {
                    (self.indicatingObject as? _ActivityIndicating)?.startIndicatingActivity()
                } else {
                    (self.indicatingObject as? _ActivityIndicating)?.stopIndicatingActivity()
                }
            }
        }
    }
    
    func incrementActivityCount() {
        queue.sync {
            _activityCount += 1
            if _activityCount == 1 {
                DispatchQueue.main.async {
                    self.isIndicatingActivity = true
                }
            }
        }
    }
    
    func decrementActivityCount() {
        queue.sync {
            guard _activityCount > 0 else { return }
            _activityCount -= 1
            if _activityCount == 0 {
                DispatchQueue.main.async {
                    self.isIndicatingActivity = false
                }
            }
        }
    }
}

internal protocol _ActivityIndicating: AnyObject {
    func startIndicatingActivity()
    func stopIndicatingActivity()
}

extension NSObject {
    var activityIndicatingHelper: ActivityIndicatingHelper {
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }
        
        if let helper = objc_getAssociatedObject(self, &activityIndicatingHelperKey) as? ActivityIndicatingHelper {
            return helper
        }
        
        let helper = ActivityIndicatingHelper(indicatingObject: self)
        objc_setAssociatedObject(self, &activityIndicatingHelperKey, helper, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return helper
    }
}

extension UIButton: _ActivityIndicating, RSTActivityIndicating {
    @objc open var isIndicatingActivity: Bool {
        get { return activityIndicatingHelper.isIndicatingActivity }
        set { activityIndicatingHelper.isIndicatingActivity = newValue }
    }
    
    public var activityCount: Int {
        return activityIndicatingHelper.activityCount
    }
    
    public func incrementActivityCount() {
        activityIndicatingHelper.incrementActivityCount()
    }
    
    public func decrementActivityCount() {
        activityIndicatingHelper.decrementActivityCount()
    }
    
    @objc(rst_activityIndicatorView)
    public var activityIndicatorView: UIActivityIndicatorView {
        return activityIndicatingHelper.activityIndicatorView
    }
    
    func startIndicatingActivity() {
        let title = self.title(for: .normal)
        activityIndicatingHelper.userInfo["title"] = title
        
        let image = self.image(for: .normal)
        activityIndicatingHelper.userInfo["image"] = image
        
        let enabled = self.isUserInteractionEnabled
        activityIndicatingHelper.userInfo["enabled"] = enabled
        
        if !self.translatesAutoresizingMaskIntoConstraints {
            let widthConstraint = self.widthAnchor.constraint(equalToConstant: self.bounds.width)
            widthConstraint.isActive = true
            activityIndicatingHelper.userInfo["widthConstraint"] = widthConstraint
        }
        
        self.setTitle(nil, for: .normal)
        self.setImage(nil, for: .normal)
        self.isUserInteractionEnabled = false
        
        let indicator = activityIndicatingHelper.activityIndicatorView
        self.addSubview(indicator)
        
        NSLayoutConstraint.activate([
            indicator.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            indicator.centerYAnchor.constraint(equalTo: self.centerYAnchor)
        ])
    }
    
    func stopIndicatingActivity() {
        activityIndicatingHelper.activityIndicatorView.removeFromSuperview()
        
        let title = activityIndicatingHelper.userInfo["title"] as? String
        self.setTitle(title, for: .normal)
        
        let image = activityIndicatingHelper.userInfo["image"] as? UIImage
        self.setImage(image, for: .normal)
        
        let enabled = activityIndicatingHelper.userInfo["enabled"] as? Bool ?? true
        self.isUserInteractionEnabled = enabled
        
        if let widthConstraint = activityIndicatingHelper.userInfo["widthConstraint"] as? NSLayoutConstraint {
            widthConstraint.isActive = false
        }
        
        activityIndicatingHelper.userInfo["title"] = nil
        activityIndicatingHelper.userInfo["image"] = nil
        activityIndicatingHelper.userInfo["enabled"] = nil
        activityIndicatingHelper.userInfo["widthConstraint"] = nil
    }
}

extension UIBarButtonItem: _ActivityIndicating, RSTActivityIndicating {
    public var isIndicatingActivity: Bool {
        get { return activityIndicatingHelper.isIndicatingActivity }
        set { activityIndicatingHelper.isIndicatingActivity = newValue }
    }
    
    public var activityCount: Int {
        return activityIndicatingHelper.activityCount
    }
    
    public func incrementActivityCount() {
        activityIndicatingHelper.incrementActivityCount()
    }
    
    public func decrementActivityCount() {
        activityIndicatingHelper.decrementActivityCount()
    }
    
    @objc(rst_activityIndicatorView)
    public var activityIndicatorView: UIActivityIndicatorView {
        return activityIndicatingHelper.activityIndicatorView
    }
    
    func startIndicatingActivity() {
        let customView = UIView()
        customView.translatesAutoresizingMaskIntoConstraints = false
        
        let indicator = activityIndicatingHelper.activityIndicatorView
        customView.addSubview(indicator)
        
        NSLayoutConstraint.activate([
            indicator.leadingAnchor.constraint(equalTo: customView.leadingAnchor, constant: 8),
            indicator.trailingAnchor.constraint(equalTo: customView.trailingAnchor, constant: -8),
            indicator.topAnchor.constraint(equalTo: customView.topAnchor),
            indicator.bottomAnchor.constraint(equalTo: customView.bottomAnchor)
        ])
        
        activityIndicatingHelper.userInfo["enabled"] = self.isEnabled
        activityIndicatingHelper.userInfo["customView"] = self.customView
        
        self.isEnabled = false
        self.customView = customView
    }
    
    func stopIndicatingActivity() {
        let enabled = activityIndicatingHelper.userInfo["enabled"] as? Bool ?? true
        self.isEnabled = enabled
        
        let customView = activityIndicatingHelper.userInfo["customView"] as? UIView
        self.customView = customView
        
        activityIndicatingHelper.userInfo["enabled"] = nil
        activityIndicatingHelper.userInfo["customView"] = nil
    }
}

extension UIImageView: _ActivityIndicating, RSTActivityIndicating {
    public var isIndicatingActivity: Bool {
        get { return activityIndicatingHelper.isIndicatingActivity }
        set { activityIndicatingHelper.isIndicatingActivity = newValue }
    }
    
    public var activityCount: Int {
        return activityIndicatingHelper.activityCount
    }
    
    public func incrementActivityCount() {
        activityIndicatingHelper.incrementActivityCount()
    }
    
    public func decrementActivityCount() {
        activityIndicatingHelper.decrementActivityCount()
    }
    
    @objc(rst_activityIndicatorView)
    public var activityIndicatorView: UIActivityIndicatorView {
        return activityIndicatingHelper.activityIndicatorView
    }
    
    func startIndicatingActivity() {
        let indicator = activityIndicatingHelper.activityIndicatorView
        self.addSubview(indicator)
        
        NSLayoutConstraint.activate([
            indicator.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            indicator.centerYAnchor.constraint(equalTo: self.centerYAnchor)
        ])
    }
    
    func stopIndicatingActivity() {
        activityIndicatingHelper.activityIndicatorView.removeFromSuperview()
    }
}

extension UITextField: _ActivityIndicating, RSTActivityIndicating {
    public var isIndicatingActivity: Bool {
        get { return activityIndicatingHelper.isIndicatingActivity }
        set { activityIndicatingHelper.isIndicatingActivity = newValue }
    }
    
    public var activityCount: Int {
        return activityIndicatingHelper.activityCount
    }
    
    public func incrementActivityCount() {
        activityIndicatingHelper.incrementActivityCount()
    }
    
    public func decrementActivityCount() {
        activityIndicatingHelper.decrementActivityCount()
    }
    
    @objc(rst_activityIndicatorView)
    public var activityIndicatorView: UIActivityIndicatorView {
        return activityIndicatingHelper.activityIndicatorView
    }
    
    func startIndicatingActivity() {
        let customView = self.rightView
        activityIndicatingHelper.userInfo["customView"] = customView
        
        let viewMode = self.rightViewMode
        activityIndicatingHelper.userInfo["viewMode"] = viewMode.rawValue
        
        let enabled = self.isUserInteractionEnabled
        activityIndicatingHelper.userInfo["enabled"] = enabled
        
        self.rightView = activityIndicatingHelper.activityIndicatorView
        self.rightViewMode = .always
        self.isUserInteractionEnabled = false
        
        self.layoutIfNeeded()
        self.setNeedsLayout()
        self.layoutIfNeeded()
    }
    
    func stopIndicatingActivity() {
        let customView = activityIndicatingHelper.userInfo["customView"] as? UIView
        self.rightView = customView
        
        if let rawMode = activityIndicatingHelper.userInfo["viewMode"] as? Int, let viewMode = UITextField.ViewMode(rawValue: rawMode) {
            self.rightViewMode = viewMode
        }
        
        let enabled = activityIndicatingHelper.userInfo["enabled"] as? Bool ?? true
        self.isUserInteractionEnabled = enabled
        
        activityIndicatingHelper.userInfo["customView"] = nil
        activityIndicatingHelper.userInfo["viewMode"] = nil
        activityIndicatingHelper.userInfo["enabled"] = nil
    }
}

extension UIApplication: _ActivityIndicating, RSTActivityIndicating {
    public var isIndicatingActivity: Bool {
        get { return activityIndicatingHelper.isIndicatingActivity }
        set { activityIndicatingHelper.isIndicatingActivity = newValue }
    }
    
    public var activityCount: Int {
        return activityIndicatingHelper.activityCount
    }
    
    public func incrementActivityCount() {
        activityIndicatingHelper.incrementActivityCount()
    }
    
    public func decrementActivityCount() {
        activityIndicatingHelper.decrementActivityCount()
    }
    
    func startIndicatingActivity() {
        // networkActivityIndicatorVisible is deprecated in iOS 13, but we can compile it
        #if os(iOS)
        self.isNetworkActivityIndicatorVisible = true
        #endif
    }
    
    func stopIndicatingActivity() {
        #if os(iOS)
        self.isNetworkActivityIndicatorVisible = false
        #endif
    }
}
