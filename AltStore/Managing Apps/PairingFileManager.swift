//
//  PairingFileManager.swift
//  AltStore
//
//  Created by Magesh K on 17/06/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import UIKit
import AltStoreCore
import UniformTypeIdentifiers
import Minimuxer

@MainActor
final class PairingFileManager: NSObject, UIDocumentPickerDelegate {
    static let shared = PairingFileManager()
    static let pairingFileName = "ALTPairingFile.mobiledevicepairing"

    private var completion: ((URL?) -> Void)?

    func loadStoredPairingFile() throws -> String {
        let fm = FileManager.default
        let documentsPath = fm.documentsDirectory.appendingPathComponent(Self.pairingFileName)
        if fm.fileExists(atPath: documentsPath.path),
           let contents = try? String(contentsOf: documentsPath), !contents.isEmpty {
            return contents
        }

        if let url = Bundle.main.url(forResource: "ALTPairingFile", withExtension: "mobiledevicepairing"),
           fm.fileExists(atPath: url.path),
           let data = fm.contents(atPath: url.path),
           let contents = String(data: data, encoding: .utf8),
           !contents.isEmpty, !UserDefaults.standard.isPairingReset {
            return contents
        }

        if let plistString = Bundle.main.object(forInfoDictionaryKey: "ALTPairingFile") as? String,
           !plistString.isEmpty,
           !plistString.contains("insert pairing file here"),
           !UserDefaults.standard.isPairingReset {
            return plistString
        }

        throw MinimuxerError.PairingFile
    }

    func fetchPairingFile(presentingVC: UIViewController) -> String? {
        if let pairingFile = try? self.loadStoredPairingFile() {
            return pairingFile
        }

        presentPairingFileAlert(
            on: presentingVC,
            title: NSLocalizedString("Pairing File", comment: ""),
            message: NSLocalizedString("Select the pairing file or select \"Help\" for help.", comment: "")
        )
        return nil
    }

    func presentPairingFileAlert(on vc: UIViewController, title: String, message: String, completion: ((URL?) -> Void)? = nil) {
        self.completion = { url in
            completion?(url)
            self.completion = nil
        }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("Help", comment: ""), style: .default) { _ in
            if let url = URL(string: "https://docs.sidestore.io/docs/advanced/pairing-file") { UIApplication.shared.open(url) }
            if completion == nil {
                sleep(2); exit(0)
            } else {
                completion?(nil)
            }
        })
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default) { _ in
            var types = UTType.types(tag: "plist", tagClass: .filenameExtension, conformingTo: nil)
            types.append(contentsOf: UTType.types(tag: "mobiledevicepairing", tagClass: .filenameExtension, conformingTo: .data))
            types.append(.xml)
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: types)
            picker.delegate = self
            picker.shouldShowFileExtensions = true
            vc.present(picker, animated: true)
            UserDefaults.standard.isPairingReset = false
        })
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel) { _ in
            completion?(nil)
        })
        vc.present(alert, animated: true)
    }

    func importPairingFile(presentingVC: UIViewController, title: String, message: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            presentPairingFileAlert(on: presentingVC, title: title, message: message) { url in
                if let url = url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: MinimuxerError.PairingFile)
                }
            }
        }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let url = urls[0]
        let isSecuredURL = url.startAccessingSecurityScopedResource() == true
        defer {
            if (isSecuredURL) {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            guard let pairingString = String(data: data, encoding: .utf8) else {
                if completion == nil {
                    if let rootVC = UIApplication.shared.windows.first?.rootViewController as? LaunchViewController {
                        rootVC.displayError("Unable to read pairing file")
                    }
                } else {
                    completion?(nil)
                }
                return
            }
            let fm = FileManager.default
            let documentsPath = fm.documentsDirectory.appendingPathComponent(Self.pairingFileName)
            if fm.fileExists(atPath: documentsPath.path) {
                try? fm.removeItem(at: documentsPath)
            }
            try pairingString.write(to: documentsPath, atomically: true, encoding: .utf8)
            UserDefaults.standard.isPairingReset = false
            
            if completion == nil {
                if let rootVC = UIApplication.shared.windows.first?.rootViewController as? LaunchViewController {
                    rootVC.start_minimuxer_threads(pairingString)
                }
            } else {
                completion?(url)
            }
        } catch {
            if completion == nil {
                if let rootVC = UIApplication.shared.windows.first?.rootViewController as? LaunchViewController {
                    rootVC.displayError("Unable to read pairing file")
                }
            } else {
                completion?(nil)
            }
        }
        
        controller.dismiss(animated: true, completion: nil)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        if completion == nil {
            if let rootVC = UIApplication.shared.windows.first?.rootViewController as? LaunchViewController {
                rootVC.displayError("Choosing a pairing file was cancelled. Please re-open the app and try again.")
            }
        } else {
            completion?(nil)
        }
    }
}
