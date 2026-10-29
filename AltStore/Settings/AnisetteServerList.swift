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

private typealias SUIButton = SwiftUI.Button

// MARK: - Anisette Server Data

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
        servers = (try? container.decode([Server].self, forKey: .servers)) ?? []
        oda = try? container.decodeIfPresent(ODAValue.self, forKey: .oda)
    }
}

// MARK: - Server

struct Server: Codable, Identifiable, Hashable {
    var id: String { address }

    var name: String
    var address: String
}

// MARK: - Anisette View Model

@MainActor
final class AnisetteViewModel: ObservableObject {
    static let defaultSource = AnisetteServersManager.defaultSource

    private static let customServersDefaultsKey = "customAnisetteServers"

    @Published var source: String = defaultSource
    @Published var items: [AnisetteServerItem] = []
    @Published var showHiddenServers = false
    @Published var isOfflineMode = false
    @Published var importedFileName: String?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isNoInternet = false

    @Published private(set) var customServerAddresses: Set<String> = []

    var hasHiddenItems: Bool {
        items.contains(where: \.isHidden)
    }

    var visibleItems: [AnisetteServerItem] {
        showHiddenServers ? items : items.filter { !$0.isHidden }
    }

    // MARK: Custom Server Persistence

    private static func loadSavedCustomServers() -> [Server] {
        guard let data = UserDefaults.standard.data(
            forKey: Self.customServersDefaultsKey
        ) else {
            return []
        }

        return (try? JSONDecoder().decode([Server].self, from: data)) ?? []
    }

    private func saveCustomServers(_ servers: [Server]) {
        guard let data = try? JSONEncoder().encode(servers) else {
            return
        }

        UserDefaults.standard.set(
            data,
            forKey: Self.customServersDefaultsKey
        )

        customServerAddresses = Set(servers.map(\.address))
    }

    /// Adds saved custom servers to a catalog without duplicating their URLs.
    private func mergingCustomServers(
        into catalog: [AnisetteServerItem]
    ) -> [AnisetteServerItem] {
        let savedServers = Self.loadSavedCustomServers()
        let savedAddresses = Set(savedServers.map(\.address))

        customServerAddresses = savedAddresses

        let customItems = savedServers.map { server in
            AnisetteServerItem(
                name: server.name,
                address: server.address,
                isHidden: false
            )
        }

        return customItems + catalog.filter {
            !savedAddresses.contains($0.address)
        }
    }

    // MARK: Initialization

    init() {
        let savedSource = UserDefaults.standard.menuAnisetteList

        if !savedSource.isEmpty {
            source = savedSource
        }

        customServerAddresses = Set(
            Self.loadSavedCustomServers().map(\.address)
        )

        Task { @MainActor in
            isOfflineMode =
                await AnisetteServersManager.shared.isOfflineMode

            importedFileName =
                await AnisetteServersManager.shared.importedFileName

            let localServers =
                await AnisetteServersManager.shared.loadLocalServers()

            if isOfflineMode || source == Self.defaultSource {
                items = mergingCustomServers(into: localServers)
            } else if !localServers.isEmpty {
                // Keep the saved list available while the remote catalog loads.
                items = mergingCustomServers(into: localServers)
            }
        }
    }

    // MARK: Fetch Servers

    @discardableResult
    func fetchServers(
        forceRemote: Bool = false
    ) async -> Result<[AnisetteServerItem], Error> {
        isLoading = true
        defer { isLoading = false }

        let offline =
            await AnisetteServersManager.shared.isOfflineMode

        let filename =
            await AnisetteServersManager.shared.importedFileName

        isOfflineMode = offline
        importedFileName = filename

        if offline && !forceRemote {
            let localServers =
                await AnisetteServersManager.shared.loadLocalServers()

            let mergedItems = mergingCustomServers(into: localServers)

            items = mergedItems
            errorMessage = nil
            isNoInternet = false

            return .success(mergedItems)
        }

        do {
            let sourceURL = source

            let catalog = try await withThrowingTaskGroup(
                of: [AnisetteServerItem].self
            ) { group in
                group.addTask {
                    try await AnisetteServersManager.shared.syncWithRemote(
                        sourceURLString: sourceURL,
                        forceRemote: forceRemote
                    )
                }

                group.addTask {
                    try await Task.sleep(
                        nanoseconds: 5_000_000_000
                    )

                    throw URLError(
                        .timedOut,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "Server list fetch timed out after 5 seconds."
                        ]
                    )
                }

                guard let result = try await group.next() else {
                    throw URLError(.timedOut)
                }

                group.cancelAll()
                return result
            }

            let mergedItems = mergingCustomServers(into: catalog)

            items = mergedItems
            errorMessage = nil
            isNoInternet = false

            debugLog(
                "AnisetteViewModel: Server list sync completed for sourceURL: \(source)"
            )

            return .success(mergedItems)
        } catch {
            let isOnline =
                await AnisetteServersManager.shared.isPublicInternetAvailable()

            let message: String

            if !isOnline {
                message =
                    "No Internet Connection. Please check your Wi-Fi or cellular network."
            } else if let urlError = error as? URLError,
                      urlError.code == .timedOut {
                message =
                    "Connection timed out (5s limit) while reaching '\(source)'."
            } else {
                message =
                    "Failed to fetch catalog from '\(source)': \(error.localizedDescription)"
            }

            isNoInternet = !isOnline
            errorMessage = message

            // Preserve current entries and restore any saved custom servers.
            items = mergingCustomServers(into: items)

            debugLog(
                "[AnisetteViewModel] Server list sync failed for URL '\(source)' | Internet Online: \(isOnline) | Error: \(error)"
            )

            return .failure(error)
        }
    }

    // MARK: Import / Export

    func importData(_ data: Data, filename: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let imported =
                try await AnisetteServersManager.shared.importFromData(
                    data: data,
                    filename: filename
                )

            items = mergingCustomServers(into: imported)
            isOfflineMode = true
            importedFileName = filename

            debugLog(
                "AnisetteViewModel: Imported servers from data: \(filename)"
            )
        } catch {
            errorMessage =
                "Failed to import file: \(error.localizedDescription)"

            debugLog("AnisetteViewModel: Import error: \(error)")
        }
    }

    func exportCatalog(unmodified: Bool = false) async -> URL? {
        guard let data =
            await AnisetteServersManager.shared.exportCatalogData(
                unmodified: unmodified
            )
        else {
            return nil
        }

        let baseName =
            (await AnisetteServersManager.shared.importedFileName)
            ?? "anisette-servers.json"

        let nameWithoutExtension =
            (baseName as NSString).deletingPathExtension

        let extensionName =
            (baseName as NSString).pathExtension.isEmpty
            ? "json"
            : (baseName as NSString).pathExtension

        let suffix = unmodified ? "-unmodified" : "-customized"
        let filename =
            "\(nameWithoutExtension)\(suffix).\(extensionName)"

        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(filename)

        do {
            try data.write(to: temporaryURL, options: .atomic)
            return temporaryURL
        } catch {
            errorMessage =
                "Failed to export catalog: \(error.localizedDescription)"
            return nil
        }
    }

    func resetToOriginalState() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let resetItems =
                try await AnisetteServersManager.shared.resetToOriginalState()

            items = mergingCustomServers(into: resetItems)

            debugLog(
                "AnisetteViewModel: Reset catalog to original uncustomized state."
            )
        } catch {
            errorMessage =
                "Failed to reset: \(error.localizedDescription)"

            debugLog("AnisetteViewModel: Reset error: \(error)")
        }
    }

    func clearImportedFile() async {
        await AnisetteServersManager.shared.clearOfflineFileMode()

        isOfflineMode = false
        importedFileName = nil
        source = Self.defaultSource
        UserDefaults.standard.menuAnisetteList = Self.defaultSource

        await fetchServers(forceRemote: true)
    }

    // MARK: Reordering

    func moveItems(from source: IndexSet, to destination: Int) {
        if showHiddenServers {
            items.move(fromOffsets: source, toOffset: destination)
        } else {
            let visibleIndices = items.enumerated().compactMap {
                index, item in
                item.isHidden ? nil : index
            }

            guard !visibleIndices.isEmpty else {
                return
            }

            let actualSourceIndices = source.compactMap { index in
                index < visibleIndices.count
                    ? visibleIndices[index]
                    : nil
            }

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

            let removedBeforeTarget = actualSourceIndices.filter {
                $0 < actualDestinationIndex
            }.count

            var targetIndex =
                actualDestinationIndex - removedBeforeTarget

            targetIndex = max(0, min(items.count, targetIndex))

            items.insert(contentsOf: movedItems, at: targetIndex)
        }

        persistLocalServers()
    }

    // MARK: Hide / Unhide Built-in Servers

    func toggleHide(item: AnisetteServerItem) {
        guard let index = items.firstIndex(
            where: { $0.address == item.address }
        ) else {
            return
        }

        items[index].isHidden.toggle()
        persistLocalServers()
    }

    // MARK: Add Custom Server

    @discardableResult
    func addCustomServer(
        name: String,
        address: String
    ) -> String? {
        var urlString = address.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !urlString.isEmpty else {
            return "Enter a server URL."
        }

        if !urlString.contains("://") {
            urlString = "https://" + urlString
        }

        guard
            let url = URL(string: urlString),
            let host = url.host,
            !host.isEmpty,
            let scheme = url.scheme?.lowercased(),
            scheme == "https" || scheme == "http"
        else {
            return "Invalid URL. Use a valid HTTP or HTTPS server URL."
        }

        let finalAddress = url.absoluteString

        guard !items.contains(where: {
            $0.address.caseInsensitiveCompare(finalAddress) == .orderedSame
        }) else {
            return "That server is already in the list."
        }

        let trimmedName = name.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        let server = Server(
            name: trimmedName.isEmpty ? host : trimmedName,
            address: finalAddress
        )

        var savedServers = Self.loadSavedCustomServers()

        guard !savedServers.contains(where: {
            $0.address.caseInsensitiveCompare(finalAddress) == .orderedSame
        }) else {
            return "That server is already in the list."
        }

        savedServers.append(server)
        saveCustomServers(savedServers)

        let item = AnisetteServerItem(
            name: server.name,
            address: server.address,
            isHidden: false
        )

        items.insert(item, at: 0)

        UserDefaults.standard.menuAnisetteURL = finalAddress
        persistLocalServers()

        return nil
    }

    // MARK: Remove Custom Server

    /// Removes a custom server and returns the URL that remains selected.
    @discardableResult
    func removeCustomServer(item: AnisetteServerItem) -> String {
        guard customServerAddresses.contains(item.address) else {
            return UserDefaults.standard.menuAnisetteURL
        }

        let remainingServers = Self.loadSavedCustomServers().filter {
            $0.address != item.address
        }

        saveCustomServers(remainingServers)

        items.removeAll {
            $0.address == item.address
        }

        let defaults = UserDefaults.standard

        if defaults.menuAnisetteURL == item.address {
            defaults.menuAnisetteURL =
                items.first(where: { !$0.isHidden })?.address ?? ""
        }

        persistLocalServers()
        return defaults.menuAnisetteURL
    }

    // MARK: Local Persistence

    private func persistLocalServers() {
        let currentItems = items

        Task { @MainActor in
            await AnisetteServersManager.shared.saveLocalServers(currentItems)
        }
    }
}

// MARK: - Add Custom Server Sheet

private struct AddCustomAnisetteServerSheet: View {
    @Binding var isPresented: Bool
    @Binding var name: String
    @Binding var address: String
    @Binding var errorMessage: String?

    var onAdd: (String, String) -> String?

    var body: some View {
        NavigationView {
            formContent
                .navigationTitle("Add Server")
                #if !os(tvOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .navigationBarItems(
                    leading: SUIButton("Cancel") {
                        isPresented = false
                    },
                    trailing: SUIButton("Add") {
                        if let error = onAdd(name, address) {
                            errorMessage = error
                        } else {
                            isPresented = false
                        }
                    }
                )
        }
    }

    @ViewBuilder
    private var formContent: some View {
        Form {
            Section(
                header: Text("Custom Anisette Server"),
                footer: Text(
                    "Enter an anisette-v3 URL. Prefer Windows ADI hosts (for example, https://ani.jkcoxson.com or https://win.ani.sidestore.io) for Apple ID sign-in."
                )
            ) {
                TextField("Name (optional)", text: $name)

                #if !os(tvOS)
                TextField("https://ani.example.com", text: $address)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .keyboardType(.URL)
                #else
                TextField("https://ani.example.com", text: $address)
                #endif
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundColor(.red)
                }
            }
        }
    }
}

// MARK: - Anisette Servers View

struct AnisetteServersView: View {
    @Environment(\.presentationMode) private var presentationMode
    @StateObject private var viewModel = AnisetteViewModel()

    @State private var selectedServerURL = ""
    @State private var showingFileImporter = false
    @State private var showingShareSheet = false
    @State private var exportFileURL: URL?
    @State private var isEditingURL = false
    @State private var editingURLText = ""
    @State private var showingClearAlert = false
    @State private var showingImportAlert = false
    @State private var showingAddServer = false
    @State private var newServerName = ""
    @State private var newServerAddress = ""
    @State private var addServerError: String?
    @State private var pendingImportData: Data?
    @State private var pendingImportName: String?

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

    
    // MARK: - SideInstaller Anisette Choice (exact Engine.anisetteAuto UI)

    private enum AnisetteChoice: Hashable {
        case auto
        case server(String)
        case custom
    }

    private var isAnisetteAuto: Bool {
        if UserDefaults.standard.object(forKey: "anisetteServerAuto") == nil { return true }
        return UserDefaults.standard.bool(forKey: "anisetteServerAuto")
    }

    private var isAnisetteCustom: Bool {
        let url = UserDefaults.standard.menuAnisetteURL
        return !isAnisetteAuto && !viewModel.items.contains { !$0.isHidden && $0.address == url }
    }

    private var anisetteStartsWithName: String {
        let url = UserDefaults.standard.menuAnisetteURL
        return viewModel.items.first { $0.address == url }?.name
            ?? (url.isEmpty ? AnisetteProvider.fallbackServerURL : url)
    }

    private var anisetteChoiceBinding: Binding<AnisetteChoice> {
        Binding(
            get: {
                if isAnisetteAuto { return .auto }
                let url = UserDefaults.standard.menuAnisetteURL
                if viewModel.items.contains(where: { !$0.isHidden && $0.address == url }) {
                    return .server(url)
                }
                return .custom
            },
            set: { choice in
                switch choice {
                case .auto:
                    UserDefaults.standard.set(true, forKey: "anisetteServerAuto")
                    AnisetteProvider.setAutoEnabled(true)
                    UserDefaults.standard.useOnDeviceAnisette = false
                    if UserDefaults.standard.menuAnisetteURL.isEmpty {
                        UserDefaults.standard.menuAnisetteURL = AnisetteProvider.fallbackServerURL
                    }
                case .server(let address):
                    UserDefaults.standard.set(false, forKey: "anisetteServerAuto")
                    AnisetteProvider.setAutoEnabled(false)
                    UserDefaults.standard.disableAnisetteRotation = true
                    UserDefaults.standard.menuAnisetteURL = address
                    selectedServerURL = address
                case .custom:
                    UserDefaults.standard.set(false, forKey: "anisetteServerAuto")
                    AnisetteProvider.setAutoEnabled(false)
                    UserDefaults.standard.disableAnisetteRotation = true
                }
            }
        )
    }

    private var customAnisetteURLBinding: Binding<String> {
        Binding(
            get: { UserDefaults.standard.menuAnisetteURL },
            set: { newValue in
                UserDefaults.standard.menuAnisetteURL = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                selectedServerURL = UserDefaults.standard.menuAnisetteURL
            }
        )
    }

var body: some View {
        serverList
            .navigationTitle("Anisette Servers")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    SwiftUI.Button {
                        newServerName = ""
                        newServerAddress = ""
                        addServerError = nil
                        showingAddServer = true
                    } label: {
                        Image(systemName: "plus")
                    }

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
                                    guard let fileURL,
                                          let data = try? Data(contentsOf: fileURL)
                                    else {
                                        return
                                    }

                                    DispatchQueue.main.async {
                                        pendingImportData = data
                                        pendingImportName = fileURL.lastPathComponent
                                        showingImportAlert = true
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
                                Label(
                                    viewModel.showHiddenServers
                                        ? "Hide Hidden"
                                        : "Show Hidden",
                                    systemImage: viewModel.showHiddenServers
                                        ? "eye.slash"
                                        : "eye"
                                )
                            }
                        }

                        SwiftUI.Button {
                            Task {
                                if let url = await viewModel.exportCatalog() {
                                    exportFileURL = url
                                    showingShareSheet = true
                                }
                            }
                        } label: {
                            Label(
                                "Export Current",
                                systemImage: "square.and.arrow.up"
                            )
                        }

                        if viewModel.isOfflineMode {
                            SwiftUI.Button {
                                Task {
                                    if let url = await viewModel.exportCatalog(
                                        unmodified: true
                                    ) {
                                        exportFileURL = url
                                        showingShareSheet = true
                                    }
                                }
                            } label: {
                                Label(
                                    "Export Original",
                                    systemImage: "doc.on.doc"
                                )
                            }
                        }

                        SwiftUI.Button(role: .destructive) {
                            Task {
                                await viewModel.resetToOriginalState()
                            }
                        } label: {
                            Label(
                                "Reset Catalog",
                                systemImage: "arrow.circlepath"
                            )
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
            .confirmationDialog(
                "Options",
                isPresented: $showingTvOptionsMenu
            ) {
                if viewModel.hasHiddenItems {
                    SwiftUI.Button(
                        viewModel.showHiddenServers
                            ? "Hide Hidden"
                            : "Show Hidden"
                    ) {
                        viewModel.showHiddenServers.toggle()
                    }
                }

                SwiftUI.Button("Export Current") {
                    Task {
                        if let url = await viewModel.exportCatalog(),
                           let topVC = UIApplication.shared.topViewController() {
                            TVWebFileTransferManager.shared.startExport(
                                fileURL: url,
                                title: "Export Anisette Servers JSON",
                                presentingVC: topVC
                            )
                        }
                    }
                }

                if viewModel.isOfflineMode {
                    SwiftUI.Button("Export Original") {
                        Task {
                            if let url = await viewModel.exportCatalog(
                                unmodified: true
                            ),
                               let topVC = UIApplication.shared.topViewController() {
                                TVWebFileTransferManager.shared.startExport(
                                    fileURL: url,
                                    title: "Export Anisette Servers JSON",
                                    presentingVC: topVC
                                )
                            }
                        }
                    }
                }

                SwiftUI.Button(
                    "Reset Catalog",
                    role: .destructive
                ) {
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
                    guard let url = urls.first else {
                        return
                    }

                    let isAccessing =
                        url.startAccessingSecurityScopedResource()

                    defer {
                        if isAccessing {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }

                    do {
                        pendingImportData = try Data(contentsOf: url)
                        pendingImportName = url.lastPathComponent
                        showingImportAlert = true
                    } catch {
                        viewModel.errorMessage =
                            "Failed to read file: \(error.localizedDescription)"
                    }

                case .failure(let error):
                    viewModel.errorMessage =
                        "Import failed: \(error.localizedDescription)"
                }
            }
            #endif
            .alert(
                "Clear Imported File?",
                isPresented: $showingClearAlert
            ) {
                SwiftUI.Button("Clear", role: .destructive) {
                    Task {
                        await viewModel.clearImportedFile()
                    }
                }

                SwiftUI.Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "Are you sure you want to remove the imported catalog '\(viewModel.importedFileName ?? "custom.json")' and return to the default server URL?"
                )
            }
            .alert(
                "Import Server Catalog?",
                isPresented: $showingImportAlert
            ) {
                SwiftUI.Button("Import") {
                    guard let data = pendingImportData,
                          let name = pendingImportName
                    else {
                        return
                    }

                    Task {
                        await viewModel.importData(data, filename: name)
                    }
                }

                SwiftUI.Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "This will replace your current server catalog with the servers from '\(pendingImportName ?? "selected file")'. Do you want to proceed?"
                )
            }
            .sheet(isPresented: $showingAddServer) {
                AddCustomAnisetteServerSheet(
                    isPresented: $showingAddServer,
                    name: $newServerName,
                    address: $newServerAddress,
                    errorMessage: $addServerError
                ) { name, address in
                    if let error = viewModel.addCustomServer(
                        name: name,
                        address: address
                    ) {
                        return error
                    }

                    selectedServerURL =
                        UserDefaults.standard.menuAnisetteURL

                    return nil
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let fileURL = exportFileURL {
                    ActivityViewController(activityItems: [fileURL])
                }
            }
            .task {
                let active = UserDefaults.standard.menuAnisetteURL

                if !active.isEmpty {
                    selectedServerURL = active
                } else if let selected, !selected.isEmpty {
                    selectedServerURL = selected
                }

                await viewModel.fetchServers()
            }
    }

    // MARK: Server List

    @ViewBuilder
    private var serverList: some View {
        List {
            // SideInstaller Settings › Anisette Server — exact Auto control
            // (Picker with Auto first, not a separate switch elsewhere)
            Section {
                Picker("Server", selection: anisetteChoiceBinding) {
                    Text("Auto").tag(AnisetteChoice.auto)
                    ForEach(viewModel.items.filter { !$0.isHidden }) { item in
                        Text(item.name).tag(AnisetteChoice.server(item.address))
                    }
                    Text("Custom…").tag(AnisetteChoice.custom)
                }
                if isAnisetteAuto {
                    Text("Starts with \(anisetteStartsWithName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if isAnisetteCustom {
                    TextField("Server URL", text: customAnisetteURLBinding)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                } else {
                    Text(UserDefaults.standard.menuAnisetteURL)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            } header: {
                Text("Anisette Server")
            } footer: {
                Text(isAnisetteAuto
                    ? "Auto starts with the server that signed in last, then tries the others, the ones most likely to work first."
                    : "Only this server is tried. If it fails, so does sign-in: choose Auto to have SideStore try the others.")
            }

            // Section 1: Server Selection

            Section {
                if viewModel.items.isEmpty || viewModel.errorMessage != nil {
                    if viewModel.items.isEmpty,
                       viewModel.errorMessage == nil,
                       viewModel.isLoading {
                        VStack(spacing: 12) {
                            Spacer()

                            ProgressView()
                                .scaleEffect(1.2)

                            Text("Fetching Anisette Servers...")
                                .font(.headline)
                                .foregroundColor(.primary)

                            Text(
                                "Reaching catalog source '\(viewModel.source)'..."
                            )
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
                            Image(
                                systemName: viewModel.isNoInternet
                                    ? "wifi.slash"
                                    : "antenna.radiowaves.left.and.right.slash"
                            )
                            .font(.system(size: 36))
                            .foregroundColor(.orange)
                            .padding(.top, 4)

                            Text(
                                viewModel.isNoInternet
                                    ? "No Internet Connection"
                                    : "Could Not Reach Servers"
                            )
                            .font(.headline)
                            .foregroundColor(.primary)

                            Text(
                                viewModel.errorMessage ?? "No servers available."
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)

                            SwiftUI.Button {
                                Task {
                                    await viewModel.fetchServers(
                                        forceRemote: true
                                    )
                                }
                            } label: {
                                if viewModel.isLoading {
                                    HStack(spacing: 8) {
                                        ProgressView()
                                        Text("Retrying...")
                                    }
                                    .font(.subheadline.weight(.medium))
                                } else {
                                    Label(
                                        "Retry Connection",
                                        systemImage: "arrow.clockwise"
                                    )
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
                    ForEach(
                        Array(viewModel.items.filter { !$0.isHidden }.enumerated()),
                        id: \.element.id
                    ) { index, item in
                        serverRow(item, index: index)
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
                    Text(
                        "Drag to reorder servers. Swipe left to remove custom servers or hide and unhide built-in servers."
                    )
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
                            exportCatalog(unmodified: false)
                        } label: {
                            Label(
                                "Export Current",
                                systemImage: "square.and.arrow.up"
                            )
                        }

                        SwiftUI.Button {
                            exportCatalog(unmodified: true)
                        } label: {
                            Label(
                                "Export Original",
                                systemImage: "doc.on.doc"
                            )
                        }

                        SwiftUI.Button(role: .destructive) {
                            Task {
                                await viewModel.resetToOriginalState()
                            }
                        } label: {
                            Label(
                                "Reset Catalog",
                                systemImage: "arrow.circlepath"
                            )
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Server List URL")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if isEditingURL {
                            TextField(
                                "https://...",
                                text: $editingURLText
                            )
                            .font(.subheadline)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
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
                            exportCatalog(unmodified: false)
                        } label: {
                            Label(
                                "Export Current",
                                systemImage: "square.and.arrow.up"
                            )
                        }

                        if viewModel.source != AnisetteViewModel.defaultSource {
                            SwiftUI.Button(role: .destructive) {
                                viewModel.source =
                                    AnisetteViewModel.defaultSource

                                UserDefaults.standard.menuAnisetteList =
                                    AnisetteViewModel.defaultSource

                                Task {
                                    await viewModel.fetchServers(
                                        forceRemote: true
                                    )
                                }
                            } label: {
                                Label(
                                    "Reset Source to Default",
                                    systemImage: "arrow.circlepath"
                                )
                            }
                        }

                        SwiftUI.Button(role: .destructive) {
                            Task {
                                await viewModel.resetToOriginalState()
                            }
                        } label: {
                            Label(
                                "Reset Catalog",
                                systemImage: "arrow.circlepath"
                            )
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Server Catalog Source")

                    Spacer()

                    if !viewModel.isOfflineMode {
                        SwiftUI.Button(
                            isEditingURL ? "Done" : "Edit"
                        ) {
                            if isEditingURL {
                                isEditingURL = false

                                let trimmed = editingURLText.trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                )

                                if !trimmed.isEmpty &&
                                   trimmed != viewModel.source {
                                    viewModel.source = trimmed
                                    UserDefaults.standard.menuAnisetteList =
                                        trimmed

                                    Task {
                                        await viewModel.fetchServers(
                                            forceRemote: true
                                        )
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
                    Text(
                        "Currently using imported file '\(viewModel.importedFileName ?? "custom.json")'. Press and hold row to export."
                    )
                } else {
                    Text(
                        "URL of the JSON file containing registered Anisette servers. Press and hold row to export."
                    )
                }
            }

            // Section 3: Customization

            Section {
                Toggle(
                    isOn: Binding(
                        get: {
                            !UserDefaults.standard.disableAnisetteRotation
                        },
                        set: {
                            UserDefaults.standard.disableAnisetteRotation = !$0
                        }
                    )
                ) {
                    Label(
                        "Enable Auto Rotation",
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                }
            } header: {
                Text("Customization")
            } footer: {
                Text(
                    "Control if SideStore automatically rotates/retries servers upon failure."
                )
            }

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
    }

    // MARK: Server Row

    @ViewBuilder
    private func serverRow(
        _ item: AnisetteServerItem,
        index: Int
    ) -> some View {
        SwiftUI.Button {
            selectedServerURL = item.address
            UserDefaults.standard.menuAnisetteURL = item.address
            // SideInstaller: picking a server turns Auto off so only that server is used
            UserDefaults.standard.set(false, forKey: "anisetteServerAuto")
            UserDefaults.standard.disableAnisetteRotation = true
        } label: {
            HStack(spacing: 12) {
                Text("#\(index + 1)")
                    .font(.subheadline.monospacedDigit().weight(.bold))
                    .foregroundColor(.secondary)
                    .frame(minWidth: 26, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.name)
                            .font(.body)
                            .foregroundColor(
                                item.isHidden ? .secondary : .primary
                            )

                        if item.isHidden {
                            Text("Hidden")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill(
                                        Color.secondary.opacity(0.2)
                                    )
                                )
                        }

                        if viewModel.customServerAddresses.contains(item.address) {
                            Text("Custom")
                                .font(.caption2)
                                .foregroundColor(.accentColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill(
                                        Color.accentColor.opacity(0.12)
                                    )
                                )
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
        .swipeActions(
            edge: .trailing,
            allowsFullSwipe: false
        ) {
            if viewModel.customServerAddresses.contains(item.address) {
                SwiftUI.Button(role: .destructive) {
                    selectedServerURL =
                        viewModel.removeCustomServer(item: item)
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            } else {
                SwiftUI.Button {
                    viewModel.toggleHide(item: item)
                } label: {
                    Label(
                        item.isHidden ? "Unhide" : "Hide",
                        systemImage: item.isHidden ? "eye" : "eye.slash"
                    )
                }
                .tint(item.isHidden ? .blue : .orange)
            }
        }
        #endif
    }

    // MARK: Export Helper

    private func exportCatalog(unmodified: Bool) {
        Task {
            if let url = await viewModel.exportCatalog(
                unmodified: unmodified
            ) {
                exportFileURL = url
                showingShareSheet = true
            }
        }
    }
}
