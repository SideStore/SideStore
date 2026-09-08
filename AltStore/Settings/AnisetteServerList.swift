//
//  AnisetteServerList.swift
//  SideStore
//
//  Created by ny on 6/18/24.
//  Copyright © 2024 SideStore. All rights reserved.
//

@preconcurrency import UIKit
import SwiftUI
import SideSign

typealias SUIButton = SwiftUI.Button

// MARK: - AnisetteServerData
struct AnisetteServerData: Codable {
    let servers: [Server]
    let oda: ODAValue?

    enum CodingKeys: String, CodingKey {
        case servers
        case oda
    }

    init(servers: [Server], oda: ODAValue? = nil) {
        self.servers = servers
        self.oda = oda
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.servers = (try? container.decode([Server].self, forKey: .servers)) ?? []
        self.oda = try? container.decodeIfPresent(ODAValue.self, forKey: .oda)
    }
}

// MARK: - Server
struct Server: Codable, Identifiable, Hashable {
    var id: String { address }
    var name: String
    var address: String
}
final class AnisetteViewModel: ObservableObject {
    static let defaultSource = AnisetteServersManager.defaultSource

    @Published var source: String = defaultSource
    @Published var items: [AnisetteServerItem] = []
    @Published var showHiddenServers: Bool = false
    @Published var isOfflineMode: Bool = false
    @Published var importedFileName: String? = nil
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var isNoInternet: Bool = false

    var hasHiddenItems: Bool {
        items.contains(where: \.isHidden)
    }

    var visibleItems: [AnisetteServerItem] {
        showHiddenServers ? items : items.filter { !$0.isHidden }
    }

    init() {
        let customSource = UserDefaults.standard.menuAnisetteList
        if !customSource.isEmpty {
            self.source = customSource
        }
        Task { @MainActor in
            self.isOfflineMode = await AnisetteServersManager.shared.isOfflineMode
            self.importedFileName = await AnisetteServersManager.shared.importedFileName
            if self.isOfflineMode || self.source == AnisetteViewModel.defaultSource {
                self.items = await AnisetteServersManager.shared.loadLocalServers()
            }
        }
    }

    @MainActor
    @discardableResult
    func fetchServers(forceRemote: Bool = false) async -> Result<[AnisetteServerItem], Error> {
        isLoading = true
        defer { isLoading = false }

        let isOffline = await AnisetteServersManager.shared.isOfflineMode
        let filename = await AnisetteServersManager.shared.importedFileName
        self.isOfflineMode = isOffline
        self.importedFileName = filename

        if isOffline && !forceRemote {
            let offline = await AnisetteServersManager.shared.loadLocalServers()
            self.items = offline
            self.errorMessage = nil
            return .success(offline)
        }

        do {
            let merged = try await withThrowingTaskGroup(of: [AnisetteServerItem].self) { group in
                group.addTask {
                    return try await AnisetteServersManager.shared.syncWithRemote(sourceURLString: self.source, forceRemote: forceRemote)
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    throw URLError(.timedOut, userInfo: [NSLocalizedDescriptionKey: "Server list fetch timed out after 5 seconds."])
                }
                guard let result = try await group.next() else {
                    throw URLError(.timedOut)
                }
                group.cancelAll()
                return result
            }
            self.errorMessage = nil
            self.items = merged
            debugLog("AnisetteViewModel: Server list sync completed for sourceURL: \(self.source)")
            return .success(merged)
        } catch {
            let isOnline = await AnisetteServersManager.shared.isPublicInternetAvailable()
            let msg: String
            if !isOnline {
                msg = "No Internet Connection. Please check your Wi-Fi or cellular network."
            } else if let urlErr = error as? URLError, urlErr.code == .timedOut {
                msg = "Connection timed out (5s limit) while reaching '\(self.source)'."
            } else {
                msg = "Failed to fetch catalog from '\(self.source)': \(error.localizedDescription)"
            }

            self.isNoInternet = !isOnline
            self.errorMessage = msg
            self.items = []
            debugLog("[AnisetteViewModel] Server list sync Failed for URL '\(self.source)' | Internet Online: \(isOnline) | Error: \(error)")
            return .failure(error)
        }
    }

    @MainActor
    func importData(_ data: Data, filename: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let imported = try await AnisetteServersManager.shared.importFromData(data: data, filename: filename)
            self.items = imported
            self.isOfflineMode = true
            self.importedFileName = filename
            debugLog("AnisetteViewModel: Imported servers from data: \(filename)")
        } catch {
            self.errorMessage = "Failed to import file: \(error.localizedDescription)"
            debugLog("AnisetteViewModel: Import error: \(error)")
        }
    }

    func exportCatalog(unmodified: Bool = false) async -> URL? {
        guard let data = await AnisetteServersManager.shared.exportCatalogData(unmodified: unmodified) else { return nil }
        let baseName = (await AnisetteServersManager.shared.importedFileName) ?? "anisette-servers.json"
        let nameWithoutExt = (baseName as NSString).deletingPathExtension
        let ext = (baseName as NSString).pathExtension.isEmpty ? "json" : (baseName as NSString).pathExtension
        let suffix = unmodified ? "-unmodified" : "-customized"
        let filename = "\(nameWithoutExt)\(suffix).\(ext)"

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? data.write(to: tempURL, options: .atomic)
        return tempURL
    }

    @MainActor
    func resetToOriginalState() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let resetItems = try await AnisetteServersManager.shared.resetToOriginalState()
            self.items = resetItems
            debugLog("AnisetteViewModel: Reset catalog to original uncustomized state.")
        } catch {
            self.errorMessage = "Failed to reset: \(error.localizedDescription)"
            debugLog("AnisetteViewModel: Reset error: \(error)")
        }
    }

    @MainActor
    func clearImportedFile() async {
        await AnisetteServersManager.shared.clearOfflineFileMode()
        self.isOfflineMode = false
        self.importedFileName = nil
        self.source = AnisetteViewModel.defaultSource
        await fetchServers(forceRemote: true)
    }

    func moveItems(from source: IndexSet, to destination: Int) {
        if showHiddenServers {
            items.move(fromOffsets: source, toOffset: destination)
        } else {
            let visibleIndices = items.enumerated().compactMap { index, item in
                item.isHidden ? nil : index
            }

            guard !visibleIndices.isEmpty else { return }

            let actualSourceIndices = source.compactMap { $0 < visibleIndices.count ? visibleIndices[$0] : nil }
            let actualDestinationIndex: Int
            if destination >= visibleIndices.count {
                actualDestinationIndex = items.count
            } else {
                actualDestinationIndex = visibleIndices[destination]
            }

            let movedItems = actualSourceIndices.map { items[$0] }
            for index in actualSourceIndices.sorted(by: >) {
                items.remove(at: index)
            }

            var targetIndex = actualDestinationIndex
            let removedBeforeTarget = actualSourceIndices.filter { $0 < actualDestinationIndex }.count
            targetIndex -= removedBeforeTarget
            targetIndex = max(0, min(items.count, targetIndex))

            items.insert(contentsOf: movedItems, at: targetIndex)
        }

        let currentItems = items
        Task {
            await AnisetteServersManager.shared.saveLocalServers(currentItems)
        }
    }

    func toggleHide(item: AnisetteServerItem) {
        if let index = items.firstIndex(where: { $0.address == item.address }) {
            items[index].isHidden.toggle()
            let currentItems = items
            Task {
                await AnisetteServersManager.shared.saveLocalServers(currentItems)
            }
        }
    }
}

struct AnisetteServersView: View {
    @Environment(\.presentationMode) var presentationMode
    @StateObject private var viewModel = AnisetteViewModel()
    @State private var selectedServerURL: String = ""
    @State private var showingResetAlert = false
    @State private var showingFileImporter = false
    @State private var showingShareSheet = false
    @State private var exportFileURL: URL? = nil
    @State private var isEditingURL = false
    @State private var editingURLText: String = ""
    @State private var showingClearAlert = false
    @State private var showingImportAlert = false
    @State private var pendingImportData: Data? = nil
    @State private var pendingImportName: String? = nil
    #if os(tvOS)
    @State private var showingTvOptionsMenu = false
    #endif

    var selected: String?
    var onResetAdiPb: (() -> Void)?

    init(
        selected: String? = nil,
        onResetAdiPb: (() -> Void)? = nil
    ) {
        self.selected = selected
        self.onResetAdiPb = onResetAdiPb
    }

    var body: some View {
        List {
            // Section 1: Server Selection
            Section {
                if viewModel.items.isEmpty || viewModel.errorMessage != nil {
                    if viewModel.items.isEmpty && viewModel.errorMessage == nil && viewModel.isLoading {
                        VStack(spacing: 12) {
                            Spacer()
                            ProgressView()
                                .scaleEffect(1.2)

                            Text("Fetching Anisette Servers...")
                                .font(.headline)
                                .foregroundColor(.primary)

                            Text(String(format: NSLocalizedString("Reaching catalog source '%@'...", comment: ""), viewModel.source))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 16)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, minHeight: 180)
                        .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: viewModel.isNoInternet ? "wifi.slash" : "antenna.radiowaves.left.and.right.slash")
                                .font(.system(size: 36))
                                .foregroundColor(.orange)
                                .padding(.top, 4)

                            Text(viewModel.isNoInternet ? "No Internet Connection" : "Could Not Reach Servers")
                                .font(.headline)
                                .foregroundColor(.primary)

                            Text(viewModel.errorMessage ?? "No servers available.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 16)

                            SwiftUI.Button {
                                Task {
                                    await viewModel.fetchServers(forceRemote: true)
                                }
                            } label: {
                                if viewModel.isLoading {
                                    HStack(spacing: 8) {
                                        ProgressView()
                                        Text("Retrying...")
                                    }
                                    .font(.subheadline.weight(.medium))
                                } else {
                                    Label("Retry Connection", systemImage: "arrow.clockwise")
                                        .font(.subheadline.weight(.medium))
                                }
                            }
                            .disabled(viewModel.isLoading)
                            .padding(.top, 4)
                            .padding(.bottom, 4)
                        }
                        .frame(maxWidth: .infinity, minHeight: 180)
                        .padding(.vertical, 8)
                    }
                } else {
                    ForEach(Array(viewModel.visibleItems.enumerated()), id: \.element.id) { index, item in
                        SwiftUI.Button {
                            selectedServerURL = item.address
                            UserDefaults.standard.menuAnisetteURL = item.address
                            UserDefaults.standard.synchronize()
                        } label: {
                            HStack(spacing: 12) {
                                Text(String(format: NSLocalizedString("#%d", comment: ""), index + 1))
                                    .font(.subheadline.monospacedDigit().weight(.bold))
                                    .foregroundColor(.secondary)
                                    .frame(minWidth: 26, alignment: .leading)

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(item.name)
                                            .font(.body)
                                            .foregroundColor(item.isHidden ? .secondary : .primary)

                                        if item.isHidden {
                                            Text("Hidden")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Capsule().fill(Color.secondary.opacity(0.2)))
                                        }
                                    }

                                    Text(item.address)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                if selectedServerURL == item.address {
                                    Image(systemName: "checkmark")
                                        .font(.body.weight(.semibold))
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .opacity(item.isHidden ? 0.6 : 1.0)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        #if !os(tvOS)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            SwiftUI.Button {
                                viewModel.toggleHide(item: item)
                            } label: {
                                Label(item.isHidden ? "Unhide" : "Hide", systemImage: item.isHidden ? "eye" : "eye.slash")
                            }
                            .tint(item.isHidden ? .blue : .orange)
                        }
                        #endif
                    }
                    .onMove(perform: viewModel.moveItems)
                }
            } header: {
                if viewModel.isOfflineMode {
                    HStack(spacing: 6) {
                        Text("Available Servers (OFFLINE)")
                        Image(systemName: "wifi.slash")
                            .font(.subheadline)
                            .foregroundColor(.orange)
                    }
                } else {
                    Text("Available Servers")
                }
            } footer: {
                if !viewModel.items.isEmpty && viewModel.errorMessage == nil {
                    Text("Drag to reorder server priority. Swipe left on a server to hide or unhide it.")
                }
            }

            // Section 2: Source Configuration
            Section {
                if viewModel.isOfflineMode {
                    HStack {
                        Text("Catalog File")
                            .foregroundColor(.primary)
                        Spacer()
                        Text(viewModel.importedFileName ?? "Imported File")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                    .contextMenu {
                         SwiftUI.Button {
                            Task {
                                if let url = await viewModel.exportCatalog(unmodified: false) {
                                    exportFileURL = url
                                    showingShareSheet = true
                                }
                            }
                        } label: {
                            Label("Export Current", systemImage: "square.and.arrow.up")
                        }

                        SwiftUI.Button {
                            Task {
                                if let url = await viewModel.exportCatalog(unmodified: true) {
                                    exportFileURL = url
                                    showingShareSheet = true
                                }
                            }
                        } label: {
                            Label("Export Original", systemImage: "doc.on.doc")
                        }

                        SwiftUI.Button(role: .destructive) {
                            Task {
                                await viewModel.resetToOriginalState()
                            }
                        } label: {
                            Label("Reset Catalog", systemImage: "arrow.circlepath")
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Server List URL")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if isEditingURL {
                            TextField("https://...", text: $editingURLText)
                                .font(.subheadline)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        } else {
                            Text(viewModel.source)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .padding(.vertical, 2)
                    .contextMenu {
                        SwiftUI.Button {
                            Task {
                                if let url = await viewModel.exportCatalog(unmodified: false) {
                                    exportFileURL = url
                                    showingShareSheet = true
                                }
                            }
                        } label: {
                            Label("Export Current", systemImage: "square.and.arrow.up")
                        }

                        if viewModel.isOfflineMode {
                            SwiftUI.Button {
                                Task {
                                    if let url = await viewModel.exportCatalog(unmodified: true) {
                                        exportFileURL = url
                                        showingShareSheet = true
                                    }
                                }
                            } label: {
                                Label("Export Original", systemImage: "doc.on.doc")
                            }
                        } else if viewModel.source != AnisetteViewModel.defaultSource {
                            SwiftUI.Button(role: .destructive) {
                                viewModel.source = AnisetteViewModel.defaultSource
                                UserDefaults.standard.menuAnisetteList = AnisetteViewModel.defaultSource
                                Task {
                                    await viewModel.fetchServers(forceRemote: true)
                                }
                            } label: {
                                Label("Reset Source to Default", systemImage: "arrow.circlepath")
                            }
                        }

                        SwiftUI.Button(role: .destructive) {
                            Task {
                                await viewModel.resetToOriginalState()
                            }
                        } label: {
                            Label("Reset Catalog", systemImage: "arrow.circlepath")
                        }
                    }
                }
                    } header: {
                        HStack {
                            Text("Server Catalog Source")
                            Spacer()
                            if !viewModel.isOfflineMode {
                                SwiftUI.Button(isEditingURL ? "Done" : "Edit") {
                                    if isEditingURL {
                                        isEditingURL = false
                                        let trimmed = editingURLText.trimmingCharacters(in: .whitespacesAndNewlines)
                                        if !trimmed.isEmpty && trimmed != viewModel.source {
                                            viewModel.source = trimmed
                                            UserDefaults.standard.menuAnisetteList = trimmed
                                            Task {
                                                await viewModel.fetchServers(forceRemote: true)
                                            }
                                        }
                                    } else {
                                        editingURLText = viewModel.source
                                        isEditingURL = true
                                    }
                                }
                                .font(.subheadline.weight(.semibold))
                            }
                        }
                    } footer: {
                        if viewModel.isOfflineMode {
                            Text(String(format: NSLocalizedString("Currently using imported file '%@'. Press and hold row to export.", comment: ""), viewModel.importedFileName ?? "custom.json"))
                        } else {
                            Text("URL of the JSON file containing registered Anisette servers. Press and hold row to export.")
                        }
                    }

                    // Section: Customization
                    Section {
                        NavigationLink(destination: AnisetteDataView()) {
                            Label("Anisette Client Configuration", systemImage: "macbook.and.iphone")
                        }
                        Toggle(isOn: Binding(
                            get: { !UserDefaults.standard.disableAnisetteRotation },
                            set: { UserDefaults.standard.disableAnisetteRotation = !$0 }
                        )) {
                            Label("Enable Auto Rotation", systemImage: "arrow.triangle.2.circlepath")
                        }
                    } header: {
                        Text("Customization")
                    } footer: {
                        Text("View, edit, or offline the header properties sent to Apple during provisioning, and control if SideStore automatically rotates/retries servers upon failure.")
                    }

                    // Section 3: Troubleshooting
                    Section {
                        SwiftUI.Button(role: .destructive) {
                            showingResetAlert = true
                        } label: {
                            HStack {
                                Text("Reset adi.pb")
                                Spacer()
                                Image(systemName: "trash")
                                    .font(.subheadline)
                            }
                        }
                        .alert(isPresented: $showingResetAlert) {
                            Alert(
                                title: Text("Reset adi.pb"),
                                message: Text("Are you sure you want to clear adi.pb from the Keychain? You will need to log back in to Apple ID in SideStore."),
                                primaryButton: .destructive(Text("Reset")) {
                                    #if !DEBUG
                                    if AnisetteConfigManager.shared.anisetteAdiBlob != nil {
                                        AnisetteConfigManager.shared.anisetteAdiBlob = nil
                                    }
                                    #endif
                                    debugLog("Cleared adi.pb from keychain")
                                    onResetAdiPb?()
                                    presentationMode.wrappedValue.dismiss()
                                },
                                secondaryButton: .cancel()
                            )
                        }
                    } header: {
                        Text("Troubleshooting")
                    } footer: {
                        Text("Resetting local Anisette data forces a fresh provisioning flow if authentication is failing.")
                    }

                    // Bottom spacing section
                    Section {
                        Color.clear
                            .frame(height: 20)
                            .listRowBackground(Color.clear)
                    }
                }
                #if !os(tvOS)
                .listStyle(.insetGrouped)
                #else
                .listStyle(.grouped)
                #endif
                .refreshable {
                    await viewModel.fetchServers(forceRemote: true)
                }
        .navigationTitle("Anisette Servers")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if viewModel.isOfflineMode {
                    SwiftUI.Button {
                        showingClearAlert = true
                    } label: {
                        Image(systemName: "xmark.circle")
                            .foregroundColor(.red)
                    }
                    .tint(.red)
                } else {
                    SwiftUI.Button {
                        #if !os(tvOS)
                        showingFileImporter = true
                        #else
                        if let topVC = UIApplication.shared.topViewController() {
                            TVWebFileTransferManager.shared.startImport(
                                acceptedExtensions: ["json"],
                                title: "Import Anisette Servers JSON",
                                presentingVC: topVC
                            ) { fileURL in
                                guard let fileURL = fileURL else { return }
                                if let data = try? Data(contentsOf: fileURL) {
                                    DispatchQueue.main.async {
                                        pendingImportData = data
                                        pendingImportName = fileURL.lastPathComponent
                                        showingImportAlert = true
                                    }
                                }
                            }
                        }
                        #endif
                    } label: {
                        Image(systemName: "doc.badge.plus")
                    }
                }

                #if !os(tvOS)
                Menu {
                    if viewModel.hasHiddenItems {
                        SwiftUI.Button {
                            viewModel.showHiddenServers.toggle()
                        } label: {
                            Label(viewModel.showHiddenServers ? "Hide Hidden" : "Show Hidden", systemImage: viewModel.showHiddenServers ? "eye.slash" : "eye")
                        }
                    }

                    SwiftUI.Button {
                        Task {
                            if let url = await viewModel.exportCatalog(unmodified: false) {
                                exportFileURL = url
                                showingShareSheet = true
                            }
                        }
                    } label: {
                        Label("Export Current", systemImage: "square.and.arrow.up")
                    }

                    if viewModel.isOfflineMode {
                        SwiftUI.Button {
                            Task {
                                if let url = await viewModel.exportCatalog(unmodified: true) {
                                    exportFileURL = url
                                    showingShareSheet = true
                                }
                            }
                        } label: {
                            Label("Export Original", systemImage: "doc.on.doc")
                        }
                    }

                    SwiftUI.Button(role: .destructive) {
                        Task {
                            await viewModel.resetToOriginalState()
                        }
                    } label: {
                        Label("Reset Catalog", systemImage: "arrow.circlepath")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                #else
                SwiftUI.Button {
                    showingTvOptionsMenu = true
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                #endif
            }
        }
        #if os(tvOS)
        .confirmationDialog("Options", isPresented: $showingTvOptionsMenu) {
            if viewModel.hasHiddenItems {
                SwiftUI.Button(viewModel.showHiddenServers ? "Hide Hidden" : "Show Hidden") {
                    viewModel.showHiddenServers.toggle()
                }
            }
            SwiftUI.Button("Export Current") {
                Task {
                    if let url = await viewModel.exportCatalog(unmodified: false), let topVC = UIApplication.shared.topViewController() {
                        TVWebFileTransferManager.shared.startExport(fileURL: url, title: "Export Anisette Servers JSON", presentingVC: topVC)
                    }
                }
            }
            if viewModel.isOfflineMode {
                SwiftUI.Button("Export Original") {
                    Task {
                        if let url = await viewModel.exportCatalog(unmodified: true), let topVC = UIApplication.shared.topViewController() {
                            TVWebFileTransferManager.shared.startExport(fileURL: url, title: "Export Anisette Servers JSON", presentingVC: topVC)
                        }
                    }
                }
            }
            SwiftUI.Button("Reset Catalog", role: .destructive) {
                Task {
                    await viewModel.resetToOriginalState()
                }
            }
        }
        #endif
        #if !os(tvOS)
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    let isAccessing = url.startAccessingSecurityScopedResource()
                    defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }
                    do {
                        let data = try Data(contentsOf: url)
                        pendingImportData = data
                        pendingImportName = url.lastPathComponent
                        showingImportAlert = true
                    } catch {
                        viewModel.errorMessage = "Failed to read file: \(error.localizedDescription)"
                    }
                }
            case .failure(let error):
                viewModel.errorMessage = "Import failed: \(error.localizedDescription)"
            }
        }
        #endif
        .alert("Clear Imported File?", isPresented: $showingClearAlert) {
            SwiftUI.Button("Clear", role: .destructive) {
                Task {
                    await viewModel.clearImportedFile()
                }
            }
            SwiftUI.Button("Cancel", role: .cancel) {}
        } message: {
            Text(String(format: NSLocalizedString("Are you sure you want to remove the imported catalog '%@' and return to the default server URL?", comment: ""), viewModel.importedFileName ?? "custom.json"))
        }
        .alert("Import Server Catalog?", isPresented: $showingImportAlert) {
            SwiftUI.Button("Import") {
                if let data = pendingImportData, let name = pendingImportName {
                    Task {
                        await viewModel.importData(data, filename: name)
                    }
                }
            }
            SwiftUI.Button("Cancel", role: .cancel) {}
        } message: {
            Text(String(format: NSLocalizedString("This will replace your current server catalog with the servers from '%@'. Do you want to proceed?", comment: ""), pendingImportName ?? "selected file"))
        }
        .sheet(isPresented: $showingShareSheet) {
            if let fileURL = exportFileURL {
                ActivityViewController(activityItems: [fileURL])
            }
        }
        .task {
            let active = selected ?? UserDefaults.standard.menuAnisetteURL
            if !active.isEmpty {
                selectedServerURL = active
            }
            await viewModel.fetchServers()
        }
    }
}


