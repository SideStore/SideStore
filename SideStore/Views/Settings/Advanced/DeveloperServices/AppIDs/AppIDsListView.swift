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
                        Text(searchText.isEmpty ? "No App IDs registered on Developer Portal." : "No matching App IDs found.")
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
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
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
                title: Text("Delete App ID?"),
                message: Text(String(format: NSLocalizedString("Are you sure you want to delete '%@' (%@)? This will also remove any associated provisioning profiles.", comment: ""), appIDToDelete?.name ?? "this App ID", appIDToDelete?.bundleIdentifier ?? "")),
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

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
