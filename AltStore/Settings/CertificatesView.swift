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
import KeychainAccess
import CommonCrypto
import Security

struct PendingImport {
    let url: URL
    let filename: String
}

struct DeveloperPortalService {
    static let shared = DeveloperPortalService()
    
    func authenticate(presentingViewController: UIViewController?) async throws -> (ALTTeam, ALTAppleAPISession) {
        try await withCheckedThrowingContinuation { continuation in
            AppManager.shared.authenticate(presentingViewController: presentingViewController) { result in
                switch result {
                case .success(let (team, _, session)):
                    continuation.resume(returning: (team, session))
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func fetchCertificates(team: ALTTeam, session: ALTAppleAPISession) async throws -> [ALTCertificate] {
        try await withCheckedThrowingContinuation { continuation in
            ALTAppleAPI.shared.fetchCertificates(for: team, session: session) { certs, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let certs = certs {
                    continuation.resume(returning: certs)
                } else {
                    continuation.resume(returning: [])
                }
            }
        }
    }
    
    func createCertificate(machineName: String, team: ALTTeam, session: ALTAppleAPISession) async throws -> ALTCertificate {
        try await withCheckedThrowingContinuation { continuation in
            ALTAppleAPI.shared.addCertificate(machineName: machineName, to: team, session: session) { cert, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let cert = cert {
                    continuation.resume(returning: cert)
                } else {
                    continuation.resume(throwing: NSError(domain: "SideStoreError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create certificate: no certificate returned."]))
                }
            }
        }
    }
    
    func revokeCertificate(_ certificate: ALTCertificate, team: ALTTeam, session: ALTAppleAPISession) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            ALTAppleAPI.shared.revoke(certificate, for: team, session: session) { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }
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
    
    private let certificateKeychain = KeychainAccess.Keychain(service: Bundle.Info.appbundleIdentifier).accessibility(.afterFirstUnlock)
    
    func loadLocalCertificates() -> [ALTCertificate] {
        var localCerts: [ALTCertificate] = []
        let serials = UserDefaults.standard.stringArray(forKey: "importedCertificateSerials") ?? []
        for serial in serials {
            if let data = try? self.certificateKeychain.getData("importedCert_" + serial) {
                var loadedCert: ALTCertificate? = nil
                if let cert = ALTCertificate(p12Data: data, password: "") {
                    loadedCert = cert
                } else if let cert = ALTCertificate(data: data) {
                    loadedCert = cert
                }
                
                if let cert = loadedCert {
                    if let metadata = UserDefaults.standard.dictionary(forKey: "certMetadata_" + cert.serialNumber) as? [String: String] {
                        cert.machineName = metadata["machineName"]
                        cert.identifier = metadata["identifier"]
                        cert.requesterEmail = metadata["requesterEmail"]
                        cert.machineIdentifier = metadata["machineIdentifier"]
                    }
                    localCerts.append(cert)
                }
            }
        }
        return localCerts
    }
    
    func saveLocalCertificate(_ cert: ALTCertificate) {
        if let p12Data = cert.p12Data() {
            try? self.certificateKeychain.set(p12Data, key: "importedCert_" + cert.serialNumber)
        } else if let derData = cert.data {
            try? self.certificateKeychain.set(derData, key: "importedCert_" + cert.serialNumber)
        } else {
            return
        }
        
        var serials = UserDefaults.standard.stringArray(forKey: "importedCertificateSerials") ?? []
        if !serials.contains(cert.serialNumber) {
            serials.append(cert.serialNumber)
            UserDefaults.standard.set(serials, forKey: "importedCertificateSerials")
        }
        
        var metadataDict: [String: String] = [:]
        if let machineName = cert.machineName {
            metadataDict["machineName"] = machineName
        }
        if let identifier = cert.identifier {
            metadataDict["identifier"] = identifier
        }
        if let requesterEmail = cert.requesterEmail {
            metadataDict["requesterEmail"] = requesterEmail
        }
        if let machineIdentifier = cert.machineIdentifier {
            metadataDict["machineIdentifier"] = machineIdentifier
        }
        UserDefaults.standard.set(metadataDict, forKey: "certMetadata_" + cert.serialNumber)
    }
    
    func deleteLocalCertificate(serialNumber: String) {
        try? self.certificateKeychain.remove("importedCert_" + serialNumber)
        
        var serials = UserDefaults.standard.stringArray(forKey: "importedCertificateSerials") ?? []
        serials.removeAll(where: { $0 == serialNumber })
        UserDefaults.standard.set(serials, forKey: "importedCertificateSerials")
    }
    
    private var activeLocalCert: ALTCertificate? {
        guard let data = Keychain.shared.signingCertificate else { return nil }
        if let cert = ALTCertificate(p12Data: data, password: nil) {
            if let metadata = UserDefaults.standard.dictionary(forKey: "certMetadata_" + cert.serialNumber) as? [String: String] {
                cert.machineName = metadata["machineName"]
                cert.identifier = metadata["identifier"]
                cert.requesterEmail = metadata["requesterEmail"]
                cert.machineIdentifier = metadata["machineIdentifier"]
            }
            return cert
        }
        return nil
    }
    
    // MARK: - Fetch & Load
    
    func loadCertificates(presentingViewController: UIViewController?, completion: (() -> Void)? = nil) {
        self.isLoading = true
        self.errorMessage = nil
        self.fetchActiveSerialNumber()
        
        let localCerts = self.loadLocalCertificates()
        let activeCert = self.activeLocalCert
        
        // Show local certificates immediately
        var mergedLocal = localCerts
        if let active = activeCert, !mergedLocal.contains(where: { $0.serialNumber == active.serialNumber }) {
            mergedLocal.append(active)
        }
        self.certificates = mergedLocal
        
        Task { @MainActor in
            defer {
                self.isLoading = false
                completion?()
            }
            
            do {
                let authVC = Keychain.shared.appleIDEmailAddress != nil ? nil : presentingViewController
                let (team, session) = try await DeveloperPortalService.shared.authenticate(presentingViewController: authVC)
                self.team = team
                self.session = session
                
                let remoteCerts = try await DeveloperPortalService.shared.fetchCertificates(team: team, session: session)
                
                var merged: [ALTCertificate] = []
                var matchedRemoteSerials = Set<String>()
                
                for remoteCert in remoteCerts {
                    if let localCopy = localCerts.first(where: { $0.serialNumber == remoteCert.serialNumber }) {
                        remoteCert.privateKey = localCopy.privateKey
                    } else if let active = activeCert, active.serialNumber == remoteCert.serialNumber {
                        remoteCert.privateKey = active.privateKey
                    }
                    
                    // Automatically cache/save the fetched remote certificate locally!
                    self.saveLocalCertificate(remoteCert)
                    
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
            } catch {
                let isCancelled = error is CancellationError
                if !isCancelled {
                    self.errorMessage = error.localizedDescription
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
        
        Task { @MainActor in
            defer {
                self.isLoading = false
            }
            
            do {
                let newCert = try await DeveloperPortalService.shared.createCertificate(machineName: machineName, team: team, session: session)
                guard let privateKey = newCert.privateKey else {
                    self.errorMessage = "Missing private key from newly created certificate."
                    return
                }
                
                let remoteCerts = try await DeveloperPortalService.shared.fetchCertificates(team: team, session: session)
                if let certificate = remoteCerts.first(where: { $0.serialNumber == newCert.serialNumber }) {
                    certificate.privateKey = privateKey
                    self.saveLocalCertificate(certificate)
                    
                    self.alertMessage = "Certificate created successfully."
                    self.showAlert = true
                    
                    self.loadCertificates(presentingViewController: nil)
                }
            } catch {
                let errorString = error.localizedDescription
                let isCancelled = error is CancellationError
                if !isCancelled {
                    self.errorMessage = errorString
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
        
        Task { @MainActor in
            defer {
                self.isLoading = false
            }
            
            do {
                let success = try await DeveloperPortalService.shared.revokeCertificate(certificate, team: team, session: session)
                if success {
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
            } catch {
                let errorString = error.localizedDescription
                let isCancelled = error is CancellationError
                if !isCancelled {
                    self.errorMessage = errorString
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
    
    func isCertificateLocallyCached(_ certificate: ALTCertificate) -> Bool {
        let serials = UserDefaults.standard.stringArray(forKey: "importedCertificateSerials") ?? []
        return serials.contains(certificate.serialNumber) || certificate.serialNumber == self.activeSerialNumber
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

func getDERData(from pemOrDer: Data) -> Data? {
    guard let str = String(data: pemOrDer, encoding: .ascii) else {
        return pemOrDer
    }
    
    if str.contains("-----BEGIN CERTIFICATE-----") {
        let clean = str
            .replacingOccurrences(of: "-----BEGIN CERTIFICATE-----", with: "")
            .replacingOccurrences(of: "-----END CERTIFICATE-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Data(base64Encoded: clean)
    }
    
    return pemOrDer
}

struct ASN1Item {
    let tag: UInt8
    let data: Data
}

func parseASN1TLV(_ data: Data, offset: inout Int) -> ASN1Item? {
    guard offset < data.count else { return nil }
    
    let tag = data[offset]
    offset += 1
    
    guard offset < data.count else { return nil }
    var length: Int = 0
    let lenByte = data[offset]
    offset += 1
    
    if lenByte & 0x80 == 0 {
        length = Int(lenByte)
    } else {
        let numBytes = Int(lenByte & 0x7F)
        guard offset + numBytes <= data.count else { return nil }
        for _ in 0..<numBytes {
            length = (length << 8) | Int(data[offset])
            offset += 1
        }
    }
    
    guard offset + length <= data.count else { return nil }
    let valueData = data[offset..<offset+length]
    offset += length
    
    return ASN1Item(tag: tag, data: Data(valueData))
}

struct CertificateBriefInfo {
    let validFrom: String
    let validUntil: String
    let type: String
}

func getBriefInfo(for data: Data?) -> CertificateBriefInfo? {
    guard let data, let cleanDer = getDERData(from: data) else { return nil }
    
    var offset = 0
    guard let outerSeq = parseASN1TLV(cleanDer, offset: &offset), outerSeq.tag == 0x30 else { return nil }
    var tbsOffset = 0
    guard let tbsSeq = parseASN1TLV(outerSeq.data, offset: &tbsOffset), tbsSeq.tag == 0x30 else { return nil }
    
    var innerOffset = 0
    if innerOffset < tbsSeq.data.count && tbsSeq.data[innerOffset] == 0xA0 {
        _ = parseASN1TLV(tbsSeq.data, offset: &innerOffset)
    }
    
    guard let _ = parseASN1TLV(tbsSeq.data, offset: &innerOffset) else { return nil }
    guard let _ = parseASN1TLV(tbsSeq.data, offset: &innerOffset) else { return nil }
    guard let issuerItem = parseASN1TLV(tbsSeq.data, offset: &innerOffset) else { return nil }
    
    guard let validityItem = parseASN1TLV(tbsSeq.data, offset: &innerOffset) else { return nil }
    var valOffset = 0
    guard let notBeforeItem = parseASN1TLV(validityItem.data, offset: &valOffset),
          let notAfterItem = parseASN1TLV(validityItem.data, offset: &valOffset) else { return nil }
    
    let fromDate = parseDate(from: notBeforeItem)
    let untilDate = parseDate(from: notAfterItem)
    
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    
    let validFromStr = fromDate != nil ? formatter.string(from: fromDate!) : "N/A"
    let validUntilStr = untilDate != nil ? formatter.string(from: untilDate!) : "N/A"
    
    let issuerDN = parseDN(issuerItem.data)
    var typeStr = "Developer Certificate"
    
    var subjectDN = ""
    if let subjectItem = parseASN1TLV(tbsSeq.data, offset: &innerOffset) {
        subjectDN = parseDN(subjectItem.data)
    }
    
    if subjectDN.contains("Root") || issuerDN.contains("Root") {
        typeStr = "Root CA"
    } else if subjectDN.contains("Authority") || subjectDN.contains("Relations") || issuerDN.contains("Authority") {
        typeStr = "Intermediate CA"
    }
    
    return CertificateBriefInfo(validFrom: validFromStr, validUntil: validUntilStr, type: typeStr)
}

struct ValidityStats {
    let totalDays: Int
    let elapsedDays: Int
    let remainingDays: Int
    let progress: Double
}

func computeValidityStats(from: Date, until: Date) -> ValidityStats {
    let totalSecs = until.timeIntervalSince(from)
    let elapsedSecs = Date().timeIntervalSince(from)
    let remainingSecs = until.timeIntervalSinceNow
    
    let totalDays = max(1, Int(totalSecs / 86400))
    let elapsedDays = max(0, Int(elapsedSecs / 86400))
    let remainingDays = max(0, Int(remainingSecs / 86400))
    
    let progress = totalSecs > 0 ? min(1.0, max(0.0, elapsedSecs / totalSecs)) : 0.0
    return ValidityStats(totalDays: totalDays, elapsedDays: elapsedDays, remainingDays: remainingDays, progress: progress)
}

struct ParsedCertificateDetails {
    var version: String = "N/A"
    var subject: String = "N/A"
    var issuer: String = "N/A"
    var serialHex: String = "N/A"
    var serialDec: String = "N/A"
    var validFrom: Date? = nil
    var validUntil: Date? = nil
    var publicKeyType: String = "N/A"
    var signatureAlgorithm: String = "N/A"
    var fingerprintSHA1: String = "N/A"
    var fingerprintSHA256: String = "N/A"
}

func computeSHA1Fingerprint(data: Data) -> String {
    var hash = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
    data.withUnsafeBytes {
        _ = CC_SHA1($0.baseAddress, CC_LONG(data.count), &hash)
    }
    return hash.map { String(format: "%02X", $0) }.joined(separator: ":")
}

func computeSHA256Fingerprint(data: Data) -> String {
    var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    data.withUnsafeBytes {
        _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
    }
    return hash.map { String(format: "%02X", $0) }.joined(separator: ":")
}

func parseDN(_ data: Data) -> String {
    var offset = 0
    var parts: [String] = []
    
    while offset < data.count {
        guard let setItem = parseASN1TLV(data, offset: &offset), setItem.tag == 0x31 else { break }
        
        var setOffset = 0
        while setOffset < setItem.data.count {
            guard let seqItem = parseASN1TLV(setItem.data, offset: &setOffset), seqItem.tag == 0x30 else { break }
            
            var seqOffset = 0
            guard let oidItem = parseASN1TLV(seqItem.data, offset: &seqOffset), oidItem.tag == 0x06,
                  let valItem = parseASN1TLV(seqItem.data, offset: &seqOffset) else { break }
            
            let oidStr = oidItem.data.map { String($0) }.joined(separator: ".")
            let label = friendlyOIDLabel(oidStr)
            
            if let strVal = String(data: valItem.data, encoding: .utf8) {
                parts.append("\(label)=\(strVal)")
            } else if let strVal = String(data: valItem.data, encoding: .ascii) {
                parts.append("\(label)=\(strVal)")
            }
        }
    }
    return parts.joined(separator: ", ")
}

func friendlyOIDLabel(_ oid: String) -> String {
    switch oid {
    case "85.4.3": return "Common Name"
    case "85.4.6": return "Country"
    case "85.4.7": return "Locality"
    case "85.4.8": return "State"
    case "85.4.10": return "Organization"
    case "85.4.11": return "Organizational Unit"
    case "42.134.72.134.247.13.1.9.1": return "Email"
    default: return oid
    }
}

func parseDate(from item: ASN1Item) -> Date? {
    guard let str = String(data: item.data, encoding: .ascii) else { return nil }
    
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    
    if item.tag == 0x17 {
        formatter.dateFormat = "yyMMddHHmmssZ"
        if let date = formatter.date(from: str) {
            return date
        }
        formatter.dateFormat = "yyMMddHHmmZ"
        return formatter.date(from: str)
    } else if item.tag == 0x18 {
        formatter.dateFormat = "yyyyMMddHHmmssZ"
        return formatter.date(from: str)
    }
    return nil
}

func parsePublicKeyType(pubKeyInfoData: Data) -> String {
    var offset = 0
    guard let algSeq = parseASN1TLV(pubKeyInfoData, offset: &offset), algSeq.tag == 0x30 else { return "RSA" }
    var algOffset = 0
    guard let oidItem = parseASN1TLV(algSeq.data, offset: &algOffset), oidItem.tag == 0x06 else { return "RSA" }
    
    let oidStr = oidItem.data.map { String($0) }.joined(separator: ".")
    if oidStr == "42.134.72.134.247.13.1.1.1" {
        return "RSA"
    } else if oidStr == "42.134.72.206.61.2.1" {
        return "EC"
    }
    return "RSA"
}

func parseSignatureAlgorithm(_ oidData: Data) -> String {
    let oidStr = oidData.map { String($0) }.joined(separator: ".")
    switch oidStr {
    case "42.134.72.134.247.13.1.1.11": return "SHA-256 with RSA"
    case "42.134.72.134.247.13.1.1.5": return "SHA-1 with RSA"
    case "42.134.72.206.61.4.3.2": return "ECDSA with SHA-256"
    default: return "SHA-256 with RSA"
    }
}

func parseCertificate(derData: Data) -> ParsedCertificateDetails {
    var details = ParsedCertificateDetails()
    guard let cleanDer = getDERData(from: derData) else { return details }
    details.fingerprintSHA1 = computeSHA1Fingerprint(data: cleanDer)
    details.fingerprintSHA256 = computeSHA256Fingerprint(data: cleanDer)
    
    var offset = 0
    guard let outerSeq = parseASN1TLV(cleanDer, offset: &offset), outerSeq.tag == 0x30 else { return details }
    var tbsOffset = 0
    guard let tbsSeq = parseASN1TLV(outerSeq.data, offset: &tbsOffset), tbsSeq.tag == 0x30 else { return details }
    
    var innerOffset = 0
    var versionVal = 1
    if innerOffset < tbsSeq.data.count && tbsSeq.data[innerOffset] == 0xA0 {
        if let taggedVersion = parseASN1TLV(tbsSeq.data, offset: &innerOffset) {
            var verOffset = 0
            if let verInt = parseASN1TLV(taggedVersion.data, offset: &verOffset), verInt.tag == 0x02 {
                if verInt.data.count == 1 {
                    versionVal = Int(verInt.data[0]) + 1
                }
            }
        }
    }
    details.version = String(versionVal)
    
    if let serialItem = parseASN1TLV(tbsSeq.data, offset: &innerOffset), serialItem.tag == 0x02 {
        details.serialHex = "0x" + serialItem.data.map { String(format: "%02X", $0) }.joined()
        var decVal: UInt64 = 0
        for byte in serialItem.data {
            decVal = (decVal << 8) | UInt64(byte)
        }
        details.serialDec = String(decVal)
    }
    
    if let sigAlgItem = parseASN1TLV(tbsSeq.data, offset: &innerOffset), sigAlgItem.tag == 0x30 {
        var sigOffset = 0
        if let sigOidItem = parseASN1TLV(sigAlgItem.data, offset: &sigOffset), sigOidItem.tag == 0x06 {
            details.signatureAlgorithm = parseSignatureAlgorithm(sigOidItem.data)
        }
    }
    
    if let issuerItem = parseASN1TLV(tbsSeq.data, offset: &innerOffset), issuerItem.tag == 0x30 {
        details.issuer = parseDN(issuerItem.data)
    }
    
    if let validityItem = parseASN1TLV(tbsSeq.data, offset: &innerOffset), validityItem.tag == 0x30 {
        var valOffset = 0
        if let notBeforeItem = parseASN1TLV(validityItem.data, offset: &valOffset),
           let notAfterItem = parseASN1TLV(validityItem.data, offset: &valOffset) {
            details.validFrom = parseDate(from: notBeforeItem)
            details.validUntil = parseDate(from: notAfterItem)
        }
    }
    
    if let subjectItem = parseASN1TLV(tbsSeq.data, offset: &innerOffset), subjectItem.tag == 0x30 {
        details.subject = parseDN(subjectItem.data)
    }
    
    if let pubKeyInfoItem = parseASN1TLV(tbsSeq.data, offset: &innerOffset), pubKeyInfoItem.tag == 0x30 {
        details.publicKeyType = parsePublicKeyType(pubKeyInfoData: pubKeyInfoItem.data)
    }
    
    return details
}

struct CertificateDetailView: View {
    let certificate: ALTCertificate
    
    @State private var isRedacted = true
    
    @State private var showPrivateKey = false
    @State private var copiedPrivateKey = false
    @State private var copiedPEM = false
    @State private var copiedSerialNumber = false
    @State private var copiedIdentifier = false
    @State private var copiedFingerprintSHA1 = false
    @State private var copiedFingerprintSHA256 = false
    
    var body: some View {
        let briefInfo = getBriefInfo(for: certificate.data)
        Form {
            Section {
                detailRow(title: "Common Name", value: redactableValue(certificate.name))
                detailRow(title: "Machine Name", value: redactableValue(certificate.machineName ?? "N/A"))
                detailRow(title: "Type", value: briefInfo?.type ?? "Developer Certificate")
                detailRow(title: "Valid From", value: briefInfo?.validFrom ?? "N/A")
                detailRow(title: "Valid Until", value: briefInfo?.validUntil ?? "N/A")
                detailRowWithCopy(title: "Serial Number", value: certificate.serialNumber, isCopied: $copiedSerialNumber)
            } header: {
                Text("Basic Information")
            }
            
            Section {
                detailRowWithCopy(title: "Certificate ID", value: certificate.identifier ?? "N/A", isCopied: $copiedIdentifier)
                detailRow(title: "Machine ID", value: certificate.machineIdentifier ?? "N/A")
                detailRow(title: "Requester Email", value: redactableValue(certificate.requesterEmail ?? "N/A"))
            } header: {
                Text("Developer Portal Info")
            }
            
            if let certData = certificate.data {
                let details = parseCertificate(derData: certData)
                Section {
                    detailRow(title: "Version", value: details.version)
                    detailRow(title: "Subject", value: redactableValue(details.subject))
                    detailRow(title: "Issuer", value: details.issuer)
                    detailRow(title: "Serial Number (hex)", value: details.serialHex)
                    detailRow(title: "Serial Number (dec)", value: details.serialDec)
                } header: {
                    Text("X.509 Fields")
                }
                
                if let from = details.validFrom, let until = details.validUntil {
                    let stats = computeValidityStats(from: from, until: until)
                    Section {
                        detailRow(title: "Valid From", value: formatDate(from))
                        detailRow(title: "Valid Until", value: formatDate(until))
                        
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Validity Progress")
                                Spacer()
                                Text(String(format: "%.0f%%", stats.progress * 100))
                                    .foregroundColor(.secondary)
                            }
                            ProgressView(value: stats.progress)
                                .tint(.accentColor)
                        }
                        
                        detailRow(title: "Validity Days", value: "Total: \(stats.totalDays), Elapsed: \(stats.elapsedDays), Remaining: \(stats.remainingDays)")
                    } header: {
                        Text("Validity Period")
                    }
                }
                
                Section {
                    detailRow(title: "Public Key", value: details.publicKeyType)
                    detailRow(title: "Signature Algorithm", value: details.signatureAlgorithm)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("SHA-1 Fingerprint")
                                .font(.subheadline)
                                .foregroundColor(.primary)
                            Spacer()
                            
                            SwiftUI.Button {
                                UIPasteboard.general.string = details.fingerprintSHA1
                                copiedFingerprintSHA1 = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    copiedFingerprintSHA1 = false
                                }
                            } label: {
                                Image(systemName: copiedFingerprintSHA1 ? "checkmark" : "doc.on.doc")
                                    .font(.footnote)
                                    .foregroundColor(copiedFingerprintSHA1 ? .green : .accentColor)
                            }
                            .buttonStyle(.plain)
                        }
                        Text(details.fingerprintSHA1)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(nil)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(.vertical, 4)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("SHA-256 Fingerprint")
                                .font(.subheadline)
                                .foregroundColor(.primary)
                            Spacer()
                            
                            SwiftUI.Button {
                                UIPasteboard.general.string = details.fingerprintSHA256
                                copiedFingerprintSHA256 = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    copiedFingerprintSHA256 = false
                                }
                            } label: {
                                Image(systemName: copiedFingerprintSHA256 ? "checkmark" : "doc.on.doc")
                                    .font(.footnote)
                                    .foregroundColor(copiedFingerprintSHA256 ? .green : .accentColor)
                            }
                            .buttonStyle(.plain)
                        }
                        Text(details.fingerprintSHA256)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(nil)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Signature & Public Key Details")
                }
            }
            
            Section {
                detailRow(title: "Has Private Key", value: certificate.privateKey != nil ? "Yes" : "No")
                
                if let privateKey = certificate.privateKey {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Private Key Data")
                                .font(.subheadline)
                                .foregroundColor(.primary)
                            Spacer()
                            
                            SwiftUI.Button {
                                showPrivateKey.toggle()
                            } label: {
                                Image(systemName: showPrivateKey ? "eye.slash" : "eye")
                                    .foregroundColor(.accentColor)
                            }
                            .buttonStyle(.plain)
                            
                            SwiftUI.Button {
                                UIPasteboard.general.string = privateKey.base64EncodedString()
                                copiedPrivateKey = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    copiedPrivateKey = false
                                }
                            } label: {
                                Image(systemName: copiedPrivateKey ? "checkmark" : "doc.on.doc")
                                    .foregroundColor(copiedPrivateKey ? .green : .accentColor)
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, 12)
                        }
                        
                        if showPrivateKey {
                            Text(privateKey.base64EncodedString())
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                                .lineLimit(nil)
                                .multilineTextAlignment(.leading)
                        } else {
                            Text("••••••••••••••••••••••••••••")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                if let certData = certificate.data {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Certificate PEM Data")
                                .font(.subheadline)
                                .foregroundColor(.primary)
                            Spacer()
                            
                            SwiftUI.Button {
                                let pem = String(data: certData, encoding: .utf8) ?? certData.base64EncodedString()
                                UIPasteboard.general.string = pem
                                copiedPEM = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    copiedPEM = false
                                }
                            } label: {
                                Image(systemName: copiedPEM ? "checkmark" : "doc.on.doc")
                                    .foregroundColor(copiedPEM ? .green : .accentColor)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        ScrollView(.vertical, showsIndicators: true) {
                            Text(String(data: certData, encoding: .utf8) ?? certData.base64EncodedString())
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(nil)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxHeight: 150)
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Cryptographic Keys")
            }
        }
        .navigationTitle("Certificate Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                SwiftUI.Button {
                    isRedacted.toggle()
                } label: {
                    Image(systemName: isRedacted ? "eye.slash" : "eye")
                }
            }
        }
    }
    
    private func redactableValue(_ value: String, sensitive: Bool = true) -> String {
        if sensitive && isRedacted {
            return "••••••••"
        }
        return value
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
    
    private func detailRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.primary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
    
    private func detailRowWithCopy(title: String, value: String, isCopied: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.primary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
            
            if value != "N/A" && !value.isEmpty && value != "••••••••" {
                SwiftUI.Button {
                    UIPasteboard.general.string = value
                    isCopied.wrappedValue = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        isCopied.wrappedValue = false
                    }
                } label: {
                    Image(systemName: isCopied.wrappedValue ? "checkmark" : "doc.on.doc")
                        .font(.footnote)
                        .foregroundColor(isCopied.wrappedValue ? .green : .accentColor)
                }
                .buttonStyle(.plain)
                .padding(.leading, 8)
            }
        }
    }
}

extension ALTCertificate {
    var creationDate: Date {
        guard let data = self.data,
              let cleanDer = getDERData(from: data) else {
            return Date.distantPast
        }
        var offset = 0
        guard let outerSeq = parseASN1TLV(cleanDer, offset: &offset), outerSeq.tag == 0x30 else { return Date.distantPast }
        var tbsOffset = 0
        guard let tbsSeq = parseASN1TLV(outerSeq.data, offset: &tbsOffset), tbsSeq.tag == 0x30 else { return Date.distantPast }
        
        var innerOffset = 0
        if innerOffset < tbsSeq.data.count && tbsSeq.data[innerOffset] == 0xA0 {
            _ = parseASN1TLV(tbsSeq.data, offset: &innerOffset)
        }
        
        guard let _ = parseASN1TLV(tbsSeq.data, offset: &innerOffset) else { return Date.distantPast }
        guard let _ = parseASN1TLV(tbsSeq.data, offset: &innerOffset) else { return Date.distantPast }
        guard let _ = parseASN1TLV(tbsSeq.data, offset: &innerOffset) else { return Date.distantPast }
        
        guard let validityItem = parseASN1TLV(tbsSeq.data, offset: &innerOffset) else { return Date.distantPast }
        var valOffset = 0
        guard let notBeforeItem = parseASN1TLV(validityItem.data, offset: &valOffset) else { return Date.distantPast }
        
        return parseDate(from: notBeforeItem) ?? Date.distantPast
    }
}
