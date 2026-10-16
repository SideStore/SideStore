//
//  ExportPairingFileHandler.swift
//  SideStore
//
//  Created by Magesh K on 20/09/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import UIKit

@MainActor
public enum ExportPairingFileHandler {
    public static func handle(urlname: String) {
        guard let pairingContent = PairingFileManager.shared.fetchPairingFile(),
              let data = pairingContent.data(using: .utf8) else {
            debugLog("[ExportPairingFileHandler] Failed to find active pairing file")
            if let topVC = UIApplication.shared.topViewController() {
                let toast = ToastView(text: NSLocalizedString("Failed to find Pairing File!", comment: ""), detailText: nil)
                toast.show(in: topVC)
            }
            return
        }

        let base64encodedCert = data.base64EncodedString()
        var allowedQueryParamAndKey = CharacterSet.urlQueryAllowed
        allowedQueryParamAndKey.remove(charactersIn: ";/?:@&=+$, ")
        guard let encodedCert = base64encodedCert.addingPercentEncoding(withAllowedCharacters: allowedQueryParamAndKey) else {
            debugLog("[ExportPairingFileHandler] Failed to encode pairing file")
            if let topVC = UIApplication.shared.topViewController() {
                let toast = ToastView(text: NSLocalizedString("Failed to encode pairingFile!", comment: ""), detailText: nil)
                toast.show(in: topVC)
            }
            return
        }

        let urlStr = "\(urlname)://pairingFile?data=$(BASE64_PAIRING)"
        let finished = urlStr.replacingOccurrences(of: "$(BASE64_PAIRING)", with: encodedCert, options: .literal, range: nil)

        debugLog("[ExportPairingFileHandler] Opening callback URL: \(finished)")
        guard let callbackUrl = URL(string: finished) else {
            debugLog("[ExportPairingFileHandler] Failed to initialize callback URL")
            if let topVC = UIApplication.shared.topViewController() {
                let toast = ToastView(text: NSLocalizedString("Failed to initialize callback URL!", comment: ""), detailText: nil)
                toast.show(in: topVC)
            }
            return
        }
        UIApplication.shared.open(callbackUrl)
    }
}
