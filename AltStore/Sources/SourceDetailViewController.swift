//
//  SourceDetailViewController.swift
//  AltStore
//
//  Created by Riley Testut on 3/15/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import UIKit
import SafariServices
import Combine
import AltStoreCore

import Nuke

extension SourceDetailViewController
{
    private class ViewModel: ObservableObject
    {
        let source: Source
        
        @Published
        var isSourceAdded: Bool? = nil
        
        @Published
        var isAddingSource: Bool = false
        
        init(source: Source)
        {
            self.source = source
            
            let sourceID = source.identifier
            
            let addedPublisher = NotificationCenter.default.publisher(for: AppManager.didAddSourceNotification, object: nil)
            let removedPublisher = NotificationCenter.default.publisher(for: AppManager.didRemoveSourceNotification, object: nil)
            
            Publishers.Merge(addedPublisher, removedPublisher)
                .filter { notification -> Bool in
                    guard let source = notification.object as? Source, let context = source.managedObjectContext else { return false }
                    
                    let updatedSourceID = context.performAndWait { source.identifier }
                    return sourceID == updatedSourceID
                }
                .compactMap { notification in
                    switch notification.name
                    {
                    case AppManager.didAddSourceNotification: return true
                    case AppManager.didRemoveSourceNotification: return false
                    default: return nil
                    }
                }
                .filter { $0 != nil }
                .receive(on: RunLoop.main)
                .assign(to: &self.$isSourceAdded)
            
            self.isSourceAdded = source.isPersisted
        }
    }
}

class SourceDetailViewController: HeaderContentViewController<SourceHeaderView, SourceDetailContentViewController>
{
    @Managed private(set) var source: Source
    
    var addedSourceHandler: ((Source) -> Void)?
    
    private let viewModel: ViewModel
    
    private var previousBounds: CGRect?
    private var cancellables = Set<AnyCancellable>()
    private var widthConstraint: NSLayoutConstraint?
    
    init?(source: Source, coder: NSCoder)
    {
        self.source = source
        self.viewModel = ViewModel(source: source)
        
        super.init(coder: coder)
        
        self.title = source.name
        self.tintColor = source.effectiveTintColor
    }
    
    required init?(coder: NSCoder)
    {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.navigationBarButton.addTarget(self, action: #selector(SourceDetailViewController.addSource), for: .primaryActionTriggered)
        
        Nuke.loadImage(with: self.source.effectiveIconURL, into: self.navigationBarIconView)
        Nuke.loadImage(with: self.source.effectiveHeaderImageURL, into: self.backgroundImageView)
        
        self.update()
        self.preparePipeline()
    }
    
    override func viewDidLayoutSubviews()
    {
        let inset = 15.0
        let headerHeight = self.headerView.fittedHeight(forWidth: self.view.bounds.width - inset * 2)
        
        if self.headerView.frame.size.height != headerHeight
        {
            self.headerView.frame.size.height = headerHeight
        }
        
        super.viewDidLayoutSubviews()
        
        self.navigationBarIconView.layer.cornerRadius = self.navigationBarIconView.bounds.midY
    }
    
    //MARK: Override
    
    override func makeContentViewController() -> SourceDetailContentViewController
    {
        guard let storyboard = self.storyboard else { fatalError("SourceDetailViewController must be initialized via UIStoryboard.") }
        
        let contentViewController = storyboard.instantiateViewController(identifier: "sourceDetailContentViewController") { coder in
            SourceDetailContentViewController(source: self.source, coder: coder)
        }
        return contentViewController
    }
    
    override func makeHeaderView() -> SourceHeaderView
    {
        let sourceAboutView = SourceHeaderView(frame: CGRect(x: 0, y: 0, width: 375, height: 200))
        sourceAboutView.configure(for: self.source)
        sourceAboutView.websiteButton.addTarget(self, action: #selector(SourceDetailViewController.showWebsite), for: .primaryActionTriggered)
        return sourceAboutView
    }
    
    override func update()
    {
        super.update()
        
        if self.source.identifier == Source.altStoreIdentifier
        {
            // Users can't remove default AltStore source, so hide buttons.
            self.navigationBarButton.isHidden = true
            
            if #available(iOS 16, *)
            {
                self.navigationItem.rightBarButtonItem?.isHidden = true
            }
        }
        else
        {
            // Update isIndicatingActivity first to ensure later updates are applied correctly.
            self.navigationBarButton.isIndicatingActivity = self.viewModel.isAddingSource
            
            let title: String
            
            switch self.viewModel.isSourceAdded
            {
            case true?:
                title = NSLocalizedString("REMOVE", comment: "")
                self.navigationBarButton.tintColor = self.source.effectiveTintColor?.adjustedForDisplay ?? .altPrimary
                self.navigationBarButton.isHidden = false
                
                if #available(iOS 16, *)
                {
                    self.navigationItem.rightBarButtonItem?.isHidden = false
                }
                
            case false?:
                title = NSLocalizedString("ADD", comment: "")
                self.navigationBarButton.tintColor = self.source.effectiveTintColor?.adjustedForDisplay ?? .altPrimary
                self.navigationBarButton.isHidden = false
                
                if #available(iOS 16, *)
                {
                    self.navigationItem.rightBarButtonItem?.isHidden = false
                }
                
            case nil:
                title = ""
                self.navigationBarButton.isHidden = true
            }
            
            if title != self.navigationBarButton.title(for: .normal) && !self.navigationBarButton.isIndicatingActivity
            {
                self.navigationBarButton.setTitle(title, for: .normal)
                self.navigationBarButton.sizeToFit()
                self.navigationBarButton.invalidateIntrinsicContentSize()
                self.navigationBarButton.superview?.invalidateIntrinsicContentSize()
                
                let barButtonItem = self.navigationItem.rightBarButtonItem
                self.navigationItem.rightBarButtonItem = nil
                self.navigationItem.rightBarButtonItem = barButtonItem
            }
            
            let currentSizeWidth = max(77, self.navigationBarButton.intrinsicContentSize.width)
            let targetWidth = currentSizeWidth + 2
            if let existingConstraint = self.widthConstraint
            {
                existingConstraint.constant = targetWidth
            }
            else
            {
                let constraint = self.navigationBarButton.widthAnchor.constraint(equalToConstant: targetWidth)
                constraint.isActive = true
                self.widthConstraint = constraint
            }
            
            self.view.setNeedsLayout()
        }
    }
    
    //MARK: Actions
    
    @objc private func addSource()
    {
        self.viewModel.isAddingSource = true
        
        Task<Void, Never> { /* @MainActor in */ // Already on MainActor, even though this function wasn't called from async context.
            var errorTitle = NSLocalizedString("Unable to Add Source", comment: "")
            
            do
            {
                let isAdded = try await self.source.isAdded
                if isAdded
                {
                    errorTitle = NSLocalizedString("Unable to Remove Source", comment: "")
                    try await AppManager.shared.remove(self.source, presentingViewController: self)
                }
                else
                {
                    try await AppManager.shared.add(self.source, presentingViewController: self)
                    
                    self.addedSourceHandler?(self.source)
                }
            }
            catch is CancellationError {}
            catch
            {
                await self.presentAlert(title: errorTitle, message: error.localizedDescription)
            }
            
            self.viewModel.isAddingSource = false
        }
    }
    
    @objc private func showWebsite()
    {
        guard let websiteURL = self.source.websiteURL else { return }
        
        let safariViewController = SFSafariViewController(url: websiteURL)
        safariViewController.preferredControlTintColor = self.source.effectiveTintColor ?? .altPrimary
        self.present(safariViewController, animated: true, completion: nil)
    }
}

private extension SourceDetailViewController
{
    func preparePipeline()
    {
        Publishers.CombineLatest(self.viewModel.$isSourceAdded, self.viewModel.$isAddingSource)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.update()
            }
            .store(in: &self.cancellables)
        
        // Adding or removing a source while viewing source details is currently broken,
        // so for now we just dismiss the view whenever the source is added or removed.
        self.viewModel.$isSourceAdded
            .compactMap { $0 }
            .dropFirst() // Ignore first non-nil value.
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] isAdded in
                if isAdded
                {
                    self?.didAddSource()
                }
                else
                {
                    self?.didRemoveSource()
                }
            }
            .store(in: &self.cancellables)
    }
    
    func didAddSource()
    {
        guard let presentingViewController = self.navigationController?.presentingViewController else { return }
        presentingViewController.dismiss(animated: true)
    }
    
    func didRemoveSource()
    {
        self.navigationController?.popToRootViewController(animated: true)
    }
}
