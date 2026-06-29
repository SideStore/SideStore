//
//  CacheManagementView.swift
//  AltStore
//
//  Created by Magesh K on 2026-06-29.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import AltStoreCore

struct CacheManagementView: View {
    @StateObject private var viewModel = CacheViewModel()
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            if viewModel.isLoading && viewModel.internalApps.isEmpty && viewModel.resignedApps.isEmpty {
                ProgressView("Loading Cache...")
                    .scaleEffect(1.1)
            } else {
                List {
                    Section(header: Text("Internal App Cache"), footer: Text("Cached unzipped app bundles stored in SideStore's private container. These are used during automatic background refreshes and resigns.")) {
                        if viewModel.internalApps.isEmpty {
                            Text("No cached internal apps.")
                                .foregroundColor(.secondary)
                                .italic()
                                .padding(.vertical, 4)
                        } else {
                            ForEach(viewModel.internalApps) { item in
                                CacheItemRow(item: item, onExport: {
                                    viewModel.activeExportURL = item.url
                                }, onDelete: {
                                    viewModel.itemToDelete = item
                                })
                            }
                            .onDelete { indexSet in
                                if let index = indexSet.first {
                                    viewModel.itemToDelete = viewModel.internalApps[index]
                                }
                            }
                        }
                    }
                    
                    Section(header: Text("Exported Resigned Apps"), footer: Text("Copies of signed app bundles exported to your Documents folder. These can be shared or retrieved via the Files app.")) {
                        if viewModel.resignedApps.isEmpty {
                            Text("No exported resigned apps.")
                                .foregroundColor(.secondary)
                                .italic()
                                .padding(.vertical, 4)
                        } else {
                            ForEach(viewModel.resignedApps) { item in
                                CacheItemRow(item: item, onExport: {
                                    viewModel.activeExportURL = item.url
                                }, onDelete: {
                                    viewModel.deleteItem(item)
                                })
                            }
                            .onDelete { indexSet in
                                if let index = indexSet.first {
                                    viewModel.deleteItem(viewModel.resignedApps[index])
                                }
                            }
                        }
                    }
                }
                .listStyle(InsetGroupedListStyle())
            }
            
            if viewModel.isLoading && !(viewModel.internalApps.isEmpty && viewModel.resignedApps.isEmpty) {
                Color.black.opacity(0.3)
                    .edgesIgnoringSafeArea(.all)
                
                ProgressView()
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemBackground)))
                    .shadow(radius: 10)
            }
        }
        .navigationTitle("Cache Management")
        .onAppear {
            viewModel.loadCacheItems()
        }
        .alert(isPresented: $viewModel.showErrorAlert) {
            Alert(
                title: Text("Error"),
                message: Text(viewModel.errorMessage ?? "An unknown error occurred."),
                dismissButton: .default(Text("OK"))
            )
        }
        .alert(isPresented: $viewModel.showDeleteAlert) {
            let appName = viewModel.itemToDelete?.name ?? "this app"
            return Alert(
                title: Text("Delete Cached App?"),
                message: Text("If deleted, SideStore will require the original IPA file during reinstall, backup, resign, or refresh procedures. Are you sure you want to delete the cached app bundle for “\(appName)” ?"),
                primaryButton: .destructive(Text("Delete")) {
                    if let item = viewModel.itemToDelete {
                        viewModel.deleteItem(item)
                    }
                },
                secondaryButton: .cancel {
                    viewModel.itemToDelete = nil
                }
            )
        }
        .sheet(isPresented: Binding<Bool>(
            get: { viewModel.activeExportURL != nil },
            set: { if !$0 { viewModel.activeExportURL = nil } }
        )) {
            if let url = viewModel.activeExportURL {
                ActivityViewController(activityItems: [url])
            }
        }
    }
}

struct CacheItemRow: View {
    let item: CacheItem
    let onExport: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            if let image = item.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
                    .cornerRadius(8)
            } else {
                Image(systemName: "square.dashed")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
                    .foregroundColor(.secondary)
                    .padding(4)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                
                if let bundleID = item.bundleIdentifier {
                    Text(bundleID)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            Text(item.sizeString)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .contextMenu {
            SwiftUI.Button(action: onExport) {
                Label("Export/Share", systemImage: "square.and.arrow.up")
            }
            SwiftUI.Button(role: .destructive, action: onDelete) {
                Label("Delete Cache", systemImage: "trash")
            }
        }
    }
}

struct ActivityViewController: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
