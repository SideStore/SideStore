//
//  AppIDsListView.swift
//  SideStore
//
//  Created by Magesh K on 2/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import SideSign

struct AppIDsListView: View {
    @ObservedObject var viewModel: DeveloperServicesViewModel
    weak var presentingViewController: UIViewController?

    @State private var searchText = ""
    @State private var showRegisterSheet = false
    @State private var newAppIDName = ""
    @State private var newAppIDBundleID = ""

    @State private var appIDToDelete: ALTAppID? = nil
    @State private var showDeleteConfirmation = false

    private var filteredAppIDs: [ALTAppID] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return viewModel.appIDs
        }
        return viewModel.appIDs.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.bundleIdentifier.localizedCaseInsensitiveContains(searchText) ||
            $0.identifier.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List {
            Section(header: Text(String(format: NSLocalizedString("Registered App IDs (%d)", comment: ""), viewModel.appIDs.count))) {
                if filteredAppIDs.isEmpty {
                    if viewModel.isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    } else {
                        Text(searchText.isEmpty ? NSLocalizedString("No App IDs registered on Developer Portal.", comment: "") : NSLocalizedString("No matching App IDs found.", comment: ""))
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    }
                } else {
                    ForEach(filteredAppIDs, id: \.identifier) { appID in
                        NavigationLink(destination: AppIDDetailView(appID: appID, viewModel: viewModel, presentingViewController: presentingViewController)) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(appID.name.isEmpty ? "App ID" : appID.name)
                                        .font(.headline)
                                    Spacer()
                                    if !appID.features.isEmpty {
                                        Text(String(format: NSLocalizedString("%d features", comment: ""), appID.features.count))
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.accentColor.opacity(0.15))
                                            .foregroundColor(.accentColor)
                                            .cornerRadius(6)
                                    }
                                }
                                Text(appID.bundleIdentifier)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                HStack {
                                    Text(String(format: NSLocalizedString("ID: %@", comment: ""), appID.identifier))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    if let expiration = appID.expirationDate {
                                        Text(String(format: NSLocalizedString("Expires: %@", comment: ""), formatDate(expiration)))
                                            .font(.caption)
                                            .foregroundColor(expiration < Date() ? .red : .secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        #if !os(tvOS)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            SwiftUI.Button(role: .destructive) {
                                appIDToDelete = appID
                                showDeleteConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        #endif
                        .contextMenu {
                            SwiftUI.Button(role: .destructive) {
                                appIDToDelete = appID
                                showDeleteConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        #if !os(tvOS)
        .listStyle(InsetGroupedListStyle())
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search App IDs")
        #else
        .listStyle(GroupedListStyle())
        #endif
        .navigationTitle("App IDs")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                SwiftUI.Button {
                    showRegisterSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .refreshable {
            await viewModel.fetchAppIDs(presentingViewController: presentingViewController, isPullToRefresh: true)
        }
        .sheet(isPresented: $showRegisterSheet) {
            NavigationView {
                Form {
                    Section(header: Text("App ID Information"), footer: Text("Bundle ID must match reverse-DNS format (e.g. com.example.myapp).")) {
                        TextField("Name (e.g. My App)", text: $newAppIDName)
                        TextField("Bundle Identifier", text: $newAppIDBundleID)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }
                }
                .navigationTitle("Register App ID")
                .navigationBarItems(
                    leading: SwiftUI.Button("Cancel") {
                        newAppIDName = ""
                        newAppIDBundleID = ""
                        showRegisterSheet = false
                    },
                    trailing: SwiftUI.Button("Register") {
                        let name = newAppIDName.trimmingCharacters(in: .whitespacesAndNewlines)
                        let bundleID = newAppIDBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty, !bundleID.isEmpty else { return }
                        Task {
                            let success = await viewModel.createAppID(name: name, bundleIdentifier: bundleID, presentingViewController: presentingViewController)
                            if success {
                                newAppIDName = ""
                                newAppIDBundleID = ""
                                showRegisterSheet = false
                            }
                        }
                    }
                    .disabled(newAppIDName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              newAppIDBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              viewModel.isActionLoading)
                )
            }
        }
        .alert(isPresented: $showDeleteConfirmation) {
            Alert(
                title: Text(viewModel.isPaidAccount ? NSLocalizedString("Delete App ID?", comment: "") : NSLocalizedString("Warning: Delete App ID?", comment: "")),
                message: Text(deleteAlertMessage),
                primaryButton: .destructive(Text("Delete")) {
                    if let target = appIDToDelete {
                        Task {
                            _ = await viewModel.deleteAppID(target, presentingViewController: presentingViewController)
                        }
                    }
                },
                secondaryButton: .cancel()
            )
        }
        .developerServicesToast(viewModel: viewModel)
    }

    private var deleteAlertMessage: String {
        guard let appID = appIDToDelete else { return "" }
        let name = appID.name.isEmpty ? NSLocalizedString("this App ID", comment: "") : "'\(appID.name)'"
        let bundleID = appID.bundleIdentifier.isEmpty ? "" : " (\(appID.bundleIdentifier))"

        if viewModel.isPaidAccount {
            return String(format: NSLocalizedString("Are you sure you want to delete %@%@? This will also remove any associated provisioning profiles.", comment: ""), name, bundleID)
        }

        if let expiration = appID.expirationDate {
            let calendar = Calendar.current
            let components = calendar.dateComponents([.day], from: Date(), to: expiration)
            if let days = components.day, days > 0 {
                return String(format: NSLocalizedString("Warning: Deleting %1$@%2$@ does not free up an App ID slot.\n\nThis App ID will become reserved and will not be available for use until it expires automatically in %3$d day(s) (from its usual 7-day validity).\n\nAre you sure you want to delete it?", comment: ""), name, bundleID, days)
            }
        }

        return String(format: NSLocalizedString("Warning: Deleting %@%@ does not free up an App ID slot.\n\nThis App ID will become reserved and will not be available for use until it expires automatically after the remaining days of its usual 7-day validity.\n\nAre you sure you want to delete it?", comment: ""), name, bundleID)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
