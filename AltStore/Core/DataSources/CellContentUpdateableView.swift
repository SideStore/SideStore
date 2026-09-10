//
//  CellContentUpdateableView.swift
//  AltStore
//
//  Created by Magesh K on 8/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

@preconcurrency import UIKit

public protocol CellContentUpdateableView: AnyObject {
    func addChange(_ change: CellContentChange)
}

public protocol CellContentTransactionUpdateable: AnyObject {
    func beginUpdates()
    func endUpdates()
}
