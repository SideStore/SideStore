//
//  CertificateExporter.swift
//  SideStore
//
//  Created by Magesh K on 2026-07-03.
//  Copyright © 2026 SideStore. All rights reserved.
//

@preconcurrency import UIKit
import SideSign

enum CertificateExporter {
    
    static func sharePublicCertAsDER(_ cert: ALTX509Certificate, onError: @escaping (String) -> Void) {
        guard let data = cert.data else { onError("Public certificate data is missing."); return }
        share(data: getDERData(from: data) ?? data, filename: (cert.machineName ?? cert.name) + ".der", onError: onError)
    }
    
    static func sharePublicCertAsPEM(_ cert: ALTX509Certificate, onError: @escaping (String) -> Void) {
        guard let data = cert.data else { onError("Public certificate data is missing."); return }
        share(data: data, filename: (cert.machineName ?? cert.name) + ".pem", onError: onError)
    }
    
    static func copyPublicCertAsPEM(_ cert: ALTX509Certificate, onError: @escaping (String) -> Void) {
        #if !os(tvOS)
        guard let data = cert.data else { onError("Public certificate data is missing."); return }
        UIPasteboard.general.string = String(data: data, encoding: .utf8) ?? data.base64EncodedString()
        #endif
    }
    
    static func shareP12(_ cert: ALTCertificate, password: String, onError: @escaping (String) -> Void) {
        do {
            let p12Data = try cert.encryptedP12Data(password: password)
            share(data: p12Data, filename: (cert.machineName ?? cert.name) + ".p12", onError: onError)
        } catch {
            debugLog("[CertificateExporter] Failed to build encrypted p12 data: \(error)")
            onError("Failed to build encrypted p12 data: \(error.localizedDescription)")
        }
    }
    
    static func sharePrivateKeyAsPEM(_ cert: ALTCertificate, onError: @escaping (String) -> Void) {
        let keyData = cert.privateKey
        share(data: keyData, filename: (cert.machineName ?? cert.name) + "_key.pem", onError: onError)
    }
    
    static func sharePrivateKeyAsDER(_ cert: ALTCertificate, onError: @escaping (String) -> Void) {
        let keyData = cert.privateKey
        share(data: getDERData(from: keyData) ?? keyData, filename: (cert.machineName ?? cert.name) + "_key.der", onError: onError)
    }
    
    static func copyPrivateKey(_ cert: ALTCertificate) {
        #if !os(tvOS)
        let keyData = cert.privateKey
        UIPasteboard.general.string = String(data: keyData, encoding: .utf8) ?? keyData.base64EncodedString()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
    
    private static func share(data: Data, filename: String, onError: @escaping (String) -> Void) {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: tempURL)
        } catch {
            onError("Failed to write temp export file: " + error.localizedDescription)
            return
        }
        guard let rootVC = UIApplication.shared.topViewController() else { return }
        #if !os(tvOS)
        rootVC.presentShareSheet(for: [tempURL])
        #else
        TVWebFileTransferManager.shared.startExport(fileURL: tempURL, title: "Export Certificate / Key", presentingVC: rootVC)
        #endif
    }
}
