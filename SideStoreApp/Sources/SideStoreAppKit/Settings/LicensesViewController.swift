//
//  LicensesViewController.swift
//  AltStore
//
//  Created by Riley Testut on 9/6/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

final class LicensesViewController: UIViewController {
    private var _didAppear = false

    @IBOutlet private var textView: UITextView!

    override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        view.setNeedsLayout()
        view.layoutIfNeeded()

        // Fix incorrect initial offset on iPhone SE.
        textView.contentOffset.y = 0
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        _didAppear = true
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        textView.textContainerInset.left = view.layoutMargins.left
        textView.textContainerInset.right = view.layoutMargins.right
        textView.textContainer.lineFragmentPadding = 0

        if !_didAppear {
            // Fix incorrect initial offset on iPhone SE.
            textView.contentOffset.y = 0
        }
    }
}
