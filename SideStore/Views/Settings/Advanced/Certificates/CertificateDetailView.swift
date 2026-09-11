//
//  CertificateDetailView.swift
//  SideStore
//
//  Created by Magesh K on 2026-06-29.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import SideSign

struct DeveloperPortalMetadata {
    var identifier: String?
    var machineName: String?
    var machineIdentifier: String?
    var requesterEmail: String?
}

struct CertificateDetailView: View {
    let certificate: ALTX509Certificate
    let portalMetadata: DeveloperPortalMetadata?
    @ObservedObject var viewModel: CertificatesViewModel
    
    private var signableCert: ALTCertificate? {
        viewModel.getSignableCertificate(for: certificate.serialNumber)
    }
    
    init(certificate: ALTX509Certificate, portalMetadata: DeveloperPortalMetadata? = nil, viewModel: CertificatesViewModel) {
        self.certificate = certificate
        self.portalMetadata = portalMetadata
        self.viewModel = viewModel
    }
    
    @State private var isRedacted = true
    
    @State private var showPrivateKey = false
    @State private var copiedPrivateKey = false
    @State private var copiedPEM = false
    @State private var copiedSerialNumber = false
    @State private var copiedIdentifier = false
    @State private var copiedFingerprintSHA1 = false
    @State private var copiedFingerprintSHA256 = false
    
    var body: some View {
        Form {
            Section {
                Section {
                    if let identifier = portalMetadata?.identifier {
                        detailRowWithCopy(title: NSLocalizedString("Certificate ID", comment: ""), value: identifier, isCopied: $copiedIdentifier)
                    }
                    if let machineID = portalMetadata?.machineIdentifier {
                        detailRow(title: NSLocalizedString("Machine ID", comment: ""), value: machineID)
                    }
                    if let email = portalMetadata?.requesterEmail {
                        detailRow(title: NSLocalizedString("Requester Email", comment: ""), value: redactableValue(email))
                    }
                } header: {
                    Text("Developer Portal Info")
                }
            }
            
            if let certData = certificate.data {
                let details = parseCertificate(derData: certData)
                Section {
                    detailRow(title: NSLocalizedString("Version", comment: ""), value: details.version)
                    detailRow(title: NSLocalizedString("Subject", comment: ""), value: redactableValue(details.subject))
                    detailRow(title: NSLocalizedString("Issuer", comment: ""), value: details.issuer)
                    detailRow(title: NSLocalizedString("Serial Number (hex)", comment: ""), value: details.serialHex)
                    detailRow(title: NSLocalizedString("Serial Number (dec)", comment: ""), value: details.serialDec)
                } header: {
                    Text("X.509 Fields")
                }
                
                if let from = details.validFrom, let until = details.validUntil {
                    let stats = computeValidityStats(from: from, until: until)
                    Section {
                        detailRow(title: NSLocalizedString("Valid From", comment: ""), value: formatDate(from))
                        detailRow(title: NSLocalizedString("Valid Until", comment: ""), value: formatDate(until))
                        
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
                        
                        detailRow(title: NSLocalizedString("Validity Days", comment: ""), value: String(format: NSLocalizedString("Total: %d, Elapsed: %d, Remaining: %d", comment: ""), stats.totalDays, stats.elapsedDays, stats.remainingDays))
                    } header: {
                        Text("Validity Period")
                    }
                }
                
                Section {
                    detailRow(title: NSLocalizedString("Public Key", comment: ""), value: details.publicKeyType)
                    detailRow(title: NSLocalizedString("Signature Algorithm", comment: ""), value: details.signatureAlgorithm)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("SHA-1 Fingerprint")
                                .font(.subheadline)
                                .foregroundColor(.primary)
                            Spacer()
                            
                            #if !os(tvOS)
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
                            #endif
                        }
                        Text(details.fingerprintSHA1)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            #if !os(tvOS)
                            .textSelection(.enabled)
                            #endif
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
                            
                            #if !os(tvOS)
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
                            #endif
                        }
                        Text(details.fingerprintSHA256)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            #if !os(tvOS)
                            .textSelection(.enabled)
                            #endif
                            .lineLimit(nil)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Signature & Public Key Details")
                }
            }
            
            Section {
                detailRow(title: NSLocalizedString("Has Private Key", comment: ""), value: signableCert != nil ? NSLocalizedString("Yes", comment: "") : NSLocalizedString("No", comment: ""))
                
                if let privateKey = signableCert?.privateKey {
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
                            
                            #if !os(tvOS)
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
                            #endif
                        }
                        
                        if showPrivateKey {
                            Text(privateKey.base64EncodedString())
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                                #if !os(tvOS)
                                .textSelection(.enabled)
                                #endif
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
                            
                            #if !os(tvOS)
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
                            #endif
                        }
                        
                        ScrollView(.horizontal, showsIndicators: true) {
                            Text(String(data: certData, encoding: .utf8) ?? certData.base64EncodedString())
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                                #if !os(tvOS)
                                .textSelection(.enabled)
                                #endif
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Cryptographic Keys")
            }
        }
        .navigationTitle("Certificate Details")
        #if !os(tvOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
                #if !os(tvOS)
                .textSelection(.enabled)
                #endif
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
                #if !os(tvOS)
                .textSelection(.enabled)
                #endif
            
            #if !os(tvOS)
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
            #endif
        }
    }
}
