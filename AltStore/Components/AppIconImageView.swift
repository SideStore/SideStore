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
                if newImage.isPredominantlyLight
                {
                    self.backgroundColor = .black
                }
                else
                {
                    self.backgroundColor = .white
                }
                super.image = newImage.withDropShadow(color: .black, radius: 4, offset: CGSize(width: 0, height: 1.5), opacity: 0.25)
            }
            else
            {
                self.backgroundColor = .white
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
    
    var isPredominantlyLight: Bool {
        guard let cgImage = self.cgImage else { return false }
        
        let width = 16
        let height = 16
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let bitsPerComponent = 8
        
        var rawData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        )
        
        guard let context = context else { return false }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        var totalLuminance: CGFloat = 0.0
        var totalOpaquePixels: CGFloat = 0.0
        
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * bytesPerPixel
                let r = CGFloat(rawData[offset])
                let g = CGFloat(rawData[offset + 1])
                let b = CGFloat(rawData[offset + 2])
                let a = CGFloat(rawData[offset + 3]) / 255.0
                
                // Only consider pixels that are not fully transparent (alpha > 0.1)
                if a > 0.1 {
                    // Relative luminance formula
                    let luminance = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0
                    totalLuminance += luminance * a
                    totalOpaquePixels += a
                }
            }
        }
        
        if totalOpaquePixels == 0 {
            return false
        }
        
        let averageLuminance = totalLuminance / totalOpaquePixels
        return averageLuminance > 0.5
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
