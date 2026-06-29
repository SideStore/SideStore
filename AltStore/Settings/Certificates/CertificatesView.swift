//
//  CertificatesView.swift
//  AltStore
//
//  Created by Magesh K on 2026-06-29.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import AltSign
import UniformTypeIdentifiers

struct CertificatesView: View {
    weak var presentingViewController: UIViewController?
    
    private var allowedImportTypes: [UTType] {
        let extensions = ["p12", "pfx", "pkcs12", "der", "cer", "crt", "pem"]
        return extensions.compactMap { UTType(filenameExtension: $0) }
    }
    
    @StateObject private var viewModel = CertificatesViewModel()
    
    @State private var showCreateDialog = false
    @State private var showFileImporter = false
    @State private var showPasswordInputForImport = false
    @State private var showRevokeConfirmation = false
    @State private var showDeactivateConfirmation = false
    @State private var showDeleteConfirmation = false
    @State private var showExportPasswordPrompt = false
    @State private var hasInitialLoaded = false
    
    @State private var newMachineName = ""
    @State private var exportPasswordInput = ""
    @State private var certificateToExport: ALTCertificate? = nil
    @State private var certificateToRevoke: ALTCertificate? = nil
    @State private var certificateToDelete: ALTCertificate? = nil
    
    private var privateCerts: [ALTCertificate] {
        viewModel.certificates
            .filter { $0.privateKey != nil }
            .sorted(by: { $0.creationDate > $1.creationDate })
    }
    
    private var publicCerts: [ALTCertificate] {
        viewModel.certificates
            .filter { $0.privateKey == nil }
            .sorted(by: { $0.creationDate > $1.creationDate })
    }
    
    @ViewBuilder
    private var activeLocalCertificateSection: some View {
        Section("Active Local Certificate") {
            if let activeSerial = viewModel.activeSerialNumber {
                HStack {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                        .font(.title2)
                    
                    VStack(alignment: .leading) {
                        Text("Active Signing Certificate")
                            .font(.headline)
                        Text("SN: " + activeSerial)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
                
                HStack {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title2)
                        .opacity(0)
                    
                    SwiftUI.Button(role: .destructive) {
                        showDeactivateConfirmation = true
                    } label: {
                        Text("Deactivate Locally")
                            .fontWeight(.medium)
                    }
                }
            } else {
                if viewModel.team == nil {
                    Text("No active local certificate found. Import a .p12 file to sign your apps.")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                } else {
                    Text("No active local certificate found. Create a new certificate or import a .p12 file to sign your apps.")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                }
            }
        }
    }
    
    @ViewBuilder
    private var certificatesListSections: some View {
        if viewModel.certificates.isEmpty {
            Section(header: Text("Certificates")) {
                if viewModel.isLoading {
                    Text("Fetching certificates...")
                        .foregroundColor(.secondary)
                } else {
                    if viewModel.team == nil {
                        Text("No local certificates found (not signed in).")
                            .foregroundColor(.secondary)
                    } else {
                        Text("No certificates found.")
                            .foregroundColor(.secondary)
                    }
                }
            }
        } else {
            if !privateCerts.isEmpty {
                Section {
                    ForEach(privateCerts, id: \.serialNumber) { cert in
                        SwiftUI.Button {
                            pushDetailView(for: cert)
                        } label: {
                            certificateRow(cert: cert, hasPrivateKey: true)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Private Certificates")
                } footer: {
                    if publicCerts.isEmpty {
                        Text("Suffix (R) indicates the certificate is registered remotely on Apple's developer portal.")
                    }
                }
            }
            
            if !publicCerts.isEmpty {
                Section {
                    ForEach(publicCerts, id: \.serialNumber) { cert in
                        SwiftUI.Button {
                            pushDetailView(for: cert)
                        } label: {
                            certificateRow(cert: cert, hasPrivateKey: false)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Public Certificates")
                } footer: {
                    Text("Suffix (R) indicates the certificate is registered remotely on Apple's developer portal.")
                }
            }
        }
    }

    var body: some View {
        ZStack {
            List {
                activeLocalCertificateSection
                certificatesListSections
            }
            .refreshable {
                await withCheckedContinuation { continuation in
                    viewModel.loadCertificates(presentingViewController: presentingViewController) {
                        continuation.resume()
                    }
                }
            }
            .navigationTitle("Certificates")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    SwiftUI.Button {
                        self.newMachineName = "SideStore - \(UIDevice.current.name)"
                        self.showCreateDialog = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Create Certificate")
                    .disabled(viewModel.team == nil)
                    
                    SwiftUI.Button {
                        self.showFileImporter = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .accessibilityLabel("Import Certificates")
                }
            }
            .onAppear {
                if !hasInitialLoaded {
                    hasInitialLoaded = true
                    viewModel.loadCertificates(presentingViewController: nil)
                }
            }
            
            if viewModel.isLoading {
                ZStack {
                    Color.black.opacity(0.2)
                        .ignoresSafeArea()
                    ProgressView()
                        .padding(20)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)
                }
            }
        }
        .alert("Error", isPresented: $viewModel.showErrorAlert) {
            SwiftUI.Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "An unknown error occurred.")
        }
        .alert("New Certificate", isPresented: $showCreateDialog) {
            TextField("Machine Name", text: $newMachineName)
            SwiftUI.Button("Create") {
                viewModel.createCertificate(machineName: newMachineName, presentingViewController: presentingViewController)
            }
            SwiftUI.Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a name for the new certificate. This will create a new certificate on Apple's servers and store the private key locally.")
        }
        .alert("Revoke Certificate", isPresented: $showRevokeConfirmation) {
            SwiftUI.Button("Revoke", role: .destructive) {
                if let cert = certificateToRevoke {
                    viewModel.revokeCertificate(cert)
                }
            }
            SwiftUI.Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to revoke this certificate? This will permanently delete the certificate on Apple's servers and delete it locally.")
        }
        .alert("Deactivate Certificate", isPresented: $showDeactivateConfirmation) {
            SwiftUI.Button("Deactivate", role: .destructive) {
                viewModel.deactivateActiveCertificate()
            }
            SwiftUI.Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to deactivate the active signing certificate locally?")
        }
        .alert("Delete Certificate", isPresented: $showDeleteConfirmation) {
            SwiftUI.Button("Delete", role: .destructive) {
                if let cert = certificateToDelete {
                    viewModel.deleteCertificate(cert)
                }
            }
            SwiftUI.Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this certificate locally? This will remove it from the cached local store.")
        }
        .alert("Import Certificate Password", isPresented: $viewModel.showPasswordPromptForImport) {
            SecureField("Password", text: $viewModel.importPasswordInput)
            SwiftUI.Button("Import") {
                viewModel.submitImportPassword()
            }
            SwiftUI.Button("Cancel", role: .cancel) {
                viewModel.cancelImport()
            }
        } message: {
            Text("Enter the password to decrypt the imported .p12 certificate file.")
        }
        .alert("Success", isPresented: $viewModel.showAlert) {
            SwiftUI.Button("OK", role: .cancel) {
                viewModel.alertMessage = nil
            }
        } message: {
            Text(viewModel.alertMessage ?? "")
        }
        .alert("Export Certificate Password", isPresented: $showExportPasswordPrompt) {
            SecureField("Password", text: $exportPasswordInput)
            SwiftUI.Button("Export") {
                if let cert = certificateToExport {
                    exportCertificate(cert, password: exportPasswordInput)
                }
            }
            SwiftUI.Button("Cancel", role: .cancel) {}
        } message: {
            Text("Set a password to encrypt the exported .p12 certificate file.")
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: allowedImportTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                viewModel.startBulkImport(urls: urls)
            case .failure(let error):
                viewModel.errorMessage = "Failed to select files: " + error.localizedDescription
            }
        }
    }
    
    private func exportCertificate(_ cert: ALTCertificate, password: String) {
        guard let p12Data = cert.encryptedP12Data(password: password) else {
            viewModel.errorMessage = "Failed to export certificate."
            return
        }
        
        let filename = (cert.machineName ?? cert.name) + ".p12"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        
        do {
            try p12Data.write(to: tempURL)
            
            let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
            
            if let rootVC = UIApplication.shared.windows.first?.rootViewController {
                let presenter = rootVC.presentedViewController ?? rootVC
                if let popover = activityVC.popoverPresentationController {
                    popover.sourceView = presenter.view
                    popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
                    popover.permittedArrowDirections = []
                }
                presenter.present(activityVC, animated: true, completion: nil)
            }
        } catch {
            viewModel.errorMessage = "Failed to write temp export file: " + error.localizedDescription
        }
    }
    
    private func exportPublicCertificateAsDER(_ cert: ALTCertificate) {
        guard let data = cert.data else {
            viewModel.errorMessage = "Public certificate data is missing."
            return
        }
        
        let filename = (cert.machineName ?? cert.name) + ".der"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        
        do {
            let derData = getDERData(from: data) ?? data
            try derData.write(to: tempURL)
            
            let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
            
            if let rootVC = UIApplication.shared.windows.first?.rootViewController {
                let presenter = rootVC.presentedViewController ?? rootVC
                if let popover = activityVC.popoverPresentationController {
                    popover.sourceView = presenter.view
                    popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
                    popover.permittedArrowDirections = []
                }
                presenter.present(activityVC, animated: true, completion: nil)
            }
        } catch {
            viewModel.errorMessage = "Failed to write temp export file: " + error.localizedDescription
        }
    }
    
    private func exportPublicCertificateAsPEM(_ cert: ALTCertificate) {
        guard let data = cert.data else {
            viewModel.errorMessage = "Public certificate data is missing."
            return
        }
        
        let filename = (cert.machineName ?? cert.name) + ".pem"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        
        do {
            try data.write(to: tempURL)
            
            let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
            
            if let rootVC = UIApplication.shared.windows.first?.rootViewController {
                let presenter = rootVC.presentedViewController ?? rootVC
                if let popover = activityVC.popoverPresentationController {
                    popover.sourceView = presenter.view
                    popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
                    popover.permittedArrowDirections = []
                }
                presenter.present(activityVC, animated: true, completion: nil)
            }
        } catch {
            viewModel.errorMessage = "Failed to write temp export file: " + error.localizedDescription
        }
    }
    
    private func copyPublicCertificateAsPEM(_ cert: ALTCertificate) {
        guard let data = cert.data else {
            viewModel.errorMessage = "Public certificate data is missing."
            return
        }
        if let pemString = String(data: data, encoding: .utf8) {
            UIPasteboard.general.string = pemString
        } else {
            UIPasteboard.general.string = data.base64EncodedString()
        }
    }
    
    @ViewBuilder
    private func certificateRow(cert: ALTCertificate, hasPrivateKey: Bool) -> some View {
        let isActive = cert.serialNumber == viewModel.activeSerialNumber
        let isRemote = viewModel.remoteSerials.contains(cert.serialNumber)
        
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text((cert.machineName ?? cert.name) + (isRemote ? " (R)" : ""))
                    .font(.headline)
                Text("Serial: " + cert.serialNumber)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                if let ident = cert.identifier {
                    Text("ID: " + ident)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.gray)
                }
                if let brief = getBriefInfo(for: cert.data) {
                    Text("Type: \(brief.type)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text("Validity: \(brief.validFrom) - \(brief.validUntil)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                if let requester = cert.requesterEmail, !requester.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "eye")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        Text("Requester: \(requester)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title3)
                } else if isRemote && viewModel.isPaidAccount {
                    SwiftUI.Button {
                        self.certificateToRevoke = cert
                        self.showRevokeConfirmation = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                }
                
                 Image(systemName: "chevron.right")
                     .foregroundColor(Color(.tertiaryLabel))
                     .font(.footnote)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .contextMenu {
            if hasPrivateKey && !isActive {
                SwiftUI.Button {
                    viewModel.makeCertificateActive(cert)
                } label: {
                    Label("Activate", systemImage: "key.fill")
                }
            }
            
            SwiftUI.Button {
                UIPasteboard.general.string = cert.serialNumber
            } label: {
                Label("Copy S/N", systemImage: "doc.on.doc")
            }
            
            if hasPrivateKey {
                SwiftUI.Button {
                    self.certificateToExport = cert
                    self.exportPasswordInput = ""
                    self.showExportPasswordPrompt = true
                } label: {
                    Label("Export (.p12)", systemImage: "square.and.arrow.up")
                }
            } else {
                SwiftUI.Button {
                    exportPublicCertificateAsDER(cert)
                } label: {
                    Label("Export (.der)", systemImage: "square.and.arrow.up")
                }
                
                SwiftUI.Button {
                    exportPublicCertificateAsPEM(cert)
                } label: {
                    Label("Export (.pem)", systemImage: "square.and.arrow.up")
                }
                
                SwiftUI.Button {
                    copyPublicCertificateAsPEM(cert)
                } label: {
                    Label("Copy (.pem)", systemImage: "doc.on.doc")
                }
            }
            
            if viewModel.isCertificateLocallyCached(cert) {
                SwiftUI.Button(role: .destructive) {
                    self.certificateToDelete = cert
                    self.showDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
    
    private func pushDetailView(for cert: ALTCertificate) {
        let detailView = CertificateDetailView(certificate: cert)
        let detailVC = UIHostingController(rootView: detailView)
        
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        detailVC.navigationItem.scrollEdgeAppearance = appearance
        detailVC.navigationItem.standardAppearance = appearance
        
        presentingViewController?.navigationController?.pushViewController(detailVC, animated: true)
    }
}
