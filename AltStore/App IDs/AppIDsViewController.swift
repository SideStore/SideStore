//
//  AppIDsViewController.swift
//  AltStore
//
//  Created by Riley Testut on 1/27/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import UIKit
import CoreData
@preconcurrency import AltStoreCore
import SwiftUI
import AltSign

final class AppIDsViewController: UICollectionViewController
{
    private lazy var dataSource = self.makeDataSource()
    
    private var didInitialFetch = false
    private var isLoading = false {
        didSet {
            self.update()
        }
    }
    private var isEditingMode = false
    private var doneBarButtonItem: UIBarButtonItem?
    
    private weak var footerView: TextCollectionReusableView?
    
    @IBOutlet var activityIndicatorBarButtonItem: UIBarButtonItem!
    
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
            
            let isSelected = self.collectionView.indexPathsForSelectedItems?.contains(indexPath) ?? false
            cell.setEditing(self.isEditingMode, isSelected: isSelected)
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
        
        AppManager.shared.fetchAppIDs { [weak self] (result) in
            guard let self = self else { return }
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
            self.collectionView.refreshControl?.endRefreshing()
            self.activityIndicatorBarButtonItem.isIndicatingActivity = false
            
            if let activeTeam = DatabaseManager.shared.activeTeam(), activeTeam.type != .free
            {
                if self.isEditingMode
                {
                    let selectedCount = self.collectionView.indexPathsForSelectedItems?.count ?? 0
                    let title = selectedCount > 0 ? NSLocalizedString("Delete", comment: "") : NSLocalizedString("Cancel", comment: "")
                    let style: UIBarButtonItem.Style = selectedCount > 0 ? .done : .plain
                    self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: title, style: style, target: self, action: #selector(self.editButtonTapped))
                }
                else
                {
                    self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: NSLocalizedString("Edit", comment: ""), style: .plain, target: self, action: #selector(self.editButtonTapped))
                }
            }
            else
            {
                self.navigationItem.leftBarButtonItem = nil
            }
            
            if self.isEditingMode
            {
                self.navigationItem.rightBarButtonItem = nil
            }
            else
            {
                self.navigationItem.rightBarButtonItem = self.doneBarButtonItem
            }
            
            if self.isEditingMode
            {
                self.collectionView.refreshControl = nil
            }
            else
            {
                if self.collectionView.refreshControl == nil
                {
                    let refreshControl = UIRefreshControl()
                    refreshControl.addTarget(self, action: #selector(AppIDsViewController.fetchAppIDs), for: .primaryActionTriggered)
                    self.collectionView.refreshControl = refreshControl
                }
            }
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

// MARK: - Editing & Deletion
private extension AppIDsViewController
{
    func enterEditMode()
    {
        self.isEditingMode = true
        self.collectionView.allowsMultipleSelection = true
        self.navigationController?.isModalInPresentation = true
        
        for cell in self.collectionView.visibleCells {
            if let cell = cell as? AppBannerCollectionViewCell, let indexPath = self.collectionView.indexPath(for: cell) {
                let isSelected = self.collectionView.indexPathsForSelectedItems?.contains(indexPath) ?? false
                cell.setEditing(true, isSelected: isSelected, animated: true)
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.collectionView.reloadData()
        }
        
        self.update()
    }
    
    func exitEditMode()
    {
        self.isEditingMode = false
        self.collectionView.allowsMultipleSelection = false
        if let selectedItems = self.collectionView.indexPathsForSelectedItems {
            for indexPath in selectedItems {
                self.collectionView.deselectItem(at: indexPath, animated: false)
            }
        }
        self.navigationController?.isModalInPresentation = false
        
        for cell in self.collectionView.visibleCells {
            if let cell = cell as? AppBannerCollectionViewCell {
                cell.setEditing(false, isSelected: false, animated: true)
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.collectionView.reloadData()
        }
        
        self.update()
    }
    
    func updateLeftBarButtonItem()
    {
        let selectedCount = self.collectionView.indexPathsForSelectedItems?.count ?? 0
        let title = selectedCount > 0 ? NSLocalizedString("Delete", comment: "") : NSLocalizedString("Cancel", comment: "")
        let style: UIBarButtonItem.Style = selectedCount > 0 ? .done : .plain
        self.navigationItem.leftBarButtonItem?.title = title
        self.navigationItem.leftBarButtonItem?.style = style
    }
    
    @objc func editButtonTapped()
    {
        if self.isEditingMode
        {
            let selectedCount = self.collectionView.indexPathsForSelectedItems?.count ?? 0
            if selectedCount > 0
            {
                let alert = UIAlertController(
                    title: NSLocalizedString("Delete App IDs", comment: ""),
                    message: String(format: NSLocalizedString("Are you sure you want to proceed to delete %d appIds?", comment: ""), selectedCount),
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
                alert.addAction(UIAlertAction(title: NSLocalizedString("Delete", comment: ""), style: .destructive) { [weak self] _ in
                    self?.deleteSelectedAppIDs()
                })
                self.present(alert, animated: true)
            }
            else
            {
                self.exitEditMode()
            }
        }
        else
        {
            self.enterEditMode()
        }
    }
    
    func reselectRemainingAppIDs(bundleIdentifiers: Set<String>)
    {
        for section in 0..<self.collectionView.numberOfSections
        {
            for item in 0..<self.collectionView.numberOfItems(inSection: section)
            {
                let indexPath = IndexPath(item: item, section: section)
                let appID = self.dataSource.item(at: indexPath)
                if bundleIdentifiers.contains(appID.bundleIdentifier)
                {
                    self.collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
                    if let cell = self.collectionView.cellForItem(at: indexPath) as? AppBannerCollectionViewCell {
                        cell.setEditing(true, isSelected: true, animated: false)
                    }
                }
            }
        }
        self.updateLeftBarButtonItem()
    }
    
    func getSessionAndTeam() async throws -> (ALTTeam, ALTAppleAPISession)
    {
        try await withCheckedThrowingContinuation { continuation in
            AppManager.shared.authenticate(presentingViewController: self) { result in
                switch result {
                case .success(let (team, _, session)):
                    continuation.resume(returning: (team, session))
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func deleteSelectedAppIDs()
    {
        let selectedIndexPaths = self.collectionView.indexPathsForSelectedItems ?? []
        let appIDsToDelete = selectedIndexPaths.compactMap { self.dataSource.item(at: $0) }
        guard !appIDsToDelete.isEmpty else { return }
        
        let progressModel = DeleteProgressModel(total: appIDsToDelete.count)
        let overlayView = DeleteOverlayView(model: progressModel) { [weak self] in
            self?.dismiss(animated: true) {
                self?.fetchAppIDs()
            }
        }
        
        let hostingController = UIHostingController(rootView: overlayView)
        hostingController.modalPresentationStyle = .overFullScreen
        hostingController.modalTransitionStyle = .crossDissolve
        hostingController.view.backgroundColor = .clear
        
        self.present(hostingController, animated: true) {
            Task {
                var completedCount = 0
                var failedAppID: AppID?
                var deletionError: Error?
                
                do
                {
                    let (team, session) = try await self.getSessionAndTeam()
                    
                    for appID in appIDsToDelete
                    {
                        let progressText = String(format: NSLocalizedString("Deleting App IDs (%d/%d)...", comment: ""), completedCount + 1, appIDsToDelete.count)
                        await MainActor.run {
                            progressModel.status = .deleting(progressText: progressText)
                        }
                        
                        let altAppID = ALTAppID(
                            name: appID.name,
                            identifier: appID.identifier,
                            bundleIdentifier: appID.bundleIdentifier,
                            expirationDate: appID.expirationDate,
                            features: appID.features
                        )
                        
                        let success = try await withCheckedThrowingContinuation { (c: CheckedContinuation<Bool, Error>) in
                            ALTAppleAPI.shared.deleteAppID(altAppID, for: team, session: session) { (success, error) in
                                if let error = error {
                                    c.resume(throwing: error)
                                } else {
                                    c.resume(returning: success)
                                }
                            }
                        }
                        
                        if success
                        {
                            await DatabaseManager.shared.persistentContainer.viewContext.perform {
                                DatabaseManager.shared.persistentContainer.viewContext.delete(appID)
                                try? DatabaseManager.shared.persistentContainer.viewContext.save()
                            }
                            completedCount += 1
                        }
                        else
                        {
                            failedAppID = appID
                            deletionError = AppIDDeletionError.unknown
                            break
                        }
                    }
                }
                catch
                {
                    deletionError = error
                    if failedAppID == nil && completedCount < appIDsToDelete.count
                    {
                        failedAppID = appIDsToDelete[completedCount]
                    }
                }
                
                let finalFailedAppID = failedAppID
                let finalError = deletionError
                
                await MainActor.run {
                    if let finalError = finalError
                    {
                        Logger.sideload.error("Failed to delete App ID: \(finalError.localizedDescription)")
                        
                        hostingController.dismiss(animated: true) {
                            let alertTitle = NSLocalizedString("Delete Failed", comment: "")
                            var alertMessage = ""
                            if let failedAppID = finalFailedAppID
                            {
                                alertMessage = String(
                                    format: NSLocalizedString("Deleted %d of %d App IDs.\n\nFailed to delete %@ (%@):\n%@", comment: ""),
                                    completedCount,
                                    appIDsToDelete.count,
                                    failedAppID.name,
                                    failedAppID.bundleIdentifier,
                                    finalError.localizedDescription
                                )
                            }
                            else
                            {
                                alertMessage = String(
                                    format: NSLocalizedString("Deleted %d of %d App IDs.\n\nError:\n%@", comment: ""),
                                    completedCount,
                                    appIDsToDelete.count,
                                    finalError.localizedDescription
                                )
                            }
                            
                            let alert = UIAlertController(title: alertTitle, message: alertMessage, preferredStyle: .alert)
                            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default) { _ in
                                let remainingBundleIdentifiers = Set(appIDsToDelete[completedCount...].map { $0.bundleIdentifier })
                                self.fetchAppIDsFromServer(completion: {
                                    DispatchQueue.main.async {
                                        self.reselectRemainingAppIDs(bundleIdentifiers: remainingBundleIdentifiers)
                                    }
                                })
                            })
                            self.present(alert, animated: true)
                        }
                    }
                    else
                    {
                        progressModel.status = .success
                    }
                }
            }
        }
    }
}

// MARK: - Collection View Delegate overrides
extension AppIDsViewController
{
    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath)
    {
        if self.isEditingMode
        {
            self.updateLeftBarButtonItem()
            if let cell = collectionView.cellForItem(at: indexPath) as? AppBannerCollectionViewCell {
                cell.setEditing(true, isSelected: true, animated: true)
            }
        }
    }
    
    override func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath)
    {
        if self.isEditingMode
        {
            self.updateLeftBarButtonItem()
            if let cell = collectionView.cellForItem(at: indexPath) as? AppBannerCollectionViewCell {
                cell.setEditing(true, isSelected: false, animated: true)
            }
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

// MARK: - SwiftUI Delete Overlay Views
enum DeleteStatus
{
    case deleting(progressText: String)
    case success
}

class DeleteProgressModel: ObservableObject
{
    @Published var status: DeleteStatus
    let total: Int
    
    init(total: Int)
    {
        self.total = total
        self.status = .deleting(progressText: String(format: NSLocalizedString("Deleting App IDs (0/%d)...", comment: ""), total))
    }
}

struct DeleteOverlayView: View
{
    @ObservedObject var model: DeleteProgressModel
    var onDismiss: () -> Void
    
    var body: some View
    {
        ZStack
        {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            VStack(spacing: 24)
            {
                switch model.status
                {
                case .deleting(let progressText):
                    VStack(spacing: 20)
                    {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                            .padding(.top, 10)
                        
                        Text(progressText)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                    }
                    
                case .success:
                    VStack(spacing: 20)
                    {
                        AnimatedCheckmarkView()
                            .padding(.top, 10)
                        
                        Text("App IDs Deleted")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                        
                        SwiftUI.Button(action: {
                            onDismiss()
                        }) {
                            Text("OK")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.white.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .padding(24)
            .frame(width: 320)
            .background(.ultraThinMaterial)
            .environment(\.colorScheme, .dark)
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)
        }
    }
}

// MARK: - Error Types
enum AppIDDeletionError: LocalizedError
{
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .unknown:
            return NSLocalizedString("Unknown deletion error", comment: "")
        }
    }
}
