//
//  PairingFileManagementView.swift
//  SideStore
//
//  Created by Magesh K on 19/09/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import UniformTypeIdentifiers
import MinimuxerCommon

private extension Color {
    static let settingsRowBackground = Color.white.opacity(0.15)
    static let settingsDivider = Color.white.opacity(0.15)
}

struct PairingFileManagementView: View {
    @StateObject private var viewModel = PairingFileManagementViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                activeProtocolSection
                pairingFilesSection
                pairingMethodsSection
                managementSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .background(Color(uiColor: .settingsBackground).ignoresSafeArea())
        .navigationTitle("Pairing File Management")
        #if !os(tvOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                SwiftUI.Button {
                    viewModel.toggleGlobalHide()
                } label: {
                    Image(systemName: viewModel.isGlobalHideActive ? "eye.slash" : "eye")
                }
                .accessibilityLabel("Toggle Sensitive Information")
            }
        }
        .onAppear {
            viewModel.refresh()
        }
        #if !os(tvOS)
        .fileImporter(
            isPresented: $viewModel.showFileImporter,
            allowedContentTypes: viewModel.allowedPairingTypes
        ) { result in
            viewModel.handleImportResult(result)
        }
        #endif
        .alert(item: $viewModel.activeAlert) { alert in
            switch alert {
            case .deleteConfirmation(let proto):
                return Alert(
                    title: Text("Delete Pairing File?"),
                    message: Text(LocalizedStringKey("Are you sure you want to delete this pairing file? This will remove the pairing credentials for **\(proto.rawValue)**.")),
                    primaryButton: .destructive(Text("Delete")) {
                        viewModel.deletePairingFile(for: proto)
                    },
                    secondaryButton: .cancel()
                )
            case .resetConfirmation:
                return Alert(
                    title: Text("Reset Pairing Files?"),
                    message: Text(LocalizedStringKey("This will delete all stored pairing files (both **Lockdown** and **Remote Pairing**). You will need to re-pair or re-import a pairing file and restart SideStore.")),
                    primaryButton: .destructive(Text("Delete and Reset")) {
                        viewModel.resetAllPairingFiles()
                    },
                    secondaryButton: .cancel()
                )
            case .resetCompleted:
                return Alert(
                    title: Text("Pairing Files Reset"),
                    message: Text("All pairing files have been reset. Please restart SideStore."),
                    dismissButton: .default(Text("OK"))
                )
            case .importError(let msg):
                return Alert(
                    title: Text("Import Error"),
                    message: Text(LocalizedStringKey(msg)),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private var activeProtocolSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ACTIVE PROTOCOL")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.6))
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                HStack {
                    Text("Active Protocol")
                        .font(.system(size: 16))
                        .foregroundColor(.white)

                    Spacer()

                    HStack(spacing: 6) {
                        Circle()
                            .fill(ledColor(for: viewModel.activeProtocol))
                            .frame(width: 7, height: 7)
                            .shadow(color: ledColor(for: viewModel.activeProtocol).opacity(0.8), radius: 3)

                        Text(activeProtocolTagText(for: viewModel.activeProtocol))
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
                }
                .padding(.horizontal, 16)
                .frame(height: 50)

                Divider()
                    .background(Color.settingsDivider)
                    .padding(.horizontal, 16)

                HStack {
                    Text("Preferred Protocol")
                        .font(.system(size: 16))
                        .foregroundColor(.white)

                    Spacer()

                    HStack(spacing: 6) {
                        Circle()
                            .fill(viewModel.preferredProtocol != nil ? ledColor(for: viewModel.preferredProtocol!) : Color.gray)
                            .frame(width: 7, height: 7)
                            .shadow(color: (viewModel.preferredProtocol != nil ? ledColor(for: viewModel.preferredProtocol!) : Color.gray).opacity(0.8), radius: 3)

                        Text(viewModel.preferredProtocol != nil ? activeProtocolTagText(for: viewModel.preferredProtocol!) : "None")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
                }
                .padding(.horizontal, 16)
                .frame(height: 50)
                .contextMenu {
                    if viewModel.preferredProtocol != nil {
                        SwiftUI.Button(role: .destructive) {
                            viewModel.clearPreferred()
                        } label: {
                            Label("Clear Preferred Protocol", systemImage: "star.slash")
                        }
                    }
                }
            }
            .background(Color.settingsRowBackground)
            .cornerRadius(14)
        }
    }

    private var pairingFilesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PAIRING FILES")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.6))
                .padding(.horizontal, 4)

            VStack(spacing: 12) {
                ForEach(viewModel.supportedProtocols, id: \.rawValue) { proto in
                    pairingFileCard(for: proto)
                }
            }
        }
    }

    private func pairingFileCard(for proto: PairingProtocol) -> some View {
        let fileURL = PairingFileManager.shared.pairingFileURL(for: proto)
        let metadata = PairingFileManager.shared.metadata(for: proto)
        let isInstalled = metadata.exists
        let content = isInstalled ? PairingFileManager.shared.fetchPairingFile(for: proto) : nil

        let parsed = content != nil ? (try? PairingFileManager.shared.parse(content: content!, preferred: proto)) : nil
        let remoteRP = parsed as? RPPairingFile
        let lockdown = parsed as? LockdownPairingFile
        let isValid = parsed != nil

        let fileSize = metadata.size
        let creationDate = metadata.creationDate
        let modDate = metadata.modificationDate

        return VStack(alignment: .leading, spacing: 0) {
            if isInstalled {
                NavigationLink(destination: PairingFileDetailView(mode: proto)) {
                    installedCardHeader(for: proto, isValid: isValid)
                }
                .contextMenu {
                    if isValid {
                        if UserDefaults.standard.isMinimuxerBackendHotswapEnabled && proto != viewModel.activeProtocol {
                            SwiftUI.Button {
                                Task {
                                    await viewModel.activate(proto: proto)
                                }
                            } label: {
                                Label("Activate", systemImage: "bolt.fill")
                            }
                        }

                        if proto != viewModel.preferredProtocol {
                            SwiftUI.Button {
                                viewModel.setPreferred(proto: proto)
                            } label: {
                                Label("Set as Preferred", systemImage: "star.fill")
                            }
                        } else {
                            SwiftUI.Button {
                                viewModel.clearPreferred()
                            } label: {
                                Label("Remove as Preferred", systemImage: "star.slash")
                            }
                        }

                        if proto == viewModel.activeProtocol {
                            SwiftUI.Button { } label: {
                                Label("Currently Active", systemImage: "checkmark.circle.fill")
                            }
                            .disabled(true)
                        }
                    }

                    SwiftUI.Button {
                        viewModel.promptImport(for: proto)
                    } label: {
                        Label("Import / Replace File", systemImage: "square.and.arrow.down")
                    }

                    SwiftUI.Button(role: .destructive) {
                        viewModel.confirmDelete(for: proto)
                    } label: {
                        Label("Delete Pairing File", systemImage: "trash")
                    }
                }

                divider

                VStack(spacing: 0) {
                    infoRow(label: "File Name", value: fileURL.lastPathComponent, isMonospaced: true)
                    divider
                    if proto == viewModel.activeProtocol || proto == viewModel.preferredProtocol {
                        protocolStatusRow(for: proto)
                        divider
                    }
                    if proto == .rppairing {
                        if let id = remoteRP?.identifier, !id.isEmpty {
                            identifierRow(label: "Identifier", value: id, fieldKey: "rp_identifier")
                            divider
                        }
                        infoRow(label: "Key Material", value: (remoteRP?.publicKey != nil && remoteRP?.privateKey != nil) ? "Public & Private Keys OK" : "Incomplete Keys")
                        divider
                    } else {
                        if let sysBUID = lockdown?.systemBUID, !sysBUID.isEmpty {
                            identifierRow(label: "SystemBUID", value: sysBUID, fieldKey: "lockdown_sysbuid")
                            divider
                        }
                        if let hostID = lockdown?.hostID, !hostID.isEmpty {
                            identifierRow(label: "HostID", value: hostID, fieldKey: "lockdown_hostid")
                            divider
                        }
                        if let udid = lockdown?.udid, !udid.isEmpty {
                            identifierRow(label: "Hardware UDID", value: udid, fieldKey: "lockdown_udid")
                            divider
                        }
                        if let wifi = lockdown?.wifiMACAddress, !wifi.isEmpty {
                            identifierRow(label: "WiFi MAC", value: wifi, fieldKey: "lockdown_wifi")
                            divider
                        }
                    }

                    infoRow(label: "File Size", value: ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))
                    if let created = creationDate {
                        divider
                        infoRow(label: "Date Created", value: formatDate(created))
                    }
                    if let mod = modDate {
                        divider
                        infoRow(label: "Date Modified", value: formatDate(mod))
                    }
                }
            } else {
                SwiftUI.Button {
                    viewModel.promptImport(for: proto)
                } label: {
                    VStack(spacing: 0) {
                        missingCardHeader(for: proto)
                        divider
                        infoRow(label: "File Name", value: fileURL.lastPathComponent, isMonospaced: true)
                    }
                }
                .buttonStyle(.plain)
                .contextMenu {
                    SwiftUI.Button {
                        viewModel.promptImport(for: proto)
                    } label: {
                        Label("Import Pairing File", systemImage: "square.and.arrow.down")
                    }
                }
            }
        }
        .background(Color.settingsRowBackground)
        .cornerRadius(14)
    }

    private func installedCardHeader(for proto: PairingProtocol, isValid: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: proto == .rppairing ? "bolt.horizontal.circle.fill" : "lock.shield.fill")
                .font(.system(size: 22))
                .foregroundColor(proto == .rppairing ? .cyan : .green)

            Text(proto == .rppairing ? "Remote Pairing File" : "Lockdown Pairing File")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)

            Spacer()

            if isValid {
                Text("Configured")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.15))
                    .cornerRadius(6)
            } else {
                Text("Invalid")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.15))
                    .cornerRadius(6)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.3))
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
    }

    private func missingCardHeader(for proto: PairingProtocol) -> some View {
        HStack(spacing: 12) {
            Image(systemName: proto == .rppairing ? "bolt.horizontal.circle" : "lock.shield")
                .font(.system(size: 22))
                .foregroundColor(Color.white.opacity(0.3))

            Text(proto == .rppairing ? "Remote Pairing File" : "Lockdown Pairing File")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Color.white.opacity(0.8))

            Spacer()

            Text("Missing")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.red)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.red.opacity(0.15))
                .cornerRadius(6)

            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.accentColor)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
    }

    private func identifierRow(label: String, value: String, fieldKey: String) -> some View {
        let isRevealed = !viewModel.isGlobalHideActive || viewModel.revealedFieldKeys.contains(fieldKey)
        let displayValue = isRevealed ? value : "••••••••••••••••"

        return SwiftUI.Button {
            viewModel.toggleReveal(for: fieldKey)
        } label: {
            HStack {
                Text(label)
                    .font(.system(size: 14))
                    .foregroundColor(Color.white.opacity(0.6))
                Spacer()
                Text(displayValue)
                    .font(.system(size: 13, weight: .medium, design: isRevealed ? .monospaced : .default))
                    .foregroundColor(Color.white.opacity(0.9))
            }
            .padding(.horizontal, 16)
            .frame(height: 40)
        }
        .buttonStyle(.plain)
    }

    private func infoRow(label: String, value: String, isMonospaced: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(Color.white.opacity(0.6))
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium, design: isMonospaced ? .monospaced : .default))
                .foregroundColor(Color.white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
    }

    @ViewBuilder
    private func protocolStatusRow(for proto: PairingProtocol) -> some View {
        HStack {
            Text("Status")
                .font(.system(size: 14))
                .foregroundColor(Color.white.opacity(0.6))

            Spacer()

            HStack(spacing: 8) {
                if proto == viewModel.activeProtocol {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(ledColor(for: proto))
                            .frame(width: 7, height: 7)
                            .shadow(color: ledColor(for: proto).opacity(0.8), radius: 3)

                        Text("Active")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
                }

                if proto == viewModel.preferredProtocol {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.yellow)
                            .frame(width: 7, height: 7)
                            .shadow(color: Color.yellow.opacity(0.8), radius: 3)

                        Text("Preferred")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
    }

    private var pairingMethodsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PAIRING METHODS")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.6))
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                NavigationLink(destination: WirelessPairView()) {
                    HStack(spacing: 12) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                        Text("Wireless Pairing")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.white)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color.white.opacity(0.4))
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 50)
                }
            }
            .background(Color.settingsRowBackground)
            .cornerRadius(14)
        }
    }

    private var managementSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MANAGEMENT")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.6))
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                SwiftUI.Button(action: {
                    viewModel.confirmReset()
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.counterclockwise.circle")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.red)
                        Text("Reset Pairing Files")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.red)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 50)
                }
            }
            .background(Color.settingsRowBackground)
            .cornerRadius(14)

            Text("Resetting pairing files removes stored Lockdown and Remote Pairing credentials. You will need to re-pair or re-import a pairing file and restart SideStore.")
                .font(.system(size: 12))
                .foregroundColor(Color.white.opacity(0.5))
                .padding(.horizontal, 4)
                .padding(.top, 4)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.settingsDivider)
            .frame(height: 1)
            .padding(.leading, 16)
    }

    private func ledColor(for proto: PairingProtocol) -> Color {
        switch proto {
        case .lockdown:
            return .green
        case .rppairing:
            return .cyan
        case .unknown:
            return .orange
        }
    }

    private func activeProtocolTagText(for proto: PairingProtocol) -> String {
        switch proto {
        case .lockdown:
            return "lockdown"
        case .rppairing:
            return "rppairing"
        case .unknown:
            return "unknown"
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
