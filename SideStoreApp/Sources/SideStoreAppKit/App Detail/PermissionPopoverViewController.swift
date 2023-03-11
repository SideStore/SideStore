//
//  PermissionPopoverViewController.swift
//  AltStore
//
//  Created by Riley Testut on 7/23/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

import SideStoreCore

final class PermissionPopoverViewController: UIViewController {
    var permission: AppPermission!

    @IBOutlet private var nameLabel: UILabel!
    @IBOutlet private var descriptionLabel: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()

        nameLabel.text = permission.type.localizedName
        descriptionLabel.text = permission.usageDescription
    }
}
