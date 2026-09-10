//
//  UIKit+ActivityIndicating.swift
//  AltStore
//
//  Created by Magesh K on 8/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

@preconcurrency import UIKit
import ObjectiveC

public protocol ActivityIndicating: AnyObject {
    var isIndicatingActivity: Bool { get set }
    var activityCount: Int { get }
    
    func incrementActivityCount()
    func decrementActivityCount()
}

private var activityIndicatingHelperKey: UInt8 = 0

internal final class ActivityIndicatingHelper: NSObject, ActivityIndicating {
    weak var indicatingObject: AnyObject?
    
    private let lock = NSLock()
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
        lock.withLock { _activityCount }
    }
    
    var isIndicatingActivity: Bool {
        get {
            lock.withLock { _isIndicatingActivity }
        }
        set {
            DispatchQueue.main.async {
                if newValue {
                    self.activityIndicatorView.startAnimating()
                } else {
                    self._activityIndicatorView?.stopAnimating()
                }
            }
            
            let didChange = lock.withLock { () -> Bool in
                if _isIndicatingActivity != newValue {
                    _isIndicatingActivity = newValue
                    return true
                }
                return false
            }
            
            guard didChange else { return }
            
            DispatchQueue.main.async {
                if newValue {
                    (self.indicatingObject as? _ActivityIndicating)?.startIndicatingActivity()
                } else {
                    (self.indicatingObject as? _ActivityIndicating)?.stopIndicatingActivity()
                }
            }
        }
    }
    
    func incrementActivityCount() {
        let shouldStart = lock.withLock { () -> Bool in
            _activityCount += 1
            return _activityCount == 1
        }
        
        if shouldStart {
            DispatchQueue.main.async {
                self.isIndicatingActivity = true
            }
        }
    }
    
    func decrementActivityCount() {
        let shouldStop = lock.withLock { () -> Bool in
            guard _activityCount > 0 else { return false }
            _activityCount -= 1
            return _activityCount == 0
        }
        
        if shouldStop {
            DispatchQueue.main.async {
                self.isIndicatingActivity = false
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

extension UIButton: _ActivityIndicating, ActivityIndicating {
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
        
        if self.title(for: .normal) == nil, let title = activityIndicatingHelper.userInfo["title"] as? String {
            self.setTitle(title, for: .normal)
        }
        
        if self.image(for: .normal) == nil, let image = activityIndicatingHelper.userInfo["image"] as? UIImage {
            self.setImage(image, for: .normal)
        }
        
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

extension UIBarButtonItem: _ActivityIndicating, ActivityIndicating {
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

extension UIImageView: _ActivityIndicating, ActivityIndicating {
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

extension UITextField: _ActivityIndicating, ActivityIndicating {
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

extension UIApplication: _ActivityIndicating, ActivityIndicating {
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
    }
    
    func stopIndicatingActivity() {
    }
}
