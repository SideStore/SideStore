//
//  SourceDetailsComponents.swift
//  AltStore
//
//  Created by Riley Testut on 3/16/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

@preconcurrency import UIKit


class TitleCollectionReusableView: UICollectionReusableView
{
    let label: UILabel
    
    override init(frame: CGRect)
    {
        #if !os(tvOS)
        let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .largeTitle).withSymbolicTraits(.traitBold)!
        #else
        let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .title1).withSymbolicTraits(.traitBold)!
        #endif
        let font = UIFont(descriptor: fontDescriptor, size: 0.0)
        
        self.label = UILabel(frame: .zero)
        self.label.font = font
        
        super.init(frame: frame)
        
        self.addSubview(self.label, pinningEdgesWith: .zero)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class ButtonCollectionReusableView: UICollectionReusableView
{
    let button: UIButton
    
    override init(frame: CGRect)
    {
        self.button = UIButton(type: .system)
        self.button.translatesAutoresizingMaskIntoConstraints = false
        
        super.init(frame: frame)
        
        self.addSubview(self.button, pinningEdgesWith: .zero)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class TextViewCollectionViewCell: UICollectionViewCell
{
    let textView = CollapsingTextView(frame: .zero)
    
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
        self.textView.font = UIFont.preferredFont(forTextStyle: .body)
        self.textView.isScrollEnabled = false
        #if !os(tvOS)
        self.textView.isEditable = false
        #endif
        self.textView.isSelectable = true
        #if !os(tvOS)
        self.textView.dataDetectorTypes = [.link]
        #endif
        self.contentView.addSubview(self.textView, pinningEdgesWith: .zero)
    }
    
    override func layoutMarginsDidChange()
    {
        super.layoutMarginsDidChange()
        
        self.textView.textContainerInset.left = self.contentView.layoutMargins.left
        self.textView.textContainerInset.right = self.contentView.layoutMargins.right
    }
}

class PlaceholderCollectionReusableView: UICollectionReusableView
{
    let placeholderView: PlaceholderView
    
    override init(frame: CGRect)
    {
        self.placeholderView = PlaceholderView(frame: .zero)
        self.placeholderView.activityIndicatorView.style = .medium
        
        super.init(frame: frame)
        
        self.addSubview(self.placeholderView, pinningEdgesWith: .zero)
        
        NSLayoutConstraint.activate([
            self.placeholderView.stackView.topAnchor.constraint(equalTo: self.placeholderView.topAnchor),
            self.placeholderView.stackView.bottomAnchor.constraint(equalTo: self.placeholderView.bottomAnchor),
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
