//
//  InfoPlistContainerView.swift
//  SideStore
//
//  Created by Magesh K on 2026-07-02.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import SideSign

// MARK: - Tree Node Model
struct PlistNode: Identifiable {
    let id = UUID()
    let key: String
    let value: String?
    let typeInfo: String
    let children: [PlistNode]?
    
    static func parse(key: String, value: Any) -> PlistNode {
        if let dict = value as? [String: Any] {
            let sortedChildren = dict.keys.sorted().map { parse(key: $0, value: dict[$0]!) }
            return PlistNode(key: key, value: nil, typeInfo: "Dictionary (\(dict.count) keys)", children: sortedChildren)
        } else if let array = value as? [Any] {
            let children = array.enumerated().map { parse(key: "Index \($0)", value: $1) }
            return PlistNode(key: key, value: nil, typeInfo: "Array (\(array.count) items)", children: children)
        } else if let data = value as? Data {
            let hex = data.map { String(format: "%02x", $0) }.joined()
            return PlistNode(key: key, value: hex, typeInfo: "Data (\(data.count) bytes)", children: nil)
        } else if let date = value as? Date {
            let str = ISO8601DateFormatter().string(from: date)
            return PlistNode(key: key, value: str, typeInfo: "Date", children: nil)
        } else {
            let typeStr: String
            if value is Bool {
                typeStr = "Boolean"
            } else if value is NSNumber {
                typeStr = "Number"
            } else {
                typeStr = "String"
            }
            return PlistNode(key: key, value: "\(value)", typeInfo: typeStr, children: nil)
        }
    }
}

// MARK: - InfoPlist Mode Enum
enum InfoPlistMode: String, CaseIterable, Identifiable {
    case semantic = "Semantic"
    case tree = "Tree"
    case rawJSON = "Raw JSON"
    case rawXML = "Raw XML"
    
    var id: String { self.rawValue }
}

// MARK: - Container View
struct InfoPlistContainerView: View {
    let plist: [String: Any]
    var title: String = "Info.plist"
    
    @State private var selectedMode: InfoPlistMode
    
    // Parent level cache to persist raw output between tab switches
    @State private var xmlString: String = ""
    @State private var jsonString: String = ""
    
    init(plist: [String: Any], title: String = "Info.plist") {
        self.plist = plist
        self.title = title
        let hasAppMetadata = plist["CFBundleDisplayName"] != nil ||
            plist["CFBundleName"] != nil ||
            plist["CFBundleIdentifier"] != nil ||
            plist["CFBundleShortVersionString"] != nil ||
            plist["CFBundleVersion"] != nil ||
            plist["MinimumOSVersion"] != nil
        _selectedMode = State(initialValue: hasAppMetadata ? .semantic : .tree)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Picker("Visualization Mode", selection: $selectedMode) {
                ForEach(InfoPlistMode.allCases) { mode in
                    Text(NSLocalizedString(mode.rawValue, comment: "")).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            #if !os(tvOS)
            .background(Color(.systemGroupedBackground))
            #else
            .background(Color.clear)
            #endif
            
            Divider()
            
            Group {
                switch selectedMode {
                case .tree:
                    InfoPlistTreeView(plist: plist)
                case .semantic:
                    InfoPlistSemanticView(plist: plist)
                case .rawJSON:
                    InfoPlistRawView(
                        plist: plist,
                        jsonString: $jsonString
                    )
                case .rawXML:
                    InfoPlistRawXMLView(
                        plist: plist,
                        xmlString: $xmlString
                    )
                }
            }
        }
        .navigationTitle(title)
        #if !os(tvOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .interactiveDismissDisabled(true)
    }
}

// MARK: - Mode 1: Tree View
struct InfoPlistTreeView: View {
    let plist: [String: Any]
    
    @State private var searchQuery = ""
    
    var rootNodes: [PlistNode] {
        let nodes = plist.keys.sorted().map { PlistNode.parse(key: $0, value: plist[$0]!) }
        if searchQuery.isEmpty {
            return nodes
        }
        return filterNodes(nodes, query: searchQuery)
    }
    
    var body: some View {
        List {
            ForEach(rootNodes) { node in
                PlistNodeRow(node: node)
            }
        }
        #if !os(tvOS)
        .listStyle(InsetGroupedListStyle())
        #else
        .listStyle(GroupedListStyle())
        #endif
        .searchable(text: $searchQuery, prompt: "Search keys")
    }
    
    private func filterNodes(_ nodes: [PlistNode], query: String) -> [PlistNode] {
        return nodes.compactMap { node in
            if node.key.localizedCaseInsensitiveContains(query) {
                return node
            }
            if let children = node.children {
                let filteredChildren = filterNodes(children, query: query)
                if !filteredChildren.isEmpty {
                    return PlistNode(key: node.key, value: node.value, typeInfo: node.typeInfo, children: filteredChildren)
                }
            }
            return nil
        }
    }
}

struct PlistNodeRow: View {
    let node: PlistNode
    
    @State private var isCopied = false
    
    var body: some View {
        #if !os(tvOS)
        if let children = node.children {
            DisclosureGroup {
                ForEach(children) { child in
                    PlistNodeRow(node: child)
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(node.key)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .bold()
                    Text(node.typeInfo)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .contextMenu {
                    SwiftUI.Button {
                        UIPasteboard.general.string = node.key
                    } label: {
                        Label("Copy Key", systemImage: "doc.on.doc")
                    }
                }
            }
        } else {
            leafRow
        }
        #else
        if let children = node.children {
            Section(header: Text(String(format: NSLocalizedString("%@ (%@)", comment: ""), node.key, node.typeInfo))) {
                ForEach(children) { child in
                    PlistNodeRow(node: child)
                }
            }
        } else {
            leafRow
        }
        #endif
    }
    
    private var leafRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(node.key)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .bold()
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(node.value ?? "N/A")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer()
            
            #if !os(tvOS)
            SwiftUI.Button {
                let textToCopy = node.value ?? ""
                UIPasteboard.general.string = textToCopy
                withAnimation {
                    isCopied = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation {
                        isCopied = false
                    }
                }
            } label: {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .font(.subheadline)
                    .foregroundColor(isCopied ? .green : .accentColor)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            #endif
        }
        .contentShape(Rectangle())
        #if !os(tvOS)
        .onTapGesture {
            let textToCopy = node.value ?? ""
            UIPasteboard.general.string = textToCopy
            withAnimation {
                isCopied = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation {
                    isCopied = false
                }
            }
        }
        #endif
    }
}

// MARK: - Mode 1.5: Raw XML View
struct InfoPlistRawXMLView: View {
    let plist: [String: Any]
    
    @State private var isCopied = false
    @State private var isWrapped = true
    
    @Binding var xmlString: String
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Spacer()
                    
                    SwiftUI.Button {
                        withAnimation {
                            isWrapped.toggle()
                        }
                    } label: {
                        Label(isWrapped ? NSLocalizedString("Wrap: On", comment: "") : NSLocalizedString("Wrap: Off", comment: ""), systemImage: isWrapped ? "text.alignleft" : "text.chevron.right")
                            .font(.footnote)
                    }
                    .buttonStyle(.bordered)
                    
                    #if !os(tvOS)
                    SwiftUI.Button {
                        UIPasteboard.general.string = xmlString
                        withAnimation {
                            isCopied = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation {
                                isCopied = false
                            }
                        }
                    } label: {
                        Label(isCopied ? NSLocalizedString("Copied!", comment: "") : NSLocalizedString("Copy XML", comment: ""), systemImage: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.footnote)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isCopied ? .green : .accentColor)
                    #endif
                }
                .padding(.horizontal)
                .padding(.top)
                
                if isWrapped {
                    Text(xmlString)
                        .font(.system(size: 11, design: .monospaced))
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        #if !os(tvOS)
                        .background(Color(.secondarySystemBackground))
                        #else
                        .background(Color.white.opacity(0.1))
                        #endif
                        .cornerRadius(8)
                        .padding(.horizontal)
                } else {
                    ScrollView(.horizontal, showsIndicators: true) {
                        Text(xmlString)
                            .font(.system(size: 11, design: .monospaced))
                            .padding()
                            #if !os(tvOS)
                            .background(Color(.secondarySystemBackground))
                            #else
                            .background(Color.white.opacity(0.1))
                            #endif
                            .cornerRadius(8)
                    }
                    .padding(.horizontal)
                }
            }
        }
        .onAppear {
            if xmlString.isEmpty {
                xmlString = generateXMLString(from: plist)
            }
        }
    }
    
    private func generateXMLString(from plist: [String: Any]) -> String {
        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0),
              let string = String(data: data, encoding: .utf8) else {
            return ""
        }
        return string
    }
}

// MARK: - Mode 2: Raw JSON View
struct InfoPlistRawView: View {
    let plist: [String: Any]
    
    @State private var isCopied = false
    @State private var isWrapped = true
    
    @Binding var jsonString: String
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Spacer()
                    
                    SwiftUI.Button {
                        withAnimation {
                            isWrapped.toggle()
                        }
                    } label: {
                        Label(isWrapped ? NSLocalizedString("Wrap: On", comment: "") : NSLocalizedString("Wrap: Off", comment: ""), systemImage: isWrapped ? "text.alignleft" : "text.chevron.right")
                            .font(.footnote)
                    }
                    .buttonStyle(.bordered)
                    
                    #if !os(tvOS)
                    SwiftUI.Button {
                        UIPasteboard.general.string = jsonString
                        withAnimation {
                            isCopied = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation {
                                isCopied = false
                            }
                        }
                    } label: {
                        Label(isCopied ? NSLocalizedString("Copied!", comment: "") : NSLocalizedString("Copy JSON", comment: ""), systemImage: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.footnote)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isCopied ? .green : .accentColor)
                    #endif
                }
                .padding(.horizontal)
                .padding(.top)
                
                if isWrapped {
                    Text(jsonString)
                        .font(.system(size: 11, design: .monospaced))
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        #if !os(tvOS)
                        .background(Color(.secondarySystemBackground))
                        #else
                        .background(Color.white.opacity(0.1))
                        #endif
                        .cornerRadius(8)
                        .padding(.horizontal)
                } else {
                    ScrollView(.horizontal, showsIndicators: true) {
                        Text(jsonString)
                            .font(.system(size: 11, design: .monospaced))
                            .padding()
                            #if !os(tvOS)
                            .background(Color(.secondarySystemBackground))
                            #else
                            .background(Color.white.opacity(0.1))
                            #endif
                            .cornerRadius(8)
                    }
                    .padding(.horizontal)
                }
            }
        }
        .onAppear {
            if jsonString.isEmpty {
                jsonString = generateJSONString(from: plist)
            }
        }
    }
    
    static func jsonSanitize(_ value: Any) -> Any {
        if let data = value as? Data {
            return data.base64EncodedString()
        } else if let date = value as? Date {
            return ISO8601DateFormatter().string(from: date)
        } else if let dict = value as? [String: Any] {
            var sanitized: [String: Any] = [:]
            for (k, v) in dict {
                sanitized[k] = jsonSanitize(v)
            }
            return sanitized
        } else if let array = value as? [Any] {
            return array.map { jsonSanitize($0) }
        } else if value is String || value is NSNumber || value is Bool {
            return value
        } else {
            return "\(value)"
        }
    }
    
    private func generateJSONString(from plist: [String: Any]) -> String {
        let sanitized = Self.jsonSanitize(plist)
        guard JSONSerialization.isValidJSONObject(sanitized),
              let data = try? JSONSerialization.data(withJSONObject: sanitized, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}

// MARK: - Mode 3: Semantic View
struct InfoPlistSemanticView: View {
    let plist: [String: Any]
    
    @State private var searchQuery = ""
    
    // Core App Metadata
    var appName: String {
        return (plist["CFBundleDisplayName"] as? String) ?? (plist["CFBundleName"] as? String) ?? "N/A"
    }
    var bundleID: String {
        return (plist["CFBundleIdentifier"] as? String) ?? "N/A"
    }
    var version: String {
        let short = plist["CFBundleShortVersionString"] as? String
        let build = plist["CFBundleVersion"] as? String
        if let short = short, let build = build {
            return "\(short) (\(build))"
        }
        return short ?? build ?? "N/A"
    }
    var minOS: String {
        return (plist["MinimumOSVersion"] as? String) ?? "N/A"
    }
    
    // Categorized Groups
    var privacyPermissions: [String: String] {
        var dict = [String: String]()
        for key in plist.keys where key.hasPrefix("NS") && key.hasSuffix("UsageDescription") {
            if let val = plist[key] as? String {
                dict[key] = val
            }
        }
        return dict
    }
    
    var customURLSchemes: [String] {
        var schemes = [String]()
        if let urlTypes = plist["CFBundleURLTypes"] as? [[String: Any]] {
            for type in urlTypes {
                if let typeSchemes = type["CFBundleURLSchemes"] as? [String] {
                    schemes.append(contentsOf: typeSchemes)
                }
            }
        }
        return schemes
    }
    
    var backgroundModes: [String] {
        return (plist["UIBackgroundModes"] as? [String]) ?? []
    }
    
    var queriedSchemes: [String] {
        return (plist["LSApplicationQueriesSchemes"] as? [String]) ?? []
    }
    
    // Custom/Uncategorized keys
    var customKeys: [String: Any] {
        let categorized: Set<String> = [
            "CFBundleDisplayName", "CFBundleName", "CFBundleIdentifier",
            "CFBundleShortVersionString", "CFBundleVersion", "MinimumOSVersion",
            "CFBundleURLTypes", "UIBackgroundModes", "LSApplicationQueriesSchemes"
        ]
        
        var dict = [String: Any]()
        for key in plist.keys {
            if categorized.contains(key) { continue }
            if key.hasPrefix("NS") && key.hasSuffix("UsageDescription") { continue }
            dict[key] = plist[key]
        }
        return dict
    }
    
    var filteredCustomKeys: [String] {
        let keys = customKeys.keys.sorted()
        if searchQuery.isEmpty {
            return keys
        }
        return keys.filter { $0.localizedCaseInsensitiveContains(searchQuery) }
    }
    
    private var hasAppMetadata: Bool {
        plist["CFBundleDisplayName"] != nil ||
        plist["CFBundleName"] != nil ||
        plist["CFBundleIdentifier"] != nil ||
        plist["CFBundleShortVersionString"] != nil ||
        plist["CFBundleVersion"] != nil ||
        plist["MinimumOSVersion"] != nil
    }
    
    var body: some View {
        List {
            // General Info — only show if app metadata is actually present in plist
            if hasAppMetadata {
                Section(header: Text("General Info")) {
                    SemanticValueRow(label: "App Name", value: appName)
                    SemanticValueRow(label: "Bundle Identifier", value: bundleID)
                    SemanticValueRow(label: "Version", value: version)
                    SemanticValueRow(label: "Minimum OS", value: minOS)
                }
            }
            
            // Privacy Permissions Card
            if !privacyPermissions.isEmpty {
                Section(header: Text(String(format: NSLocalizedString("Privacy Permissions (%d)", comment: ""), privacyPermissions.count))) {
                    ForEach(privacyPermissions.keys.sorted(), id: \.self) { key in
                        LocalCopyableDescriptionRow(key: key, value: privacyPermissions[key] ?? "")
                    }
                }
            }
            
            // Custom URL Schemes Card
            if !customURLSchemes.isEmpty {
                Section(header: Text("Custom URL Schemes")) {
                    ForEach(customURLSchemes, id: \.self) { scheme in
                        LocalCopyableValueOnlyRow(value: scheme)
                    }
                }
            }
            
            // Background Modes Card
            if !backgroundModes.isEmpty {
                Section(header: Text("Background Modes")) {
                    ForEach(backgroundModes, id: \.self) { mode in
                        HStack {
                            Image(systemName: getBackgroundModeIcon(mode))
                                .foregroundColor(.accentColor)
                                .frame(width: 24)
                            Text(mode)
                                .font(.subheadline)
                            Spacer()
                        }
                    }
                }
            }
            
            // Queried URL Schemes Card
            if !queriedSchemes.isEmpty {
                Section(header: Text("Queries Schemes")) {
                    ForEach(queriedSchemes, id: \.self) { scheme in
                        HStack {
                            Text(scheme)
                                .font(.subheadline)
                            Spacer()
                        }
                    }
                }
            }
            
            // Other Custom/Advanced Keys
            Section(header: Text("Advanced / Custom Keys")) {
                SearchBarView(text: $searchQuery)
                    .listRowInsets(EdgeInsets())
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                
                ForEach(filteredCustomKeys, id: \.self) { key in
                    let val = customKeys[key] ?? ""
                    CopyableValueRow(key: key, value: val)
                }
            }
        }
        #if !os(tvOS)
        .listStyle(InsetGroupedListStyle())
        #else
        .listStyle(GroupedListStyle())
        #endif
    }
    
    private func getBackgroundModeIcon(_ mode: String) -> String {
        switch mode {
        case "audio": return "music.note"
        case "location": return "location.fill"
        case "voip": return "phone.fill"
        case "newsstand-content": return "newspaper"
        case "external-accessory": return "cable.connector"
        case "bluetooth-central": return "wave.3.left"
        case "bluetooth-peripheral": return "wave.3.right"
        case "fetch": return "arrow.down.to.line"
        case "remote-notification": return "bell.badge.fill"
        case "processing": return "cpu"
        default: return "ellipsis.bubble.fill"
        }
    }
}

// MARK: - Localized Semantic Value Row
struct SemanticValueRow: View {
    let label: LocalizedStringKey
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundColor(.primary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .contextMenu {
            SwiftUI.Button {
                #if !os(tvOS)
                UIPasteboard.general.string = value
                #endif
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
        }
    }
}

// MARK: - Localized Description Row
struct LocalCopyableDescriptionRow: View {
    let key: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(key)
                .font(.caption)
                .foregroundColor(.secondary)
                .bold()
            Text(value)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
        .padding(.vertical, 4)
        .contextMenu {
            SwiftUI.Button {
                #if !os(tvOS)
                UIPasteboard.general.string = value
                #endif
            } label: {
                Label("Copy Value", systemImage: "doc.on.doc")
            }
            SwiftUI.Button {
                #if !os(tvOS)
                UIPasteboard.general.string = key
                #endif
            } label: {
                Label("Copy Key", systemImage: "doc.on.doc")
            }
        }
    }
}

// MARK: - Localized Value Only Row
struct LocalCopyableValueOnlyRow: View {
    let value: String
    
    var body: some View {
        HStack {
            Text(value)
                .font(.subheadline)
            Spacer()
        }
        .contextMenu {
            SwiftUI.Button {
                #if !os(tvOS)
                UIPasteboard.general.string = value
                #endif
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
        }
    }
}

// MARK: - Localized Copyable Value Row
struct CopyableValueRow: View {
    let key: String
    let value: Any
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(key)
                .font(.caption)
                .foregroundColor(.secondary)
                .bold()
            
            ScrollView(.horizontal, showsIndicators: false) {
                Text(formatValue(value))
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
            }
        }
        .contextMenu {
            SwiftUI.Button {
                #if !os(tvOS)
                UIPasteboard.general.string = formatValue(value)
                #endif
            } label: {
                Label("Copy Value", systemImage: "doc.on.doc")
            }
            SwiftUI.Button {
                #if !os(tvOS)
                UIPasteboard.general.string = key
                #endif
            } label: {
                Label("Copy Key", systemImage: "doc.on.doc")
            }
        }
    }
    
    private func formatValue(_ val: Any) -> String {
        let sanitized = InfoPlistRawView.jsonSanitize(val)
        if JSONSerialization.isValidJSONObject(sanitized) {
            if let data = try? JSONSerialization.data(withJSONObject: sanitized, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
               let string = String(data: data, encoding: .utf8) {
                let lines = string.components(separatedBy: .newlines)
                let formatted = lines.map { line -> String in
                    let leadingSpaces = line.prefix(while: { $0 == " " }).count
                    let newIndent = String(repeating: " ", count: leadingSpaces * 2)
                    return newIndent + line.dropFirst(leadingSpaces)
                }.joined(separator: "\n")
                return formatted
            }
        }
        if let data = val as? Data {
            return data.map { String(format: "%02x", $0) }.joined()
        }
        if let date = val as? Date {
            return ISO8601DateFormatter().string(from: date)
        }
        if let array = val as? [Any] {
            return "[" + array.map { formatValue($0) }.joined(separator: ", ") + "]"
        }
        if let dict = val as? [String: Any] {
            return "{" + dict.map { "\($0.key): \(formatValue($0.value))" }.sorted().joined(separator: ", ") + "}"
        }
        return "\(val)"
    }
}

// MARK: - Search Bar Helper View
struct SearchBarView: View {
    @Binding var text: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("Search keys", text: $text)
                .textFieldStyle(PlainTextFieldStyle())
                
            if !text.isEmpty {
                SwiftUI.Button(action: {
                    self.text = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        #if !os(tvOS)
        .background(Color(.secondarySystemBackground))
        #else
        .background(Color.white.opacity(0.1))
        #endif
        .cornerRadius(8)
    }
}
