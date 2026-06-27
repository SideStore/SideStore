//
//  RSTCellContentPrefetchingDataSource.swift
//  AltStoreCore
//
//  Created by Magesh K on 6/17/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import UIKit

public protocol RSTCellContentPrefetchingDataSource: AnyObject {
    associatedtype ContentType
    associatedtype CellType: UIView & RSTCellContentCell
    associatedtype PrefetchContentType
    
    var prefetchItemCache: NSCache<AnyObject, AnyObject> { get }
    var prefetchHandler: ((ContentType, IndexPath, @escaping (PrefetchContentType?, Error?) -> Void) -> Operation?)? { get set }
    var prefetchCompletionHandler: ((CellType, PrefetchContentType?, IndexPath, Error?) -> Void)? { get set }
}
