//
//  DeveloperServicesView.swift
//  SideStore
//
//  Created by Magesh K on 2/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import SideSign

struct DeveloperServicesView: View {
    @StateObject private var viewModel = DeveloperServicesViewModel()
    weak var presentingViewController: UIViewController?

    init(presentingViewController: UIViewController? = nil) {
        self.presentingViewController = presentingViewController
    }

    var body: some View {
        ZStack {
            List {
                if let team = viewModel.team {
                    Section(header: Text("Developer Account")) {
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 36))
                                .foregroundColor(.accentColor)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(team.name)
                                    .font(.headline)
                                Text(String(format: NSLocalizedString("Team ID: %@", comment: ""), team.identifier))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Text(team.type.displayName)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.15))
                                .foregroundColor(.secondary)
                                .cornerRadius(8)
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section(header: Text("Developer Portal Services")) {
                    NavigationLink(destination: AppIDsListView(viewModel: viewModel, presentingViewController: presentingViewController)) {
                        HStack(spacing: 14) {
                            Image(systemName: "app.badge.checkmark")
                                .font(.system(size: 20))
                                .foregroundColor(.blue)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("App IDs")
                                    .font(.body)
                                Text(String(format: NSLocalizedString("%d registered", comment: ""), viewModel.appIDs.count))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    NavigationLink(destination: ProfilesListView(viewModel: viewModel, presentingViewController: presentingViewController)) {
                        HStack(spacing: 14) {
                            Image(systemName: "doc.plaintext")
                                .font(.system(size: 20))
                                .foregroundColor(.orange)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Provisioning Profiles")
                                    .font(.body)
                                Text(String(format: NSLocalizedString("%d active on portal", comment: ""), viewModel.profiles.count))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    NavigationLink(destination: AppGroupsListView(viewModel: viewModel, presentingViewController: presentingViewController)) {
                        HStack(spacing: 14) {
                            Image(systemName: "person.2")
                                .font(.system(size: 20))
                                .foregroundColor(.green)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("App Groups")
                                    .font(.body)
                                Text(String(format: NSLocalizedString("%d configured", comment: ""), viewModel.appGroups.count))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    NavigationLink(destination: DevicesListView(viewModel: viewModel, presentingViewController: presentingViewController)) {
                        HStack(spacing: 14) {
                            Image(systemName: "iphone.and.arrow.forward")
                                .font(.system(size: 20))
                                .foregroundColor(.purple)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Registered Devices")
                                    .font(.body)
                                Text(String(format: NSLocalizedString("%d devices", comment: ""), viewModel.devices.count))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            #if !os(tvOS)
            .listStyle(InsetGroupedListStyle())
            #else
            .listStyle(GroupedListStyle())
            #endif

            if viewModel.isLoading && viewModel.appIDs.isEmpty && viewModel.profiles.isEmpty {
                Color.black.opacity(0.15)
                    .edgesIgnoringSafeArea(.all)
                ProgressView("Connecting to Developer Portal...")
                    .padding()
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                    .shadow(radius: 6)
            }
        }
        .navigationTitle("Developer Portal")
        .onAppear {
            if viewModel.appIDs.isEmpty && viewModel.profiles.isEmpty {
                Task {
                    await viewModel.loadAll(presentingViewController: presentingViewController)
                }
            }
        }
        .refreshable {
            await viewModel.loadAll(presentingViewController: presentingViewController, isPullToRefresh: true)
        }
        .alert(isPresented: $viewModel.showErrorAlert) {
            Alert(
                title: Text("Developer Portal Error"),
                message: Text(viewModel.errorMessage ?? "An unknown error occurred."),
                dismissButton: .default(Text("OK"))
            )
        }
        .developerServicesToast(viewModel: viewModel)
    }
}

extension View {
    func developerServicesToast(viewModel: DeveloperServicesViewModel) -> some View {
        self.overlay(
            DeveloperServicesToastView(isShowing: Binding(
                get: { viewModel.showToast },
                set: { viewModel.showToast = $0 }
            ), message: viewModel.toastMessage)
        )
    }
}

struct DeveloperServicesToastView: View {
    @Binding var isShowing: Bool
    let message: String

    var body: some View {
        VStack {
            Spacer()
            if isShowing {
                Text(message)
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(UIColor.label).opacity(0.85))
                    .foregroundColor(Color(UIColor.systemBackground))
                    .cornerRadius(20)
                    .shadow(radius: 5)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            withAnimation {
                                isShowing = false
                            }
                        }
                    }
            }
        }
        .padding(.bottom, 24)
        .animation(.easeInOut, value: isShowing)
    }
}
