//
//  UIViewController+ShareSheet.swift
//  SideStore
//
//  Copyright © 2026 SideStore. All rights reserved.
//

#if !os(tvOS)

import UIKit

extension UIViewController {
    
    /// Presents a share sheet for `items`, anchored to this view controller.
    ///
    /// Wherever the trait environment calls for it - an iPad, or a regular width window on any
    /// device - UIKit presents `UIActivityViewController` as a popover, and a popover without an
    /// anchor throws before it can appear:
    ///
    /// > UIPopoverPresentationController (...) should have a non-nil sourceView or barButtonItem
    /// > set before the presentation occurs.
    ///
    /// These sheets are opened from SwiftUI rows that have no UIKit view to point at, so the
    /// popover is centred on the presenting view controller with no arrow.
    func presentShareSheet(for items: [Any],
                           applicationActivities: [UIActivity]? = nil,
                           animated: Bool = true) {
        let activityViewController = UIActivityViewController(activityItems: items,
                                                              applicationActivities: applicationActivities)
        
        if let popover = activityViewController.popoverPresentationController {
            popover.sourceView = self.view
            popover.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        self.present(activityViewController, animated: animated)
    }
}

#endif
