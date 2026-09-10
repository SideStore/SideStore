//
//  CellContentChange.swift
//  AltStore
//
//  Created by Magesh K on 8/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

@preconcurrency import UIKit
import CoreData

public let UnknownSectionIndex: Int = -1

public final class CellContentChange: NSObject {
    public enum ChangeType: Int {
        case insert
        case delete
        case move
        case update
    }

    public let type: ChangeType
    public let currentIndexPath: IndexPath?
    public let destinationIndexPath: IndexPath?
    public let sectionIndex: Int
    public var rowAnimation: UITableView.RowAnimation = .automatic

    public init(type: ChangeType, currentIndexPath: IndexPath?, destinationIndexPath: IndexPath?) {
        self.type = type
        self.currentIndexPath = currentIndexPath
        self.destinationIndexPath = destinationIndexPath
        self.sectionIndex = UnknownSectionIndex
        super.init()
    }

    public init(type: ChangeType, sectionIndex: Int) {
        self.type = type
        self.currentIndexPath = nil
        self.destinationIndexPath = nil
        self.sectionIndex = sectionIndex
        super.init()
    }
}
