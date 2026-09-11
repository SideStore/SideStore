//
//  CertificatesListView.swift
//  SideStore
//
//  Created by Magesh K on 2026-07-03.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import SideSign

struct CertificatesListView: View {
    @ObservedObject var viewModel: CertificatesViewModel
    
    var onRowTap:     (ALTX509Certificate) -> Void
    var onRevoke:     (ALTX509Certificate) -> Void
    var onExportP12:  (ALTX509Certificate) -> Void
    var onClearKey:   (ALTX509Certificate) -> Void
    var onAddKeyBin:  (ALTX509Certificate) -> Void
    var onAddKeyText: (ALTX509Certificate) -> Void
    var onDelete:     (ALTX509Certificate) -> Void
    
    var body: some View {
        if viewModel.certificates.isEmpty {
            Section(header: Text("All Certificates")) {
                if viewModel.isLoading {
                    Text("Fetching certificates...").foregroundColor(.secondary)
                } else {
                    Text("No local certificates found.").foregroundColor(.secondary)
                }
            }
        } else {
            ForEach(viewModel.groupedCertificatesList) { group in
                Section {
                    ForEach(group.certificates, id: \.serialNumber) { cert in
                        AdaptiveTappableRow {
                            onRowTap(cert)
                        } content: {
                            CertificateRowView(
                                cert:        cert,
                                viewModel:   viewModel,
                                onRevoke:    { onRevoke(cert) },
                                onExportP12: { onExportP12(cert) },
                                onClearKey:  { onClearKey(cert) },
                                onAddKeyBin: { onAddKeyBin(cert) },
                                onAddKeyText:{ onAddKeyText(cert) },
                                onDelete:    { onDelete(cert) }
                            )
                        }
                        #if !os(tvOS)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if viewModel.remoteSerials.contains(cert.serialNumber) {
                                SwiftUI.Button(role: .destructive) {
                                    onRevoke(cert)
                                } label: {
                                    Label("Revoke", systemImage: "xmark.circle")
                                }
                            }
                            if viewModel.isCertificateLocallyCached(cert) {
                                SwiftUI.Button(role: .destructive) {
                                    onDelete(cert)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            if cert.serialNumber == viewModel.activeSerialNumber {
                                SwiftUI.Button {
                                    viewModel.deactivateActiveCertificate()
                                } label: {
                                    Label("Deactivate", systemImage: "xmark.seal")
                                }
                                .tint(.gray)
                            } else {
                                SwiftUI.Button {
                                    viewModel.makeCertificateActive(cert)
                                } label: {
                                    Label("Activate", systemImage: "checkmark.seal")
                                }
                                .tint(.green)
                            }
                        }
                        #endif
                    }
                } header: {
                    CertGroupHeaderView(group: group, viewModel: viewModel)
                } footer: {
                    if group.id == viewModel.groupedCertificatesList.last?.id {
                        Text("Suffix (R) indicates the certificate is registered remotely on Apple's developer portal.")
                    }
                }
            }
        }
    }
}

private struct CertGroupHeaderView: View {
    let group: GroupedCertificates
    @ObservedObject var viewModel: CertificatesViewModel
    #if os(tvOS)
    @State private var showSortDialog: Bool = false
    @State private var showGroupDialog: Bool = false
    #endif
    
    var body: some View {
        HStack(spacing: 12) {
            Text(group.name)
            Spacer()
            #if !os(tvOS)
            Menu {
                ForEach(SortOption.allCases) { option in
                    SwiftUI.Button {
                        if viewModel.currentSort == option { viewModel.isAscending.toggle() }
                        else { viewModel.currentSort = option; viewModel.isAscending = (option == .name) }
                    } label: {
                        if viewModel.currentSort == option {
                            Label(String(format: NSLocalizedString("%@ %@", comment: ""), NSLocalizedString(option.rawValue, comment: ""), viewModel.isAscending ? "↑" : "↓"), systemImage: "checkmark")
                        } else {
                            Text(NSLocalizedString(option.rawValue, comment: ""))
                        }
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down").font(.system(size: 13)).foregroundColor(.accentColor)
            }
            Menu {
                Picker("Group By", selection: $viewModel.currentGroup) {
                    ForEach(GroupOption.allCases) { option in
                        Text(NSLocalizedString(option.rawValue, comment: "")).tag(option)
                    }
                }
            } label: {
                Image(systemName: "rectangle.3.group").font(.system(size: 13)).foregroundColor(.accentColor)
            }
            #else
            SwiftUI.Button {
                showSortDialog = true
            } label: {
                Image(systemName: "arrow.up.arrow.down").font(.system(size: 13)).foregroundColor(.accentColor)
            }
            .confirmationDialog("Sort Certificates", isPresented: $showSortDialog) {
                ForEach(SortOption.allCases) { option in
                    SwiftUI.Button(String(format: NSLocalizedString("%@ %@", comment: ""), NSLocalizedString(option.rawValue, comment: ""), viewModel.currentSort == option && viewModel.isAscending ? "↑" : "↓")) {
                        if viewModel.currentSort == option { viewModel.isAscending.toggle() }
                        else { viewModel.currentSort = option; viewModel.isAscending = (option == .name) }
                    }
                }
            }
            SwiftUI.Button {
                showGroupDialog = true
            } label: {
                Image(systemName: "rectangle.3.group").font(.system(size: 13)).foregroundColor(.accentColor)
            }
            .confirmationDialog("Group Certificates", isPresented: $showGroupDialog) {
                ForEach(GroupOption.allCases) { option in
                    SwiftUI.Button(NSLocalizedString(option.rawValue, comment: "")) {
                        viewModel.currentGroup = option
                    }
                }
            }
            #endif
            SwiftUI.Button {
                viewModel.isSectionHideActive.toggle()
            } label: {
                Image(systemName: viewModel.isSectionHideActive ? "eye.slash" : "eye")
                    .font(.subheadline)
                    .foregroundColor(viewModel.isGlobalHideActive ? .gray : .accentColor)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isGlobalHideActive)
        }
    }
}

private struct AdaptiveTappableRow<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        #if !os(tvOS)
        content()
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
        #else
        SwiftUI.Button(action: action) {
            content()
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        #endif
    }
}
