//
//  UITableView+CellContent.swift
//  AltStoreCore
//
//  Created by Magesh K on 6/17/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import UIKit
extension UITableView: RSTCellContentUpdateableView {
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

extension UICollectionView: RSTCellContentUpdateableView {
    private struct AssociatedKeys {
        static var nestedUpdatesCounter = "rst_nestedUpdatesCounter"
        static var operations = "rst_operations"
    }

    private var rst_nestedUpdatesCounter: Int {
        get { objc_getAssociatedObject(self, &AssociatedKeys.nestedUpdatesCounter) as? Int ?? 0 }
        set { objc_setAssociatedObject(self, &AssociatedKeys.nestedUpdatesCounter, newValue, .OBJC_ASSOCIATION_COPY_NONATOMIC) }
    }

    private var rst_operations: [RSTCellContentChange]? {
        get { objc_getAssociatedObject(self, &AssociatedKeys.operations) as? [RSTCellContentChange] }
        set { objc_setAssociatedObject(self, &AssociatedKeys.operations, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    @objc public func beginUpdates() {
        if rst_nestedUpdatesCounter == 0 {
            rst_operations = []
        }
        rst_nestedUpdatesCounter += 1
    }

    @objc public func endUpdates() {
        guard rst_nestedUpdatesCounter > 0 else { return }
        rst_nestedUpdatesCounter -= 1
        
        if rst_nestedUpdatesCounter > 0 {
            return
        }
        
        guard let operations = rst_operations else { return }
        rst_operations = nil
        
        var postMoveUpdateChanges = [RSTCellContentChange]()
        for change in operations {
            if change.type == .move, let destinationIndexPath = change.destinationIndexPath {
                let updateChange = RSTCellContentChange(type: .update, currentIndexPath: destinationIndexPath, destinationIndexPath: nil)
                updateChange.rowAnimation = change.rowAnimation
                postMoveUpdateChanges.append(updateChange)
            }
        }
        
        var isFinished = false
        let finish = { [weak self] in
            guard let self = self, !isFinished else { return }
            isFinished = true
            
            if postMoveUpdateChanges.isEmpty {
                return
            }
            
            self.performBatchUpdates({
                for change in postMoveUpdateChanges {
                    if let currentIndexPath = change.currentIndexPath {
                        self.reloadItems(at: [currentIndexPath])
                    }
                }
            }, completion: nil)
        }
        
        CATransaction.begin()
        CATransaction.setCompletionBlock {
            finish()
        }
        
        self.performBatchUpdates({
            for change in operations {
                if change.sectionIndex != RSTUnknownSectionIndex {
                    let indexSet = IndexSet(integer: change.sectionIndex)
                    switch change.type {
                    case .insert: self.insertSections(indexSet)
                    case .delete: self.deleteSections(indexSet)
                    case .update: self.reloadSections(indexSet)
                    default: break
                    }
                } else {
                    switch change.type {
                    case .insert:
                        if let destinationIndexPath = change.destinationIndexPath {
                            self.insertItems(at: [destinationIndexPath])
                        }
                    case .delete:
                        if let currentIndexPath = change.currentIndexPath {
                            self.deleteItems(at: [currentIndexPath])
                        }
                    case .update:
                        if let currentIndexPath = change.currentIndexPath {
                            self.reloadItems(at: [currentIndexPath])
                        }
                    case .move:
                        if let currentIndexPath = change.currentIndexPath, let destinationIndexPath = change.destinationIndexPath {
                            self.moveItem(at: currentIndexPath, to: destinationIndexPath)
                        }
                    }
                }
            }
        }, completion: { _ in
            finish()
        })
        
        CATransaction.commit()
    }

    public func addChange(_ change: RSTCellContentChange) {
        if rst_nestedUpdatesCounter > 0 {
            rst_operations?.append(change)
        } else {
            self.performBatchUpdates({
                if change.sectionIndex != RSTUnknownSectionIndex {
                    let indexSet = IndexSet(integer: change.sectionIndex)
                    switch change.type {
                    case .insert: self.insertSections(indexSet)
                    case .delete: self.deleteSections(indexSet)
                    case .update: self.reloadSections(indexSet)
                    default: break
                    }
                } else {
                    switch change.type {
                    case .insert:
                        if let destinationIndexPath = change.destinationIndexPath { self.insertItems(at: [destinationIndexPath]) }
                    case .delete:
                        if let currentIndexPath = change.currentIndexPath { self.deleteItems(at: [currentIndexPath]) }
                    case .update:
                        if let currentIndexPath = change.currentIndexPath { self.reloadItems(at: [currentIndexPath]) }
                    case .move:
                        if let currentIndexPath = change.currentIndexPath, let destinationIndexPath = change.destinationIndexPath {
                            self.moveItem(at: currentIndexPath, to: destinationIndexPath)
                        }
                    }
                }
            }, completion: nil)
        }
    }
}
