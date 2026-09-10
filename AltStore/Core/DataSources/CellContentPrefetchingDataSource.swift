//
//  CellContentPrefetchingDataSource.swift
//  AltStore
//
//  Created by Magesh K on 8/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

@preconcurrency import UIKit

public protocol CellContentPrefetchingDataSource: AnyObject {
    associatedtype ContentType
    associatedtype CellType: UIView & CellContentCell
    associatedtype PrefetchContentType
    
    var prefetchItemCache: NSCache<AnyObject, AnyObject> { get }
    var prefetchHandler: ((ContentType, IndexPath) async throws -> PrefetchContentType?)? { get set }
    var prefetchCompletionHandler: ((CellType, PrefetchContentType?, IndexPath, Error?) -> Void)? { get set }
}
