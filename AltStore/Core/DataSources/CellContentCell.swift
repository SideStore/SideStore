//
//  CellContentCell.swift
//  AltStore
//
//  Created by Magesh K on 8/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

@preconcurrency import UIKit

public protocol CellContentCell: AnyObject {
    static var nib: UINib { get }
    static func instantiate(with nib: UINib) -> Self
}

extension UICollectionViewCell: CellContentCell {}

public extension UICollectionViewCell {
    class var nib: UINib {
        UINib(nibName: String(describing: self), bundle: nil)
    }

    class func instantiate(with nib: UINib) -> Self {
        nib.instantiate(withOwner: nil, options: nil).compactMap { $0 as? Self }.first ?? Self(frame: .zero)
    }
}

extension UITableViewCell: CellContentCell {}

public extension UITableViewCell {
    class var nib: UINib {
        UINib(nibName: String(describing: self), bundle: nil)
    }

    class func instantiate(with nib: UINib) -> Self {
        nib.instantiate(withOwner: nil, options: nil).compactMap { $0 as? Self }.first ?? Self(style: .default, reuseIdentifier: nil)
    }
}
