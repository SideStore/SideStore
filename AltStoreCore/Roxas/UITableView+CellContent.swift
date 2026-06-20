//
//  UITableView+CellContent.swift
//  AltStoreCore
//
//  Created by Magesh K on 6/17/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import UIKit

extension UITableView: RSTCellContentUpdateableView, RSTCellContentTransactionUpdateable {
    public func addChange(_ change: RSTCellContentChange) {
        if change.sectionIndex != RSTUnknownSectionIndex {
            let indexSet = IndexSet(integer: change.sectionIndex)
            switch change.type {
            case .insert:
                self.insertSections(indexSet, with: change.rowAnimation)
            case .delete:
                self.deleteSections(indexSet, with: change.rowAnimation)
            case .update:
                self.reloadSections(indexSet, with: change.rowAnimation)
            default:
                break
            }
        } else {
            switch change.type {
            case .insert:
                if let destinationIndexPath = change.destinationIndexPath {
                    self.insertRows(at: [destinationIndexPath], with: change.rowAnimation)
                }
            case .delete:
                if let currentIndexPath = change.currentIndexPath {
                    self.deleteRows(at: [currentIndexPath], with: change.rowAnimation)
                }
            case .update:
                if let currentIndexPath = change.currentIndexPath {
                    self.reloadRows(at: [currentIndexPath], with: change.rowAnimation)
                }
            case .move:
                if let currentIndexPath = change.currentIndexPath, let destinationIndexPath = change.destinationIndexPath {
                    DispatchQueue.main.async {
                        self.reloadRows(at: [destinationIndexPath], with: change.rowAnimation)
                    }
                    self.moveRow(at: currentIndexPath, to: destinationIndexPath)
                }
            }
        }
    }
}
