//
//  VPNHostingViewController.swift
//  SideStore
//
//  UIKit host for the SwiftUI LocalDevVPN tab.
//

import SwiftUI
import UIKit

/// A plain UIViewController that hosts `VPNRootView` via a UIHostingController child.
/// It is the root of the "LocalDevVPN" navigation controller in the tab bar.
final class VPNHostingViewController: UIViewController {

    private var hostingController: UIHostingController<VPNRootView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        embedVPNView()
    }

    private func embedVPNView() {
        let hosting = UIHostingController(rootView: VPNRootView())
        hostingController = hosting

        addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting.view)

        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        hosting.didMove(toParent: self)
    }
}
