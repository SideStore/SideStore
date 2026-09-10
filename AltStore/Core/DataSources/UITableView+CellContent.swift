//
//  UITableView+CellContent.swift
//  AltStore
//
//  Created by Magesh K on 8/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

@preconcurrency import UIKit

extension UITableView: CellContentUpdateableView, CellContentTransactionUpdateable {
    public func addChange(_ change: CellContentChange) {
        if change.sectionIndex != UnknownSectionIndex {
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
                    Task { @MainActor [weak self] in
                        self?.reloadRows(at: [destinationIndexPath], with: change.rowAnimation)
                    }
                    self.moveRow(at: currentIndexPath, to: destinationIndexPath)
                }
            }
        }
    }
}
