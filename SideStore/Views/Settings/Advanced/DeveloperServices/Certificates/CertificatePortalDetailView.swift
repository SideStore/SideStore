//
//  CertificatePortalDetailView.swift
//  SideStore
//
//  Created by Magesh K on 8/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import SideSign

struct CertificatePortalDetailView: View {
    let certificate: ALTX509Certificate
    @ObservedObject var viewModel: DeveloperServicesViewModel
    weak var presentingViewController: UIViewController?
    @Environment(\.presentationMode) var presentationMode

    @State private var showRevokeAlert = false

    private var isExpired: Bool {
        certificate.expiryDate < Date()
    }

    var body: some View {
        List {
            Section(header: Text("Certificate Details")) {
                InfoRow(label: "Name", value: certificate.name)
                InfoRow(label: "Serial Number", value: certificate.serialNumber)
                if let identifier = certificate.identifier {
                    InfoRow(label: "Certificate ID", value: identifier)
                }
                if let machineName = certificate.machineName {
                    InfoRow(label: "Machine Name", value: machineName)
                }
                if let machineIdentifier = certificate.machineIdentifier {
                    InfoRow(label: "Machine Identifier", value: machineIdentifier)
                }
                if let email = certificate.requesterEmail {
                    InfoRow(label: "Requester Email", value: email)
                }
                if let teamName = viewModel.team?.name {
                    InfoRow(label: "Team Name", value: teamName)
                }
                if let teamID = viewModel.team?.identifier {
                    InfoRow(label: "Team Identifier", value: teamID)
                }
                InfoRow(label: "Created Date", value: formatDate(certificate.creationDate))
                InfoRow(label: "Expiration Date", value: formatDate(certificate.expiryDate), valueColor: isExpired ? .red : .primary)
                InfoRow(label: "Status", value: isExpired ? "Expired" : "Active", valueColor: isExpired ? .red : .green)
            }

            Section(footer: Text("Revoking a certificate permanently invalidates it on Apple's servers. Any provisioning profiles tied exclusively to this certificate may need to be re-generated.")) {
                SwiftUI.Button(role: .destructive) {
                    showRevokeAlert = true
                } label: {
                    HStack {
                        Spacer()
                        Image(systemName: "trash")
                        Text("Revoke Certificate on Portal")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
            }
        }
        #if !os(tvOS)
        .listStyle(InsetGroupedListStyle())
        #else
        .listStyle(GroupedListStyle())
        #endif
        .navigationTitle(certificate.name)
        .refreshable {
            await viewModel.fetchCertificates(presentingViewController: presentingViewController, isPullToRefresh: true)
        }
        .alert(isPresented: $showRevokeAlert) {
            Alert(
                title: Text("Revoke Certificate?"),
                message: Text(String(format: NSLocalizedString("Are you sure you want to revoke '%@' on the Apple Developer Portal? This action cannot be undone.", comment: ""), certificate.name)),
                primaryButton: .destructive(Text("Revoke")) {
                    Task {
                        let success = await viewModel.revokeCertificate(certificate, presentingViewController: presentingViewController)
                        if success {
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                },
                secondaryButton: .cancel()
            )
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
