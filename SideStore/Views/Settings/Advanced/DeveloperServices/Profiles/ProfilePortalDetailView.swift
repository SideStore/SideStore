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
    let profile: ALTListedProvisioningProfile
    @ObservedObject var viewModel: DeveloperServicesViewModel
    weak var presentingViewController: UIViewController?
    @Environment(\.presentationMode) var presentationMode

    @State private var editedName: String = ""
    @State private var selectedAppIDId: String = ""
    @State private var selectedCertificateIDs: Set<String> = []
    @State private var selectedDeviceIDs: Set<String> = []

    @State private var customCertInput: String = ""
    @State private var customDeviceInput: String = ""

    @State private var showDeleteAlert = false

    private var isExpired: Bool {
        profile.dateExpire < Date()
    }

    private var hasChanges: Bool {
        let nameChanged = !editedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && editedName != profile.name
        let originalAppID = profile.appId?.appIdId ?? profile.appId?.identifier ?? ""
        let appIDChanged = !selectedAppIDId.isEmpty && selectedAppIDId != originalAppID
        let originalDevices = Set(profile.deviceIds ?? [])
        let devicesChanged = selectedDeviceIDs != originalDevices
        return nameChanged || appIDChanged || devicesChanged
    }

    private var canSave: Bool {
        !editedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !selectedAppIDId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !selectedCertificateIDs.isEmpty &&
        !selectedDeviceIDs.isEmpty &&
        !viewModel.isActionLoading
    }

    var body: some View {
        List {
            Section(header: Text("Profile Information"), footer: Text("You can edit the profile name and regenerate the profile with updated certificate or device associations.")) {
                HStack {
                    Text("Name")
                        .foregroundColor(.secondary)
                        .frame(width: 100, alignment: .leading)
                    TextField("Profile Name", text: $editedName)
                }

                InfoRow(label: "UUID", value: profile.uuid.uuidString)
                if let identifier = profile.identifier {
                    InfoRow(label: "Identifier", value: identifier)
                }
                if let profType = profile.profileType {
                    InfoRow(label: "Type", value: profType.displayName)
                } else if let rawType = profile.type {
                    InfoRow(label: "Type", value: rawType)
                }
                if let isTeam = profile.isTeamProfile {
                    InfoRow(label: "Managed By", value: isTeam ? NSLocalizedString("Xcode (Team Profile)", comment: "") : NSLocalizedString("Manual (Portal)", comment: ""))
                }
                InfoRow(label: "Status", value: isExpired ? NSLocalizedString("Expired", comment: "") : (profile.status ?? NSLocalizedString("Active", comment: "")), valueColor: isExpired ? .red : .primary)
                InfoRow(label: "Expiration Date", value: formatDate(profile.dateExpire), valueColor: isExpired ? .red : .primary)
            }

            Section(header: Text("App ID Association"), footer: Text("Choose from registered team App IDs or specify a custom App ID / identifier.")) {
                if !viewModel.appIDs.isEmpty {
                    Picker("Team App ID", selection: $selectedAppIDId) {
                        Text("Choose App ID").tag("")
                        ForEach(viewModel.appIDs, id: \.identifier) { appID in
                            Text(String(format: NSLocalizedString("%@ (%@)", comment: ""), appID.name, appID.bundleIdentifier)).tag(appID.identifier)
                        }
                    }
                }

                HStack {
                    Text("App ID ID")
                        .foregroundColor(.secondary)
                        .frame(width: 100, alignment: .leading)
                    TextField("App ID Identifier (e.g. R7V954WR9W)", text: $selectedAppIDId)
                        .font(.system(.subheadline, design: .monospaced))
                }
            }

            Section(header: Text(String(format: NSLocalizedString("Associated Certificates (%d)", comment: ""), selectedCertificateIDs.count)), footer: Text("Select which certificates are authorized to sign with this profile, or add custom certificate IDs.")) {
                if viewModel.certificates.isEmpty {
                    Text("No certificates found on this team.")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                } else {
                    ForEach(viewModel.certificates, id: \.serialNumber) { cert in
                        let certID = cert.identifier ?? cert.serialNumber
                        SwiftUI.Button {
                            if selectedCertificateIDs.contains(certID) {
                                selectedCertificateIDs.remove(certID)
                            } else {
                                selectedCertificateIDs.insert(certID)
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(cert.commonName ?? cert.name)
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                    Text(String(format: NSLocalizedString("Serial: %@", comment: ""), cert.serialNumber))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if selectedCertificateIDs.contains(certID) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack {
                    TextField("Add Custom Certificate ID", text: $customCertInput)
                        .font(.system(.subheadline, design: .monospaced))
                    SwiftUI.Button("Add") {
                        let trimmed = customCertInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            selectedCertificateIDs.insert(trimmed)
                            customCertInput = ""
                        }
                    }
                    .disabled(customCertInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            Section(header: HStack {
                Text(String(format: NSLocalizedString("Associated Devices (%d)", comment: ""), selectedDeviceIDs.count))
                Spacer()
                if !viewModel.devices.isEmpty {
                    SwiftUI.Button(selectedDeviceIDs.count >= viewModel.devices.count ? NSLocalizedString("Deselect All", comment: "") : NSLocalizedString("Select All", comment: "")) {
                        if selectedDeviceIDs.count >= viewModel.devices.count {
                            selectedDeviceIDs.removeAll()
                        } else {
                            selectedDeviceIDs = Set(viewModel.devices.compactMap { $0.deviceID ?? $0.identifier })
                        }
                    }
                    .font(.caption)
                }
            }, footer: Text("Select devices allowed to run apps with this profile, or enter a custom Device ID / UDID.")) {
                if viewModel.devices.isEmpty {
                    Text("No registered devices found on this team.")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                } else {
                    ForEach(viewModel.devices, id: \.identifier) { device in
                        let devID = device.deviceID ?? device.identifier
                        let isSelected = selectedDeviceIDs.contains(devID) || selectedDeviceIDs.contains(device.identifier)
                        SwiftUI.Button {
                            if isSelected {
                                selectedDeviceIDs.remove(devID)
                                selectedDeviceIDs.remove(device.identifier)
                            } else {
                                selectedDeviceIDs.insert(devID)
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.name)
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                    Text(device.identifier)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack {
                    TextField("Add Custom Device ID / UDID", text: $customDeviceInput)
                        .font(.system(.subheadline, design: .monospaced))
                    SwiftUI.Button("Add") {
                        let trimmed = customDeviceInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            selectedDeviceIDs.insert(trimmed)
                            customDeviceInput = ""
                        }
                    }
                    .disabled(customDeviceInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            if hasChanges {
                Section {
                    SwiftUI.Button {
                        Task {
                            let success = await viewModel.updateProfile(
                                profile,
                                name: editedName.trimmingCharacters(in: .whitespacesAndNewlines),
                                appIDId: selectedAppIDId.trimmingCharacters(in: .whitespacesAndNewlines),
                                certificateIDs: Array(selectedCertificateIDs),
                                deviceIDs: Array(selectedDeviceIDs),
                                type: profile.profileType,
                                presentingViewController: presentingViewController
                            )
                            if success {
                                presentationMode.wrappedValue.dismiss()
                            }
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if viewModel.isActionLoading {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("Save Changes (Regenerate Profile)")
                                    .fontWeight(.bold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(!canSave)
                }
            }

            Section {
                SwiftUI.Button {
                    Task {
                        guard let downloaded = await viewModel.downloadProfile(profile: profile) else { return }
                        let safeName = profile.name.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
                        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName).mobileprovision")
                        do {
                            try downloaded.data.write(to: tempURL)
                            #if !os(tvOS)
                            let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
                            if let popover = activityVC.popoverPresentationController {
                                popover.sourceView = presentingViewController?.view
                            }
                            presentingViewController?.present(activityVC, animated: true)
                            #endif
                        } catch {
                            debugLog("[ProfilePortalDetailView] Failed to write profile to temp: \(error)")
                        }
                    }
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isActionLoading {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.down.doc")
                            Text("Download Profile (.mobileprovision)")
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .disabled(viewModel.isActionLoading)
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
        .onAppear {
            if editedName.isEmpty {
                editedName = profile.name
            }
            if selectedAppIDId.isEmpty {
                selectedAppIDId = profile.appId?.appIdId ?? profile.appId?.identifier ?? ""
            }
            if selectedDeviceIDs.isEmpty, let devIDs = profile.deviceIds {
                selectedDeviceIDs = Set(devIDs)
            }
            if selectedCertificateIDs.isEmpty {
                selectedCertificateIDs = Set(viewModel.certificates.compactMap { $0.identifier ?? $0.serialNumber })
            }
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
