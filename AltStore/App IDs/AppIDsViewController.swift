//
//  AppIDsViewController.swift
//  AltStore
//
//  Created by Riley Testut on 1/27/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

@preconcurrency import UIKit
import CoreData
import SwiftUI
import SideSign

extension AppIDsViewController {
    static let didDismissNotification = Notification.Name("AppIDsViewControllerDidDismissNotification")
}

final class AppIDsViewController: UICollectionViewController
{
    private lazy var dataSource = self.makeDataSource()
    
    private var didInitialFetch = false
    private var isLoading = false {
        didSet {
            self.update()
        }
    }
    private var doneBarButtonItem: UIBarButtonItem?
    
    private weak var footerView: TextCollectionReusableView?
    
    @IBOutlet var activityIndicatorBarButtonItem: UIBarButtonItem!

    override func viewWillDisappear(_ animated: Bool)
    {
        super.viewWillDisappear(animated)
        NotificationCenter.default.post(name: AppIDsViewController.didDismissNotification, object: self)
    }
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.navigationController?.additionalSafeAreaInsets.top = 20
        self.doneBarButtonItem = self.navigationItem.rightBarButtonItem
        
        self.collectionView.dataSource = self.dataSource
        self.dataSource.contentView = self.collectionView
        self.dataSource.fetchedResultsController.delegate = self
        
        self.activityIndicatorBarButtonItem.isIndicatingActivity = true
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
    func makeDataSource() -> FetchedResultsCollectionViewDataSource<AppID>
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
        
        let dataSource = FetchedResultsCollectionViewDataSource<AppID>(fetchRequest: fetchRequest, managedObjectContext: DatabaseManager.shared.viewContext)
        dataSource.proxy = self
        dataSource.cellConfigurationHandler = { [weak self] (cell, appID, indexPath) in
            guard let self = self else { return }
            let tintColor = UIColor.altPrimary
            
            let cell = cell as! AppBannerCollectionViewCell
            cell.tintColor = tintColor
            
            cell.contentView.preservesSuperviewLayoutMargins = false
            cell.contentView.layoutMargins = UIEdgeInsets(top: 0, left: self.view.layoutMargins.left, bottom: 0, right: self.view.layoutMargins.right)
                        
            cell.bannerView.iconImageView.isHidden = true
            cell.bannerView.button.isIndicatingActivity = false
            
            cell.bannerView.buttonLabel.text = NSLocalizedString("Expires in", comment: "")
            
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
                let timeIntervalText = timeInterval ?? NSLocalizedString("Unknown", comment: "")
                cell.bannerView.button.setTitle(timeIntervalText.uppercased(), for: .normal)
                
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
                let nsRange = NSRange(range, in: attributedBundleIdentifier.string)
                attributedBundleIdentifier.addAttributes([.accessibilitySpeechSpellOut: true], range: nsRange)
            }
            
            attributedAccessibilityLabel.append(attributedBundleIdentifier)
            cell.bannerView.accessibilityAttributedLabel = attributedAccessibilityLabel
            
            cell.layoutIfNeeded()
        }
        
        return dataSource
    }
    
    @objc func fetchAppIDs()
    {
        self.fetchAppIDsFromServer(completion: nil)
    }
    
    func fetchAppIDsFromServer(completion: (() -> Void)?)
    {
        guard !self.isLoading else { return }
        self.isLoading = true
        
        AppManager.shared.syncAppIDs { [weak self] (result) in
            guard let self = self else { return }
            do
            {
                try result.get()
            }
            catch
            {
                DispatchQueue.main.async {
                    let toastView = ToastView(error: error)
                    toastView.show(in: self)
                }
            }
            
            DispatchQueue.main.async {
                self.didInitialFetch = true
                self.isLoading = false
                completion?()
            }
        }
    }
    
    func update()
    {
        let isInitialLoading = self.isLoading && !self.didInitialFetch
        
        if !isInitialLoading
        {
            #if !os(tvOS)
            self.collectionView.refreshControl?.endRefreshing()
            #endif
            self.activityIndicatorBarButtonItem.isIndicatingActivity = false
            
            self.navigationItem.leftBarButtonItem = nil
            self.navigationItem.rightBarButtonItem = self.doneBarButtonItem
            
            #if !os(tvOS)
            if self.collectionView.refreshControl == nil
            {
                let refreshControl = UIRefreshControl()
                refreshControl.addTarget(self, action: #selector(AppIDsViewController.fetchAppIDs), for: .primaryActionTriggered)
                self.collectionView.refreshControl = refreshControl
            }
            #endif
        }
        else
        {
            self.activityIndicatorBarButtonItem.isIndicatingActivity = true
            self.navigationItem.leftBarButtonItem = self.activityIndicatorBarButtonItem
        }
    }
    
    func footerText() -> String {
        let count = self.dataSource.itemCount
        return count == 1
            ? NSLocalizedString("1 App ID", comment: "")
            : String(format: NSLocalizedString("%@ App IDs", comment: ""), NSNumber(value: count))
    }
    
    func refreshFooter()
    {
        self.footerView?.textLabel.text = self.footerText()
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
        if let activeTeam = DatabaseManager.shared.activeTeam(), activeTeam.type == .free
        {
            return CGSize(width: collectionView.bounds.width, height: 220)
        }
        else
        {
            return CGSize(width: collectionView.bounds.width, height: 160)
        }
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
                Each app and app extension installed with SideStore must register an App ID with Apple. Apple limits non-developer Apple IDs to 10 App IDs at a time.

                **App IDs can't be deleted**, but they do expire after one week. SideStore will automatically renew App IDs for all active apps once they've expired.
                """, comment: "")
                
                let attributedText = NSAttributedString(markdownRepresentation: text, attributes: [.font: headerView.textLabel.font as Any])
                headerView.textLabel.attributedText = attributedText
            }
            else
            {
                headerView.textLabel.text = NSLocalizedString("""
                Each app and app extension installed with SideStore must register an App ID with Apple.
                
                App IDs for paid developer accounts never expire, and there is no limit to how many you can create.
                """, comment: "")
            }
            
            return headerView
            
        case UICollectionView.elementKindSectionFooter:
            let footerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "Footer", for: indexPath) as! TextCollectionReusableView
            self.footerView = footerView  // keep direct reference for live updates
            footerView.textLabel.text = self.footerText()
            return footerView
            
        default: fatalError()
        }
    }
}


// MARK: - NSFetchedResultsControllerDelegate (proxy)
extension AppIDsViewController: NSFetchedResultsControllerDelegate
{
    func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>)
    {
        self.dataSource.controllerWillChangeContent(controller)
    }
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange sectionInfo: NSFetchedResultsSectionInfo, atSectionIndex sectionIndex: Int, for type: NSFetchedResultsChangeType)
    {
        self.dataSource.controller(controller, didChange: sectionInfo, atSectionIndex: sectionIndex, for: type)
    }
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?)
    {
        self.dataSource.controller(controller, didChange: anObject, at: indexPath, for: type, newIndexPath: newIndexPath)
    }
    
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>)
    {
        // Forward to the data source first so it performs animated cell batch updates
        self.dataSource.controllerDidChangeContent(controller)
        
        DispatchQueue.main.async {
            self.refreshFooter()
        }
    }
}

