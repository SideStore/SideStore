//
//  AppBannerCollectionViewCell.swift
//  AltStore
//
//  Created by Riley Testut on 3/23/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import UIKit

class AppBannerCollectionViewCell: UICollectionViewListCell
{
    let bannerView = AppBannerView(frame: .zero)
    let checkmarkImageView = UIImageView(frame: .zero)
    
    private var bannerViewLeadingConstraint: NSLayoutConstraint?
    private var bannerViewLeadingEditingConstraint: NSLayoutConstraint?
    
    override init(frame: CGRect)
    {
        super.init(frame: frame)
        
        self.initialize()
    }
    
    required init?(coder: NSCoder)
    {
        super.init(coder: coder)
        
        self.initialize()
    }
    
    private func initialize()
    {
        // Remove any storyboard-created duplicate subviews.
        for subview in self.contentView.subviews {
            subview.removeFromSuperview()
        }
        
        // Prevent content "squishing" when scrolling offscreen.
        self.insetsLayoutMarginsFromSafeArea = false
        self.contentView.insetsLayoutMarginsFromSafeArea = false
        self.bannerView.insetsLayoutMarginsFromSafeArea = false
        
        self.backgroundView = UIView() // Clear background
        self.selectedBackgroundView = UIView() // Disable selection highlighting.
        
        self.contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.contentView.preservesSuperviewLayoutMargins = true
        
        self.checkmarkImageView.translatesAutoresizingMaskIntoConstraints = false
        self.checkmarkImageView.contentMode = .scaleAspectFit
        self.checkmarkImageView.isHidden = true
        self.contentView.addSubview(self.checkmarkImageView)
        
        self.bannerView.translatesAutoresizingMaskIntoConstraints = false
        self.contentView.addSubview(self.bannerView)
        
        let leadingNormal = self.bannerView.leadingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.leadingAnchor)
        let leadingEditing = self.bannerView.leadingAnchor.constraint(equalTo: self.checkmarkImageView.trailingAnchor, constant: 12)
        
        self.bannerViewLeadingConstraint = leadingNormal
        self.bannerViewLeadingEditingConstraint = leadingEditing
        
        NSLayoutConstraint.activate([
            self.bannerView.topAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.topAnchor),
            self.bannerView.bottomAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.bottomAnchor),
            self.bannerView.trailingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.trailingAnchor),
            
            self.checkmarkImageView.centerYAnchor.constraint(equalTo: self.contentView.centerYAnchor),
            self.checkmarkImageView.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 20),
            self.checkmarkImageView.widthAnchor.constraint(equalToConstant: 24),
            self.checkmarkImageView.heightAnchor.constraint(equalToConstant: 24),
            
            leadingNormal
        ])
    }
    
    func setEditing(_ editing: Bool, isSelected: Bool, animated: Bool = false)
    {
        let systemImageName = isSelected ? "checkmark.circle.fill" : "circle"
        self.checkmarkImageView.image = UIImage(systemName: systemImageName)
        self.checkmarkImageView.tintColor = isSelected ? .altPrimary : .secondaryLabel
        
        let changeConstraints = {
            if editing
            {
                self.checkmarkImageView.isHidden = false
                self.checkmarkImageView.alpha = 1.0
                self.bannerViewLeadingConstraint?.isActive = false
                self.bannerViewLeadingEditingConstraint?.isActive = true
            }
            else
            {
                self.checkmarkImageView.alpha = 0.0
                self.bannerViewLeadingEditingConstraint?.isActive = false
                self.bannerViewLeadingConstraint?.isActive = true
            }
            self.layoutIfNeeded()
        }
        
        if animated
        {
            UIView.animate(withDuration: 0.3, animations: changeConstraints) { _ in
                if !editing {
                    self.checkmarkImageView.isHidden = true
                }
            }
        }
        else
        {
            changeConstraints()
            if !editing {
                self.checkmarkImageView.isHidden = true
            }
        }
    }
    
    override func prepareForReuse()
    {
        super.prepareForReuse()
        self.setEditing(false, isSelected: false)
    }
}
