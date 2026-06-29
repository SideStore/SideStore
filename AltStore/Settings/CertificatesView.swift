//
//  CertificatesView.swift
//  AltStore
//
//  Created by Magesh K on 2026-06-29.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import AltSign
import AltStoreCore
import UniformTypeIdentifiers

struct PendingImport {
    let url: URL
    let filename: String
}

class CertificatesViewModel: ObservableObject {
    @Published var certificates: [ALTCertificate] = []
    @Published var isLoading = false
    @Published var errorMessage: String? = nil {
        didSet {
            showErrorAlert = errorMessage != nil
        }
    }
    @Published var showErrorAlert = false
    @Published var activeSerialNumber: String? = nil
    @Published var alertMessage: String? = nil
    @Published var showAlert = false
    
    // Bulk import properties
    @Published var pendingImports: [PendingImport] = []
    @Published var currentImportIndex = 0
    @Published var showPasswordPromptForImport = false
    @Published var importPasswordInput = ""
    
    var lastUsedPassword = ""
    var session: ALTAppleAPISession?
    var team: ALTTeam?
    
    var isPaidAccount: Bool {
        guard let team = self.team else { return false }
        return team.type != .free && team.type != .unknown
    }
    
    func fetchActiveSerialNumber() {
        if let serial = Keychain.shared.signingCertificateSerialNumber {
            self.activeSerialNumber = serial
        } else if let data = Keychain.shared.signingCertificate,
                  let cert = ALTCertificate(p12Data: data, password: nil) {
            self.activeSerialNumber = cert.serialNumber
        } else {
            self.activeSerialNumber = nil
        }
    }
    
    // MARK: - Local Storage Helpers
    
    func loadLocalCertificates() -> [ALTCertificate] {
        var localCerts: [ALTCertificate] = []
        let serials = UserDefaults.standard.stringArray(forKey: "importedCertificateSerials") ?? []
        for serial in serials {
            if let data = try? Keychain.shared.keychain.getData("importedCert_" + serial),
               let cert = ALTCertificate(p12Data: data, password: "") {
                localCerts.append(cert)
            }
        }
        return localCerts
    }
    
    func saveLocalCertificate(_ cert: ALTCertificate) {
        if let data = cert.p12Data() {
            try? Keychain.shared.keychain.set(data, key: "importedCert_" + cert.serialNumber)
            
            var serials = UserDefaults.standard.stringArray(forKey: "importedCertificateSerials") ?? []
            if !serials.contains(cert.serialNumber) {
                serials.append(cert.serialNumber)
                UserDefaults.standard.set(serials, forKey: "importedCertificateSerials")
            }
        }
    }
    
    func deleteLocalCertificate(serialNumber: String) {
        try? Keychain.shared.keychain.remove("importedCert_" + serialNumber)
        
        var serials = UserDefaults.standard.stringArray(forKey: "importedCertificateSerials") ?? []
        serials.removeAll(where: { $0 == serialNumber })
        UserDefaults.standard.set(serials, forKey: "importedCertificateSerials")
    }
    
    private var activeLocalCert: ALTCertificate? {
        guard let data = Keychain.shared.signingCertificate else { return nil }
        return ALTCertificate(p12Data: data, password: nil)
    }
    
    // MARK: - Fetch & Load
    
    func loadCertificates(presentingViewController: UIViewController?) {
        self.isLoading = true
        self.errorMessage = nil
        self.fetchActiveSerialNumber()
        
        let localCerts = self.loadLocalCertificates()
        let activeCert = self.activeLocalCert
        
        AppManager.shared.authenticate(presentingViewController: presentingViewController) { [weak self] result in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                switch result {
                case .success(let (team, _, session)):
                    self.team = team
                    self.session = session
                    
                    ALTAppleAPI.shared.fetchCertificates(for: team, session: session) { [weak self] (certs, error) in
                        guard let self = self else { return }
                        DispatchQueue.main.async {
                            self.isLoading = false
                            if let error = error {
                                self.errorMessage = error.localizedDescription
                                var merged = localCerts
                                if let active = activeCert, !merged.contains(where: { $0.serialNumber == active.serialNumber }) {
                                    merged.append(active)
                                }
                                self.certificates = merged
                            } else if let remoteCerts = certs {
                                var merged: [ALTCertificate] = []
                                var matchedRemoteSerials = Set<String>()
                                
                                for remoteCert in remoteCerts {
                                    if let localCopy = localCerts.first(where: { $0.serialNumber == remoteCert.serialNumber }) {
                                        remoteCert.privateKey = localCopy.privateKey
                                    } else if let active = activeCert, active.serialNumber == remoteCert.serialNumber {
                                        remoteCert.privateKey = active.privateKey
                                    }
                                    merged.append(remoteCert)
                                    matchedRemoteSerials.insert(remoteCert.serialNumber)
                                }
                                
                                for localCert in localCerts {
                                    if !matchedRemoteSerials.contains(localCert.serialNumber) {
                                        merged.append(localCert)
                                    }
                                }
                                
                                if let active = activeCert, !matchedRemoteSerials.contains(active.serialNumber) {
                                    if !localCerts.contains(where: { $0.serialNumber == active.serialNumber }) {
                                        merged.append(active)
                                    }
                                }
                                
                                self.certificates = merged
                            }
                        }
                    }
                    
                case .failure(let error):
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                    var merged = localCerts
                    if let active = activeCert, !merged.contains(where: { $0.serialNumber == active.serialNumber }) {
                        merged.append(active)
                    }
                    self.certificates = merged
                }
            }
        }
    }
    
    // MARK: - Bulk Import Password Caching Flow
    
    func startBulkImport(urls: [URL]) {
        self.pendingImports = urls.map { PendingImport(url: $0, filename: $0.lastPathComponent) }
        self.currentImportIndex = 0
        processNextImport()
    }
    
    func processNextImport() {
        guard currentImportIndex < pendingImports.count else {
            self.pendingImports = []
            self.loadCertificates(presentingViewController: nil)
            return
        }
        
        let pending = pendingImports[currentImportIndex]
        let url = pending.url
        
        if !lastUsedPassword.isEmpty && tryUnlock(url: url, password: lastUsedPassword) {
            currentImportIndex += 1
            processNextImport()
            return
        }
        
        if tryUnlock(url: url, password: "") {
            currentImportIndex += 1
            processNextImport()
            return
        }
        
        DispatchQueue.main.async {
            self.importPasswordInput = ""
            self.showPasswordPromptForImport = true
        }
    }
    
    func submitImportPassword() {
        let pending = pendingImports[currentImportIndex]
        let url = pending.url
        let password = importPasswordInput
        
        if tryUnlock(url: url, password: password) {
            self.lastUsedPassword = password
            self.showPasswordPromptForImport = false
            self.currentImportIndex += 1
            self.processNextImport()
        } else {
            self.errorMessage = "Incorrect password for " + pending.filename
        }
    }
    
    func cancelImport() {
        self.pendingImports = []
        self.showPasswordPromptForImport = false
    }
    
    private func tryUnlock(url: URL, password: String) -> Bool {
        _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }
        
        guard let certData = try? Data(contentsOf: url) else { return false }
        guard let altCert = ALTCertificate(p12Data: certData, password: password) else { return false }
        
        saveLocalCertificate(altCert)
        return true
    }
    
    // MARK: - Certificate Management Actions
    
    func createCertificate(machineName: String, presentingViewController: UIViewController?) {
        guard let team = self.team, let session = self.session else {
            self.errorMessage = "Not authenticated"
            return
        }
        
        self.isLoading = true
        self.errorMessage = nil
        
        ALTAppleAPI.shared.addCertificate(machineName: machineName, to: team, session: session) { [weak self] (newCert, error) in
            guard let self = self else { return }
            
            if let error = error {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                }
                return
            }
            
            guard let newCert = newCert, let privateKey = newCert.privateKey else {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = "Missing private key from newly created certificate."
                }
                return
            }
            
            ALTAppleAPI.shared.fetchCertificates(for: team, session: session) { [weak self] (certs, error) in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.isLoading = false
                    if let error = error {
                        self.errorMessage = error.localizedDescription
                    } else if let certs = certs {
                        if let certificate = certs.first(where: { $0.serialNumber == newCert.serialNumber }) {
                            certificate.privateKey = privateKey
                            
                            self.saveLocalCertificate(certificate)
                            
                            self.alertMessage = "Certificate created successfully."
                            self.showAlert = true
                            
                            self.loadCertificates(presentingViewController: nil)
                        }
                    }
                }
            }
        }
    }
    
    func revokeCertificate(_ certificate: ALTCertificate) {
        guard let team = self.team, let session = self.session else {
            self.errorMessage = "Not authenticated"
            return
        }
        
        self.isLoading = true
        self.errorMessage = nil
        
        ALTAppleAPI.shared.revoke(certificate, for: team, session: session) { [weak self] (success, error) in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isLoading = false
                if let error = error {
                    self.errorMessage = error.localizedDescription
                } else if success {
                    self.deleteLocalCertificate(serialNumber: certificate.serialNumber)
                    self.certificates.removeAll(where: { $0.serialNumber == certificate.serialNumber })
                    
                    if self.activeSerialNumber == certificate.serialNumber {
                        Keychain.shared.signingCertificate = nil
                        Keychain.shared.signingCertificatePassword = nil
                        self.activeSerialNumber = nil
                    }
                    self.alertMessage = "Certificate revoked successfully."
                    self.showAlert = true
                } else {
                    self.errorMessage = "Failed to revoke certificate."
                }
            }
        }
    }
    
    func deleteCertificate(_ certificate: ALTCertificate) {
        deleteLocalCertificate(serialNumber: certificate.serialNumber)
        self.certificates.removeAll(where: { $0.serialNumber == certificate.serialNumber })
        
        if self.activeSerialNumber == certificate.serialNumber {
            Keychain.shared.signingCertificate = nil
            Keychain.shared.signingCertificatePassword = nil
            self.activeSerialNumber = nil
        }
        self.alertMessage = "Certificate deleted locally."
        self.showAlert = true
    }
    
    func makeCertificateActive(_ certificate: ALTCertificate) {
        guard certificate.privateKey != nil else {
            self.errorMessage = "Cannot activate certificate: private key missing."
            return
        }
        
        Keychain.shared.signingCertificate = certificate.p12Data()
        Keychain.shared.signingCertificatePassword = certificate.machineIdentifier ?? ""
        self.fetchActiveSerialNumber()
        
        self.alertMessage = "Active signing certificate replaced successfully."
        self.showAlert = true
    }
    
    func deactivateActiveCertificate() {
        Keychain.shared.signingCertificate = nil
        Keychain.shared.signingCertificatePassword = nil
        self.activeSerialNumber = nil
        self.alertMessage = "Local certificate deactivated."
        self.showAlert = true
    }
}

struct CertificatesView: View {
    weak var presentingViewController: UIViewController?
    
    private let p12Type = UTType(filenameExtension: "p12") ?? .data
    
    @StateObject private var viewModel = CertificatesViewModel()
    
    @State private var showCreateDialog = false
    @State private var showFileImporter = false
    @State private var showPasswordInputForImport = false
    @State private var showRevokeConfirmation = false
    @State private var showDeactivateConfirmation = false
    @State private var showDeleteConfirmation = false
    @State private var showExportPasswordPrompt = false
    
    @State private var newMachineName = ""
    @State private var exportPasswordInput = ""
    @State private var certificateToExport: ALTCertificate? = nil
    @State private var certificateToRevoke: ALTCertificate? = nil
    @State private var certificateToDelete: ALTCertificate? = nil
    
    var body: some View {
        ZStack {
            List {
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
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                        
                        SwiftUI.Button(role: .destructive) {
                            showDeactivateConfirmation = true
                        } label: {
                            Text("Deactivate Locally")
                                .fontWeight(.medium)
                        }
                    } else {
                        Text("No active local certificate found. Create a new certificate or import a .p12 file to sign your apps.")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    }
                }
                
                let privateCerts = viewModel.certificates.filter { $0.privateKey != nil }
                let publicCerts = viewModel.certificates.filter { $0.privateKey == nil }
                
                if viewModel.certificates.isEmpty {
                    Section(header: Text("Certificates")) {
                        if viewModel.isLoading {
                            Text("Fetching certificates...")
                                .foregroundColor(.secondary)
                        } else {
                            Text("No certificates found.")
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    if !privateCerts.isEmpty {
                        Section(header: Text("Private Certificates")) {
                            ForEach(privateCerts, id: \.serialNumber) { cert in
                                certificateRow(cert: cert, hasPrivateKey: true)
                            }
                        }
                    }
                    
                    if !publicCerts.isEmpty {
                        Section(header: Text("Public Certificates")) {
                            ForEach(publicCerts, id: \.serialNumber) { cert in
                                certificateRow(cert: cert, hasPrivateKey: false)
                            }
                        }
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
                    
                    SwiftUI.Button {
                        self.showFileImporter = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .accessibilityLabel("Import Certificates")
                }
            }
            .onAppear {
                viewModel.loadCertificates(presentingViewController: presentingViewController)
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
            Text("Enter a machine name to identify this certificate on Apple's developer portal.")
        }
        .alert("Local Deactivation", isPresented: $showDeactivateConfirmation) {
            SwiftUI.Button("Deactivate", role: .destructive) {
                viewModel.deactivateActiveCertificate()
            }
            SwiftUI.Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to deactivate the active certificate locally? This will not revoke it on Apple's portal.")
        }
        .alert("Revoke Certificate", isPresented: $showRevokeConfirmation) {
            SwiftUI.Button("Revoke", role: .destructive) {
                if let cert = certificateToRevoke {
                    viewModel.revokeCertificate(cert)
                }
            }
            SwiftUI.Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to revoke this certificate? Any apps signed with this certificate on other devices will stop working.")
        }
        .alert("Delete Certificate", isPresented: $showDeleteConfirmation) {
            SwiftUI.Button("Delete", role: .destructive) {
                if let cert = certificateToDelete {
                    viewModel.deleteCertificate(cert)
                }
            }
            SwiftUI.Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this certificate locally?")
        }
        .alert("Notification", isPresented: $viewModel.showAlert) {
            SwiftUI.Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.alertMessage ?? "")
        }
        .alert("Password Required", isPresented: $viewModel.showPasswordPromptForImport) {
            SecureField("Password", text: $viewModel.importPasswordInput)
            SwiftUI.Button("Unlock") {
                viewModel.submitImportPassword()
            }
            SwiftUI.Button("Cancel", role: .cancel) {
                viewModel.cancelImport()
            }
        } message: {
            if viewModel.currentImportIndex < viewModel.pendingImports.count {
                Text("Enter the password to unlock \(viewModel.pendingImports[viewModel.currentImportIndex].filename).")
            } else {
                Text("Enter the password to unlock.")
            }
        }
        .alert("Export Password", isPresented: $showExportPasswordPrompt) {
            SecureField("Password (Optional)", text: $exportPasswordInput)
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
            allowedContentTypes: [p12Type],
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
    
    private func exportPublicCertificate(_ cert: ALTCertificate) {
        guard let data = cert.data else {
            viewModel.errorMessage = "Public certificate data is missing."
            return
        }
        
        let filename = (cert.machineName ?? cert.name) + ".der"
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
    
    @ViewBuilder
    private func certificateRow(cert: ALTCertificate, hasPrivateKey: Bool) -> some View {
        let isActive = cert.serialNumber == viewModel.activeSerialNumber
        let isRemote = cert.identifier != nil
        
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(cert.machineName ?? cert.name)
                    .font(.headline)
                Text("Serial: " + cert.serialNumber)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                if let ident = cert.identifier {
                    Text("ID: " + ident)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            
            Spacer()
            
            if isActive {
                Text("Active")
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.2))
                    .foregroundColor(.green)
                    .cornerRadius(6)
            } else if isRemote && viewModel.isPaidAccount {
                SwiftUI.Button(role: .destructive) {
                    self.certificateToRevoke = cert
                    self.showRevokeConfirmation = true
                } label: {
                    Text("Revoke")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .tint(.red)
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
            
            SwiftUI.Button {
                if hasPrivateKey {
                    self.certificateToExport = cert
                    self.exportPasswordInput = ""
                    self.showExportPasswordPrompt = true
                } else {
                    exportPublicCertificate(cert)
                }
            } label: {
                Label(hasPrivateKey ? "Export (.p12)" : "Export (.der)", systemImage: "square.and.arrow.up")
            }
            
            SwiftUI.Button(role: .destructive) {
                self.certificateToDelete = cert
                self.showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
