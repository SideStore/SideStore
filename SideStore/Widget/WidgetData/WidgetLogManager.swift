//
//  WidgetLogManager.swift
//  SideStore
//
//  Created by Magesh K on 8/13/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation

public enum WidgetLogManager {
    public static var widgetLogURL: URL? {
        FileManager.default.altstoreSharedDirectory?.appendingPathComponent("widget.log")
    }
    
    public static var widgetLogsDirectory: URL {
        let docs = FileManager.default.documentsDirectory
        let dir = docs.appendingPathComponent("WidgetLogs")
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    @discardableResult
    public static func rotateLog() throws -> URL? {
        guard let logURL = widgetLogURL, FileManager.default.fileExists(atPath: logURL.path) else {
            return nil
        }
        
        let fileHandle = try FileHandle(forUpdating: logURL)
        defer { try? fileHandle.close() }
        
        let fd = fileHandle.fileDescriptor
        flock(fd, LOCK_EX)
        defer { flock(fd, LOCK_UN) }
        
        guard let data = try fileHandle.readToEnd(), !data.isEmpty else {
            return nil
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let timestamp = formatter.string(from: Date())
        
        let rotatedFilename = "widget_\(timestamp).log"
        let destinationURL = widgetLogsDirectory.appendingPathComponent(rotatedFilename)
        
        try data.write(to: destinationURL, options: Data.WritingOptions.atomic)
        
        try fileHandle.truncate(atOffset: 0)
        try fileHandle.seek(toOffset: 0)
        
        let resetHeader = """
        
        ===================================================
        [INFO] Log file rotated at \(timestamp)
        ===================================================
        
        
        """
        if let resetData = resetHeader.data(using: .utf8) {
            try fileHandle.write(contentsOf: resetData)
        }
        
        return destinationURL
    }
}
