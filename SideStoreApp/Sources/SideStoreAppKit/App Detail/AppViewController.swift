//
//  AppViewController.swift
//  AltStore
//
//  Created by Riley Testut on 7/22/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

import SideStoreCore
import RoxasUIKit

import Nuke

@objc
@objcMembers
public final class AppViewController: UIViewController {
    var app: StoreApp!

    private var contentViewController: AppContentViewController!
    private var contentViewControllerShadowView: UIView!

    private var blurAnimator: UIViewPropertyAnimator?
    private var navigationBarAnimator: UIViewPropertyAnimator?

    private var contentSizeObservation: NSKeyValueObservation?

    @IBOutlet private var scrollView: UIScrollView!
    @IBOutlet private var contentView: UIView!

    @IBOutlet private var bannerView: AppBannerView!

    @IBOutlet private var backButton: UIButton!
    @IBOutlet private var backButtonContainerView: UIVisualEffectView!

    @IBOutlet private var backgroundAppIconImageView: UIImageView!
    @IBOutlet private var backgroundBlurView: UIVisualEffectView!

    @IBOutlet private var navigationBarTitleView: UIView!
    @IBOutlet private var navigationBarDownloadButton: PillButton!
    @IBOutlet private var navigationBarAppIconImageView: UIImageView!
    @IBOutlet private var navigationBarAppNameLabel: UILabel!

    private var _shouldResetLayout = false
    private var _backgroundBlurEffect: UIBlurEffect?
    private var _backgroundBlurTintColor: UIColor?

    private var _preferredStatusBarStyle: UIStatusBarStyle = .default

	public override var preferredStatusBarStyle: UIStatusBarStyle {
        _preferredStatusBarStyle
    }

	public override func viewDidLoad() {
        super.viewDidLoad()

        navigationBarTitleView.sizeToFit()
        navigationItem.titleView = navigationBarTitleView

        contentViewControllerShadowView = UIView()
        contentViewControllerShadowView.backgroundColor = .white
        contentViewControllerShadowView.layer.cornerRadius = 38
        contentViewControllerShadowView.layer.shadowColor = UIColor.black.cgColor
        contentViewControllerShadowView.layer.shadowOffset = CGSize(width: 0, height: -1)
        contentViewControllerShadowView.layer.shadowRadius = 10
        contentViewControllerShadowView.layer.shadowOpacity = 0.3
        contentViewController.view.superview?.insertSubview(contentViewControllerShadowView, at: 0)

        contentView.addGestureRecognizer(scrollView.panGestureRecognizer)

        contentViewController.view.layer.cornerRadius = 38
        contentViewController.view.layer.masksToBounds = true

        contentViewController.tableView.panGestureRecognizer.require(toFail: scrollView.panGestureRecognizer)
        contentViewController.tableView.showsVerticalScrollIndicator = false

        // Bring to front so the scroll indicators are visible.
        view.bringSubviewToFront(scrollView)
        scrollView.isUserInteractionEnabled = false

        bannerView.frame = CGRect(x: 0, y: 0, width: 300, height: 93)
        bannerView.backgroundEffectView.effect = UIBlurEffect(style: .regular)
        bannerView.backgroundEffectView.backgroundColor = .clear
        bannerView.iconImageView.image = nil
        bannerView.iconImageView.tintColor = app.tintColor
        bannerView.button.tintColor = app.tintColor
        bannerView.tintColor = app.tintColor

        bannerView.configure(for: app)
        bannerView.accessibilityTraits.remove(.button)

        bannerView.button.addTarget(self, action: #selector(AppViewController.performAppAction(_:)), for: .primaryActionTriggered)

        backButtonContainerView.tintColor = app.tintColor

        navigationController?.navigationBar.tintColor = app.tintColor
        navigationBarDownloadButton.tintColor = app.tintColor
        navigationBarAppNameLabel.text = app.name
        navigationBarAppIconImageView.tintColor = app.tintColor

        contentSizeObservation = contentViewController.tableView.observe(\.contentSize) { [weak self] _, _ in
            self?.view.setNeedsLayout()
            self?.view.layoutIfNeeded()
        }

        update()

        NotificationCenter.default.addObserver(self, selector: #selector(AppViewController.didChangeApp(_:)), name: .NSManagedObjectContextObjectsDidChange, object: DatabaseManager.shared.viewContext)
        NotificationCenter.default.addObserver(self, selector: #selector(AppViewController.willEnterForeground(_:)), name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(AppViewController.didBecomeActive(_:)), name: UIApplication.didBecomeActiveNotification, object: nil)

        _backgroundBlurEffect = backgroundBlurView.effect as? UIBlurEffect
        _backgroundBlurTintColor = backgroundBlurView.contentView.backgroundColor

        // Load Images
        for imageView in [bannerView.iconImageView!, backgroundAppIconImageView!, navigationBarAppIconImageView!] {
            imageView.isIndicatingActivity = true

            Nuke.loadImage(with: app.iconURL, options: .shared, into: imageView, progress: nil) { [weak imageView] response, _ in
                if response?.image != nil {
                    imageView?.isIndicatingActivity = false
                }
            }
        }
    }

	public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        prepareBlur()

        // Update blur immediately.
        view.setNeedsLayout()
        view.layoutIfNeeded()

        transitionCoordinator?.animate(alongsideTransition: { _ in
            self.hideNavigationBar()
        }, completion: nil)
    }

	public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        _shouldResetLayout = true
        view.setNeedsLayout()
        view.layoutIfNeeded()
    }

	public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        // Guard against "dismissing" when presenting via 3D Touch pop.
        guard self.navigationController != nil else { return }

        // Store reference since self.navigationController will be nil after disappearing.
        let navigationController = self.navigationController
        navigationController?.navigationBar.barStyle = .default // Don't animate, or else status bar might appear messed-up.

        transitionCoordinator?.animate(alongsideTransition: { _ in
            self.showNavigationBar(for: navigationController)
        }, completion: { context in
            if !context.isCancelled {
                self.showNavigationBar(for: navigationController)
            }
        })
    }

	public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        if navigationController == nil {
            resetNavigationBarAnimation()
        }
    }

	public override func prepare(for segue: UIStoryboardSegue, sender _: Any?) {
        guard segue.identifier == "embedAppContentViewController" else { return }

        contentViewController = segue.destination as? AppContentViewController
        contentViewController.app = app

        if #available(iOS 15, *) {
            // Fix navigation bar + tab bar appearance on iOS 15.
            self.setContentScrollView(self.scrollView)
            self.navigationItem.scrollEdgeAppearance = self.navigationController?.navigationBar.standardAppearance
        }
    }

	public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        if _shouldResetLayout {
            // Various events can cause UI to mess up, so reset affected components now.

            if navigationController?.topViewController == self {
                hideNavigationBar()
            }

            prepareBlur()

            // Reset navigation bar animation, and create a new one later in this method if necessary.
            resetNavigationBarAnimation()

            _shouldResetLayout = false
        }

        let statusBarHeight = UIApplication.shared.statusBarFrame.height
        let cornerRadius = contentViewControllerShadowView.layer.cornerRadius

        let inset = 12 as CGFloat
        let padding = 20 as CGFloat

        let backButtonSize = backButton.sizeThatFits(CGSize(width: 1000, height: 1000))
        var backButtonFrame = CGRect(x: inset, y: statusBarHeight,
                                     width: backButtonSize.width + 20, height: backButtonSize.height + 20)

        var headerFrame = CGRect(x: inset, y: 0, width: view.bounds.width - inset * 2, height: bannerView.bounds.height)
        var contentFrame = CGRect(x: 0, y: 0, width: view.bounds.width, height: view.bounds.height)
        var backgroundIconFrame = CGRect(x: 0, y: 0, width: view.bounds.width, height: view.bounds.width)

        let minimumHeaderY = backButtonFrame.maxY + 8

        let minimumContentY = minimumHeaderY + headerFrame.height + padding
        let maximumContentY = view.bounds.width * 0.667

        // A full blur is too much, so we reduce the visible blur by 0.3, resulting in 70% blur.
        let minimumBlurFraction = 0.3 as CGFloat

        contentFrame.origin.y = maximumContentY - scrollView.contentOffset.y
        headerFrame.origin.y = contentFrame.origin.y - padding - headerFrame.height

        // Stretch the app icon image to fill additional vertical space if necessary.
        let height = max(contentFrame.origin.y + cornerRadius * 2, backgroundIconFrame.height)
        backgroundIconFrame.size.height = height

        let blurThreshold = 0 as CGFloat
        if scrollView.contentOffset.y < blurThreshold {
            // Determine how much to lessen blur by.

            let range = 75 as CGFloat
            let difference = -scrollView.contentOffset.y

            let fraction = min(difference, range) / range

            let fractionComplete = (fraction * (1.0 - minimumBlurFraction)) + minimumBlurFraction
            blurAnimator?.fractionComplete = fractionComplete
        } else {
            // Set blur to default.

            blurAnimator?.fractionComplete = minimumBlurFraction
        }

        // Animate navigation bar.
        let showNavigationBarThreshold = (maximumContentY - minimumContentY) + backButtonFrame.origin.y
        if scrollView.contentOffset.y > showNavigationBarThreshold {
            if navigationBarAnimator == nil {
                prepareNavigationBarAnimation()
            }

            let difference = scrollView.contentOffset.y - showNavigationBarThreshold
            let range = (headerFrame.height + padding) - (navigationController?.navigationBar.bounds.height ?? view.safeAreaInsets.top)

            let fractionComplete = min(difference, range) / range
            navigationBarAnimator?.fractionComplete = fractionComplete
        } else {
            resetNavigationBarAnimation()
        }

        let beginMovingBackButtonThreshold = (maximumContentY - minimumContentY)
        if scrollView.contentOffset.y > beginMovingBackButtonThreshold {
            let difference = scrollView.contentOffset.y - beginMovingBackButtonThreshold
            backButtonFrame.origin.y -= difference
        }

        let pinContentToTopThreshold = maximumContentY
        if scrollView.contentOffset.y > pinContentToTopThreshold {
            contentFrame.origin.y = 0
            backgroundIconFrame.origin.y = 0

            let difference = scrollView.contentOffset.y - pinContentToTopThreshold
            contentViewController.tableView.contentOffset.y = difference
        } else {
            // Keep content table view's content offset at the top.
            contentViewController.tableView.contentOffset.y = 0
        }

        // Keep background app icon centered in gap between top of content and top of screen.
        backgroundIconFrame.origin.y = (contentFrame.origin.y / 2) - backgroundIconFrame.height / 2

        // Set frames.
        contentViewController.view.superview?.frame = contentFrame
        bannerView.frame = headerFrame
        backgroundAppIconImageView.frame = backgroundIconFrame
        backgroundBlurView.frame = backgroundIconFrame
        backButtonContainerView.frame = backButtonFrame

        contentViewControllerShadowView.frame = contentViewController.view.frame

        backButtonContainerView.layer.cornerRadius = backButtonContainerView.bounds.midY

        scrollView.scrollIndicatorInsets.top = statusBarHeight

        // Adjust content offset + size.
        let contentOffset = scrollView.contentOffset

        var contentSize = contentViewController.tableView.contentSize
        contentSize.height += maximumContentY

        scrollView.contentSize = contentSize
        scrollView.contentOffset = contentOffset

        bannerView.backgroundEffectView.backgroundColor = .clear
    }

	public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        _shouldResetLayout = true
    }

    deinit {
        self.blurAnimator?.stopAnimation(true)
        self.navigationBarAnimator?.stopAnimation(true)
    }
}

extension AppViewController {
    final class func makeAppViewController(app: StoreApp) -> AppViewController {
		let storyboard = UIStoryboard(name: "Main", bundle: Bundle.init(for: AppViewController.self))

        let appViewController = storyboard.instantiateViewController(withIdentifier: "appViewController") as! AppViewController
        appViewController.app = app
        return appViewController
    }
}

private extension AppViewController {
    func update() {
        for button in [bannerView.button!, navigationBarDownloadButton!] {
            button.tintColor = app.tintColor
            button.isIndicatingActivity = false

            if app.installedApp == nil {
                button.setTitle(NSLocalizedString("FREE", comment: ""), for: .normal)
            } else {
                button.setTitle(NSLocalizedString("OPEN", comment: ""), for: .normal)
            }

            let progress = AppManager.shared.installationProgress(for: app)
            button.progress = progress
        }

        if let versionDate = app.latestVersion?.date, versionDate > Date() {
            bannerView.button.countdownDate = versionDate
            navigationBarDownloadButton.countdownDate = versionDate
        } else {
            bannerView.button.countdownDate = nil
            navigationBarDownloadButton.countdownDate = nil
        }

        let barButtonItem = navigationItem.rightBarButtonItem
        navigationItem.rightBarButtonItem = nil
        navigationItem.rightBarButtonItem = barButtonItem
    }

    func showNavigationBar(for navigationController: UINavigationController? = nil) {
        let navigationController = navigationController ?? self.navigationController
        navigationController?.navigationBar.alpha = 1.0
        navigationController?.navigationBar.tintColor = .altPrimary
        navigationController?.navigationBar.setNeedsLayout()

        if traitCollection.userInterfaceStyle == .dark {
            _preferredStatusBarStyle = .lightContent
        } else {
            _preferredStatusBarStyle = .default
        }

        navigationController?.setNeedsStatusBarAppearanceUpdate()
    }

    func hideNavigationBar(for navigationController: UINavigationController? = nil) {
        let navigationController = navigationController ?? self.navigationController
        navigationController?.navigationBar.alpha = 0.0

        _preferredStatusBarStyle = .lightContent
        navigationController?.setNeedsStatusBarAppearanceUpdate()
    }

    func prepareBlur() {
        if let animator = blurAnimator {
            animator.stopAnimation(true)
        }

        backgroundBlurView.effect = _backgroundBlurEffect
        backgroundBlurView.contentView.backgroundColor = _backgroundBlurTintColor

        blurAnimator = UIViewPropertyAnimator(duration: 1.0, curve: .linear) { [weak self] in
            self?.backgroundBlurView.effect = nil
            self?.backgroundBlurView.contentView.backgroundColor = .clear
        }

        blurAnimator?.startAnimation()
        blurAnimator?.pauseAnimation()
    }

    func prepareNavigationBarAnimation() {
        resetNavigationBarAnimation()

        navigationBarAnimator = UIViewPropertyAnimator(duration: 1.0, curve: .linear) { [weak self] in
            self?.showNavigationBar()
            self?.navigationController?.navigationBar.tintColor = self?.app.tintColor
            self?.navigationController?.navigationBar.barTintColor = nil
            self?.contentViewController.view.layer.cornerRadius = 0
        }

        navigationBarAnimator?.startAnimation()
        navigationBarAnimator?.pauseAnimation()

        update()
    }

    func resetNavigationBarAnimation() {
        navigationBarAnimator?.stopAnimation(true)
        navigationBarAnimator = nil

        hideNavigationBar()

        contentViewController.view.layer.cornerRadius = contentViewControllerShadowView.layer.cornerRadius
    }
}

extension AppViewController {
    @IBAction func popViewController(_: UIButton) {
        navigationController?.popViewController(animated: true)
    }

    @IBAction func performAppAction(_: PillButton) {
        if let installedApp = app.installedApp {
            open(installedApp)
        } else {
            downloadApp()
        }
    }

    func downloadApp() {
        guard app.installedApp == nil else { return }

        let group = AppManager.shared.install(app, presentingViewController: self) { result in
            do {
                _ = try result.get()
            } catch OperationError.cancelled {
                // Ignore
            } catch {
                DispatchQueue.main.async {
                    let toastView = ToastView(error: error)
                    toastView.show(in: self)
                }
            }

            DispatchQueue.main.async {
                self.bannerView.button.progress = nil
                self.navigationBarDownloadButton.progress = nil
                self.update()
            }
        }

        bannerView.button.progress = group.progress
        navigationBarDownloadButton.progress = group.progress
    }

    func open(_ installedApp: InstalledApp) {
        UIApplication.shared.open(installedApp.openAppURL)
    }
}

private extension AppViewController {
    @objc func didChangeApp(_: Notification) {
        // Async so that AppManager.installationProgress(for:) is nil when we update.
        DispatchQueue.main.async {
            self.update()
        }
    }

    @objc func willEnterForeground(_: Notification) {
        guard let navigationController = navigationController, navigationController.topViewController == self else { return }

        _shouldResetLayout = true
        view.setNeedsLayout()
    }

    @objc func didBecomeActive(_: Notification) {
        guard let navigationController = navigationController, navigationController.topViewController == self else { return }

        // Fixes Navigation Bar appearing after app becomes inactive -> active again.
        _shouldResetLayout = true
        view.setNeedsLayout()
    }
}

extension AppViewController: UIScrollViewDelegate {
	public func scrollViewDidScroll(_: UIScrollView) {
        view.setNeedsLayout()
        view.layoutIfNeeded()
    }
}
