//
//  ProfilesListView.swift
//  SideStore
//
//  Created by Magesh K on 2/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import SideSign

struct ProfilesListView: View {
    @ObservedObject var viewModel: DeveloperServicesViewModel
    weak var presentingViewController: UIViewController?

    @State private var searchText = ""
    @State private var showDownloadSheet = false
    @State private var selectedAppIDForDownload: ALTAppID? = nil

    @State private var profileToDelete: ALTProvisioningProfile? = nil
    @State private var showDeleteConfirmation = false
    @State private var showPurgeAllConfirmation = false

    private var filteredProfiles: [ALTProvisioningProfile] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return viewModel.profiles
        }
        return viewModel.profiles.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.bundleIdentifier.localizedCaseInsensitiveContains(searchText) ||
            $0.uuid.uuidString.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List {
            Section(header: Text(String(format: NSLocalizedString("Provisioning Profiles (%d)", comment: ""), viewModel.profiles.count)), footer: Text("Deleting profiles on the developer portal allows Apple to issue fresh profiles with updated certificates and unflagged UUIDs.")) {
                if filteredProfiles.isEmpty {
                    if viewModel.isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    } else {
                        Text(searchText.isEmpty ? "No Provisioning Profiles found on Developer Portal." : "No matching Provisioning Profiles found.")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    }
                } else {
                    ForEach(filteredProfiles, id: \.uuid) { profile in
                        NavigationLink(destination: ProfilePortalDetailView(profile: profile, viewModel: viewModel, presentingViewController: presentingViewController)) {
                            ProfileRow(profile: profile, formatDate: formatDate)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            SwiftUI.Button(role: .destructive) {
                                profileToDelete = profile
                                showDeleteConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            if !viewModel.profiles.isEmpty {
                Section {
                    SwiftUI.Button(role: .destructive) {
                        showPurgeAllConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Image(systemName: "trash")
                            Text("Delete All Profiles on Portal")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                }
            }
        }
        #if !os(tvOS)
        .listStyle(InsetGroupedListStyle())
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search Profiles")
        #else
        .listStyle(GroupedListStyle())
        #endif
        .navigationTitle("Profiles")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                SwiftUI.Button {
                    showDownloadSheet = true
                } label: {
                    Image(systemName: "arrow.down.doc")
                }
            }
        }
        .refreshable {
            await viewModel.fetchProfiles(presentingViewController: presentingViewController, isPullToRefresh: true)
        }
        .sheet(isPresented: $showDownloadSheet) {
            NavigationView {
                List {
                    Section(header: Text("Select App ID to Generate Profile")) {
                        if viewModel.appIDs.isEmpty {
                            Text("No App IDs available. Register an App ID first.")
                                .foregroundColor(.secondary)
                                .font(.subheadline)
                        } else {
                            ForEach(viewModel.appIDs, id: \.identifier) { appID in
                                SwiftUI.Button {
                                    Task {
                                        showDownloadSheet = false
                                        _ = await viewModel.downloadProfile(for: appID, presentingViewController: presentingViewController)
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(appID.name.isEmpty ? "App ID" : appID.name)
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        Text(appID.bundleIdentifier)
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                    }
                }
                #if !os(tvOS)
                .listStyle(InsetGroupedListStyle())
                #else
                .listStyle(GroupedListStyle())
                #endif
                .navigationTitle("Download Profile")
                .navigationBarItems(trailing: SwiftUI.Button("Cancel") {
                    showDownloadSheet = false
                })
            }
        }
        .alert(isPresented: $showDeleteConfirmation) {
            Alert(
                title: Text("Delete Provisioning Profile?"),
                message: Text(String(format: NSLocalizedString("Are you sure you want to delete '%@' from the Apple Developer Portal?", comment: ""), profileToDelete?.name ?? "this profile")),
                primaryButton: .destructive(Text("Delete")) {
                    if let target = profileToDelete {
                        Task {
                            _ = await viewModel.deleteProfile(target, presentingViewController: presentingViewController)
                        }
                    }
                },
                secondaryButton: .cancel()
            )
        }
        .alert("Purge All Profiles?", isPresented: $showPurgeAllConfirmation) {
            SwiftUI.Button(String(format: NSLocalizedString("Delete All (%d)", comment: ""), viewModel.profiles.count), role: .destructive) {
                Task {
                    _ = await viewModel.deleteAllProfiles(presentingViewController: presentingViewController)
                }
            }
            SwiftUI.Button("Cancel", role: .cancel) {}
        } message: {
            Text(String(format: NSLocalizedString("This will permanently delete all %d provisioning profile(s) for team '%@' on Apple's developer portal. SideStore will automatically generate fresh profiles on next app install or refresh.", comment: ""), viewModel.profiles.count, viewModel.team?.name ?? ""))
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

private struct ProfileRow: View {
    let profile: ALTProvisioningProfile
    let formatDate: (Date) -> String

    private var isExpired: Bool {
        profile.expirationDate < Date()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(profile.name)
                    .font(.headline)
                Spacer()
                if isExpired {
                    Text("Expired")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.15))
                        .foregroundColor(.red)
                        .cornerRadius(6)
                }
            }
            Text(profile.bundleIdentifier)
                .font(.subheadline)
                .foregroundColor(.secondary)
            HStack {
                Text(String(format: NSLocalizedString("UUID: %@...", comment: ""), String(profile.uuid.uuidString.prefix(8))))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(String(format: NSLocalizedString("Expires: %@", comment: ""), formatDate(profile.expirationDate)))
                    .font(.caption)
                    .foregroundColor(isExpired ? .red : .secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

