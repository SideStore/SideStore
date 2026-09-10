//
//  CreateManualProfileView.swift
//  SideStore
//
//  Created by Magesh K on 8/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import SideSign

struct CreateManualProfileView: View {
    @ObservedObject var viewModel: DeveloperServicesViewModel
    weak var presentingViewController: UIViewController?
    @Environment(\.presentationMode) var presentationMode

    @State private var profileName: String = ""
    @State private var selectedAppIDIdentifier: String = ""
    @State private var selectedCertificateIDs: Set<String> = []
    @State private var selectedDeviceIDs: Set<String> = []

    private var selectedAppID: ALTAppID? {
        viewModel.appIDs.first { $0.identifier == selectedAppIDIdentifier }
    }

    private var canSubmit: Bool {
        !profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        selectedAppID != nil &&
        !selectedCertificateIDs.isEmpty &&
        !selectedDeviceIDs.isEmpty &&
        !viewModel.isActionLoading
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Profile Information"), footer: Text("Choose a descriptive name for this manual provisioning profile.")) {
                    TextField("Profile Name", text: $profileName)
                }

                Section(header: Text("App ID")) {
                    if viewModel.appIDs.isEmpty {
                        Text("No App IDs found. Create an App ID first.")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    } else {
                        Picker("App ID", selection: $selectedAppIDIdentifier) {
                            ForEach(viewModel.appIDs, id: \.identifier) { appID in
                                Text(String(format: NSLocalizedString("%@ (%@)", comment: ""), appID.name, appID.bundleIdentifier)).tag(appID.identifier)
                            }
                        }
                    }
                }

                Section(header: Text(String(format: NSLocalizedString("Certificates (%d/%d)", comment: ""), selectedCertificateIDs.count, viewModel.certificates.count)), footer: Text("Select which development certificates are permitted to sign with this profile.")) {
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
                }

                Section(header: HStack {
                    Text(String(format: NSLocalizedString("Devices (%d/%d)", comment: ""), selectedDeviceIDs.count, viewModel.devices.count))
                    Spacer()
                    if !viewModel.devices.isEmpty {
                        SwiftUI.Button(selectedDeviceIDs.count == viewModel.devices.count ? "Deselect All" : "Select All") {
                            if selectedDeviceIDs.count == viewModel.devices.count {
                                selectedDeviceIDs.removeAll()
                            } else {
                                selectedDeviceIDs = Set(viewModel.devices.compactMap { $0.deviceID })
                            }
                        }
                        .font(.caption)
                    }
                }, footer: Text("Select registered test devices that can install apps signed with this profile.")) {
                    if viewModel.devices.isEmpty {
                        Text("No registered devices found on this team.")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    } else {
                        ForEach(viewModel.devices, id: \.identifier) { device in
                            let devID = device.deviceID ?? device.identifier
                            SwiftUI.Button {
                                if selectedDeviceIDs.contains(devID) {
                                    selectedDeviceIDs.remove(devID)
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
                                    if selectedDeviceIDs.contains(devID) {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.accentColor)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("New Manual Profile")
            .navigationBarItems(
                leading: SwiftUI.Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: SwiftUI.Button {
                    guard let appID = selectedAppID else { return }
                    Task {
                        let success = await viewModel.createManualProfile(
                            name: profileName.trimmingCharacters(in: .whitespacesAndNewlines),
                            appID: appID,
                            certificateIDs: Array(selectedCertificateIDs),
                            deviceIDs: Array(selectedDeviceIDs),
                            presentingViewController: presentingViewController
                        )
                        if success {
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                } label: {
                    if viewModel.isActionLoading {
                        ProgressView()
                    } else {
                        Text("Create")
                            .bold()
                    }
                }
                .disabled(!canSubmit)
            )
            .onAppear {
                if selectedAppIDIdentifier.isEmpty, let firstAppID = viewModel.appIDs.first {
                    selectedAppIDIdentifier = firstAppID.identifier
                    if profileName.isEmpty {
                        profileName = "\(firstAppID.name) Development"
                    }
                }
                if selectedCertificateIDs.isEmpty {
                    selectedCertificateIDs = Set(viewModel.certificates.compactMap { $0.identifier ?? $0.serialNumber })
                }
                if selectedDeviceIDs.isEmpty {
                    selectedDeviceIDs = Set(viewModel.devices.compactMap { $0.deviceID })
                }
            }
        }
    }
}
