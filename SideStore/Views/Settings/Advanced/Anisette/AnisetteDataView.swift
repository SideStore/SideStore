//  AnisetteDataView.swift
//  SideStore
//
//  Created by Magesh K on 31/7/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import UniformTypeIdentifiers

private extension Color {
    static let settingsRowBackground = Color.white.opacity(0.15)
    static let settingsDivider = Color.white.opacity(0.15)
}

@MainActor
class AnisetteDataViewModel: ObservableObject {
    @Published var clientInfo: String = ""
    @Published var userAgent: String = ""
    @Published var customDeviceID: String = ""
    @Published var customLocalUserID: String = ""
    @Published var customLocale: String = ""
    @Published var customTimeZone: String = ""
    @Published var customSerialNumber: String = ""
    @Published var customRoutingInfo: String = ""
    @Published var customXcodeVersion: String = ""
    
    @Published var isOfflineMode: Bool = false
    @Published var isLoading: Bool = false
    
    @Published var viewMode: Int = 0 // 0 = Interactive, 1 = Raw JSON
    @Published var rawEditableJSON: String = ""
    @Published var serverReturnedHeadersJSON: String = "{}"
    
    init() {
        Task {
            await loadData()
        }
    }
    
    func loadData() async {
        isOfflineMode = AnisetteConfigManager.shared.isOfflineMode
        let config = await AnisetteConfigManager.shared.loadConfig()
        clientInfo = config.clientInfo
        userAgent = config.userAgent
        customDeviceID = config.customDeviceID ?? ""
        customLocalUserID = config.customLocalUserID ?? ""
        customLocale = config.customLocale ?? ""
        customTimeZone = config.customTimeZone ?? ""
        customSerialNumber = config.customSerialNumber ?? ""
        customRoutingInfo = config.customRoutingInfo ?? ""
        customXcodeVersion = config.customXcodeVersion ?? ""
        
        updateRawEditableJSON()
        
        let serverHeaders = await AnisetteConfigManager.shared.loadServerHeaders()
        if let data = try? JSONSerialization.data(withJSONObject: serverHeaders, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
           let str = String(data: data, encoding: .utf8) {
            serverReturnedHeadersJSON = str
        }
    }
    
    func updateRawEditableJSON() {
        var dict: [String: String] = [
            "clientInfo": clientInfo,
            "userAgent": userAgent
        ]
        if !customDeviceID.isEmpty { dict["customDeviceID"] = customDeviceID }
        if !customLocalUserID.isEmpty { dict["customLocalUserID"] = customLocalUserID }
        if !customLocale.isEmpty { dict["customLocale"] = customLocale }
        if !customTimeZone.isEmpty { dict["customTimeZone"] = customTimeZone }
        if !customSerialNumber.isEmpty { dict["customSerialNumber"] = customSerialNumber }
        if !customRoutingInfo.isEmpty { dict["customRoutingInfo"] = customRoutingInfo }
        if !customXcodeVersion.isEmpty { dict["customXcodeVersion"] = customXcodeVersion }
        
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
           let str = String(data: data, encoding: .utf8) {
            rawEditableJSON = str
        }
    }
    
    func save() async {
        AnisetteConfigManager.shared.isOfflineMode = isOfflineMode
        let config = AnisetteConfig(
            clientInfo: clientInfo,
            userAgent: userAgent,
            customDeviceID: customDeviceID.isEmpty ? nil : customDeviceID,
            customLocalUserID: customLocalUserID.isEmpty ? nil : customLocalUserID,
            customLocale: customLocale.isEmpty ? nil : customLocale,
            customTimeZone: customTimeZone.isEmpty ? nil : customTimeZone,
            customXcodeVersion: customXcodeVersion.isEmpty ? nil : customXcodeVersion,
            customSerialNumber: customSerialNumber.isEmpty ? nil : customSerialNumber,
            customRoutingInfo: customRoutingInfo.isEmpty ? nil : customRoutingInfo
        )
        await AnisetteConfigManager.shared.saveConfig(config)
        updateRawEditableJSON()
        showToast(text: "Saved configuration successfully.")
    }
    
    func saveRawJSON() async {
        guard let data = rawEditableJSON.data(using: .utf8) else {
            showToast(text: "Encoding Failed", detailText: "Unable to encode JSON as UTF-8.")
            return
        }
        
        do {
            let config = try Foundation.JSONDecoder().decode(AnisetteConfig.self, from: data)
            
            clientInfo = config.clientInfo
            userAgent = config.userAgent
            customDeviceID = config.customDeviceID ?? ""
            customLocalUserID = config.customLocalUserID ?? ""
            customLocale = config.customLocale ?? ""
            customTimeZone = config.customTimeZone ?? ""
            customSerialNumber = config.customSerialNumber ?? ""
            customRoutingInfo = config.customRoutingInfo ?? ""
            customXcodeVersion = config.customXcodeVersion ?? ""
            
            await AnisetteConfigManager.shared.saveConfig(config)
            showToast(text: "JSON configuration saved successfully!")
        } catch {
            showToast(text: "Invalid JSON Structure", error: error)
        }
    }
    
    func reset() async {
        let config = await AnisetteConfigManager.shared.resetToDefaults()
        clientInfo = config.clientInfo
        userAgent = config.userAgent
        customDeviceID = ""
        customLocalUserID = ""
        customLocale = ""
        customTimeZone = ""
        customSerialNumber = ""
        customRoutingInfo = ""
        customXcodeVersion = ""
        updateRawEditableJSON()
        await save()
        showToast(text: "Reset to default configuration.")
    }
    
    func importJSON(url: URL) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let gotAccess = url.startAccessingSecurityScopedResource()
            defer {
                if gotAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            let config = try await AnisetteConfigManager.shared.importFromFile(url: url)
            clientInfo = config.clientInfo
            userAgent = config.userAgent
            customDeviceID = config.customDeviceID ?? ""
            customLocalUserID = config.customLocalUserID ?? ""
            customLocale = config.customLocale ?? ""
            customTimeZone = config.customTimeZone ?? ""
            customSerialNumber = config.customSerialNumber ?? ""
            customRoutingInfo = config.customRoutingInfo ?? ""
            customXcodeVersion = config.customXcodeVersion ?? ""
            updateRawEditableJSON()
            showToast(text: "Imported successfully", detailText: url.lastPathComponent)
        } catch {
            showToast(text: "Import Failed", error: error)
        }
    }
    
    func exportJSON() async -> URL? {
        guard let data = await AnisetteConfigManager.shared.exportConfigData() else { return nil }
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("anisette-config.json")
        do {
            try data.write(to: tempURL, options: .atomic)
            return tempURL
        } catch {
            showToast(text: "Export Failed", error: error)
            return nil
        }
    }
    
    func fetchFreshFromServer() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let activeServer = UserDefaults.standard.menuAnisetteURL
            guard !activeServer.isEmpty, let url = URL(string: activeServer) else {
                throw NSError(domain: "AnisetteDataViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "No active anisette server URL configured."])
            }
            
            let clientInfoURL = url.appendingPathComponent("v3").appendingPathComponent("client_info")
            var request = URLRequest(url: clientInfoURL)
            request.timeoutInterval = 10
            
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: String] else {
                throw NSError(domain: "AnisetteDataViewModel", code: -2, userInfo: [NSLocalizedDescriptionKey: "Server response is not a valid JSON."])
            }
            
            await AnisetteConfigManager.shared.saveServerHeaders(json)
            
            let serverHeaders = await AnisetteConfigManager.shared.loadServerHeaders()
            if let data = try? JSONSerialization.data(withJSONObject: serverHeaders, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
               let str = String(data: data, encoding: .utf8) {
                serverReturnedHeadersJSON = str
            }
            
            showToast(text: "Fetched server config!", detailText: url.host)
        } catch {
            showToast(text: "Fetch Failed", error: error)
        }
    }
    
    func loadServerHeadersIntoOverrides() async {
        let serverHeaders = await AnisetteConfigManager.shared.loadServerHeaders()
        guard !serverHeaders.isEmpty else {
            showToast(text: "No fetched headers found", detailText: "Fetch from server first.")
            return
        }
        
        func getValue(forKeys keys: [String]) -> String? {
            for key in keys {
                if let val = serverHeaders[key] {
                    return val
                }
            }
            return nil
        }
        
        if let val = getValue(forKeys: ["client_info", "clientInfo", "X-Mme-Client-Info"]) {
            clientInfo = val
        }
        if let val = getValue(forKeys: ["user_agent", "userAgent", "User-Agent"]) {
            userAgent = val
        }
        if let val = getValue(forKeys: ["custom_device_id", "customDeviceID", "X-Mme-Device-Id", "deviceUniqueIdentifier"]) {
            customDeviceID = val
        }
        if let val = getValue(forKeys: ["custom_local_user_id", "customLocalUserID", "X-Apple-I-MD-LU", "localUserID"]) {
            customLocalUserID = val
        }
        if let val = getValue(forKeys: ["custom_locale", "customLocale", "X-Apple-Locale", "locale"]) {
            customLocale = val
        }
        if let val = getValue(forKeys: ["custom_time_zone", "customTimeZone", "X-Apple-I-TimeZone", "timeZone"]) {
            customTimeZone = val
        }
        if let val = getValue(forKeys: ["custom_serial_number", "customSerialNumber", "X-Apple-I-SRL-NO", "serialNumber"]) {
            customSerialNumber = val
        }
        if let val = getValue(forKeys: ["custom_routing_info", "customRoutingInfo", "X-Apple-I-MD-RINFO", "routingInfo"]) {
            customRoutingInfo = val
        }
        if let val = getValue(forKeys: ["custom_xcode_version", "customXcodeVersion", "X-Xcode-Version", "xcodeVersion"]) {
            customXcodeVersion = val
        }
        
        await save()
        showToast(text: "Loaded fetched data into overrides!")
    }
    
    func showToast(text: String, detailText: String? = nil, error: Error? = nil) {
        let toast: ToastView
        if let error = error {
            toast = ToastView(error: error, opensLog: true)
        } else {
            toast = ToastView(text: text, detailText: detailText)
        }
        
        let keyWindow = UIApplication.shared.alt_keyWindow
        if let rootVC = keyWindow?.rootViewController {
            let presentingVC = rootVC.presentedViewController ?? rootVC
            toast.show(in: presentingVC)
        }
    }
}

struct AnisetteDataView: View {
    @StateObject private var viewModel = AnisetteDataViewModel()
    @State private var showingResetAlert = false
    @State private var showingFileImporter = false
    @State private var showingServerHeaders = false
    @State private var isCopiedServer = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Picker("View Mode", selection: $viewModel.viewMode) {
                    Text("Interactive").tag(0)
                    Text("Raw JSON").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 4)
                
                if viewModel.viewMode == 0 {
                    // SECTION 1: PRIMARY CLIENT HEADERS
                    VStack(alignment: .leading, spacing: 8) {
                        sectionHeader("PRIMARY CLIENT HEADERS")
                        
                        VStack(spacing: 0) {
                            headerFieldRow(
                                title: "Client Info",
                                headerKey: "X-Mme-Client-Info",
                                text: $viewModel.clientInfo,
                                placeholder: AppConstants.Anisette.defaultClientInfo,
                                isMultiline: true
                            )
                            
                            divider
                            
                            headerFieldRow(
                                title: "User Agent",
                                headerKey: "User-Agent",
                                text: $viewModel.userAgent,
                                placeholder: AppConstants.Anisette.defaultUserAgent,
                                isMultiline: true
                            )
                        }
                        .background(Color.settingsRowBackground)
                        .cornerRadius(14)
                    }
                    
                    // SECTION 2: DEVICE & IDENTITY
                    VStack(alignment: .leading, spacing: 8) {
                        sectionHeader("DEVICE & IDENTITY")
                        
                        VStack(spacing: 0) {
                            headerFieldRow(
                                title: "Device Identifier",
                                headerKey: "X-Mme-Device-Id",
                                text: $viewModel.customDeviceID,
                                placeholder: "System Generated Device UUID"
                            )
                            
                            divider
                            
                            headerFieldRow(
                                title: "Local User ID",
                                headerKey: "X-Apple-I-MD-LU",
                                text: $viewModel.customLocalUserID,
                                placeholder: "0"
                            )
                            
                            divider
                            
                            headerFieldRow(
                                title: "Serial Number",
                                headerKey: "X-Apple-I-SRL-NO",
                                text: $viewModel.customSerialNumber,
                                placeholder: AppConstants.Anisette.defaultDeviceSerialNumber
                            )
                            
                            divider
                            
                            headerFieldRow(
                                title: "Routing Info",
                                headerKey: "X-Apple-I-MD-RINFO",
                                text: $viewModel.customRoutingInfo,
                                placeholder: "17106176"
                            )
                        }
                        .background(Color.settingsRowBackground)
                        .cornerRadius(14)
                    }
                    
                    // SECTION 3: ENVIRONMENT & LOCALIZATION
                    VStack(alignment: .leading, spacing: 8) {
                        sectionHeader("ENVIRONMENT & LOCALIZATION")
                        
                        VStack(spacing: 0) {
                            headerFieldRow(
                                title: "Locale",
                                headerKey: "X-Apple-Locale",
                                text: $viewModel.customLocale,
                                placeholder: "en_US"
                            )
                            
                            divider
                            
                            headerFieldRow(
                                title: "Time Zone",
                                headerKey: "X-Apple-I-TimeZone",
                                text: $viewModel.customTimeZone,
                                placeholder: "e.g. UTC, EDT",
                                autocapitalization: .allCharacters
                            )
                            
                            divider
                            
                            headerFieldRow(
                                title: "Xcode Version",
                                headerKey: "X-Xcode-Version",
                                text: $viewModel.customXcodeVersion,
                                placeholder: "26.0 (26A242)"
                            )
                        }
                        .background(Color.settingsRowBackground)
                        .cornerRadius(14)
                    }
                    
                    // SECTION 4: DYNAMIC TOKENS (INFORMATIONAL)
                    VStack(alignment: .leading, spacing: 8) {
                        sectionHeader("DYNAMIC CRYPTOGRAPHIC TOKENS")
                        
                        VStack(spacing: 0) {
                            infoTokenRow(
                                title: "One-Time Password (OTP)",
                                headerKey: "X-Apple-I-MD",
                                subtitle: "Signed HMAC token dynamically calculated by ADI engine per request"
                            )
                            
                            divider
                            
                            infoTokenRow(
                                title: "Machine ID",
                                headerKey: "X-Apple-I-MD-M",
                                subtitle: "Hardware identifier computed from adi.pb and device identity"
                            )
                            
                            divider
                            
                            infoTokenRow(
                                title: "Client Time",
                                headerKey: "X-Apple-I-Client-Time",
                                subtitle: "ISO8601 UTC timestamp locked to OTP generation time"
                            )
                        }
                        .background(Color.settingsRowBackground)
                        .cornerRadius(14)
                    }
                    
                    // SAVE OVERRIDES BUTTON
                    SwiftUI.Button {
                        Task {
                            await viewModel.save()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Label("Save Overrides", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(.white)
                            Spacer()
                        }
                        .frame(height: 50)
                        .background(Color.accentColor)
                        .cornerRadius(14)
                    }
                    .disabled(viewModel.clientInfo.isEmpty || viewModel.userAgent.isEmpty)
                } else {
                    // RAW JSON VIEW
                    VStack(alignment: .leading, spacing: 8) {
                        sectionHeader("RAW CONFIGURATION JSON")
                        
                        VStack(spacing: 12) {
                            TextEditor(text: $viewModel.rawEditableJSON)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.white)
                                .frame(minHeight: 320)
                                .padding(8)
                                .background(Color.white.opacity(0.06))
                                .cornerRadius(10)
                            
                            SwiftUI.Button {
                                Task {
                                    await viewModel.saveRawJSON()
                                }
                            } label: {
                                HStack {
                                    Spacer()
                                    Label("Save Raw JSON", systemImage: "square.and.arrow.down.fill")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.white)
                                    Spacer()
                                }
                                .frame(height: 48)
                                .background(Color.accentColor)
                                .cornerRadius(12)
                            }
                            .disabled(viewModel.rawEditableJSON.isEmpty)
                        }
                        .padding(16)
                        .background(Color.settingsRowBackground)
                        .cornerRadius(14)
                    }
                }
                
                // SECTION: REMOTE SERVER SYNC (ONLY IN REMOTE MODE)
                if !UserDefaults.standard.useOnDeviceAnisette {
                    VStack(alignment: .leading, spacing: 8) {
                        sectionHeader("REMOTE SERVER SYNC")
                        
                        VStack(spacing: 0) {
                            DisclosureGroup(isExpanded: $showingServerHeaders) {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text(String(format: NSLocalizedString("Server: %@", comment: ""), URL(string: UserDefaults.standard.menuAnisetteURL)?.host ?? NSLocalizedString("Active Server", comment: "")))
                                            .font(.caption)
                                            .foregroundColor(Color.white.opacity(0.6))
                                        Spacer()
                                        SwiftUI.Button {
                                            #if !os(tvOS)
                                            UIPasteboard.general.string = viewModel.serverReturnedHeadersJSON
                                            #endif
                                            withAnimation { isCopiedServer = true }
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                                withAnimation { isCopiedServer = false }
                                            }
                                        } label: {
                                            HStack(spacing: 4) {
                                                Image(systemName: isCopiedServer ? "checkmark" : "doc.on.doc")
                                                Text(isCopiedServer ? NSLocalizedString("Copied", comment: "") : NSLocalizedString("Copy", comment: ""))
                                            }
                                            .font(.footnote.weight(.semibold))
                                            .foregroundColor(isCopiedServer ? .green : .accentColor)
                                        }
                                    }
                                    
                                    ScrollView(.horizontal, showsIndicators: true) {
                                        Text(viewModel.serverReturnedHeadersJSON)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(.white)
                                            .padding(10)
                                            .background(Color.black.opacity(0.3))
                                            .cornerRadius(8)
                                    }
                                    
                                    SwiftUI.Button {
                                        Task {
                                            await viewModel.loadServerHeadersIntoOverrides()
                                        }
                                    } label: {
                                        HStack {
                                            Spacer()
                                            Label("Save as Overrides", systemImage: "square.and.arrow.down.on.square")
                                                .font(.system(size: 15, weight: .bold))
                                                .foregroundColor(.white)
                                            Spacer()
                                        }
                                        .frame(height: 44)
                                        .background(Color.white.opacity(0.12))
                                        .cornerRadius(10)
                                    }
                                    .disabled(viewModel.serverReturnedHeadersJSON == "{}" || viewModel.serverReturnedHeadersJSON.isEmpty)
                                }
                                .padding(.top, 8)
                            } label: {
                                HStack {
                                    Label("Remote Server Sync", systemImage: "network")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.white)
                                    Spacer()
                                    SwiftUI.Button {
                                        Task {
                                            await viewModel.fetchFreshFromServer()
                                            withAnimation { showingServerHeaders = true }
                                        }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "arrow.clockwise")
                                            Text("Fetch")
                                        }
                                        .font(.footnote.weight(.semibold))
                                        .foregroundColor(.accentColor)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.white.opacity(0.1))
                                        .cornerRadius(8)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .background(Color.settingsRowBackground)
                        .cornerRadius(14)
                    }
                }
                
                // SECTION: ACTIONS
                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader("ACTIONS")
                    
                    VStack(spacing: 0) {
                        SwiftUI.Button {
                            #if !os(tvOS)
                            showingFileImporter = true
                            #else
                            if let topVC = UIApplication.shared.topViewController() {
                                TVWebFileTransferManager.shared.startImport(
                                    acceptedExtensions: ["json"],
                                    title: "Import Anisette Client Config JSON",
                                    presentingVC: topVC
                                ) { fileURL in
                                    guard let fileURL = fileURL else { return }
                                    Task {
                                        await viewModel.importJSON(url: fileURL)
                                    }
                                }
                            }
                            #endif
                        } label: {
                            HStack {
                                Label("Import Config JSON", systemImage: "square.and.arrow.down")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(Color.white.opacity(0.4))
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 50)
                        }
                        
                        divider
                        
                        SwiftUI.Button {
                            Task {
                                if let url = await viewModel.exportJSON() {
                                    #if !os(tvOS)
                                    guard let topVC = UIApplication.shared.topViewController() else { return }
                                    let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                                    if let popover = activityVC.popoverPresentationController {
                                        popover.sourceView = topVC.view
                                        popover.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 0, height: 0)
                                        popover.permittedArrowDirections = []
                                    }
                                    topVC.present(activityVC, animated: true)
                                    #else
                                    if let topVC = UIApplication.shared.topViewController() {
                                        TVWebFileTransferManager.shared.startExport(
                                            fileURL: url,
                                            title: "Export Anisette Client Config JSON",
                                            presentingVC: topVC
                                        )
                                    }
                                    #endif
                                }
                            }
                        } label: {
                            HStack {
                                Label("Export Config JSON", systemImage: "square.and.arrow.up")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(Color.white.opacity(0.4))
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 50)
                        }
                        
                        divider
                        
                        SwiftUI.Button(role: .destructive) {
                            showingResetAlert = true
                        } label: {
                            HStack {
                                Label("Reset to Defaults", systemImage: "arrow.circlepath")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.red)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 50)
                        }
                        .alert("Reset to Defaults?", isPresented: $showingResetAlert) {
                            SwiftUI.Button("Reset", role: .destructive) {
                                Task {
                                    await viewModel.reset()
                                }
                            }
                            SwiftUI.Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("This will restore the client headers to the default recommended values.")
                        }
                    }
                    .background(Color.settingsRowBackground)
                    .cornerRadius(14)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .background(Color(uiColor: .settingsBackground).ignoresSafeArea())
        .navigationTitle("Client Config")
        #if !os(tvOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .overlay(
            Group {
                if viewModel.isLoading {
                    ProgressView()
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.settingsRowBackground))
                        .shadow(radius: 10)
                }
            }
        )
        #if !os(tvOS)
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    Task {
                        await viewModel.importJSON(url: url)
                    }
                }
            case .failure(let error):
                viewModel.showToast(text: "File Selection Failed", error: error)
            }
        }
        #endif
    }
    
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(Color.white.opacity(0.6))
            .padding(.horizontal, 16)
    }
    
    private func headerFieldRow(
        title: String,
        headerKey: String,
        text: Binding<String>,
        placeholder: String,
        isMultiline: Bool = false,
        autocapitalization: UITextAutocapitalizationType = .none
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Text(headerKey)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color.white.opacity(0.45))
            }
            
            if isMultiline {
                #if !os(tvOS)
                TextEditor(text: text)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(minHeight: 64)
                    .padding(6)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(8)
                #else
                TextField(placeholder, text: text)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(8)
                #endif
            } else {
                TextField(placeholder, text: text)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.white)
                    .autocapitalization(autocapitalization)
                    .disableAutocorrection(true)
                    .padding(8)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    
    private func infoTokenRow(title: String, headerKey: String, subtitle: String) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Text(headerKey)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.45))
                }
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(Color.white.opacity(0.55))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
    
    private var divider: some View {
        Rectangle()
            .fill(Color.settingsDivider)
            .frame(height: 0.5)
            .padding(.horizontal, 16)
    }
}
