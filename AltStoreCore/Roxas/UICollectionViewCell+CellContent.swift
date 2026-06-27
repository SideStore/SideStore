//
//  UICollectionViewCell+CellContent.swift
//  AltStoreCore
//
//  Created by Magesh K on 6/17/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import UIKit

extension UICollectionViewCell: RSTCellContentCell {}

public extension UICollectionViewCell {
    class var nib: UINib {
        UINib(nibName: String(describing: self), bundle: nil)
    }

    class func instantiate(with nib: UINib) -> Self {
        nib.instantiate(withOwner: nil, options: nil).compactMap { $0 as? Self }.first ?? Self(frame: .zero)
    }
}
