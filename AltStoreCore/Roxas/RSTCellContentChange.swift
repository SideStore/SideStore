//
//  RSTCellContentChange.swift
//  AltStoreCore
//
//  Created by Magesh K on 6/17/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import UIKit
import CoreData
public let RSTUnknownSectionIndex: Int = -1

@objc(RSTCellContentChange)
public final class RSTCellContentChange: NSObject {
    @objc public enum ChangeType: Int {
        case insert
        case delete
        case move
        case update
    }

    @objc public let type: ChangeType
    @objc public let currentIndexPath: IndexPath?
    @objc public let destinationIndexPath: IndexPath?
    @objc public let sectionIndex: Int
    @objc public var rowAnimation: UITableView.RowAnimation = .automatic

    @objc(initWithType:currentIndexPath:destinationIndexPath:)
    public init(type: ChangeType, currentIndexPath: IndexPath?, destinationIndexPath: IndexPath?) {
        self.type = type
        self.currentIndexPath = currentIndexPath
        self.destinationIndexPath = destinationIndexPath
        self.sectionIndex = RSTUnknownSectionIndex
        super.init()
    }

    @objc(initWithType:sectionIndex:)
    public init(type: ChangeType, sectionIndex: Int) {
        self.type = type
        self.currentIndexPath = nil
        self.destinationIndexPath = nil
        self.sectionIndex = sectionIndex
        super.init()
    }
}
