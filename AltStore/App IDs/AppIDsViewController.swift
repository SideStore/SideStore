//
//  AppIDsViewController.swift
//  AltStore
//
//  Created by Riley Testut on 1/27/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import UIKit

import AltStoreCore
import Roxas

final class AppIDsViewController: UICollectionViewController
{
    private lazy var dataSource = self.makeDataSource()
    
    private var didInitialFetch = false
    private var isLoading = false {
        didSet {
            self.update()
        }
    }
    
    @IBOutlet var activityIndicatorBarButtonItem: UIBarButtonItem!
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.collectionView.dataSource = self.dataSource
        
        self.activityIndicatorBarButtonItem.isIndicatingActivity = true
        
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(AppIDsViewController.fetchAppIDs), for: .primaryActionTriggered)
        self.collectionView.refreshControl = refreshControl
    }
    
    override func viewWillAppear(_ animated: Bool)
    {
        super.viewWillAppear(animated)
        
        if !self.didInitialFetch
        {
            self.fetchAppIDs()
        }
    }
}

private extension AppIDsViewController
{
    func makeDataSource() -> RSTFetchedResultsCollectionViewDataSource<AppID>
    {
        let fetchRequest = AppID.fetchRequest() as NSFetchRequest<AppID>
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \AppID.name, ascending: true),
                                        NSSortDescriptor(keyPath: \AppID.bundleIdentifier, ascending: true),
                                        NSSortDescriptor(keyPath: \AppID.expirationDate, ascending: true)]
        fetchRequest.returnsObjectsAsFaults = false
        
        if let team = DatabaseManager.shared.activeTeam()
        {
            fetchRequest.predicate = NSPredicate(format: "%K == %@", #keyPath(AppID.team), team)
        }
        else
        {
            fetchRequest.predicate = NSPredicate(value: false)
        }
        
        let dataSource = RSTFetchedResultsCollectionViewDataSource<AppID>(fetchRequest: fetchRequest, managedObjectContext: DatabaseManager.shared.viewContext)
        dataSource.proxy = self
        dataSource.cellConfigurationHandler = { (cell, appID, indexPath) in
            let tintColor = UIColor.altPrimary
            
            let cell = cell as! AppBannerCollectionViewCell
            cell.tintColor = tintColor
            
            cell.contentView.preservesSuperviewLayoutMargins = false
            cell.contentView.layoutMargins = UIEdgeInsets(top: 0, left: self.view.layoutMargins.left, bottom: 0, right: self.view.layoutMargins.right)
                        
            cell.bannerView.iconImageView.isHidden = true
            cell.bannerView.button.isIndicatingActivity = false
            
            cell.bannerView.buttonLabel.text = NSLocalizedString("过期时间", comment: "")
            
            let attributedAccessibilityLabel = NSMutableAttributedString(string: appID.name + ". ")
            
            if let expirationDate = appID.expirationDate
            {
                cell.bannerView.button.isHidden = false
                cell.bannerView.button.isUserInteractionEnabled = false
                
                cell.bannerView.buttonLabel.isHidden = false

                let currentDate = Date()

                let formatter = DateComponentsFormatter()
                formatter.unitsStyle = .full
                formatter.includesApproximationPhrase = false
                formatter.includesTimeRemainingPhrase = false
                formatter.allowedUnits = [.minute, .hour, .day]
                formatter.maximumUnitCount = 1

                let timeInterval = formatter.string(from: currentDate, to: expirationDate)
                let timeIntervalText = timeInterval ?? NSLocalizedString("未知", comment: "")
                cell.bannerView.button.setTitle(timeIntervalText.uppercased(), for: .normal)
                
                // formatter.includesTimeRemainingPhrase = true
                attributedAccessibilityLabel.mutableString.append(timeIntervalText)
            }
            else
            {
                cell.bannerView.button.isHidden = true
                cell.bannerView.button.isUserInteractionEnabled = true
                
                cell.bannerView.buttonLabel.isHidden = true
            }
                                                
            cell.bannerView.titleLabel.text = appID.name
            cell.bannerView.subtitleLabel.text = appID.bundleIdentifier
            cell.bannerView.subtitleLabel.numberOfLines = 2
            cell.bannerView.subtitleLabel.minimumScaleFactor = 1.0 // Disable font shrinking
            
            let attributedBundleIdentifier = NSMutableAttributedString(string: appID.bundleIdentifier.lowercased(), attributes: [.accessibilitySpeechPunctuation: true])
            
            if let team = appID.team, let range = attributedBundleIdentifier.string.range(of: team.identifier.lowercased())
            {
                // Prefer to speak the team ID one character at a time.
                let nsRange = NSRange(range, in: attributedBundleIdentifier.string)
                attributedBundleIdentifier.addAttributes([.accessibilitySpeechSpellOut: true], range: nsRange)
            }
            
            attributedAccessibilityLabel.append(attributedBundleIdentifier)
            cell.bannerView.accessibilityAttributedLabel = attributedAccessibilityLabel
            
            // Make sure refresh button is correct size.
            cell.layoutIfNeeded()
        }
        
        return dataSource
    }
    
    @objc func fetchAppIDs()
    {
        guard !self.isLoading else { return }
        self.isLoading = true
        
        AppManager.shared.fetchAppIDs { (result) in
            do
            {
                let (_, context) = try result.get()
                try context.save()
            }
            catch
            {
                DispatchQueue.main.async {
                    let toastView = ToastView(error: error)
                    toastView.show(in: self)
                }
            }
            
            DispatchQueue.main.async {
                self.isLoading = false
            }
        }
    }
    
    func update()
    {
        if !self.isLoading
        {
            self.collectionView.refreshControl?.endRefreshing()
            self.activityIndicatorBarButtonItem.isIndicatingActivity = false
        }
    }
}

extension AppIDsViewController: UICollectionViewDelegateFlowLayout
{
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize
    {
        return CGSize(width: collectionView.bounds.width, height: 80)
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize
    {
        // let indexPath = IndexPath(row: 0, section: section)
        // let headerView = self.collectionView(collectionView, viewForSupplementaryElementOfKind: UICollectionView.elementKindSectionHeader, at: indexPath)
        
        // // Use this view to calculate the optimal size based on the collection view's width
        // let size = headerView.systemLayoutSizeFitting(CGSize(width: collectionView.frame.width, height: UIView.layoutFittingCompressedSize.height),
        //                                               withHorizontalFittingPriority: .required, // Width is fixed
        //                                               verticalFittingPriority: .fittingSizeLevel) // Height can be as large as needed
        // return size
        
        // NOTE: double dequeue of cell has been discontinued
        // TODO: Using harcoded value until this is fixed
        return CGSize(width: collectionView.bounds.width, height: 200)
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForFooterInSection section: Int) -> CGSize
    {
        return CGSize(width: collectionView.bounds.width, height: 50)
    }
    
    override func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView
    {
        switch kind
        {
        case UICollectionView.elementKindSectionHeader:
            let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "Header", for: indexPath) as! TextCollectionReusableView
            headerView.layoutMargins.left = self.view.layoutMargins.left
            headerView.layoutMargins.right = self.view.layoutMargins.right
            
            if let activeTeam = DatabaseManager.shared.activeTeam(), activeTeam.type == .free
            {
                let text = NSLocalizedString("""
                每个通过 SideStore 安装的应用及其扩展都必须在 Apple 注册一个 App ID。Apple 限制非开发者的 Apple ID 每次最多注册 10 个 App ID。

                **App ID 不能删除**，但它们会在一周后过期。AppFlex 会自动为所有活跃的应用更新过期的 App ID。
                """, comment: "")
                
                let attributedText = NSAttributedString(string: text, attributes: [.font: headerView.textLabel.font as Any])
                headerView.textLabel.attributedText = attributedText
            }
            else
            {
                headerView.textLabel.text = NSLocalizedString("""
                每个通过 AppFlex 安装的应用及其扩展都必须在 Apple 注册一个 App ID。
                
                付费开发者账户的 App ID 永久有效，并且没有创建数量的限制。
                """, comment: "")
            }
            
            return headerView
            
        case UICollectionView.elementKindSectionFooter:
            let footerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "Footer", for: indexPath) as! TextCollectionReusableView
            
            let count = self.dataSource.itemCount
            if count == 1
            {
                footerView.textLabel.text = NSLocalizedString("1 个 App ID", comment: "")
            }
            else
            {
                footerView.textLabel.text = String(format: NSLocalizedString("共有 %@ 个 App ID", comment: ""), NSNumber(value: count))
            }
            
            return footerView
            
        default: fatalError()
        }
    }
}
