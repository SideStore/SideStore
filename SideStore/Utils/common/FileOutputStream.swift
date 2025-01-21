//
//  FileOutputStream.swift
//  AltStore
//
//  Created by Magesh K on 28/12/24.
//  Copyright © 2024 SideStore. All rights reserved.
//

import Foundation

public class FileOutputStream: OutputStream {
    private let fileHandle: FileHandle
    
    init(_ fileHandle: FileHandle) {
        self.fileHandle = fileHandle
    }
    
    public func write(_ data: Data) {
        fileHandle.write(data)
    }
    
    public func flush() {
        fileHandle.synchronizeFile()
    }
    
    public func close() {
        fileHandle.closeFile()
    }
}
