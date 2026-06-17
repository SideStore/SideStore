//
//  UIImage+Manipulation.swift
//  AltStoreCore
//
//  Created by Magesh K on 6/17/26.
//

import UIKit

public extension UIImage {
    @objc(imageByResizingToSize:)
    func resizing(to size: CGSize) -> UIImage? {
        var finalSize = size
        switch self.imageOrientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            finalSize = CGSize(width: size.height, height: size.width)
        default:
            break
        }
        
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = self.scale
        let renderer = UIGraphicsImageRenderer(size: finalSize, format: format)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: finalSize))
        }.withRenderingMode(self.renderingMode)
    }
    
    @objc(imageByResizingToFitSize:)
    func resizing(toFit size: CGSize) -> UIImage? {
        let imageSize = self.size
        let horizontalScale = size.width / imageSize.width
        let verticalScale = size.height / imageSize.height
        let scale = min(horizontalScale, verticalScale)
        let finalSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return self.resizing(to: finalSize)
    }
    
    @objc(imageByResizingToFillSize:)
    func resizing(toFill size: CGSize) -> UIImage? {
        let imageSize = self.size
        let horizontalScale = size.width / imageSize.width
        let verticalScale = size.height / imageSize.height
        let scale = max(horizontalScale, verticalScale)
        let finalSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return self.resizing(to: finalSize)
    }
    
    @objc(imageWithCornerRadius:)
    func withCornerRadius(_ cornerRadius: CGFloat) -> UIImage? {
        return self.withCornerRadius(cornerRadius, inset: .zero)
    }
    
    @objc(imageWithCornerRadius:inset:)
    func withCornerRadius(_ cornerRadius: CGFloat, inset: UIEdgeInsets) -> UIImage? {
        var correctedInset = inset
        switch self.imageOrientation {
        case .left, .leftMirrored:
            correctedInset.top = inset.left
            correctedInset.bottom = inset.right
            correctedInset.left = inset.bottom
            correctedInset.right = inset.top
        case .right, .rightMirrored:
            correctedInset.top = inset.right
            correctedInset.bottom = inset.left
            correctedInset.left = inset.top
            correctedInset.right = inset.bottom
        case .down, .downMirrored:
            correctedInset.top = inset.bottom
            correctedInset.bottom = inset.top
            correctedInset.left = inset.left
            correctedInset.right = inset.right
        default:
            break
        }
        
        let clippedRect = CGRect(x: 0, y: 0, width: self.size.width - correctedInset.left - correctedInset.right, height: self.size.height - correctedInset.top - correctedInset.bottom)
        let drawingRect = CGRect(x: -correctedInset.left, y: -correctedInset.top, width: self.size.width, height: self.size.height)
        
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = self.scale
        let renderer = UIGraphicsImageRenderer(size: clippedRect.size, format: format)
        return renderer.image { context in
            let path = UIBezierPath(roundedRect: clippedRect, cornerRadius: cornerRadius)
            path.addClip()
            self.draw(in: drawingRect)
        }.withRenderingMode(self.renderingMode)
    }
    
    @objc(rotatedToImageOrientation:)
    func rotated(to imageOrientation: UIImage.Orientation) -> UIImage? {
        guard let cgImage = self.cgImage else { return nil }
        return UIImage(cgImage: cgImage, scale: self.scale, orientation: imageOrientation).rotatedToIntrinsicOrientation()
    }
    
    @objc(rotatedToIntrinsicOrientation)
    func rotatedToIntrinsicOrientation() -> UIImage? {
        if self.imageOrientation == .up {
            return self
        }
        
        var transform = CGAffineTransform.identity
        
        switch self.imageOrientation {
        case .down, .downMirrored:
            transform = transform.translatedBy(x: self.size.width, y: self.size.height)
            transform = transform.rotated(by: .pi)
        case .left, .leftMirrored:
            transform = transform.translatedBy(x: self.size.width, y: 0)
            transform = transform.rotated(by: .pi / 2)
        case .right, .rightMirrored:
            transform = transform.translatedBy(x: 0, y: self.size.height)
            transform = transform.rotated(by: -.pi / 2)
        default:
            break
        }
        
        switch self.imageOrientation {
        case .upMirrored, .downMirrored:
            transform = transform.translatedBy(x: self.size.width, y: 0)
            transform = transform.scaledBy(x: -1, y: 1)
        case .leftMirrored, .rightMirrored:
            transform = transform.translatedBy(x: self.size.height, y: 0)
            transform = transform.scaledBy(x: -1, y: 1)
        default:
            break
        }
        
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = self.scale
        
        var renderSize = self.size
        switch self.imageOrientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            renderSize = CGSize(width: self.size.height, height: self.size.width)
        default:
            break
        }
        
        let renderer = UIGraphicsImageRenderer(size: renderSize, format: format)
        return renderer.image { context in
            context.cgContext.concatenate(transform)
            
            switch self.imageOrientation {
            case .left, .leftMirrored, .right, .rightMirrored:
                self.draw(in: CGRect(x: 0, y: 0, width: renderSize.height, height: renderSize.width))
            default:
                self.draw(in: CGRect(origin: .zero, size: renderSize))
            }
        }.withRenderingMode(self.renderingMode)
    }
}
