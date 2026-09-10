//
//  BundleResourceBrowserView.swift
//  SideStore
//
//  Created by Magesh K on 2/7/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
#if !os(tvOS)
import QuickLook
#endif
import SideSign
import CodeSignKit

// MARK: - Bundle Item Model

struct BundleItem: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    let isDirectory: Bool
    let fileSize: Int64
    let childCount: Int
}

// MARK: - Bundle Resource Browser View

struct BundleResourceBrowserView: View {
    let rootURL: URL
    let title: String

    @State private var items: [BundleItem] = []
    @State private var searchQuery = ""
    @State private var isLoaded = false
    @State private var isSelecting = false
    @State private var selectedURLs: Set<URL> = []
    @State private var showingShareSheet = false

    var filteredItems: [BundleItem] {
        guard !searchQuery.isEmpty else { return items }
        return items.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) }
    }

    var body: some View {
        List {
            if filteredItems.isEmpty {
                Text(items.isEmpty ? NSLocalizedString("Empty directory", comment: "") : NSLocalizedString("No results", comment: ""))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(filteredItems) { item in
                    BundleItemRow(
                        item: item,
                        isSelecting: isSelecting,
                        isSelected: selectedURLs.contains(item.url),
                        onToggleSelection: {
                            if selectedURLs.contains(item.url) {
                                selectedURLs.remove(item.url)
                            } else if !item.isDirectory {
                                selectedURLs.insert(item.url)
                            }
                        }
                    )
                }
            }
        }
        #if !os(tvOS)
        .listStyle(InsetGroupedListStyle())
        .navigationBarTitleDisplayMode(.inline)
        #else
        .listStyle(GroupedListStyle())
        #endif
        .navigationTitle(isSelecting
            ? (selectedURLs.isEmpty ? "Select Files" : "\(selectedURLs.count) selected")
            : title)
        .searchable(text: $searchQuery, prompt: "Search files")
        .toolbar {
            // Trailing: Select / Done
            ToolbarItem(placement: .navigationBarTrailing) {
                SwiftUI.Button(isSelecting ? "Done" : "Select") {
                    withAnimation {
                        isSelecting.toggle()
                        if !isSelecting { selectedURLs.removeAll() }
                    }
                }
            }
            #if !os(tvOS)
            // Leading Share
            ToolbarItem(placement: .navigationBarLeading) {
                if isSelecting && !selectedURLs.isEmpty {
                    SwiftUI.Button {
                        showingShareSheet = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            #endif
        }
        #if !os(tvOS)
        .sheet(isPresented: $showingShareSheet) {
            ActivityView(items: Array(selectedURLs))
        }
        #endif
        .onAppear {
            guard !isLoaded else { return }
            isLoaded = true
            loadItems()
        }
    }

    private func loadItems() {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        items = contents.compactMap { url -> BundleItem? in
            guard let rv = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey]) else { return nil }
            let isDir = rv.isDirectory ?? false
            let size = Int64(rv.fileSize ?? 0)
            let count = isDir ? ((try? FileManager.default.contentsOfDirectory(atPath: url.path).count) ?? 0) : 0
            return BundleItem(url: url, name: url.lastPathComponent, isDirectory: isDir, fileSize: size, childCount: count)
        }
        .sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}

// MARK: - Bundle Item Row

struct BundleItemRow: View {
    let item: BundleItem
    var isSelecting: Bool = false
    var isSelected: Bool = false
    var onToggleSelection: (() -> Void)? = nil

    private let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "tiff", "heic", "bmp", "ico"]
    private let textExtensions: Set<String> = [
        "txt", "log", "md", "xml", "json", "html", "htm", "js", "css",
        "swift", "m", "mm", "c", "cpp", "h", "strings", "stringsdict"
    ]

    var body: some View {
        if isSelecting {
            SwiftUI.Button(action: { onToggleSelection?() }) {
                rowContent(selected: isSelected)
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(destination: destination) {
                rowContent(selected: false)
            }
        }
    }

    @ViewBuilder
    private func rowContent(selected: Bool) -> some View {
        HStack(spacing: 12) {
            // Selection indicator or file icon
            if isSelecting {
                Image(systemName: selected ? "checkmark.circle.fill" : (item.isDirectory ? "minus.circle" : "circle"))
                    .font(.system(size: 22))
                    #if !os(tvOS)
                    .foregroundColor(selected ? .accentColor : (item.isDirectory ? Color(.systemGray3) : Color(.systemGray2)))
                    #else
                    .foregroundColor(selected ? .accentColor : (item.isDirectory ? Color.gray.opacity(0.6) : Color.gray))
                    #endif
                    .frame(width: 28)
            } else {
                Image(systemName: fileIcon)
                    .font(.system(size: 20))
                    .foregroundColor(iconColor)
                    .frame(width: 28)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()

            // In select mode still show file icon on the right
            if isSelecting {
                Image(systemName: fileIcon)
                    .font(.system(size: 16))
                    .foregroundColor(iconColor)
                    .opacity(0.5)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private var isMachOItem: Bool {
        !item.isDirectory && CodeSignKit.MachOParser.isMachOBinary(at: item.url)
    }

    private var isCodeResourcesItem: Bool {
        !item.isDirectory && (item.name.lowercased() == "coderesources" || item.url.pathExtension.lowercased() == "coderesources")
    }

    private var isMobileProvisionItem: Bool {
        !item.isDirectory && (item.url.pathExtension.lowercased() == "mobileprovision" || item.name.hasSuffix(".mobileprovision"))
    }

    @ViewBuilder
    private var destination: some View {
        let ext = item.url.pathExtension.lowercased()
        if item.isDirectory {
            BundleResourceBrowserView(rootURL: item.url, title: item.name)
        } else if isMachOItem {
            MachOResourceViewer(url: item.url)
        } else if isCodeResourcesItem {
            CodeResourcesViewer(url: item.url)
        } else if isMobileProvisionItem {
            ProvisioningProfileResourceViewer(url: item.url)
        } else if ext == "ipa" {
            IPAContentsView(ipaURL: item.url)
        } else if ext == "plist" {
            PlistResourceViewer(url: item.url)
        } else if imageExtensions.contains(ext) {
            ResourceImageViewer(url: item.url)
        } else if textExtensions.contains(ext) {
            ResourceTextViewer(url: item.url)
        } else {
            #if !os(tvOS)
            QLPreviewControllerView(url: item.url)
            #else
            ResourceTextViewer(url: item.url)
            #endif
        }
    }

    private var subtitle: String {
        if item.isDirectory {
            return "\(item.childCount) item\(item.childCount == 1 ? "" : "s")"
        }
        let fmt = ByteCountFormatter()
        fmt.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        fmt.countStyle = .file
        return fmt.string(fromByteCount: item.fileSize)
    }

    private var fileIcon: String {
        if item.isDirectory {
            switch item.name.lowercased() {
            case "plugins", "plugIns": return "puzzlepiece.extension.fill"
            case "frameworks": return "square.stack.3d.up.fill"
            case "resources": return "archivebox.fill"
            case "_codesignature": return "lock.shield.fill"
            default: return "folder.fill"
            }
        }
        if isMachOItem {
            return "cpu.fill"
        }
        if isCodeResourcesItem {
            return "doc.badge.gearshape.fill"
        }
        if isMobileProvisionItem {
            return "lock.shield.fill"
        }
        switch item.url.pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "webp", "tiff", "heic", "bmp", "ico": return "photo"
        case "mp3", "wav", "aac", "m4a", "aiff", "caf": return "music.note"
        case "mp4", "mov", "avi", "mkv", "m4v": return "video"
        case "pdf": return "doc.richtext"
        case "plist": return "list.bullet.rectangle"
        case "xml": return "chevron.left.forwardslash.chevron.right"
        case "json": return "curlybraces"
        case "txt", "log", "md": return "doc.plaintext"
        case "ipa": return "app.badge"
        case "appex": return "puzzlepiece.extension"
        case "dylib", "so", "a": return "cpu"
        case "mobileprovision": return "lock.shield"
        case "car": return "paintpalette"
        case "nib", "xib": return "rectangle.on.rectangle"
        case "storyboard": return "rectangle.3.group"
        case "strings", "stringsdict": return "textformat"
        case "ttf", "otf": return "textformat.alt"
        case "zip", "gz", "bz2": return "archivebox"
        case "html", "htm": return "globe"
        case "swift", "m", "mm", "c", "cpp", "h": return "doc.text"
        default: return "doc"
        }
    }

    private var iconColor: Color {
        if item.isDirectory { return .blue }
        if isMachOItem { return .indigo }
        if isCodeResourcesItem { return .teal }
        if isMobileProvisionItem { return .yellow }
        switch item.url.pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "webp", "tiff", "heic", "bmp", "ico": return .orange
        case "mp3", "wav", "aac", "m4a", "aiff", "caf": return .pink
        case "mp4", "mov", "avi", "mkv", "m4v": return .purple
        case "pdf": return .red
        case "plist", "xml", "json": return .green
        case "ipa": return .blue
        case "appex": return .indigo
        case "mobileprovision": return .yellow
        case "dylib", "so", "a", "car": return .gray
        #if !os(tvOS)
        default: return Color(.systemGray2)
        #else
        default: return Color.gray
        #endif
        }
    }
}

// MARK: - IPA Extraction State 
final class IPAExtraction: ObservableObject {
    @Published var bundleURL: URL? = nil
    @Published var isExtracting = true
    @Published var error: String? = nil

    private var tempDir: URL? = nil

    func extract(from ipaURL: URL) async {
        guard bundleURL == nil else { return }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BundleInspect_\(UUID().uuidString)")
        do {
            let appURL = try await Task.detached(priority: .userInitiated) {
                try FileManager.default.unzipAppBundle(at: ipaURL, to: dir)
            }.value
            await MainActor.run {
                self.tempDir = dir
                self.bundleURL = appURL
                self.isExtracting = false
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.isExtracting = false
            }
            try? FileManager.default.removeItem(at: dir)
        }
    }

    deinit {
        // Only runs when the view is truly popped — not on forward navigation
        if let dir = tempDir {
            try? FileManager.default.removeItem(at: dir)
        }
    }
}

// MARK: - IPA Contents View

struct IPAContentsView: View {
    let ipaURL: URL
    @StateObject private var extraction = IPAExtraction()

    var body: some View {
        Group {
            if let bundleURL = extraction.bundleURL {
                FullAppBundleView(bundleURL: bundleURL)
            } else if extraction.isExtracting {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text(String(format: NSLocalizedString("Extracting %@\u{2026}", comment: ""), ipaURL.lastPathComponent))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(ipaURL.deletingPathExtension().lastPathComponent)
                #if !os(tvOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
            } else if let error = extraction.error {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 44))
                        .foregroundColor(.orange)
                    Text("Extraction Failed")
                        .font(.headline)
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(ipaURL.deletingPathExtension().lastPathComponent)
                #if !os(tvOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
            }
        }
        .task { await extraction.extract(from: ipaURL) }
    }
}


// MARK: - Full App Bundle View (for extracted IPA or any .app bundle URL)

struct FullAppBundleView: View {
    let bundleURL: URL
    @StateObject private var certificatesViewModel = CertificatesViewModel()

    private var infoPlist: [String: Any]? {
        NSDictionary(contentsOf: bundleURL.appendingPathComponent("Info.plist")) as? [String: Any]
    }

    private var provisioningProfile: ALTProvisioningProfile? {
        try? ALTProvisioningProfile(url: bundleURL.appendingPathComponent("embedded.mobileprovision"))
    }

    private var appExtensions: [URL] {
        let dir = bundleURL.appendingPathComponent("PlugIns")
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }
        return contents.filter { $0.pathExtension == "appex" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private var displayName: String {
        infoPlist?["CFBundleDisplayName"] as? String
            ?? infoPlist?["CFBundleName"] as? String
            ?? bundleURL.deletingPathExtension().lastPathComponent
    }

    var body: some View {
        List {
            // Header
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayName)
                        .font(.headline)
                    if let bundleID = infoPlist?["CFBundleIdentifier"] as? String {
                        Text(bundleID)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }

            // General Info — all from Info.plist
            Section(header: Text("General Info")) {
                let plist = infoPlist
                let bundleID = plist?["CFBundleIdentifier"] as? String ?? "N/A"
                let short = plist?["CFBundleShortVersionString"] as? String
                let build = plist?["CFBundleVersion"] as? String
                let versionStr: String = {
                    if let s = short, let b = build { return "\(s) (\(b))" }
                    return short ?? build ?? "N/A"
                }()

                InfoRow(label: "Bundle Identifier", value: bundleID)
                InfoRow(label: "Version", value: versionStr)
                if let minOS = plist?["MinimumOSVersion"] as? String {
                    InfoRow(label: "Min iOS", value: minOS)
                }
                if let exec = plist?["CFBundleExecutable"] as? String {
                    let execURL = bundleURL.appendingPathComponent(exec)
                    if FileManager.default.fileExists(atPath: execURL.path) && CodeSignKit.MachOParser.isMachOBinary(at: execURL) {
                        NavigationLink(destination: MachOResourceViewer(url: execURL)) {
                            HStack {
                                Text("Executable")
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                Spacer()
                                Text(exec)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        InfoRow(label: "Executable", value: exec)
                    }
                }
            }

            // Provisioning Profile — from embedded.mobileprovision
            if let profile = provisioningProfile {
                Section(header: Text("Provisioning Profile")) {
                    NavigationLink(destination: ProvisioningProfileDetailView(profile: profile, certificatesViewModel: certificatesViewModel)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(profile.name)
                                .font(.subheadline)
                            Text(String(format: NSLocalizedString("UUID: %@", comment: ""), profile.uuid.uuidString))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(String(format: NSLocalizedString("Expires: %@", comment: ""), formatDate(profile.expirationDate)))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            // Info.plist
            if let plist = infoPlist {
                Section(header: Text("Info.plist")) {
                    NavigationLink(destination: InfoPlistContainerView(plist: plist)) {
                        Text(String(format: NSLocalizedString("View Info.plist (%d keys)", comment: ""), plist.count))
                            .font(.subheadline)
                    }
                }
            }

            // App Extensions
            if !appExtensions.isEmpty {
                Section(header: Text(String(format: NSLocalizedString("App Extensions (%d)", comment: ""), appExtensions.count))) {
                    ForEach(appExtensions, id: \.path) { extURL in
                        let extPlist = NSDictionary(contentsOf: extURL.appendingPathComponent("Info.plist")) as? [String: Any]
                        let extName = extPlist?["CFBundleDisplayName"] as? String
                            ?? extPlist?["CFBundleName"] as? String
                            ?? extURL.deletingPathExtension().lastPathComponent
                        let extBundleID = extPlist?["CFBundleIdentifier"] as? String ?? "Unknown"
                        NavigationLink(destination: BundleInspectorView(bundleURL: extURL, certificatesViewModel: certificatesViewModel)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(extName)
                                    .font(.subheadline)
                                Text(extBundleID)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }

            // Resources — recursive browser
            Section(header: Text("Resources")) {
                NavigationLink(destination: BundleResourceBrowserView(rootURL: bundleURL, title: "Bundle Contents")) {
                    Text("Browse Bundle Contents")
                        .font(.subheadline)
                }
            }
        }
        #if !os(tvOS)
        .listStyle(InsetGroupedListStyle())
        .navigationBarTitleDisplayMode(.inline)
        #else
        .listStyle(GroupedListStyle())
        #endif
        .navigationTitle(displayName)
        .interactiveDismissDisabled(true)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Plist Resource Viewer (auto-routes to InfoPlistContainerView or raw text)

struct PlistResourceViewer: View {
    let url: URL

    @State private var plistDict: [String: Any]? = nil
    @State private var rawText: String = ""
    @State private var isLoaded = false

    var body: some View {
        Group {
            if let dict = plistDict {
                InfoPlistContainerView(plist: dict, title: url.lastPathComponent)
            } else {
                ScrollView {
                    Text(rawText.isEmpty ? "Loading\u{2026}" : rawText)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            }
        }
        .navigationTitle(url.lastPathComponent)
        #if !os(tvOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            guard !isLoaded else { return }
            isLoaded = true
            // Try as structured dict first (XML or binary plist)
            if let dict = NSDictionary(contentsOf: url) as? [String: Any] {
                plistDict = dict
            } else {
                rawText = (try? String(contentsOf: url, encoding: .utf8))
                    ?? (try? String(contentsOf: url, encoding: .isoLatin1))
                    ?? "(Cannot decode file)"
            }
        }
    }
}

// MARK: - Resource Image Viewer

struct ResourceImageViewer: View {
    let url: URL

    var body: some View {
        Group {
            if let uiImage = UIImage(contentsOfFile: url.path) {
                ScrollView([.horizontal, .vertical]) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .padding()
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "photo.slash")
                        .font(.system(size: 44))
                        .foregroundColor(.secondary)
                    Text("Could not load image")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(url.lastPathComponent)
        #if !os(tvOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - Resource Text Viewer

struct ResourceTextViewer: View {
    var url: URL? = nil
    var title: String? = nil
    var explicitContent: String? = nil

    @State private var content: String = ""
    @State private var isLoaded = false
    @State private var showingShareSheet = false

    var body: some View {
        ScrollView {
            Text(content.isEmpty ? "Loading\u{2026}" : content)
                .font(.system(size: 12, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(title ?? url?.lastPathComponent ?? "Text")
        #if !os(tvOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !content.isEmpty {
                    SwiftUI.Button {
                        UIPasteboard.general.string = content
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                }
            }
        }
        #endif
        .onAppear {
            guard !isLoaded else { return }
            isLoaded = true
            if let explicit = explicitContent {
                content = explicit
            } else if let url = url {
                content = (try? String(contentsOf: url, encoding: .utf8))
                    ?? (try? String(contentsOf: url, encoding: .isoLatin1))
                    ?? "(Cannot decode file as text)"
            }
        }
    }
}

#if !os(tvOS)
// MARK: - QuickLook Preview Controller Bridge

struct QLPreviewControllerView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

// MARK: - Activity View (Share Sheet)

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

// Provisioning Profile Resource Viewer Bridge
struct ProvisioningProfileResourceViewer: View {
    let url: URL
    @StateObject private var certificatesViewModel = CertificatesViewModel()

    var body: some View {
        Group {
            if let profile = try? ALTProvisioningProfile(url: url) {
                ProvisioningProfileDetailView(profile: profile, certificatesViewModel: certificatesViewModel)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 44))
                        .foregroundColor(.orange)
                    Text("Invalid Provisioning Profile")
                        .font(.headline)
                    Text(String(format: NSLocalizedString("Could not decode provisioning profile from %@.", comment: ""), url.lastPathComponent))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(url.lastPathComponent)
            }
        }
    }
}
