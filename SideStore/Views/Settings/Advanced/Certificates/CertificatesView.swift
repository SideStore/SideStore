//
//  CertificatesView.swift
//  SideStore
//
//  Created by Magesh K on 2026-06-29.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import SideSign
import UniformTypeIdentifiers

struct CertificatesView: View {
    weak var presentingViewController: UIViewController?
    
    @StateObject private var viewModel = CertificatesViewModel()
    
    private var allowedImportTypes: [UTType] {
        ["p12", "pfx", "pkcs12", "der", "cer", "crt", "pem"].compactMap { UTType(filenameExtension: $0) }
    }
    private var allowedKeyImportTypes: [UTType] {
        ["key", "pem", "der"].compactMap { UTType(filenameExtension: $0) }
    }
    
    @State private var showCreateSheet            = false
    @State private var showFileImporter           = false
    @State private var showRevokeConfirmation     = false
    @State private var showDeactivateConfirmation = false
    @State private var showDeleteConfirmation     = false
    @State private var showExportPasswordPrompt   = false
    @State private var showClearKeyConfirmation   = false
    @State private var hasInitialLoaded           = false
    @State private var hasCopiedActiveSerial      = false
    
    @State private var exportPasswordInput   = ""
    @State private var fileImportMode: FileImportMode       = .certificate
    @State private var keyTextImportItem: KeyTextImportItem? = nil
    @State private var privateKeyTextInput   = ""
    
    @State private var deleteLocalOnRevoke: Bool = true
    
    @State private var certificateToRevoke:      ALTX509Certificate? = nil
    @State private var certificateToDelete:      ALTX509Certificate? = nil
    @State private var certificateToExport:      ALTX509Certificate? = nil
    @State private var certificateToAddKeyFor:   ALTX509Certificate? = nil
    @State private var certificateToClearKeyFor: ALTX509Certificate? = nil
    
    var body: some View {
        ZStack {
            List {
                ActiveCertSectionView(
                    viewModel: viewModel,
                    hasCopiedActiveSerial: $hasCopiedActiveSerial,
                    onDeactivate: { showDeactivateConfirmation = true }
                )
                CertificatesListView(
                    viewModel: viewModel,
                    onRowTap:     { pushDetailView(for: $0) },
                    onRevoke:     { presentRevokeAlert(for: $0) },
                    onExportP12:  { cert in
                        certificateToExport = cert
                        exportPasswordInput = ""
                        showExportPasswordPrompt = true
                    },
                    onClearKey:   { cert in
                        certificateToClearKeyFor = cert
                        showClearKeyConfirmation = true
                    },
                    onAddKeyBin:  { cert in
                        importPrivateKeyAction(for: cert)
                    },
                    onAddKeyText: { cert in
                        keyTextImportItem = KeyTextImportItem(id: cert.serialNumber, cert: cert)
                    },
                    onDelete: { certificateToDelete = $0; showDeleteConfirmation = true }
                )
            }
            .refreshable {
                await withCheckedContinuation { continuation in
                    viewModel.loadCertificates(presentingViewController: presentingViewController, isPullToRefresh: true) {
                        continuation.resume()
                    }
                }
            }
            .navigationTitle("Certificates")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    SwiftUI.Button {
                        viewModel.isGlobalHideActive.toggle()
                    } label: {
                        Image(systemName: viewModel.isGlobalHideActive ? "eye.slash" : "eye")
                    }
                    .accessibilityLabel("Toggle Hide Sensitive Information")
                    
                    SwiftUI.Button {
                        showCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Create Certificate")
                    .disabled(viewModel.team == nil)
                    
                    SwiftUI.Button {
                        importCertificatesAction()
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .accessibilityLabel("Import Certificates")
                }
            }
            .onAppear {
                guard !hasInitialLoaded else { return }
                hasInitialLoaded = true
                viewModel.loadCertificates(presentingViewController: nil)
            }
            
            if viewModel.isLoading { LoadingOverlay() }
        }
        .alert("Error", isPresented: $viewModel.showErrorAlert) {
            SwiftUI.Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "An unknown error occurred.")
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateCertificateSheetView(
                viewModel: viewModel,
                presentingViewController: presentingViewController,
                isPresented: $showCreateSheet
            )
        }
        .alert("Deactivate Certificate", isPresented: $showDeactivateConfirmation) {
            SwiftUI.Button("Deactivate", role: .destructive) { viewModel.deactivateActiveCertificate() }
            SwiftUI.Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to deactivate the active signing certificate locally?")
        }
        .alert("Delete Certificate", isPresented: $showDeleteConfirmation) {
            SwiftUI.Button("Delete", role: .destructive) {
                if let cert = certificateToDelete { viewModel.deleteCertificate(cert) }
            }
            SwiftUI.Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this certificate locally? This will remove it from the cached local store.")
        }
        .alert("Import Certificate Password", isPresented: $viewModel.showPasswordPromptForImport) {
            SecureField("Password", text: $viewModel.importPasswordInput)
            SwiftUI.Button("Import") { viewModel.submitImportPassword() }
            SwiftUI.Button("Cancel", role: .cancel) { viewModel.cancelImport() }
        } message: {
            Text(String(format: NSLocalizedString("Enter the password to decrypt the imported certificate file.\n\nFile: %@", comment: ""), viewModel.currentImportFilename))
        }
        .alert("Success", isPresented: $viewModel.showAlert) {
            SwiftUI.Button("OK", role: .cancel) { viewModel.alertMessage = nil }
        } message: {
            Text(viewModel.alertMessage ?? "")
        }
        .alert("Import Summary", isPresented: $viewModel.showImportSummary) {
            if viewModel.importFailedCount > 0 {
                SwiftUI.Button("Show Failed") {
                    DispatchQueue.main.async {
                        viewModel.showFailuresAlert = true
                    }
                }
                SwiftUI.Button("OK", role: .cancel) {}
            } else {
                SwiftUI.Button("OK", role: .cancel) {}
            }
        } message: {
            Text(viewModel.importSummaryMessage)
        }
        .sheet(isPresented: $viewModel.showFailuresAlert) {
            NavigationView {
                List {
                    ForEach(viewModel.failedImportsList, id: \.self) { failure in
                        Text(failure)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.red)
                    }
                }
                .navigationTitle("Import Failures")
                #if !os(tvOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        SwiftUI.Button("Done") {
                            viewModel.showFailuresAlert = false
                        }
                    }
                }
            }
        }
        .alert("Export Certificate Password", isPresented: $showExportPasswordPrompt) {
            SecureField("Password", text: $exportPasswordInput)
            SwiftUI.Button("Export") {
                if let cert = certificateToExport, let signable = viewModel.getSignableCertificate(for: cert.serialNumber) {
                    CertificateExporter.shareP12(signable, password: exportPasswordInput) { viewModel.errorMessage = $0 }
                }
            }
            SwiftUI.Button("Cancel", role: .cancel) {}
        } message: {
            Text("Set a password to encrypt the exported .p12 certificate file.")
        }
        .alert("Clear Private Key", isPresented: $showClearKeyConfirmation) {
            if let cert = certificateToClearKeyFor {
                SwiftUI.Button("Clear Key", role: .destructive) {
                    viewModel.clearPrivateKey(for: cert)
                    certificateToClearKeyFor = nil
                }
            }
            SwiftUI.Button("Cancel", role: .cancel) { certificateToClearKeyFor = nil }
        } message: {
            if let cert = certificateToClearKeyFor {
                Text(String(format: NSLocalizedString("This will clear the locally stored private key of this certificate.\n\nName: %@\nS/N: %@", comment: ""), cert.name, cert.serialNumber))
            }
        }
        #if !os(tvOS)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: fileImportMode == .certificate ? allowedImportTypes : allowedKeyImportTypes,
            allowsMultipleSelection: fileImportMode == .certificate
        ) { result in
            switch result {
            case .success(let urls):
                switch fileImportMode {
                case .certificate:
                    viewModel.startBulkImport(urls: urls)
                case .privateKey:
                    if let url = urls.first, let cert = certificateToAddKeyFor {
                        _ = url.startAccessingSecurityScopedResource()
                        defer { url.stopAccessingSecurityScopedResource() }
                        do {
                            viewModel.importPrivateKey(data: try Data(contentsOf: url), for: cert)
                        } catch {
                            viewModel.errorMessage = "Failed to read private key: " + error.localizedDescription
                        }
                    }
                }
            case .failure(let error):
                let type = fileImportMode == .certificate ? "files" : "private key"
                viewModel.errorMessage = "Failed to select \(type): " + error.localizedDescription
            }
        }
        #endif
        .sheet(item: $keyTextImportItem) { item in
            PrivateKeyTextInputView(
                text: $privateKeyTextInput,
                cert: item.cert,
                viewModel: viewModel,
                allowedKeyImportTypes: allowedKeyImportTypes,
                onCancel: {
                    keyTextImportItem = nil
                    privateKeyTextInput = ""
                }
            )
        }
    }
    
    private func pushDetailView(for cert: ALTX509Certificate) {
        let metadata = DeveloperPortalMetadata(
            identifier: cert.identifier,
            machineName: cert.machineName,
            machineIdentifier: cert.machineIdentifier,
            requesterEmail: cert.requesterEmail
        )
        let detailVC = UIHostingController(rootView: CertificateDetailView(certificate: cert, portalMetadata: metadata, viewModel: viewModel))
        #if !os(tvOS)
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        detailVC.navigationItem.scrollEdgeAppearance = appearance
        detailVC.navigationItem.standardAppearance   = appearance
        #endif
        presentingViewController?.navigationController?.pushViewController(detailVC, animated: true)
    }
    
    private func presentRevokeAlert(for cert: ALTX509Certificate) {
        let contentVC = RevokeAlertViewController()
        
        let alertController = UIAlertController(
            title: NSLocalizedString("Revoke Certificate", comment: ""),
            message: NSLocalizedString("Are you sure you want to revoke this certificate? This will permanently delete the certificate on Apple's servers.", comment: ""),
            preferredStyle: .alert
        )
        
        alertController.setValue(contentVC, forKey: "contentViewController")
        
        let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil)
        let revokeAction = UIAlertAction(title: NSLocalizedString("Revoke", comment: ""), style: .destructive) { _ in
            let keepLocal = contentVC.isKeepLocalChecked
            viewModel.revokeCertificate(cert, keepLocal: keepLocal, presentingViewController: presentingViewController)
        }
        
        alertController.addAction(cancelAction)
        alertController.addAction(revokeAction)
        
        presentingViewController?.present(alertController, animated: true)
    }
    
    private func importPrivateKeyAction(for cert: ALTX509Certificate) {
        certificateToAddKeyFor = cert
        fileImportMode = .privateKey
        #if !os(tvOS)
        showFileImporter = true
        #else
        guard let topVC = presentingViewController ?? UIApplication.shared.topViewController() else { return }
        TVWebFileTransferManager.shared.startImport(
            acceptedExtensions: ["der", "key", "pem", "p12"],
            title: "Import Private Key (.der/.pem)",
            presentingVC: topVC
        ) { fileURL in
            guard let fileURL = fileURL else { return }
            do {
                let data = try Data(contentsOf: fileURL)
                viewModel.importPrivateKey(data: data, for: cert)
            } catch {
                viewModel.errorMessage = "Failed to read private key: " + error.localizedDescription
            }
            certificateToAddKeyFor = nil
        }
        #endif
    }
    
    private func importCertificatesAction() {
        fileImportMode = .certificate
        #if !os(tvOS)
        showFileImporter = true
        #else
        guard let topVC = presentingViewController ?? UIApplication.shared.topViewController() else { return }
        TVWebFileTransferManager.shared.startImport(
            acceptedExtensions: ["p12", "der", "pem", "cer", "crt"],
            title: "Import Certificates",
            presentingVC: topVC
        ) { fileURL in
            guard let fileURL = fileURL else { return }
            viewModel.startBulkImport(urls: [fileURL])
        }
        #endif
    }
}

private struct LoadingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.2).ignoresSafeArea()
            ProgressView()
                .padding(20)
                #if !os(tvOS)
                .background(Color(.secondarySystemBackground))
                #else
                .background(Color.white.opacity(0.1))
                #endif
                .cornerRadius(10)
        }
    }
}

private struct CreateCertificateSheetView: View {
    @ObservedObject var viewModel: CertificatesViewModel
    var presentingViewController: UIViewController?
    @Binding var isPresented: Bool

    @State private var machineName: String = "SideStore - \(UIDevice.current.name)"
    @State private var selectedCertificateType: CertificateType = .development

    private var isPaidWarningVisible: Bool {
        selectedCertificateType.isPaidOnly && !viewModel.isPaidAccount
    }

    private var canCreate: Bool {
        !machineName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationView {
            Form {
                Section(
                    header: Text("Certificate Information"),
                    footer: Text(isPaidWarningVisible
                        ? "This certificate type requires a paid Apple Developer account."
                        : "Select the certificate type and machine name. This registers the certificate on Apple's servers and saves the private key locally.")
                ) {
                    Picker("Certificate Type", selection: $selectedCertificateType) {
                        ForEach(viewModel.availableCertificateTypes, id: \.rawValue) { certType in
                            Text(certType.displayName).tag(certType)
                        }
                    }

                    TextField("Machine Name", text: $machineName)
                }
            }
            .navigationTitle("New Certificate")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    SwiftUI.Button("Cancel") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    SwiftUI.Button("Create") {
                        let name = machineName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else { return }
                        isPresented = false
                        viewModel.createCertificate(
                            machineName: name,
                            type: selectedCertificateType,
                            presentingViewController: presentingViewController
                        )
                    }
                    .disabled(!canCreate)
                }
            }
        }
    }
}
