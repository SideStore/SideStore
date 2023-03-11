//
//  InstructionsViewController.swift
//  AltStore
//
//  Created by Riley Testut on 9/6/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

final class InstructionsViewController: UIViewController {
    var completionHandler: (() -> Void)?

    var showsBottomButton: Bool = false

    @IBOutlet private var contentStackView: UIStackView!
    @IBOutlet private var dismissButton: UIButton!

    override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        if UIScreen.main.isExtraCompactHeight {
            contentStackView.layoutMargins.top = 0
            contentStackView.layoutMargins.bottom = contentStackView.layoutMargins.left
        }

        dismissButton.clipsToBounds = true
        dismissButton.layer.cornerRadius = 16

        if showsBottomButton {
            navigationItem.hidesBackButton = true
        } else {
            dismissButton.isHidden = true
        }
    }
}

private extension InstructionsViewController {
    @IBAction func dismiss() {
        completionHandler?()
    }
}
