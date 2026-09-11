//
//  AppIDDetailView.swift
//  SideStore
//
//  Created by Magesh K on 2/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import SideSign

struct AppIDDetailView: View {
    let appID: ALTAppID
    @ObservedObject var viewModel: DeveloperServicesViewModel
    weak var presentingViewController: UIViewController?

    @State private var selectedGroupIDs: Set<String> = []
    @State private var hasModifiedGroups = false
    @State private var isSavingGroups = false

    init(appID: ALTAppID, viewModel: DeveloperServicesViewModel, presentingViewController: UIViewController? = nil) {
        self.appID = appID
        self.viewModel = viewModel
        self.presentingViewController = presentingViewController
    }

    private var currentAppID: ALTAppID {
        viewModel.appIDs.first(where: { $0.identifier == appID.identifier }) ?? appID
    }

    var body: some View {
        List {
            Section(header: Text("App ID Metadata")) {
                InfoRow(label: "Name", value: currentAppID.name)
                InfoRow(label: "Bundle Identifier", value: currentAppID.bundleIdentifier)
                InfoRow(label: "App ID (Identifier)", value: currentAppID.identifier)
                if let expiration = currentAppID.expirationDate {
                    InfoRow(label: "Expiration Date", value: formatDate(expiration), valueColor: expiration < Date() ? .red : .primary)
                }
            }

            Section(header: Text(String(format: NSLocalizedString("Capabilities & Features (%d)", comment: ""), currentAppID.features.count))) {
                if currentAppID.features.isEmpty {
                    Text("No special features enabled for this App ID.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    let sortedFeatures = currentAppID.features.sorted { $0.key.rawValue < $1.key.rawValue }
                    ForEach(sortedFeatures, id: \.key.rawValue) { feature, value in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(displayName(for: feature))
                                    .font(.subheadline)
                                Text(feature.rawValue)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(value)
                                .font(.caption)
                                .foregroundColor(value == "true" ? .green : .secondary)
                        }
                    }
                }
            }

            Section(header: Text("Associated App Groups"), footer: Text("Select the App Groups to associate with this App ID, then tap Save.")) {
                if viewModel.appGroups.isEmpty {
                    Text("No App Groups available on this team. Create an App Group first.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(viewModel.appGroups, id: \.identifier) { group in
                        SwiftUI.Button {
                            if selectedGroupIDs.contains(group.identifier) {
                                selectedGroupIDs.remove(group.identifier)
                            } else {
                                selectedGroupIDs.insert(group.identifier)
                            }
                            hasModifiedGroups = true
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group.name)
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                    Text(group.identifier)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if selectedGroupIDs.contains(group.identifier) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.accentColor)
                                        .imageScale(.large)
                                } else {
                                    Image(systemName: "circle")
                                        .foregroundColor(.secondary)
                                        .imageScale(.large)
                                }
                            }
                        }
                    }

                    if hasModifiedGroups {
                        SwiftUI.Button {
                            let groupsToAssign = viewModel.appGroups.filter { selectedGroupIDs.contains($0.identifier) }
                            Task {
                                isSavingGroups = true
                                let success = await viewModel.updateAppGroups(for: currentAppID, to: groupsToAssign, presentingViewController: presentingViewController)
                                isSavingGroups = false
                                if success {
                                    hasModifiedGroups = false
                                }
                            }
                        } label: {
                            HStack {
                                Spacer()
                                if isSavingGroups {
                                    ProgressView()
                                        .padding(.trailing, 8)
                                }
                                Text("Save Group Associations")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }
                        .disabled(isSavingGroups)
                    }
                }
            }

            Section(header: Text("Actions")) {
                SwiftUI.Button {
                    Task {
                        _ = await viewModel.downloadProfile(for: currentAppID, presentingViewController: presentingViewController)
                    }
                } label: {
                    HStack {
                        Image(systemName: "arrow.down.doc")
                        Text("Download Provisioning Profile")
                    }
                }
            }
        }
        #if !os(tvOS)
        .listStyle(InsetGroupedListStyle())
        #else
        .listStyle(GroupedListStyle())
        #endif
        .navigationTitle(currentAppID.name.isEmpty ? NSLocalizedString("App ID Details", comment: "") : currentAppID.name)
        .onAppear {
            initializeSelectedGroups()
        }
        .refreshable {
            async let fetchIDs: () = viewModel.fetchAppIDs(presentingViewController: presentingViewController, isPullToRefresh: true)
            async let fetchGroups: () = viewModel.fetchAppGroups(presentingViewController: presentingViewController, isPullToRefresh: true)
            _ = await (fetchIDs, fetchGroups)
        }
        .developerServicesToast(viewModel: viewModel)
    }

    private func initializeSelectedGroups() {
        var initial = Set<String>()
        let appGroupFeatureKey = Feature.appGroups.rawValue
        if currentAppID.features.keys.contains(where: { $0.rawValue == appGroupFeatureKey }) {
            for group in viewModel.appGroups {
                initial.insert(group.identifier)
            }
        }
        self.selectedGroupIDs = initial
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func displayName(for feature: Feature) -> String {
        switch feature {
        case .appGroups: return "App Groups"
        case .gameCenter: return "Game Center"
        case .inAppPurchase: return "In-App Purchase"
        case .pushNotifications: return "Push Notifications"
        case .interAppAudio: return "Inter-App Audio"
        case .associatedDomains: return "Associated Domains"
        case .dataProtection: return "Data Protection"
        case .siri: return "Siri"
        case .applePay: return "Apple Pay"
        case .vpn: return "Personal VPN"
        case .networkExtensions: return "Network Extensions"
        case .multipath: return "Multipath"
        case .hotspot: return "Hotspot"
        case .nfc: return "NFC Tag Reading"
        case .classKit: return "ClassKit"
        case .autoFillCredentialProvider: return "AutoFill Credential Provider"
        case .accessWiFiInformation: return "Access WiFi Information"
        case .wirelessAccessoryConfiguration: return "Wireless Accessory Config"
        case .increasedMemoryLimit: return "Increased Memory Limit"
        case .extendedVirtualAddressing: return "Extended Virtual Addressing"
        case .increasedDebuggingMemoryLimit: return "Increased Debugging Memory Limit"
        default: return feature.rawValue
        }
    }
}
