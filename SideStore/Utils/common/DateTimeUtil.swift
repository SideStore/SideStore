//
//  DateTimeUtil.swift
//  AltStore
//
//  Created by Magesh K on 02/01/25.
//  Copyright © 2025 SideStore. All rights reserved.
//

import Foundation

public class DateTimeUtil {
    public static func getDateInTimeStamp(date: Date) -> String {
        let formatter = DateFormatter()
        // (upto millis accurate for uniqueness)
        formatter.dateFormat = "yyyyMMdd_HHmmss_SSS" // Format: 20241228_142345_300
        // Ensures 24-hour clock format coz the locale value overrides it if it is of AM/PM format?! (why apple!)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }
    
    public static func getTimeStampSuffixedFileName(fileName: String, timestamp: String, extn: String) -> String {
        // create a log file with the current timestamp
        let fnameWithTimestamp = "\(fileName)-\(timestamp)\(extn)"
        return fnameWithTimestamp
    }
}
