//
//  UIColor+Hex.swift
//  AltStore
//
//  Created by Riley Testut on 7/15/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import UIKit

public extension UIColor {
    // Borrowed from https://stackoverflow.com/a/26341062
    var hexString: String {
        let components = cgColor.components
        let r: CGFloat = components?[0] ?? 0.0
        let g: CGFloat = components?[1] ?? 0.0
        let b: CGFloat = components?[2] ?? 0.0

        let hexString = String(format: "%02lX%02lX%02lX", lroundf(Float(r * 255)), lroundf(Float(g * 255)), lroundf(Float(b * 255)))
        return hexString
    }
}

public extension UIColor {
    convenience init?(hexString: String) {
        let hexString = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        let scanner = Scanner(string: hexString)

        if hexString.hasPrefix("#") {
            scanner.scanLocation = 1
            // TODO: Test if this works to replace the above deprecation @JoeMatt
//            scanner.currentIndex = .init(utf16Offset: 1, in: hexString)
        }

        var hexNumber: UInt64 = 0

        guard scanner.scanHexInt64(&hexNumber) else {
            return nil
        }

        var alpha: UInt64 = 255
        var red: UInt64 = 0
        var green: UInt64 = 0
        var blue: UInt64 = 0

        switch hexString.count {
        case 3: // RGB (12-bit)
            red = ((hexNumber & 0xF00) >> 8) * 17
            green = ((hexNumber & 0x0F0) >> 4) * 17
            blue = (hexNumber & 0x00F) * 17
        case 6: // RGB (24-bit)
            red = (hexNumber & 0xFF0000) >> 16
            green = (hexNumber & 0x00FF00) >> 8
            blue = hexNumber & 0x0000FF
        case 8: // ARGB (32-bit)
            alpha = (hexNumber & 0xFF00_0000) >> 24
            red = (hexNumber & 0x00FF_0000) >> 16
            green = (hexNumber & 0x0000_FF00) >> 8
            blue = hexNumber & 0x0000_00FF
        default:
            return nil
        }

        self.init(
            red: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: CGFloat(alpha) / 255
        )
    }
}
