//
//  CertificatesPortalListView.swift
//  SideStore
//
//  Created by Magesh K on 8/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import SideSign

struct CertificatesPortalListView: View {
    @ObservedObject var viewModel: DeveloperServicesViewModel
    weak var presentingViewController: UIViewController?

    @State private var searchText = ""
    @State private var certificateToRevoke: ALTX509Certificate? = nil
    @State private var showRevokeConfirmation = false

    private var filteredCertificates: [ALTX509Certificate] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return viewModel.certificates
        }
        return viewModel.certificates.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            ($0.machineName?.localizedCaseInsensitiveContains(searchText) == true) ||
            $0.serialNumber.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List {
            Section(header: Text("Certificates (\(viewModel.certificates.count))"), footer: Text("Development certificates registered on your Apple Developer team. Revoking invalidates the certificate on Apple's portal.")) {
                if filteredCertificates.isEmpty {
                    if viewModel.isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    } else {
                        Text(searchText.isEmpty ? "No certificates found on Developer Portal." : "No matching certificates found.")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    }
                } else {
                    ForEach(filteredCertificates, id: \.serialNumber) { cert in
                        NavigationLink(destination: CertificatePortalDetailView(certificate: cert, viewModel: viewModel, presentingViewController: presentingViewController)) {
                            CertificatePortalRow(certificate: cert, formatDate: formatDate)
                        }
                        #if !os(tvOS)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            SwiftUI.Button(role: .destructive) {
                                certificateToRevoke = cert
                                showRevokeConfirmation = true
                            } label: {
                                Label("Revoke", systemImage: "trash")
                            }
                        }
                        #endif
                        .contextMenu {
                            SwiftUI.Button(role: .destructive) {
                                certificateToRevoke = cert
                                showRevokeConfirmation = true
                            } label: {
                                Label("Revoke", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        #if !os(tvOS)
        .listStyle(InsetGroupedListStyle())
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search Certificates")
        #else
        .listStyle(GroupedListStyle())
        #endif
        .navigationTitle("Certificates")
        .refreshable {
            await viewModel.fetchCertificates(presentingViewController: presentingViewController, isPullToRefresh: true)
        }
        .alert(isPresented: $showRevokeConfirmation) {
            Alert(
                title: Text("Revoke Certificate?"),
                message: Text("Are you sure you want to revoke '\(certificateToRevoke?.name ?? "this certificate")' on the Apple Developer Portal? This action cannot be undone."),
                primaryButton: .destructive(Text("Revoke")) {
                    if let cert = certificateToRevoke {
                        Task {
                            _ = await viewModel.revokeCertificate(cert, presentingViewController: presentingViewController)
                        }
                    }
                },
                secondaryButton: .cancel()
            )
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

private struct CertificatePortalRow: View {
    let certificate: ALTX509Certificate
    let formatDate: (Date) -> String

    private var isExpired: Bool {
        certificate.expiryDate < Date()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(certificate.name)
                    .font(.headline)
                Spacer()
                if isExpired {
                    Text("Expired")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.15))
                        .foregroundColor(.red)
                        .cornerRadius(6)
                } else {
                    Text("Active")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.12))
                        .foregroundColor(.green)
                        .cornerRadius(6)
                }
                Text("Expires: \(formatDate(certificate.expiryDate))")
                    .font(.caption)
                    .foregroundColor(isExpired ? .red : .secondary)
            }

            if let machine = certificate.machineName {
                Text(machine)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Text("Serial: \(certificate.serialNumber)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.8))
        }
        .padding(.vertical, 2)
    }
}
