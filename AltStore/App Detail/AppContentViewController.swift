//
//  AppContentViewController.swift
//  AltStore
//
//  Created by Riley Testut on 7/22/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

import AltStoreCore
import Roxas

import Nuke

extension AppContentViewController
{
    private enum Row: Int, CaseIterable
    {
        case subtitle
        case screenshots
        case description
        case versionDescription
        case permissions
    }
}

final class AppContentViewController: UITableViewController
{
    var app: StoreApp!
    
//     private lazy var screenshotsDataSource = self.makeScreenshotsDataSource()
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
//    @IBOutlet private var descriptionTextView: CollapsingTextView!
    @IBOutlet private var descriptionTextView: CollapsingMarkdownView!
//    @IBOutlet private var versionDescriptionTextView: CollapsingTextView!
    @IBOutlet private var versionDescriptionTextView: CollapsingMarkdownView!
    @IBOutlet private var versionLabel: UILabel!
    @IBOutlet private var versionDateLabel: UILabel!
    @IBOutlet private var sizeLabel: UILabel!
    
    @IBOutlet private(set) var appScreenshotsViewController: AppScreenshotsViewController!
    @IBOutlet private var appScreenshotsHeightConstraint: NSLayoutConstraint!
    
    @IBOutlet private(set) var appDetailCollectionViewController: AppDetailCollectionViewController!
    @IBOutlet private var appDetailCollectionViewHeightConstraint: NSLayoutConstraint!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.tableView.contentInset.bottom = 20
        
        self.subtitleLabel.text = self.app.subtitle
        let desc = self.app.localizedDescription
        self.descriptionTextView.text = desc
        
        if let version = self.app.latestAvailableVersion {
            self.versionDescriptionTextView.text = version.localizedDescription ?? "nil"
            self.versionLabel.text = String(format: NSLocalizedString("Version %@", comment: ""), version.localizedVersion)
            self.versionDateLabel.text = Date().relativeDateString(since: version.date)
            self.sizeLabel.text = ByteCountFormatter.string(fromByteCount: version.size, countStyle: .file)
        } else {
            self.versionDescriptionTextView.text = "nil"
            self.versionLabel.text = nil
            self.versionDateLabel.text = nil
            self.sizeLabel.text = ByteCountFormatter.string(fromByteCount: 0, countStyle: .file)
        }
        
        self.descriptionTextView.maximumNumberOfLines = 5
        self.versionDescriptionTextView.maximumNumberOfLines = 5
        
        self.descriptionTextView.toggleButton.addTarget(self, action: #selector(AppContentViewController.toggleCollapsingSection(_:)), for: .primaryActionTriggered)
        self.versionDescriptionTextView.toggleButton.addTarget(self, action: #selector(AppContentViewController.toggleCollapsingSection(_:)), for: .primaryActionTriggered)
    }
    
    override func viewDidLayoutSubviews()
    {
        super.viewDidLayoutSubviews()
        
        var needsTableViewUpdate = false
        
        let screenshotsHeight = self.appScreenshotsViewController.collectionView.contentSize.height
        if self.appScreenshotsHeightConstraint.constant != screenshotsHeight && screenshotsHeight > 0
        {
            self.appScreenshotsHeightConstraint.constant = screenshotsHeight
            needsTableViewUpdate = true
        }
        
        let permissionsHeight = self.appDetailCollectionViewController.collectionView.contentSize.height
        if self.appDetailCollectionViewHeightConstraint.constant != permissionsHeight && permissionsHeight > 0
        {
            self.appDetailCollectionViewHeightConstraint.constant = permissionsHeight
            needsTableViewUpdate = true
        }
        
        if needsTableViewUpdate
        {
            UIView.performWithoutAnimation {
                // Update row height without animation.
                self.tableView.beginUpdates()
                self.tableView.endUpdates()
            }
        }
    }
}

private extension AppContentViewController
{
    @IBSegueAction
    func makeAppScreenshotsViewController(_ coder: NSCoder, sender: Any?) -> UIViewController?
    {
        let appScreenshotsViewController = AppScreenshotsViewController(app: self.app, coder: coder)
        self.appScreenshotsViewController = appScreenshotsViewController
        return appScreenshotsViewController
    }
    
    func makePermissionsDataSource() -> RSTArrayCollectionViewDataSource<AppPermission>
    {        
        let dataSource = RSTArrayCollectionViewDataSource(items: Array(self.app.permissions))
        dataSource.cellConfigurationHandler = { (cell, permission, indexPath) in
            let cell = cell as! PermissionCollectionViewCell
            // cell.button.setImage(permission.type.icon, for: .normal)
            // cell.button.tintColor = .label
            // cell.textLabel.text = permission.type.localizedShortName ?? permission.type.localizedName
            
            let icon = UIImage(systemName: permission.symbolName ?? "lock")
            cell.button.setImage(icon, for: .normal)
            
            cell.textLabel.text = permission.localizedDisplayName
        }
        
        return dataSource
    }
    
    @IBSegueAction
    func makeAppDetailCollectionViewController(_ coder: NSCoder, sender: Any?) -> UIViewController?
    {
        let appDetailViewController = AppDetailCollectionViewController(app: self.app, coder: coder)
        self.appDetailCollectionViewController = appDetailViewController
        return appDetailViewController
    }
}

private extension AppContentViewController
{
    @objc func toggleCollapsingSection(_ sender: UIButton)
    {
        let indexPath: IndexPath
        
        switch sender
        {
        case self.descriptionTextView.toggleButton:
            indexPath = IndexPath(row: Row.description.rawValue, section: 0)
            
        case self.versionDescriptionTextView.toggleButton:
            indexPath = IndexPath(row: Row.versionDescription.rawValue, section: 0)

        default: return
        }
        
        // Disable animations to prevent some potentially strange ones.
        UIView.performWithoutAnimation {
            self.tableView.reloadRows(at: [indexPath], with: .none)
        }
    }
}

extension AppContentViewController
{
    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath)
    {
        cell.tintColor = self.app.tintColor
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat
    {
        switch Row.allCases[indexPath.row]
        {
        case .screenshots:
            guard !self.app.allScreenshots.isEmpty else { return 0.0 }
            return UITableView.automaticDimension
            
        case .permissions:
            guard !self.app.permissions.isEmpty else { return 0.0 }
            return UITableView.automaticDimension
            
        default:
            return super.tableView(tableView, heightForRowAt: indexPath)
        }
    }
}
