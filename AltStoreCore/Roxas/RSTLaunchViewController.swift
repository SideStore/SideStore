//
//  RSTLaunchViewController.swift
//  AltStoreCore
//
//  Created by Magesh K on 6/17/26.
//

import UIKit

@objc(RSTLaunchCondition)
public final class RSTLaunchCondition: NSObject {
    @objc public let condition: () -> Bool
    @objc public let action: (@escaping (Error?) -> Void) -> Void
    
    @objc public init(condition: @escaping () -> Bool, action: @escaping (@escaping (Error?) -> Void) -> Void) {
        self.condition = condition
        self.action = action
        super.init()
    }
}

@objc(RSTLaunchViewController)
open class RSTLaunchViewController: UIViewController {
    private var launchView: UIView?
    
    @objc open var launchConditions: [RSTLaunchCondition] {
        return []
    }
    
    open override func viewDidLoad() {
        super.viewDidLoad()
        
        guard let storyboardName = Bundle.main.object(forInfoDictionaryKey: "UILaunchStoryboardName") as? String else { return }
        
        if Bundle.main.url(forResource: storyboardName, withExtension: "nib") != nil {
            let launchNib = UINib(nibName: storyboardName, bundle: .main)
            let objects = launchNib.instantiate(withOwner: nil, options: nil)
            for view in objects {
                if let view = view as? UIView {
                    self.launchView = view
                    break
                }
            }
        } else {
            let launchStoryboard = UIStoryboard(name: storyboardName, bundle: .main)
            let initialViewController = launchStoryboard.instantiateInitialViewController()
            self.launchView = initialViewController?.view
        }
        
        if let launchView = self.launchView {
            self.view.addSubview(launchView, pinningEdgesWith: .zero)
            self.view.sendSubviewToBack(launchView)
        }
    }
    
    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        handleLaunchConditions()
    }
    
    @objc open func handleLaunchConditions() {
        handleLaunchCondition(at: 0)
    }
    
    private func handleLaunchCondition(at index: Int) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                self.handleLaunchCondition(at: index)
            }
            return
        }
        
        if index >= launchConditions.count {
            finishLaunching()
            return
        }
        
        let condition = launchConditions[index]
        if condition.condition() {
            handleLaunchCondition(at: index + 1)
        } else {
            condition.action { [weak self] error in
                guard let self = self else { return }
                if let error = error {
                    rst_dispatch_sync_on_main_thread {
                        self.handleLaunchError(error)
                    }
                    return
                }
                self.handleLaunchCondition(at: index + 1)
            }
        }
    }
    
    @objc open func handleLaunchError(_ error: Error) {
        print("Launch Error: \(error.localizedDescription)")
    }
    
    @objc open func finishLaunching() {}
}
