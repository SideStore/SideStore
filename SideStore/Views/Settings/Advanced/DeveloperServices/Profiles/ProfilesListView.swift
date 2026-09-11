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
    @State private var showCreateProfileSheet = false

    @State private var profileToDelete: ALTListedProvisioningProfile? = nil
    @State private var showDeleteConfirmation = false
    @State private var showPurgeAllConfirmation = false

    private var filteredProfiles: [ALTListedProvisioningProfile] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return viewModel.profiles
        }
        return viewModel.profiles.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            ($0.bundleIdentifier?.localizedCaseInsensitiveContains(searchText) == true) ||
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
                        Text(searchText.isEmpty ? NSLocalizedString("No Provisioning Profiles found on Developer Portal.", comment: "") : NSLocalizedString("No matching Provisioning Profiles found.", comment: ""))
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    }
                } else {
                    ForEach(filteredProfiles, id: \.uuid) { profile in
                        NavigationLink(destination: ProfilePortalDetailView(profile: profile, viewModel: viewModel, presentingViewController: presentingViewController)) {
                            ProfileRow(profile: profile, formatDate: formatDate)
                        }
                        #if !os(tvOS)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            SwiftUI.Button(role: .destructive) {
                                profileToDelete = profile
                                showDeleteConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        #endif
                        .contextMenu {
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
                    showCreateProfileSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .refreshable {
            await viewModel.fetchProfiles(presentingViewController: presentingViewController, isPullToRefresh: true)
        }
        .sheet(isPresented: $showCreateProfileSheet) {
            CreateManualProfileView(viewModel: viewModel, presentingViewController: presentingViewController)
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
    let profile: ALTListedProvisioningProfile
    let formatDate: (Date) -> String

    private var isExpired: Bool {
        profile.dateExpire < Date()
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
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.15))
                        .foregroundColor(.red)
                        .cornerRadius(6)
                }
                Text(String(format: NSLocalizedString("Expires: %@", comment: ""), formatDate(profile.dateExpire)))
                    .font(.caption)
                    .foregroundColor(isExpired ? .red : .secondary)
            }

            HStack {
                if let bundleID = profile.bundleIdentifier {
                    Text(bundleID)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if let type = profile.profileType {
                    Text(type.rawValue.uppercased())
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12))
                        .foregroundColor(.secondary)
                        .cornerRadius(6)
                }
                if let isTeam = profile.isTeamProfile {
                    Text(isTeam ? NSLocalizedString("Xcode Managed", comment: "") : NSLocalizedString("Manual", comment: ""))
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isTeam ? Color.blue.opacity(0.12) : Color.purple.opacity(0.12))
                        .foregroundColor(isTeam ? .blue : .purple)
                        .cornerRadius(6)
                }
            }

            Text(profile.uuid.uuidString)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.8))
        }
        .padding(.vertical, 2)
    }
}

