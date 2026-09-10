//
//  CertificateRowView.swift
//  SideStore
//
//  Created by Magesh K on 2026-07-03.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import SideSign

struct CertificateRowView: View {
    let cert: ALTX509Certificate
    @ObservedObject var viewModel: CertificatesViewModel
    
    var onRevoke:     () -> Void
    var onExportP12:  () -> Void
    var onClearKey:   () -> Void
    var onAddKeyBin:  () -> Void
    var onAddKeyText: () -> Void
    var onDelete:     () -> Void
    
    private var hasPrivateKey: Bool { viewModel.hasPrivateKey(for: cert) }
    private var isActive:      Bool { cert.serialNumber == viewModel.activeSerialNumber }
    private var isRemote:      Bool { viewModel.remoteSerials.contains(cert.serialNumber) }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text((cert.machineName ?? cert.name) + (isRemote ? " (R)" : ""))
                    .font(.headline)
                
                let displaySerial = viewModel.displaySerial(for: cert)
                (
                    Text("Serial: ").font(.system(size: 11))
                    + Text(displaySerial).font(.system(size: 11, design: .monospaced))
                )
                .foregroundColor(.secondary)
                
                if let displayIdent = viewModel.displayIdentifier(for: cert) {
                    (
                        Text("ID: ").font(.system(size: 10))
                        + Text(displayIdent).font(.system(size: 10, design: .monospaced))
                    )
                    .foregroundColor(.gray)
                }
                
                if let brief = getBriefInfo(for: cert.data) {
                    CertBriefInfoView(brief: brief, cert: cert, viewModel: viewModel)
                }
                
                if let displayReq = viewModel.displayRequester(for: cert) {
                    let isHidden = displayReq.contains("•")
                    (
                        Text("Requester: ").font(.system(size: 10))
                        + Text(displayReq).font(isHidden ? .system(size: 10, design: .monospaced) : .system(size: 10))
                    )
                    .foregroundColor(.secondary)
                }
                
                (
                    Text("Keys: ").font(.system(size: 10))
                    + Text(hasPrivateKey ? NSLocalizedString("public + private", comment: "") : NSLocalizedString("public", comment: "")).font(.system(size: 10))
                )
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            CertTrailingIcons(isActive: isActive, isRemote: isRemote, onRevoke: onRevoke)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .contextMenu {
            let isMasked = viewModel.isSerialMasked(for: cert)
            SwiftUI.Button { toggleReveal() } label: {
                Label(isMasked ? "Reveal Details" : "Hide Details",
                      systemImage: isMasked ? "eye" : "eye.slash")
            }
            if hasPrivateKey && !isActive {
                SwiftUI.Button { viewModel.makeCertificateActive(cert) } label: {
                    Label("Activate", systemImage: "key.fill")
                }
            }
            SwiftUI.Button {
                #if !os(tvOS)
                UIPasteboard.general.string = cert.serialNumber
                #endif
            } label: {
                Label("Copy S/N", systemImage: "doc.on.doc")
            }
            if hasPrivateKey {
                CertPrivateKeyMenuItems(cert: cert, viewModel: viewModel, onExportP12: onExportP12, onClearKey: onClearKey)
            } else {
                CertPublicKeyMenuItems(cert: cert, viewModel: viewModel, onAddKeyBin: onAddKeyBin, onAddKeyText: onAddKeyText, onExportP12: onExportP12)
            }
            if isRemote {
                SwiftUI.Button(role: .destructive) { onRevoke() } label: {
                    Label("Revoke", systemImage: "xmark.circle")
                }
            }
            if viewModel.isCertificateLocallyCached(cert) {
                SwiftUI.Button(role: .destructive) { onDelete() } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
    
    private func toggleReveal() {
        if viewModel.revealedSerials.contains(cert.serialNumber) { viewModel.revealedSerials.remove(cert.serialNumber) }
        else { viewModel.revealedSerials.insert(cert.serialNumber) }
    }
}

private struct CertBriefInfoView: View {
    let brief: CertificateBriefInfo
    let cert: ALTX509Certificate
    @ObservedObject var viewModel: CertificatesViewModel
    
    var body: some View {
        let displayType      = viewModel.displayBriefType(for: brief, cert: cert)
        let displayValidity  = viewModel.displayBriefValidity(for: brief, cert: cert)
        let isTypeHidden     = displayType.contains("•")
        let isValidityHidden = displayValidity.contains("•")
        Group {
            (
                Text("Type: ").font(.system(size: 10))
                + Text(displayType).font(isTypeHidden ? .system(size: 10, design: .monospaced) : .system(size: 10))
            )
            .foregroundColor(.secondary)
            (
                Text("Validity: ").font(.system(size: 10))
                + Text(displayValidity).font(isValidityHidden ? .system(size: 10, design: .monospaced) : .system(size: 10))
            )
            .foregroundColor(.secondary)
        }
    }
}

private struct CertTrailingIcons: View {
    let isActive: Bool
    let isRemote: Bool
    var onRevoke: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            if isActive {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.title3)
            } else if isRemote {
                SwiftUI.Button { onRevoke() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.red).font(.title3)
                }
                .buttonStyle(.plain)
            }
            Image(systemName: "chevron.right").foregroundColor(Color(.tertiaryLabel)).font(.footnote)
        }
    }
}

private struct AdaptiveMenu<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        #if !os(tvOS)
        Menu {
            content()
        } label: {
            Label(title, systemImage: systemImage)
        }
        #else
        content()
        #endif
    }
}

private struct CertPrivateKeyMenuItems: View {
    let cert: ALTX509Certificate
    @ObservedObject var viewModel: CertificatesViewModel
    var onExportP12: () -> Void
    var onClearKey:  () -> Void
    
    var body: some View {
        Group {
            if let signable = viewModel.getSignableCertificate(for: cert.serialNumber) {
                SwiftUI.Button { CertificateExporter.copyPrivateKey(signable) } label: { Label("Copy pKey (.pem)", systemImage: "doc.on.doc") }
                AdaptiveMenu(title: "Export Private Key", systemImage: "key") {
                    SwiftUI.Button { CertificateExporter.sharePrivateKeyAsPEM(signable) { viewModel.errorMessage = $0 } } label: { Label("Export (.pem)", systemImage: "doc.text") }
                    SwiftUI.Button { CertificateExporter.sharePrivateKeyAsDER(signable) { viewModel.errorMessage = $0 } } label: { Label("Export (.der)", systemImage: "doc.text") }
                }
            }
            
            Divider()
            
            SwiftUI.Button { CertificateExporter.copyPublicCertAsPEM(cert) { viewModel.errorMessage = $0 } } label: { Label("Copy pubK (.pem)", systemImage: "doc.on.doc") }
            AdaptiveMenu(title: "Export Public Key", systemImage: "square.and.arrow.up") {
                SwiftUI.Button { CertificateExporter.sharePublicCertAsPEM(cert) { viewModel.errorMessage = $0 } } label: { Label("Export (.pem)", systemImage: "doc.text") }
                SwiftUI.Button { CertificateExporter.sharePublicCertAsDER(cert) { viewModel.errorMessage = $0 } } label: { Label("Export (.der)", systemImage: "doc.text") }
            }
            
            Divider()
            
            AdaptiveMenu(title: "Export Certificate", systemImage: "square.and.arrow.up") {
                SwiftUI.Button { onExportP12() } label: { Label("Export Full (.p12)", systemImage: "doc.zipper") }
                SwiftUI.Button { CertificateExporter.sharePublicCertAsDER(cert) { viewModel.errorMessage = $0 } } label: { Label("Export Public (.der)", systemImage: "doc.text") }
                SwiftUI.Button { CertificateExporter.sharePublicCertAsPEM(cert) { viewModel.errorMessage = $0 } } label: { Label("Export Public (.pem)", systemImage: "doc.text") }
            }
            
            SwiftUI.Button(role: .destructive) { onClearKey() } label: { Label("Clear pKey", systemImage: "key.slash") }
        }
    }
}

private struct CertPublicKeyMenuItems: View {
    let cert: ALTX509Certificate
    @ObservedObject var viewModel: CertificatesViewModel
    var onAddKeyBin:  () -> Void
    var onAddKeyText: () -> Void
    var onExportP12:  () -> Void
    
    var body: some View {
        Group {
            SwiftUI.Button { onAddKeyText() } label: { Label("Add pKey (.pem)", systemImage: "square.and.pencil") }
            SwiftUI.Button { onAddKeyBin() } label: { Label("Add pKey (.der)", systemImage: "doc.badge.plus") }
            
            Divider()
            
            SwiftUI.Button { CertificateExporter.copyPublicCertAsPEM(cert) { viewModel.errorMessage = $0 } } label: { Label("Copy pubK (.pem)", systemImage: "doc.on.doc") }
            AdaptiveMenu(title: "Export Public Key", systemImage: "square.and.arrow.up") {
                SwiftUI.Button { CertificateExporter.sharePublicCertAsPEM(cert) { viewModel.errorMessage = $0 } } label: { Label("Export (.pem)", systemImage: "doc.text") }
                SwiftUI.Button { CertificateExporter.sharePublicCertAsDER(cert) { viewModel.errorMessage = $0 } } label: { Label("Export (.der)", systemImage: "doc.text") }
            }
            
            Divider()
            
            AdaptiveMenu(title: "Export Certificate", systemImage: "square.and.arrow.up") {
                SwiftUI.Button { onExportP12() } label: { Label("Export Full (.p12)", systemImage: "doc.zipper") }
                SwiftUI.Button { CertificateExporter.sharePublicCertAsDER(cert) { viewModel.errorMessage = $0 } } label: { Label("Export Public (.der)", systemImage: "doc.text") }
                SwiftUI.Button { CertificateExporter.sharePublicCertAsPEM(cert) { viewModel.errorMessage = $0 } } label: { Label("Export Public (.pem)", systemImage: "doc.text") }
            }
        }
    }
}
