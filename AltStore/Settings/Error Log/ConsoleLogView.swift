//
//  ConsoleLogView.swift
//  AltStore
//
//  Created by Magesh K on 29/12/24.
//  Copyright © 2024 SideStore. All rights reserved.
//
import SwiftUI

class ConsoleLogViewModel: ObservableObject {
    @Published var logLines: [String] = []
    
    @Published var searchTerm: String = ""
    @Published var currentSearchIndex: Int = 0
    @Published var searchResults: [Int] = []  // Stores indices of matching lines
    
    private var fileWatcher: DispatchSourceFileSystemObject?
    
    private let backgroundQueue = DispatchQueue(label: "com.myapp.backgroundQueue", qos: .background)
    private var logURL: URL
    
    init(logURL: URL) {
        self.logURL = logURL
        startFileWatcher() // Start monitoring the log file for changes
        reloadLogData() // Load initial log data
    }
    
    private func startFileWatcher() {
        let fileDescriptor = open(logURL.path, O_RDONLY)
        guard fileDescriptor != -1 else {
            print("Unable to open file for reading.")
            return
        }
        
        fileWatcher = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fileDescriptor, eventMask: .write, queue: backgroundQueue)
        fileWatcher?.setEventHandler {
            self.reloadLogData()
        }
        fileWatcher?.resume()
    }
    
    private func reloadLogData() {
        if let fileContents = try? String(contentsOf: logURL) {
            let lines = fileContents.split(whereSeparator: \.isNewline).map { String($0) }
            DispatchQueue.main.async {
                self.logLines = lines
            }
        }
    }
    
    deinit {
        fileWatcher?.cancel()
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
           HStack {
               Text("Console Log")
                   .font(.system(size: 22, weight: .semibold))
                   .foregroundColor(.white)
               Spacer()
               
               if(!searchBarState){
                   SwiftUI.Button(action: {
                       searchBarState.toggle()
                   }) {
                       Image(systemName: "magnifyingglass")
                           .foregroundColor(.white)
                           .imageScale(.large)
                   }
                   .padding(.trailing)
               }
               SwiftUI.Button(action: {
                   scrollToBottom.toggle()
               }) {
                   Image(systemName: "ellipsis")
                       .foregroundColor(.white)
                       .imageScale(.large)
               }
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
                      .textFieldStyle(RoundedBorderTextFieldStyle())
                      .onChange(of: searchText) { newValue in
                          viewModel.searchTerm = newValue
                          viewModel.performSearch()
                      }
                      .keyboardShortcut("f", modifiers: .command) // Focus search field
                  
                  if !searchText.isEmpty {
                      // Search navigation buttons
                      SwiftUI.Button(action: {
                          viewModel.previousSearchResult()
                          scrollToIndex = viewModel.searchResults[viewModel.currentSearchIndex]
                      }) {
                          Image(systemName: "chevron.up")
                      }
                      .keyboardShortcut(.return, modifiers: [.command, .shift])
                      .disabled(viewModel.searchResults.isEmpty)
                      
                      SwiftUI.Button(action: {
                          viewModel.nextSearchResult()
                          scrollToIndex = viewModel.searchResults[viewModel.currentSearchIndex]
                      }) {
                          Image(systemName: "chevron.down")
                      }
                      .keyboardShortcut(.return, modifiers: .command)
                      .disabled(viewModel.searchResults.isEmpty)

                      // Results counter
                      Text("\(viewModel.currentSearchIndex + 1)/\(viewModel.searchResults.count)")
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
                            Text(viewModel.logLines[index])
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.white)
                                .background(
                                    viewModel.searchResults.contains(index) ?
                                    otherResultsColor.opacity(otherResultsOpacity) : Color.clear
                                )
                                .background(
                                    viewModel.searchResults[safe: viewModel.currentSearchIndex] == index ?
                                    resultHighlightColor.opacity(resultHighlightOpacity) : Color.clear
                                )
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
    }
}

// Helper extension for safe array access
extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
