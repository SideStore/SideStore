//
//  FileImportHandler.swift
//  SideStore
//
//  Created by Magesh K on 20/09/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import UIKit
import MinimuxerCommon

@MainActor
public final class FileImportHandler {
    public static let shared = FileImportHandler()

    private var pendingImportIPAURL: URL?

    private init() {
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.flushPendingImport()
        }
    }

    private func flushPendingImport() {
        guard let url = pendingImportIPAURL else { return }
        pendingImportIPAURL = nil
        NotificationCenter.default.post(
            name: AppDelegate.importAppDeepLinkNotification,
            object: nil,
            userInfo: [AppDelegate.importAppDeepLinkURLKey: url]
        )
    }

    @discardableResult
    public func handle(fileURL: URL) -> Bool {
        debugLog("[FileImportHandler] handle(fileURL:) called with URL: \(fileURL)")

        let isSecured = fileURL.startAccessingSecurityScopedResource()
        defer {
            if isSecured {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        let ext = fileURL.pathExtension.lowercased()
        if ext == "ipa" {
            return handleIPAImport(fileURL: fileURL)
        } else if AppConstants.Pairing.supportedExtensions.contains(ext) {
            return handlePairingFileImport(fileURL: fileURL)
        }

        debugLog("[FileImportHandler] Unsupported file extension: \(ext)")
        return false
    }

    private func handleIPAImport(fileURL: URL) -> Bool {
        let temporaryDirectory = FileManager.default.uniqueTemporaryURL()
        do {
            try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            debugLog("[FileImportHandler] Failed to create temp directory for imported IPA: \(error)")
            return false
        }

        let ipa = temporaryDirectory.appendingPathComponent(fileURL.lastPathComponent)
        do {
            try FileManager.default.copyItem(at: fileURL, to: ipa)
        } catch {
            debugLog("[FileImportHandler] Failed to copy imported IPA: \(error)")
            return false
        }

        if UIApplication.shared.applicationState == .active {
            NotificationCenter.default.post(
                name: AppDelegate.importAppDeepLinkNotification,
                object: nil,
                userInfo: [AppDelegate.importAppDeepLinkURLKey: ipa]
            )
        } else {
            self.pendingImportIPAURL = ipa
        }
        return true
    }

    private func handlePairingFileImport(fileURL: URL) -> Bool {
        do {
            try PairingFileManager.shared.importPairingFile(from: fileURL)
            debugLog("[FileImportHandler] Successfully saved imported pairing file")
            if let topVC = UIApplication.shared.topViewController() {
                let toast = ToastView(text: NSLocalizedString("Pairing File Imported Successfully!", comment: ""), detailText: nil)
                toast.show(in: topVC)
            }
            return true
        } catch {
            debugLog("[FileImportHandler] Failed to save imported pairing file: \(error)")
            if let topVC = UIApplication.shared.topViewController() {
                let toast = ToastView(text: NSLocalizedString("Failed to save Pairing File", comment: ""), detailText: nil)
                toast.show(in: topVC)
            }
            return false
        }
    }
}
