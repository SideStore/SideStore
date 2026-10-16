//
//  PairingFileDetailView.swift
//  SideStore
//
//  Created by Magesh K on 20/09/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import MinimuxerCommon
import CryptoKit

private extension Color {
    static let settingsRowBackground = Color.white.opacity(0.15)
    static let settingsDivider = Color.white.opacity(0.15)
}

struct PairingFileDetailView: View {
    let mode: PairingProtocol
    
    @State private var rawContent: String
    @State private var isEditing = false
    @State private var editedContent = ""
    @State private var showingInvalidPlistAlert = false
    @State private var invalidPlistMessage = ""
    @State private var hasCopiedContent = false

    init(mode: PairingProtocol) {
        self.mode = mode
        let content = PairingFileManager.shared.fetchPairingFile(for: mode) ?? ""
        _rawContent = State(initialValue: content)
        _editedContent = State(initialValue: content)
    }

    private var fileURL: URL {
        PairingFileManager.shared.pairingFileURL(for: mode)
    }

    private var fileName: String {
        fileURL.lastPathComponent
    }

    private var fileMetadata: PairingFileMetadata {
        PairingFileManager.shared.metadata(for: mode)
    }

    private var isInstalled: Bool {
        fileMetadata.exists && !rawContent.isEmpty
    }

    private var fileSize: Int64 {
        fileMetadata.size
    }

    private var creationDate: Date? {
        fileMetadata.creationDate
    }

    private var modificationDate: Date? {
        fileMetadata.modificationDate
    }

    private var currentSHA256: String {
        let data = Data(rawContent.utf8)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private var titleText: String {
        switch mode {
        case .rppairing:
            return "Remote Pairing File"
        case .lockdown:
            return "Lockdown Pairing File"
        case .unknown:
            return "Pairing File"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                fileInfoSection
                xmlContentSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .background(Color(uiColor: .settingsBackground).ignoresSafeArea())
        .navigationTitle(titleText)
        #if !os(tvOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if isEditing {
                    SwiftUI.Button("Cancel") {
                        editedContent = rawContent
                        isEditing = false
                    }
                    SwiftUI.Button("Save") {
                        saveEditedContent()
                    }
                    .font(.system(size: 17, weight: .bold))
                } else {
                    if !rawContent.isEmpty {
                        SwiftUI.Button {
                            UIPasteboard.general.string = rawContent
                            hasCopiedContent = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                hasCopiedContent = false
                            }
                        } label: {
                            Image(systemName: hasCopiedContent ? "checkmark" : "doc.on.doc")
                        }
                        .accessibilityLabel("Copy XML")

                        SwiftUI.Button("Edit") {
                            requestEnterEditMode()
                        }
                    }
                }
            }
        }
        .alert("Invalid Property List", isPresented: $showingInvalidPlistAlert) {
            SwiftUI.Button("OK", role: .cancel) { }
        } message: {
            Text(invalidPlistMessage)
        }
    }

    private var fileInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FILE INFORMATION")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.6))
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                metadataRow(label: "File Name", value: fileName)
                divider
                metadataRow(label: "Protocol Type", value: mode == .rppairing ? "RPPairing (Tunnel)" : "Lockdown")
                divider
                metadataRow(label: "Status", value: isInstalled ? "Installed" : "Not Found", valueColor: isInstalled ? .green : .red)
                if isInstalled {
                    divider
                    metadataRow(label: "File Size", value: ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))
                    if let created = creationDate {
                        divider
                        metadataRow(label: "Date Created", value: formatDate(created))
                    }
                    if let modified = modificationDate {
                        divider
                        metadataRow(label: "Date Modified", value: formatDate(modified))
                    }
                }
            }
            .background(Color.settingsRowBackground)
            .cornerRadius(14)
        }
    }

    private var xmlContentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(isEditing ? "EDIT RAW XML" : "RAW XML CONTENT")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.6))
                Spacer()
                let displayed = isEditing ? editedContent : rawContent
                if !displayed.isEmpty {
                    Text("\(displayed.count) bytes")
                        .font(.system(size: 12))
                        .foregroundColor(Color.white.opacity(0.4))
                }
            }
            .padding(.horizontal, 4)

            if isEditing {
                TextEditor(text: $editedContent)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundColor(.white)
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(12)
                    .frame(minHeight: 380)
            } else if !rawContent.isEmpty {
                ScrollView([.horizontal, .vertical]) {
                    Text(rawContent)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.9))
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color.black.opacity(0.3))
                .cornerRadius(12)
                .frame(minHeight: 300, maxHeight: 500)
            } else {
                Text("No pairing file installed.")
                    .font(.system(size: 14))
                    .foregroundColor(Color.white.opacity(0.5))
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .background(Color.settingsRowBackground)
                    .cornerRadius(14)
            }
        }
    }

    private func metadataRow(label: String, value: String, valueColor: Color = .white) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 15))
                .foregroundColor(Color.white.opacity(0.7))
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(valueColor)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.settingsDivider)
            .frame(height: 1)
            .padding(.leading, 16)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func requestEnterEditMode() {
        guard !rawContent.isEmpty else { return }
        let currentHash = currentSHA256
        if UserDefaults.standard.isPairingFileEditSuppressed(forHash: currentHash) {
            editedContent = rawContent
            isEditing = true
            return
        }

        guard let topVC = UIApplication.shared.topViewController() else {
            editedContent = rawContent
            isEditing = true
            return
        }

        let alert = UIAlertController(
            title: NSLocalizedString("Warning", comment: ""),
            message: NSLocalizedString("Editing manually may corrupt the pairing file. Are you sure you know what you are doing and want to continue?", comment: ""),
            preferredStyle: .alert
        )
        let contentVC = PairingFileEditAlertViewController()
        alert.setValue(contentVC, forKey: "contentViewController")

        let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil)
        let continueAction = UIAlertAction(title: NSLocalizedString("Continue", comment: ""), style: .destructive) { _ in
            if contentVC.isChecked {
                UserDefaults.standard.setPairingFileEditSuppressed(true, forHash: currentHash)
            }
            editedContent = rawContent
            isEditing = true
        }

        alert.addAction(cancelAction)
        alert.addAction(continueAction)
        topVC.present(alert, animated: true)
    }

    private func saveEditedContent() {
        guard let data = editedContent.data(using: .utf8) else {
            invalidPlistMessage = "Could not encode text as UTF-8."
            showingInvalidPlistAlert = true
            return
        }

        do {
            _ = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            invalidPlistMessage = "The property list contains syntax errors: \(error.localizedDescription)"
            showingInvalidPlistAlert = true
            return
        }

        do {
            try PairingFileManager.shared.savePairingFile(contents: editedContent, preferred: mode)
            rawContent = editedContent
            UserDefaults.standard.setPairingFileEditSuppressed(true, forHash: currentSHA256)
            isEditing = false
        } catch {
            invalidPlistMessage = "Failed to save pairing file: \(error.localizedDescription)"
            showingInvalidPlistAlert = true
        }
    }
}
