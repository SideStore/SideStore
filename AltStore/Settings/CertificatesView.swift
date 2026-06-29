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
    
    var session: ALTAppleAPISession?
    var team: ALTTeam?
    
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
    
    func loadCertificates(presentingViewController: UIViewController?) {
        self.isLoading = true
        self.errorMessage = nil
        self.fetchActiveSerialNumber()
        
        // 1. Authenticate first using the cached Apple ID credentials
        AppManager.shared.authenticate(presentingViewController: presentingViewController) { [weak self] result in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                switch result {
                case .success(let (team, _, session)):
                    self.team = team
                    self.session = session
                    
                    // 2. Fetch certificates from developer portal
                    ALTAppleAPI.shared.fetchCertificates(for: team, session: session) { [weak self] (certs, error) in
                        guard let self = self else { return }
                        DispatchQueue.main.async {
                            self.isLoading = false
                            if let error = error {
                                self.errorMessage = error.localizedDescription
                            } else if let certs = certs {
                                self.certificates = certs
                            }
                        }
                    }
                    
                case .failure(let error):
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
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
            
            // Now fetch the certificates list from Apple to get the machineIdentifier and metadata
            ALTAppleAPI.shared.fetchCertificates(for: team, session: session) { [weak self] (certs, error) in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.isLoading = false
                    if let error = error {
                        self.errorMessage = error.localizedDescription
                    } else if let certs = certs {
                        self.certificates = certs
                        
                        // Find the matching certificate to get the machineIdentifier
                        if let certificate = certs.first(where: { $0.serialNumber == newCert.serialNumber }) {
                            certificate.privateKey = privateKey
                            
                            // Save this certificate as active in local keychain
                            Keychain.shared.signingCertificate = certificate.p12Data()
                            Keychain.shared.signingCertificatePassword = certificate.machineIdentifier
                            
                            self.fetchActiveSerialNumber()
                            self.alertMessage = "Certificate created and set as active signing certificate successfully."
                            self.showAlert = true
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
                    // Remove from list
                    self.certificates.removeAll(where: { $0.serialNumber == certificate.serialNumber })
                    
                    // If we revoked the active certificate, clear it from Keychain
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
    
    func importCertificate(url: URL, password: String) {
        self.isLoading = true
        self.errorMessage = nil
        
        do {
            _ = url.startAccessingSecurityScopedResource()
            defer { url.stopAccessingSecurityScopedResource() }
            
            let certData = try Data(contentsOf: url)
            
            guard let altCert = ALTCertificate(p12Data: certData, password: password) else {
                self.isLoading = false
                self.errorMessage = "Failed to parse certificate. Check if the password is correct."
                return
            }
            
            Keychain.shared.signingCertificate = altCert.encryptedP12Data(withPassword: "")!
            Keychain.shared.signingCertificatePassword = ""
            self.fetchActiveSerialNumber()
            
            self.isLoading = false
            self.alertMessage = "Certificate imported successfully!"
            self.showAlert = true
        } catch {
            self.isLoading = false
            self.errorMessage = "Failed to import certificate: \(error.localizedDescription)"
        }
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
    @State private var showPasswordInput = false
    @State private var showRevokeConfirmation = false
    @State private var showDeactivateConfirmation = false
    
    @State private var newMachineName = ""
    @State private var importPassword = ""
    @State private var selectedURL: URL? = nil
    @State private var certificateToRevoke: ALTCertificate? = nil
    
    var body: some View {
        ZStack {
            List {
                Section(header: Text("Active Local Certificate")) {
                    if let activeSerial = viewModel.activeSerialNumber {
                        VStack(alignment: .leading, spacing: 6) {
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
                            
                            SwiftUI.Button(role: .destructive) {
                                showDeactivateConfirmation = true
                            } label: {
                                Text("Deactivate Locally")
                                    .fontWeight(.medium)
                            }
                            .buttonStyle(.borderless)
                            .padding(.top, 4)
                        }
                        .padding(.vertical, 4)
                    } else {
                        Text("No active local certificate found. Create a new certificate or import a .p12 file to sign your apps.")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    }
                }
                
                Section(header: Text("Portal Certificates")) {
                    if viewModel.certificates.isEmpty {
                        if viewModel.isLoading {
                            Text("Fetching certificates...")
                                .foregroundColor(.secondary)
                        } else {
                            Text("No certificates found on your Apple Developer account.")
                                .foregroundColor(.secondary)
                        }
                    } else {
                        ForEach(viewModel.certificates, id: \.serialNumber) { cert in
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
                                
                                if cert.serialNumber == viewModel.activeSerialNumber {
                                    Text("Active")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.green.opacity(0.2))
                                        .foregroundColor(.green)
                                        .cornerRadius(6)
                                } else {
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
                        }
                    }
                }
            }
            .navigationTitle("Certificates")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    SwiftUI.Button {
                        // Prefill default name: "SideStore - [Device Name]"
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
                    .accessibilityLabel("Import Certificate")
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
        .alert("Notification", isPresented: $viewModel.showAlert) {
            SwiftUI.Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.alertMessage ?? "")
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [p12Type],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    self.selectedURL = url
                    self.showPasswordInput = true
                }
            case .failure(let error):
                viewModel.errorMessage = "Failed to select file: \(error.localizedDescription)"
            }
        }
        .alert("Certificate Password", isPresented: $showPasswordInput) {
            SecureField("Password", text: $importPassword)
            SwiftUI.Button("Import") {
                if let url = selectedURL {
                    viewModel.importCertificate(url: url, password: importPassword)
                }
            }
            SwiftUI.Button("Cancel", role: .cancel) {
                importPassword = ""
            }
        } message: {
            Text("Enter the password for the selected certificate file.")
        }
    }
}
