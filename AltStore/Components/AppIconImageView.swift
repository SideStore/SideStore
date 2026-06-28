//
//  AppIconImageView.swift
//  AltStore
//
//  Created by Riley Testut on 5/9/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

extension AppIconImageView
{
    enum Style
    {
        case icon
        case circular
    }
}

class AppIconImageView: UIImageView
{
    var style: Style = .icon {
        didSet {
            self.setNeedsLayout()
        }
    }
    
    override var image: UIImage? {
        get {
            return super.image
        }
        set {
            if let newImage = newValue, newImage.hasAlphaChannel
            {
                super.image = newImage.withDropShadow(color: .black, radius: 4, offset: CGSize(width: 0, height: 1.5), opacity: 0.25)
            }
            else
            {
                super.image = newValue
            }
        }
    }
    
    init(style: Style) 
    {
        self.style = style
        
        super.init(image: nil)
        
        self.initialize()
    }
    
    required init?(coder: NSCoder) 
    {
        super.init(coder: coder)
        
        self.initialize()
    }
    
    private func initialize()
    {
        self.contentMode = .scaleAspectFill
        self.clipsToBounds = true
        self.backgroundColor = .white
        
        self.layer.cornerCurve = .continuous
    }
    
    override func layoutSubviews()
    {
        super.layoutSubviews()
        
        switch self.style
        {
        case .icon:
            // Based off of 60pt icon having 12pt radius.
            let radius = self.bounds.height / 5
            self.layer.cornerRadius = radius
            
        case .circular:
            let radius = self.bounds.height / 2
            self.layer.cornerRadius = radius
        }
    }
}

private extension UIImage
{
    var hasAlphaChannel: Bool {
        guard let cgImage = self.cgImage else { return false }
        let alphaInfo = cgImage.alphaInfo
        return alphaInfo != .none &&
               alphaInfo != .noneSkipLast &&
               alphaInfo != .noneSkipFirst
    }
    
    func withDropShadow(color: UIColor, radius: CGFloat, offset: CGSize, opacity: Float) -> UIImage?
    {
        let shadowColor = color.withAlphaComponent(CGFloat(opacity)).cgColor
        
        let format = UIGraphicsImageRendererFormat()
        format.scale = self.scale
        
        let renderer = UIGraphicsImageRenderer(size: self.size, format: format)
        return renderer.image { context in
            let cgContext = context.cgContext
            cgContext.setShadow(offset: offset, blur: radius, color: shadowColor)
            self.draw(in: CGRect(origin: .zero, size: self.size))
        }
    }
}
