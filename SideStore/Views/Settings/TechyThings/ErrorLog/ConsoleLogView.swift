//
//  ConsoleLogView.swift
//  SideStore
//
//  Created by Magesh K on 29/12/24.
//  Copyright © 2024 SideStore. All rights reserved.
//
import SwiftUI
import UniformTypeIdentifiers

enum LogSource: Equatable {
    case console
    case widget
    case imported(url: URL)
}

@MainActor
class ConsoleLogViewModel: ObservableObject {
    @Published var logLines: [String] = []
    @Published var activeSource: LogSource = .console
    @Published var importedURL: URL? = nil
    
    @Published var searchTerm: String = ""
    @Published var currentSearchIndex: Int = 0
    @Published var searchResults: [Int] = []  // Stores indices of matching lines
    
    private let safeSizeLimit: UInt64 = 15 * 1024 * 1024
    
    private var fileWatcher: DispatchSourceFileSystemObject?
    let consoleLogURL: URL
    let widgetLogURL: URL
    private var currentSecurityScopedURL: URL?
    private var lastReadOffset: UInt64 = 0
    
    var activeLogURL: URL {
        switch activeSource {
        case .console:
            return consoleLogURL
        case .widget:
            return widgetLogURL
        case .imported(let url):
            return url
        }
    }
    
    var activeHeaderTitle: String {
        switch activeSource {
        case .console:
            return "Console Log"
        case .widget:
            return "Widget Log"
        case .imported(let url):
            return url.lastPathComponent
        }
    }
    
    init(logURL: URL) {
        self.consoleLogURL = logURL
        
        self.widgetLogURL = WidgetLogManager.widgetLogURL
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("widget.log")
        
        startFileWatcher() // Start monitoring the initial log file for changes
        
        Task {
            await reloadLogData(isInitial: true)
        }
    }
    
    func setSource(_ source: LogSource) {
        guard activeSource != source else { return }
        activeSource = source
        resetAndReload()
    }
    
    func importLog(from url: URL) {
        // Access security-scoped resource if needed
        if url.startAccessingSecurityScopedResource() {
            currentSecurityScopedURL?.stopAccessingSecurityScopedResource()
            currentSecurityScopedURL = url
        }
        
        self.importedURL = url
        self.activeSource = .imported(url: url)
        resetAndReload()
    }
    
    func clearImportedLog() {
        if case .imported = activeSource {
            activeSource = .console
        }
        currentSecurityScopedURL?.stopAccessingSecurityScopedResource()
        currentSecurityScopedURL = nil
        importedURL = nil
        resetAndReload()
    }
    
    private func resetAndReload() {
        fileWatcher?.cancel()
        fileWatcher = nil
        lastReadOffset = 0
        logLines = []
        searchTerm = ""
        searchResults = []
        currentSearchIndex = 0
        
        startFileWatcher()
        Task {
            await reloadLogData(isInitial: true)
        }
    }
    
    private func startFileWatcher() {
        let targetURL = activeLogURL
        let fileDescriptor = open(targetURL.path, O_RDONLY)
        guard fileDescriptor != -1 else {
            debugLog("Unable to open file for reading at \(targetURL.path)")
            return
        }
        
        let queue = DispatchQueue(label: "com.myapp.backgroundQueue", qos: .background)
        fileWatcher = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fileDescriptor, eventMask: .write, queue: queue)
        fileWatcher?.setEventHandler { [weak self] in
            Task { [weak self] in
                await self?.reloadLogData(isInitial: false)
            }
        }
        fileWatcher?.setCancelHandler {
            close(fileDescriptor)
        }
        fileWatcher?.resume()
    }
    
    private func reloadLogData(isInitial: Bool) async {
        let targetURL = self.activeLogURL
        let lastReadOffset = self.lastReadOffset
        let safeSizeLimit = self.safeSizeLimit
        
        let result = await Task.detached(priority: .userInitiated) { () -> (lines: [String], newOffset: UInt64, isReset: Bool)? in
            do {
                let fileHandle = try FileHandle(forReadingFrom: targetURL)
                defer { try? fileHandle.close() }
                
                let currentSize = try fileHandle.seekToEnd()
                
                if currentSize > safeSizeLimit && isInitial {
                    let startOffset = currentSize - safeSizeLimit
                    try fileHandle.seek(toOffset: startOffset)
                    if let data = try fileHandle.readToEnd() {
                        let content = String(decoding: data, as: UTF8.self)
                        let lines = content.split(whereSeparator: \.isNewline).map { String($0) }
                        let formattedLimit = ByteCountFormatter.string(fromByteCount: Int64(safeSizeLimit), countStyle: .file)
                        var formattedLines = ["--- [File truncated: showing last \(formattedLimit) of log] ---"]
                        formattedLines.append(contentsOf: lines)
                        return (formattedLines, currentSize, true)
                    }
                }
                
                if isInitial || currentSize < lastReadOffset {
                    try fileHandle.seek(toOffset: 0)
                    if let data = try fileHandle.readToEnd() {
                        let content = String(decoding: data, as: UTF8.self)
                        let lines = content.split(whereSeparator: \.isNewline).map { String($0) }
                        return (lines, currentSize, true)
                    }
                } else if currentSize > lastReadOffset {
                    try fileHandle.seek(toOffset: lastReadOffset)
                    if let data = try fileHandle.readToEnd() {
                        let content = String(decoding: data, as: UTF8.self)
                        let lines = content.split(whereSeparator: \.isNewline).map { String($0) }
                        return (lines, currentSize, false)
                    }
                }
            } catch {
                debugLog("Error reading log file at \(targetURL.path): \(error)")
            }
            return nil
        }.value
        
        guard let result = result else { return }
        
        self.lastReadOffset = result.newOffset
        if result.isReset {
            self.logLines = result.lines
        } else {
            self.logLines.append(contentsOf: result.lines)
        }
    }
    
    deinit {
        fileWatcher?.cancel()
        currentSecurityScopedURL?.stopAccessingSecurityScopedResource()
    }
    
    func performSearch() {
        searchResults = logLines.enumerated()
            .filter { $0.element.localizedCaseInsensitiveContains(searchTerm) }
            .map { $0.offset }
    }
    
    func nextSearchResult() {
        guard !searchResults.isEmpty else { return }
        currentSearchIndex = (currentSearchIndex + 1) % searchResults.count
    }
    
    func previousSearchResult() {
        guard !searchResults.isEmpty else { return }
        currentSearchIndex = (currentSearchIndex - 1 + searchResults.count) % searchResults.count
    }
}


public struct ConsoleLogView: View {
    
    @ObservedObject var viewModel: ConsoleLogViewModel
    @State private var scrollToBottom: Bool = false  // State variable to trigger scroll
    @State private var searchBarState: Bool = false
    @FocusState private var isSearchFieldFocused: Bool
    
    @State private var searchText: String = ""
    @State private var scrollToIndex: Int?
    @State private var showTimestamp: Bool = false
    @State private var showShareSheet: Bool = false
    @State private var showFileImporter: Bool = false
    @State private var fontSize: CGFloat = 12
    @State private var visibleIndices: Set<Int> = []
    @State private var showCopiedBanner: Bool = false
    #if os(tvOS)
    @State private var showTvMenu: Bool = false
    #endif
    
    private let resultHighlightColor = Color.orange
    private let resultHighlightOpacity = 0.5
    private let otherResultsColor = Color.yellow
    private let otherResultsOpacity = 0.3

    init(logURL: URL) {
        self.viewModel = ConsoleLogViewModel(logURL: logURL)
    }
    
    public var body: some View {
       VStack {
           
           // Custom Header Bar (similar to QuickLook's preview screen)
           HStack(spacing: 12) {
               Text(viewModel.activeHeaderTitle)
                   .font(.system(size: 22, weight: .semibold))
                   .foregroundColor(.white)
                   .lineLimit(1)
               Spacer()
               
               if(!searchBarState){
                   SwiftUI.Button(action: {
                       searchBarState.toggle()
                   }) {
                       Image(systemName: "magnifyingglass")
                           .foregroundColor(.white)
                           .imageScale(.large)
                   }
               }

                SwiftUI.Button(action: {
                    fontSize = max(6, fontSize - 1)
                }) {
                    Image(systemName: "minus")
                        .foregroundColor(.white)
                        .imageScale(.medium)
                }
                
                SwiftUI.Button(action: {
                    fontSize = min(30, fontSize + 1)
                }) {
                    Image(systemName: "plus")
                        .foregroundColor(.white)
                        .imageScale(.medium)
                }
                
                SwiftUI.Button(action: {
                    showTimestamp.toggle()
                }) {
                    Image(systemName: showTimestamp ? "clock.fill" : "clock")
                        .foregroundColor(.white)
                        .font(.system(size: 19))
                }

                SwiftUI.Button(action: {
                    #if !os(tvOS)
                    showShareSheet = true
                    #else
                    if let topVC = UIApplication.shared.topViewController() {
                        TVWebFileTransferManager.shared.startExport(fileURL: viewModel.activeLogURL, title: "Export Log", presentingVC: topVC)
                    }
                    #endif
                }) {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundColor(.white)
                        .font(.system(size: 19))
                }
                
                #if !os(tvOS)
                Menu {
                    SwiftUI.Button(action: {
                        viewModel.setSource(.console)
                    }) {
                        HStack {
                            Text("Console Log")
                            if viewModel.activeSource == .console {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    
                    SwiftUI.Button(action: {
                        viewModel.setSource(.widget)
                    }) {
                        HStack {
                            Text("Widget Log")
                            if viewModel.activeSource == .widget {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    
                    if let importedURL = viewModel.importedURL {
                        SwiftUI.Button(action: {
                            viewModel.setSource(.imported(url: importedURL))
                        }) {
                            HStack {
                                Text(String(format: NSLocalizedString("Imported Log\n(%@)", comment: ""), importedURL.lastPathComponent))
                                if case .imported = viewModel.activeSource {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                    
                    Divider()
                    
                    if viewModel.importedURL == nil {
                        SwiftUI.Button(action: {
                            showFileImporter = true
                        }) {
                            Label("Import Log...", systemImage: "square.and.arrow.down")
                        }
                    } else {
                        SwiftUI.Button(role: .destructive, action: {
                            viewModel.clearImportedLog()
                        }) {
                            Label("Remove Imported", systemImage: "xmark.circle")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundColor(.white)
                        .imageScale(.large)
                } primaryAction: {
                    scrollToBottom.toggle()
                }
                #else
                SwiftUI.Button(action: {
                    showTvMenu = true
                }) {
                    Image(systemName: "ellipsis")
                        .foregroundColor(.white)
                        .imageScale(.large)
                }
                #endif
           }
           .padding(15)
           .padding(.top, 5)
           .padding(.bottom, 2.5)
           .background(Color.black.opacity(0.9))
           .overlay(
               Rectangle()
                   .frame(height: 1)
                   .foregroundColor(Color.gray.opacity(0.2)), alignment: .bottom
           )

           if(searchBarState){
               // Search bar
              HStack {
                  Image(systemName: "magnifyingglass")
                      .foregroundColor(.gray)
                      .padding(.trailing, 4)

                   TextField("Search", text: $searchText)
                       #if !os(tvOS)
                       .textFieldStyle(RoundedBorderTextFieldStyle())
                       #endif
                       .onChange(of: searchText) { newValue in
                           viewModel.searchTerm = newValue
                           viewModel.performSearch()
                       }
                       #if !os(tvOS)
                       .keyboardShortcut("f", modifiers: .command) // Focus search field
                       #endif
                   
                   if !searchText.isEmpty {
                       // Search navigation buttons
                       SwiftUI.Button(action: {
                           viewModel.previousSearchResult()
                           scrollToIndex = viewModel.searchResults[viewModel.currentSearchIndex]
                       }) {
                           Image(systemName: "chevron.up")
                       }
                       #if !os(tvOS)
                       .keyboardShortcut(.return, modifiers: [.command, .shift])
                       #endif
                       .disabled(viewModel.searchResults.isEmpty)
                       
                       SwiftUI.Button(action: {
                           viewModel.nextSearchResult()
                           scrollToIndex = viewModel.searchResults[viewModel.currentSearchIndex]
                       }) {
                           Image(systemName: "chevron.down")
                       }
                       #if !os(tvOS)
                       .keyboardShortcut(.return, modifiers: .command)
                       #endif
                       .disabled(viewModel.searchResults.isEmpty)

                       // Results counter
                       Text(String(format: NSLocalizedString("%d/%d", comment: ""), viewModel.currentSearchIndex + 1, viewModel.searchResults.count))
                           .foregroundColor(.gray)
                           .font(.caption)
                   }
                  
                  SwiftUI.Button(action: {
                      searchBarState.toggle()
                  }) {
                      Image(systemName: "xmark")
                  }
              }
              .padding(.horizontal, 15)
           }

           

           // Main Log Display (scrollable area)
            ScrollView(.vertical) {
                ScrollViewReader { proxy in
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(viewModel.logLines.indices, id: \.self) { index in
                            let line = viewModel.logLines[index]
                            let displayLine = showTimestamp ? line : stripTimestamp(from: line)
                             Text(displayLine)
                                 .font(.system(size: fontSize, design: .monospaced))
                                 .foregroundColor(.white)
                                 #if !os(tvOS)
                                 .textSelection(.enabled)
                                 #endif
                                .background(
                                    viewModel.searchResults.contains(index) ?
                                    otherResultsColor.opacity(otherResultsOpacity) : Color.clear
                                )
                                .background(
                                    viewModel.searchResults[safe: viewModel.currentSearchIndex] == index ?
                                    resultHighlightColor.opacity(resultHighlightOpacity) : Color.clear
                                )
                                .onAppear {
                                    visibleIndices.insert(index)
                                }
                                .onDisappear {
                                    visibleIndices.remove(index)
                                }
                        }
                    }
                    .onChange(of: scrollToIndex) { newIndex in
                        if let index = newIndex {
                            withAnimation {
                                proxy.scrollTo(index, anchor: .center)
                            }
                        }
                    }
                    .onChange(of: scrollToBottom) { _ in
                        viewModel.logLines.indices.last.map { last in
                            proxy.scrollTo(last, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(Color.black)  // Set background color to mimic QL's dark theme
        .edgesIgnoringSafeArea(.all)
        #if !os(tvOS)
        .sheet(isPresented: $showShareSheet) {
            ActivityViewController(activityItems: [viewModel.activeLogURL])
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.plainText, .text, .data, UTType(filenameExtension: "log") ?? .plainText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let selectedURL = urls.first else { return }
                viewModel.importLog(from: selectedURL)
            case .failure(let error):
                debugLog("Failed to select log file: \(error)")
            }
        }
        #else
        .confirmationDialog("Logs Menu", isPresented: $showTvMenu) {
            SwiftUI.Button("Console Log") { viewModel.setSource(.console) }
            SwiftUI.Button("Widget Log") { viewModel.setSource(.widget) }
            if let importedURL = viewModel.importedURL {
                SwiftUI.Button(String(format: NSLocalizedString("Imported Log (%@)", comment: ""), importedURL.lastPathComponent)) { viewModel.setSource(.imported(url: importedURL)) }
            }
            if viewModel.importedURL == nil {
                SwiftUI.Button("Import Log...") {
                    if let topVC = UIApplication.shared.topViewController() {
                        TVWebFileTransferManager.shared.startImport(acceptedExtensions: ["log", "txt"], title: "Import Log File", presentingVC: topVC) { fileURL in
                            guard let fileURL = fileURL else { return }
                            viewModel.importLog(from: fileURL)
                        }
                    }
                }
            } else {
                SwiftUI.Button("Remove Imported", role: .destructive) { viewModel.clearImportedLog() }
            }
            SwiftUI.Button("Scroll to Bottom") { scrollToBottom.toggle() }
        }
        #endif
        .overlay(
            Group {
                if showCopiedBanner {
                    Text("Copied Visible Logs to Clipboard")
                        .font(.caption)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.gray.opacity(0.9))
                        .foregroundColor(.white)
                        .cornerRadius(20)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, 50)
                }
            },
            alignment: .top
        )
    }

    private func copyVisibleLogs() {
        let sortedIndices = visibleIndices.sorted()
        guard !sortedIndices.isEmpty else { return }
        let linesToCopy = sortedIndices.compactMap { idx -> String? in
            guard viewModel.logLines.indices.contains(idx) else { return nil }
            let line = viewModel.logLines[idx]
            return showTimestamp ? line : stripTimestamp(from: line)
        }
        let textToCopy = linesToCopy.joined(separator: "\n")
        #if !os(tvOS)
        UIPasteboard.general.string = textToCopy
        #endif
        withAnimation {
            showCopiedBanner = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showCopiedBanner = false
            }
        }
    }

    private static let timestampRegex = try? NSRegularExpression(
        pattern: "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\\.[0-9]{3} \\[[A-Z]\\]: ",
        options: []
    )

    private func stripTimestamp(from line: String) -> String {
        guard let regex = Self.timestampRegex else { return line }
        let range = NSRange(location: 0, length: line.utf16.count)
        if let match = regex.firstMatch(in: line, range: range) {
            let matchRange = Range(match.range, in: line)!
            return String(line[matchRange.upperBound...])
        }
        return line
    }
}

// Helper extension for safe array access
extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
