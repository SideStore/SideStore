//
//  OutputStream.swift
//  AltStore
//
//  Created by Magesh K on 28/12/24.
//  Copyright © 2024 SideStore. All rights reserved.
//

import Foundation

public protocol OutputStream {
    func write(_ data: Data)
    func flush()
    func close()
}
