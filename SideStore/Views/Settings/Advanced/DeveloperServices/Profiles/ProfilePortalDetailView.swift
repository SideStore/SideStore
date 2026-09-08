//
//  ProfilePortalDetailView.swift
//  SideStore
//
//  Created by Magesh K on 2/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import SideSign

struct ProfilePortalDetailView: View {
    let profile: ALTProvisioningProfile
    @ObservedObject var viewModel: DeveloperServicesViewModel
    weak var presentingViewController: UIViewController?
    @Environment(\.presentationMode) var presentationMode

    @State private var showDeleteAlert = false

    var body: some View {
        List {
            Section(header: Text("Profile Metadata")) {
                InfoRow(label: "Name", value: profile.name)
                InfoRow(label: "UUID", value: profile.uuid.uuidString)
                if let identifier = profile.identifier {
                    InfoRow(label: "Identifier", value: identifier)
                }
                InfoRow(label: "Team Name", value: profile.teamName)
                InfoRow(label: "Team Identifier", value: profile.teamIdentifier)
                InfoRow(label: "App Bundle ID", value: profile.bundleIdentifier)
                InfoRow(label: "Created Date", value: formatDate(profile.creationDate))
                InfoRow(label: "Expiration Date", value: formatDate(profile.expirationDate), valueColor: profile.expirationDate < Date() ? .red : .primary)
                InfoRow(label: "Free Developer Profile", value: profile.isFreeProvisioningProfile ? "Yes" : "No")
            }

            if !profile.certificates.isEmpty {
                Section(header: Text(String(format: NSLocalizedString("Developer Certificates (%d)", comment: ""), profile.certificates.count))) {
                    ForEach(profile.certificates, id: \.serialNumber) { cert in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(cert.name)
                                .font(.subheadline)
                            Text(String(format: NSLocalizedString("Serial: %@", comment: ""), cert.serialNumber))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            if !profile.deviceIDs.isEmpty {
                Section(header: Text(String(format: NSLocalizedString("Provisioned Devices (%d)", comment: ""), profile.deviceIDs.count))) {
                    ForEach(profile.deviceIDs, id: \.self) { deviceID in
                        Text(deviceID)
                            .font(.system(.caption, design: .monospaced))
                    }
                }
            }

            if !profile.entitlements.isEmpty {
                Section(header: Text(String(format: NSLocalizedString("Entitlements (%d)", comment: ""), profile.entitlements.count))) {
                    let sortedEntitlements = profile.entitlements.sorted { $0.key < $1.key }
                    ForEach(sortedEntitlements, id: \.key) { entitlement, value in
                        EntitlementRow(key: entitlement, value: value)
                    }
                }
            }

            Section {
                SwiftUI.Button(role: .destructive) {
                    showDeleteAlert = true
                } label: {
                    HStack {
                        Spacer()
                        Image(systemName: "trash")
                        Text("Delete Profile from Portal")
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
        .navigationTitle(profile.name)
        .refreshable {
            await viewModel.fetchProfiles(presentingViewController: presentingViewController, isPullToRefresh: true)
        }
        .alert(isPresented: $showDeleteAlert) {
            Alert(
                title: Text("Delete Provisioning Profile?"),
                message: Text(String(format: NSLocalizedString("Are you sure you want to delete '%@' from the Apple Developer Portal?", comment: ""), profile.name)),
                primaryButton: .destructive(Text("Delete")) {
                    Task {
                        let success = await viewModel.deleteProfile(profile, presentingViewController: presentingViewController)
                        if success {
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                },
                secondaryButton: .cancel()
            )
        }
        .developerServicesToast(viewModel: viewModel)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
