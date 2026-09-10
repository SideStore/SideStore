//
//  PlaceholderView.swift
//  AltStore
//
//  Created by Magesh K on 8/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import UIKit

public class PlaceholderView: UIView {
    public let stackView = UIStackView()
    public let imageView = UIImageView()
    public let textLabel = UILabel()
    public let activityIndicatorView: UIActivityIndicatorView
    public let detailTextLabel = UILabel()
    
    public override init(frame: CGRect) {
        self.activityIndicatorView = UIActivityIndicatorView(style: .medium)
        super.init(frame: frame)
        initialize()
    }
    
    public required init?(coder: NSCoder) {
        self.activityIndicatorView = UIActivityIndicatorView(style: .medium)
        super.init(coder: coder)
        initialize()
    }
    
    private func initialize() {
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.distribution = .equalSpacing
        stackView.alignment = .center
        stackView.spacing = UIDevice.current.userInterfaceIdiom == .tv ? 15 : 8
        
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.isHidden = true
        
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.textAlignment = .center
        textLabel.numberOfLines = 0
        textLabel.font = .preferredFont(forTextStyle: .title1)
        textLabel.textColor = UIColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1)
        
        activityIndicatorView.translatesAutoresizingMaskIntoConstraints = false
        activityIndicatorView.hidesWhenStopped = true
        activityIndicatorView.isHidden = true
        
        detailTextLabel.translatesAutoresizingMaskIntoConstraints = false
        detailTextLabel.textAlignment = .center
        detailTextLabel.numberOfLines = 0
        if UIDevice.current.userInterfaceIdiom == .tv {
            detailTextLabel.font = .preferredFont(forTextStyle: .headline)
        } else {
            detailTextLabel.font = .preferredFont(forTextStyle: .callout)
        }
        detailTextLabel.textColor = UIColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1)
        
        let detailTextWidthConstraint = detailTextLabel.widthAnchor.constraint(equalTo: stackView.widthAnchor)
        detailTextWidthConstraint.priority = UILayoutPriority(750)
        
        stackView.addArrangedSubview(imageView)
        stackView.addArrangedSubview(textLabel)
        stackView.addArrangedSubview(activityIndicatorView)
        stackView.addArrangedSubview(detailTextLabel)
        
        addSubview(stackView)
        
        let centerYConstraint = stackView.centerYAnchor.constraint(equalTo: centerYAnchor)
        centerYConstraint.priority = UILayoutPriority(750)
        
        let centerXConstraint = stackView.centerXAnchor.constraint(equalTo: centerXAnchor)
        centerXConstraint.priority = UILayoutPriority(999)
        
        let leadingConstraint = stackView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20)
        leadingConstraint.priority = UILayoutPriority(999)
        
        let trailingConstraint = trailingAnchor.constraint(greaterThanOrEqualTo: stackView.trailingAnchor, constant: 20)
        trailingConstraint.priority = UILayoutPriority(999)
        
        let preferredWidthConstraint = stackView.widthAnchor.constraint(equalTo: widthAnchor, constant: -40)
        preferredWidthConstraint.priority = UILayoutPriority(750)
        
        NSLayoutConstraint.activate([
            detailTextWidthConstraint,
            centerXConstraint,
            centerYConstraint,
            leadingConstraint,
            trailingConstraint,
            preferredWidthConstraint,
        ])
    }
}
