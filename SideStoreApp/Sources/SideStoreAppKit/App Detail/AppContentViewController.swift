//
//  AppContentViewController.swift
//  AltStore
//
//  Created by Riley Testut on 7/22/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

import SideStoreCore
import RoxasUIKit
import os.log

import Nuke

extension AppContentViewController {
    private enum Row: Int, CaseIterable {
        case subtitle
        case screenshots
        case description
        case versionDescription
        case permissions
    }
}

final class AppContentViewController: UITableViewController {
    var app: StoreApp!

    private lazy var screenshotsDataSource = self.makeScreenshotsDataSource()
    private lazy var permissionsDataSource = self.makePermissionsDataSource()

    private lazy var dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none
        return dateFormatter
    }()

    private lazy var byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        return formatter
    }()

    @IBOutlet private var subtitleLabel: UILabel!
    @IBOutlet private var descriptionTextView: CollapsingTextView!
    @IBOutlet private var versionDescriptionTextView: CollapsingTextView!
    @IBOutlet private var versionLabel: UILabel!
    @IBOutlet private var versionDateLabel: UILabel!
    @IBOutlet private var sizeLabel: UILabel!

    @IBOutlet private var screenshotsCollectionView: UICollectionView!
    @IBOutlet private var permissionsCollectionView: UICollectionView!

    var preferredScreenshotSize: CGSize? {
        let layout = self.screenshotsCollectionView.collectionViewLayout as! UICollectionViewFlowLayout

        let aspectRatio: CGFloat = 16.0 / 9.0 // Hardcoded for now.

        let width = self.screenshotsCollectionView.bounds.width - (layout.minimumInteritemSpacing * 2)

        let itemWidth = width / 1.5
        let itemHeight = itemWidth * aspectRatio

        return CGSize(width: itemWidth, height: itemHeight)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.contentInset.bottom = 20

        screenshotsCollectionView.dataSource = screenshotsDataSource
        screenshotsCollectionView.prefetchDataSource = screenshotsDataSource

        permissionsCollectionView.dataSource = permissionsDataSource

        subtitleLabel.text = app.subtitle
        descriptionTextView.text = app.localizedDescription

        if let version = app.latestVersion {
            versionDescriptionTextView.text = version.localizedDescription
            versionLabel.text = String(format: NSLocalizedString("Version %@", comment: ""), version.version)
            versionDateLabel.text = Date().relativeDateString(since: version.date, dateFormatter: dateFormatter)
            sizeLabel.text = byteCountFormatter.string(fromByteCount: version.size)
        } else {
            versionDescriptionTextView.text = nil
            versionLabel.text = nil
            versionDateLabel.text = nil
            sizeLabel.text = byteCountFormatter.string(fromByteCount: 0)
        }

        descriptionTextView.maximumNumberOfLines = 5
        descriptionTextView.moreButton.addTarget(self, action: #selector(AppContentViewController.toggleCollapsingSection(_:)), for: .primaryActionTriggered)

        versionDescriptionTextView.maximumNumberOfLines = 3
        versionDescriptionTextView.moreButton.addTarget(self, action: #selector(AppContentViewController.toggleCollapsingSection(_:)), for: .primaryActionTriggered)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        guard var size = preferredScreenshotSize else { return }
        size.height = min(size.height, screenshotsCollectionView.bounds.height) // Silence temporary "item too tall" warning.

        let layout = screenshotsCollectionView.collectionViewLayout as! UICollectionViewFlowLayout
        layout.itemSize = size
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        guard segue.identifier == "showPermission" else { return }

        guard let cell = sender as? UICollectionViewCell, let indexPath = permissionsCollectionView.indexPath(for: cell) else { return }

        let permission = permissionsDataSource.item(at: indexPath)

        let maximumWidth = view.bounds.width - 20

        let permissionPopoverViewController = segue.destination as! PermissionPopoverViewController
        permissionPopoverViewController.permission = permission
        permissionPopoverViewController.view.widthAnchor.constraint(lessThanOrEqualToConstant: maximumWidth).isActive = true

        let size = permissionPopoverViewController.view.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        permissionPopoverViewController.preferredContentSize = size

        permissionPopoverViewController.popoverPresentationController?.delegate = self
        permissionPopoverViewController.popoverPresentationController?.sourceRect = cell.frame
        permissionPopoverViewController.popoverPresentationController?.sourceView = permissionsCollectionView
    }
}

private extension AppContentViewController {
    func makeScreenshotsDataSource() -> RSTArrayCollectionViewPrefetchingDataSource<NSURL, UIImage> {
        let dataSource = RSTArrayCollectionViewPrefetchingDataSource<NSURL, UIImage>(items: app.screenshotURLs as [NSURL])
        dataSource.cellConfigurationHandler = { cell, _, _ in
            let cell = cell as! ScreenshotCollectionViewCell
            cell.imageView.image = nil
            cell.imageView.isIndicatingActivity = true
        }
        dataSource.prefetchHandler = { imageURL, _, completionHandler in
            RSTAsyncBlockOperation { operation in
                let request = ImageRequest(url: imageURL as URL, processor: .screenshot)
                ImagePipeline.shared.loadImage(with: request, progress: nil, completion: { response, error in
                    guard !operation.isCancelled else { return operation.finish() }

                    if let image = response?.image {
                        completionHandler(image, nil)
                    } else {
                        completionHandler(nil, error)
                    }
                })
            }
        }
        dataSource.prefetchCompletionHandler = { cell, image, _, error in
            let cell = cell as! ScreenshotCollectionViewCell
            cell.imageView.isIndicatingActivity = false
            cell.imageView.image = image

            if let error = error {
                os_log("Error loading image: %@", type: .error, error.localizedDescription)
            }
        }

        return dataSource
    }

    func makePermissionsDataSource() -> RSTArrayCollectionViewDataSource<AppPermission> {
        let dataSource = RSTArrayCollectionViewDataSource(items: app.permissions)
        dataSource.cellConfigurationHandler = { cell, permission, _ in
            let cell = cell as! PermissionCollectionViewCell
            cell.button.setImage(permission.type.icon, for: .normal)
            cell.button.tintColor = .label
            cell.textLabel.text = permission.type.localizedShortName ?? permission.type.localizedName
        }

        return dataSource
    }
}

private extension AppContentViewController {
    @objc func toggleCollapsingSection(_ sender: UIButton) {
        let indexPath: IndexPath

        switch sender {
        case descriptionTextView.moreButton: indexPath = IndexPath(row: Row.description.rawValue, section: 0)
        case versionDescriptionTextView.moreButton: indexPath = IndexPath(row: Row.versionDescription.rawValue, section: 0)
        default: return
        }

        // Disable animations to prevent some potentially strange ones.
        UIView.performWithoutAnimation {
            self.tableView.reloadRows(at: [indexPath], with: .none)
        }
    }
}

extension AppContentViewController {
    override func tableView(_: UITableView, willDisplay cell: UITableViewCell, forRowAt _: IndexPath) {
        cell.tintColor = app.tintColor
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch Row.allCases[indexPath.row] {
        case .screenshots:
            guard let size = preferredScreenshotSize else { return 0.0 }
            return size.height

        case .permissions:
            guard !app.permissions.isEmpty else { return 0.0 }
            return super.tableView(tableView, heightForRowAt: indexPath)

        default:
            return super.tableView(tableView, heightForRowAt: indexPath)
        }
    }
}

extension AppContentViewController: UIPopoverPresentationControllerDelegate {
    func adaptivePresentationStyle(for _: UIPresentationController, traitCollection _: UITraitCollection) -> UIModalPresentationStyle {
        .none
    }
}
