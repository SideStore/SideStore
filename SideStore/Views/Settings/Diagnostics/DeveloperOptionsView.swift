//
//  DeveloperOptionsView.swift
//  SideStore
//
//  Created by Magesh K on 8/2/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import CoreData
import UniformTypeIdentifiers
#if !os(tvOS)
import WidgetKit
#else
import TVServices
#endif
import SideSign
import MinimuxerCommon

private extension Color {
    static let settingsRowBackground = Color.white.opacity(0.15)
    static let settingsDivider = Color.white.opacity(0.15)
}

struct DeveloperOptionsView: View {
    @State private var responseCachingDisabled: Bool = UserDefaults.standard.responseCachingDisabled
    @State private var isVerboseOperationsLoggingEnabled: Bool = UserDefaults.standard.isVerboseOperationsLoggingEnabled
    @State private var isSideStoreVerboseLoggingEnabled: Bool = UserDefaults.standard.isSideStoreVerboseLoggingEnabled
    @State private var isAltWidgetVerboseLoggingEnabled: Bool = WidgetDataManager.shared.isVerboseLoggingEnabled
    @State private var isAltSignVerboseLoggingEnabled: Bool = UserDefaults.standard.isAltSignVerboseLoggingEnabled
    @State private var isMinimuxerVerboseLoggingEnabled: Bool = UserDefaults.standard.isMinimuxerVerboseLoggingEnabled
    @State private var isRotateLogsOnStartupEnabled: Bool = UserDefaults.standard.isRotateLogsOnStartupEnabled
    @State private var recreateDatabaseOnNextStart: Bool = UserDefaults.standard.recreateDatabaseOnNextStart
    @State private var alwaysShowWireGuardConfig: Bool = UserDefaults.standard.alwaysShowWireGuardConfig
    @State private var tcpProbeTimeoutText: String = ""
    
    @State private var isExportingDB: Bool = false
    @State private var showDeleteConfirmation: Bool = false
    @State private var showClearRefreshAttemptsConfirmation: Bool = false
    @State private var showClearKeychainConfirmation: Bool = false
    @State private var showExportPasswordPrompt: Bool = false
    @State private var exportCertPassword: String = ""
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Section 1: Logging & Diagnostics
                VStack(alignment: .leading, spacing: 8) {
                    Text("LOGGING & DIAGNOSTICS")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.6))
                        .padding(.horizontal, 16)
                    
                    VStack(spacing: 0) {
                        toggleRow(title: "Disable URL Response Caching", isOn: Binding(
                            get: { responseCachingDisabled },
                            set: { newValue in
                                responseCachingDisabled = newValue
                                UserDefaults.standard.responseCachingDisabled = newValue
                            }
                        ))
                        
                        divider
                        
                        toggleRow(title: "Rotate Logs on Startup", isOn: Binding(
                            get: { isRotateLogsOnStartupEnabled },
                            set: { newValue in
                                isRotateLogsOnStartupEnabled = newValue
                                UserDefaults.standard.isRotateLogsOnStartupEnabled = newValue
                                let suffixFormat: SuffixFormat = newValue ? .timestamp : .none
                                if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
                                    appDelegate.consoleLog.updateConfiguration(baseName: "console", suffixFormat: suffixFormat, policy: .immediate)
                                }
                            }
                        ))
                        
                        divider
                        
                        toggleRow(title: "SideStore Verbose Logging", isOn: Binding(
                            get: { isSideStoreVerboseLoggingEnabled },
                            set: { newValue in
                                isSideStoreVerboseLoggingEnabled = newValue
                                UserDefaults.standard.isSideStoreVerboseLoggingEnabled = newValue
                                SideStoreLogging.setLogging(newValue)
                            }
                        ))
                        
                        divider
                        
                        #if !os(tvOS)
                        let title = "Widget Verbose Logging"
                        #else
                        let title = "Top Shelf Verbose Logging"
                        #endif
                        toggleRow(title: title, isOn: Binding(
                            get: { isAltWidgetVerboseLoggingEnabled },
                            set: { newValue in
                                isAltWidgetVerboseLoggingEnabled = newValue
                                WidgetDataManager.shared.isVerboseLoggingEnabled = newValue
                            }
                        ))
                        
                        divider
                        
                        toggleRow(title: "AltSign Verbose Logging", isOn: Binding(
                            get: { isAltSignVerboseLoggingEnabled },
                            set: { newValue in
                                isAltSignVerboseLoggingEnabled = newValue
                                UserDefaults.standard.isAltSignVerboseLoggingEnabled = newValue
                                AltSign.setLogging(newValue)
                            }
                        ))
                        
                        divider
                        
                        toggleRow(title: "Minimuxer Verbose Logging", isOn: Binding(
                            get: { isMinimuxerVerboseLoggingEnabled },
                            set: { newValue in
                                isMinimuxerVerboseLoggingEnabled = newValue
                                UserDefaults.standard.isMinimuxerVerboseLoggingEnabled = newValue
                                minimuxerSetLogging(newValue)
                            }
                        ))
                        
                        divider
                        
                        toggleRow(title: "Operations Verbose Logging", isOn: Binding(
                            get: { isVerboseOperationsLoggingEnabled },
                            set: { newValue in
                                isVerboseOperationsLoggingEnabled = newValue
                                UserDefaults.standard.isVerboseOperationsLoggingEnabled = newValue
                            }
                        ))
                        
                        divider
                        
                        NavigationLink(destination: OperationsLoggingControlView()) {
                            HStack {
                                Text("Operations Logging Control")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(.white)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(Color.white.opacity(0.4))
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 50)
                        }
                    }
                    .background(Color.settingsRowBackground)
                    .cornerRadius(14)
                }
                
                // Section: Bonjour
                VStack(alignment: .leading, spacing: 8) {
                    Text("BONJOUR")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.6))
                        .padding(.horizontal, 16)
                    
                    VStack(spacing: 0) {
                        NavigationLink(destination: BonjourDiscoveryView()) {
                            HStack {
                                Text("Network Discovery")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(.white)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(Color.white.opacity(0.4))
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 50)
                        }
                    }
                    .background(Color.settingsRowBackground)
                    .cornerRadius(14)
                }
                
                // Section: Widget Options
                VStack(alignment: .leading, spacing: 8) {
                    #if !os(tvOS)
                    let title = "WIDGET OPTIONS"
                    #else
                    let title = "TOP SHELF OPTIONS"
                    #endif
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.6))
                        .padding(.horizontal, 16)
                    
                    VStack(spacing: 0) {
                        SwiftUI.Button(action: { triggerReloadAllWidgets() }) {
                            HStack(spacing: 12) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)

                                #if !os(tvOS)
                                let title = "Reload All Widgets"
                                #else
                                let title = "Reload Top Shelf"
                                #endif
                                Text(title)
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(.white)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 50)
                        }
                        
                        divider
                        
                        SwiftUI.Button(action: { triggerRotateWidgetLog() }) {
                            HStack(spacing: 12) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                                
                                #if !os(tvOS)
                                let title = "Rotate Widget Log"
                                #else
                                let title = "Rotate Top Shelf Log"
                                #endif
                                Text(title)
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(.white)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 50)
                        }
                    }
                    .background(Color.settingsRowBackground)
                    .cornerRadius(14)
                }
                
                // Section 2: Database Options
                VStack(alignment: .leading, spacing: 8) {
                    Text("DATABASE OPTIONS")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.6))
                        .padding(.horizontal, 16)
                    
                    VStack(spacing: 0) {
                        SwiftUI.Button(action: { exportDatabase() }) {
                            HStack(spacing: 12) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                                Text("Export Database")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(.white)
                                Spacer()
                                if isExportingDB {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                }
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 50)
                        }
                        .disabled(isExportingDB)
                        
                        divider
                        
                        SwiftUI.Button(action: { showClearRefreshAttemptsConfirmation = true }) {
                            HStack(spacing: 12) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(Color(red: 1.0, green: 0.27, blue: 0.27))
                                Text("Clear Refresh Attempts")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(Color(red: 1.0, green: 0.27, blue: 0.27))
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 50)
                        }
                        
                        divider
                        
                        SwiftUI.Button(action: { showDeleteConfirmation = true }) {
                            HStack(spacing: 12) {
                                Image(systemName: "trash")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(Color(red: 1.0, green: 0.27, blue: 0.27))
                                Text("Delete Database")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(Color(red: 1.0, green: 0.27, blue: 0.27))
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 50)
                        }
                        
                        divider
                        
                        SwiftUI.Button(action: { showClearKeychainConfirmation = true }) {
                            HStack(spacing: 12) {
                                Image(systemName: "key")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(Color(red: 1.0, green: 0.27, blue: 0.27))
                                Text("Clear Keychain Items")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(Color(red: 1.0, green: 0.27, blue: 0.27))
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 50)
                        }
                        
                        divider
                        
                        toggleRow(title: "Wipe Database on Next Start", isOn: Binding(
                            get: { recreateDatabaseOnNextStart },
                            set: { newValue in
                                recreateDatabaseOnNextStart = newValue
                                UserDefaults.standard.recreateDatabaseOnNextStart = newValue
                            }
                        ))
                    }
                    .background(Color.settingsRowBackground)
                    .cornerRadius(14)
                }
                
                // Section 3: WireGuard Configuration
                VStack(alignment: .leading, spacing: 8) {
                    Text("WIREGUARD CONFIGURATION")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.6))
                        .padding(.horizontal, 16)
                    
                    VStack(spacing: 0) {
                        SwiftUI.Button(action: { triggerStartEMProxy() }) {
                            HStack(spacing: 12) {
                                Image(systemName: "play.circle")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                                Text("Start EMProxy")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(.white)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 50)
                        }
                        
                        divider
                        
                        SwiftUI.Button(action: { triggerStopEMProxy() }) {
                            HStack(spacing: 12) {
                                Image(systemName: "stop.circle")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                                Text("Stop EMProxy")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(.white)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 50)
                        }
                        
                        divider
                        
                        toggleRow(title: "Show WireGuard Settings", isOn: Binding(
                            get: { alwaysShowWireGuardConfig },
                            set: { newValue in
                                alwaysShowWireGuardConfig = newValue
                                UserDefaults.standard.alwaysShowWireGuardConfig = newValue
                            }
                        ))
                    }
                    .background(Color.settingsRowBackground)
                    .cornerRadius(14)
                }
                
                // Section: Device (TCP) Probe Timeout
                VStack(alignment: .leading, spacing: 8) {
                    Text("DEVICE (TCP) PROBE TIMEOUT")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.6))
                        .padding(.horizontal, 16)
                    
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            Text("Timeout (ms)")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(.white)
                            
                            Spacer()
                            
                            TextField("ms", text: $tcpProbeTimeoutText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .foregroundColor(.white)
                                .font(.system(size: 17))
                                .frame(width: 90)
                                .onChange(of: tcpProbeTimeoutText) { newValue in
                                    let filtered = newValue.filter { "0123456789".contains($0) }
                                    if filtered != newValue {
                                        tcpProbeTimeoutText = filtered
                                    }
                                    if let timeout = Int(filtered), timeout > 0 {
                                        minimuxerSetDeviceProbeTimeout(timeout)
                                    }
                                }
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 50)
                        
                        divider
                        
                        SwiftUI.Button(action: {
                            let defaultTimeout = MinimuxerConstants.defaultTCPProbeTimeoutMs
                            tcpProbeTimeoutText = String(defaultTimeout)
                            minimuxerSetDeviceProbeTimeout(defaultTimeout)
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                                Text(String(format: NSLocalizedString("Use Default (%d ms)", comment: ""), MinimuxerConstants.defaultTCPProbeTimeoutMs))
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(.white)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 50)
                        }
                    }
                    .background(Color.settingsRowBackground)
                    .cornerRadius(14)
                }
                
                #if DEBUG
                // Section 3: Account Management
                VStack(alignment: .leading, spacing: 8) {
                    Text("ACCOUNT MANAGEMENT")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.6))
                        .padding(.horizontal, 16)
                    
                    VStack(spacing: 0) {
                        SwiftUI.Button(action: { showImportAccountPicker() }) {
                            HStack(spacing: 12) {
                                Image(systemName: "square.and.arrow.down")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                                Text("Import Account JSON")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(.white)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 50)
                        }
                        
                        divider
                        
                        SwiftUI.Button(action: {
                            if AuthManager.shared.currentAppleID == nil ||
                               AuthManager.shared.password == nil ||
                               CertificateManager.shared.activeCertificate == nil {
                                if let top = UIApplication.shared.topViewController() {
                                    let toastView = ToastView(text: NSLocalizedString("Failed to export account!", comment: ""), detailText: "Account not found or missing credentials.")
                                    toastView.show(in: top)
                                }
                            } else {
                                exportCertPassword = ""
                                showExportPasswordPrompt = true
                            }
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                                Text("Export Account JSON")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(.white)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 50)
                        }
                    }
                    .background(Color.settingsRowBackground)
                    .cornerRadius(14)
                }
                #endif
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .background(Color(uiColor: .settingsBackground).ignoresSafeArea())
        .navigationTitle("Developer Options")
        #if !os(tvOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .alert("Delete Database", isPresented: $showDeleteConfirmation) {
            SwiftUI.Button("Delete & Exit", role: .destructive) {
                _ = DatabaseManager.deleteDatabase()
                exit(0)
            }
            SwiftUI.Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deleting the database will remove all app entries and sources from SideStore.")
        }
        .alert("Clear Refresh Attempts", isPresented: $showClearRefreshAttemptsConfirmation) {
            SwiftUI.Button("Clear", role: .destructive) {
                clearRefreshAttempts()
            }
            SwiftUI.Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to clear all existing refresh attempt entries?")
        }
        #if DEBUG
        .alert("Export Account", isPresented: $showExportPasswordPrompt) {
            SecureField("Certificate Password", text: $exportCertPassword)
            SwiftUI.Button("Export") {
                exportAccountJSON(password: exportCertPassword)
            }
            SwiftUI.Button("Cancel", role: .cancel) {}
        } message: {
            Text("Please enter a password for the certificate.")
        }
        #endif
        .alert("Clear Keychain Items", isPresented: $showClearKeychainConfirmation) {
            SwiftUI.Button("Clear All", role: .destructive) {
                Keychain.shared.clearAll()
            }
            SwiftUI.Button("Cancel", role: .cancel) {}
        } message: {
            Text("Do you want to clear all keychain items related to this SideStore instance?")
        }
        .onAppear {
            tcpProbeTimeoutText = String(minimuxerGetDeviceProbeTimeout())
        }
    }
    
    #if DEBUG
    private func showImportAccountPicker() {
        guard let top = UIApplication.shared.topViewController() else { return }
        #if !os(tvOS)
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType(filenameExtension: "sideconf")!, .json], asCopy: false)
        ImportExport.documentPickerHandler = DocumentPickerHandler { selectedURL in
            guard let url = selectedURL else { return }
            do {
                try ImportExport.importAccountJSON(from: url)
                let email = AuthManager.shared.currentAppleID ?? ""
                let toastView = ToastView(text: String(format: NSLocalizedString("Successfully imported '%@'!", comment: ""), email), detailText: "SideStore should be fully operational!")
                toastView.show(in: top)
            } catch {
                let toastView = ToastView(text: NSLocalizedString("Failed to import account JSON!", comment: ""), detailText: error.localizedDescription)
                toastView.show(in: top)
            }
        }
        picker.delegate = ImportExport.documentPickerHandler
        top.present(picker, animated: true)
        #else
        TVWebFileTransferManager.shared.startImport(
            acceptedExtensions: ["sideconf", "json"],
            title: "Import Account",
            presentingVC: top
        ) { selectedURL in
            guard let url = selectedURL else { return }
            do {
                try ImportExport.importAccountJSON(from: url)
                let email = AuthManager.shared.currentAppleID ?? ""
                let toastView = ToastView(text: String(format: NSLocalizedString("Successfully imported '%@'!", comment: ""), email), detailText: "SideStore should be fully operational!")
                toastView.show(in: top)
            } catch {
                let toastView = ToastView(text: NSLocalizedString("Failed to import account JSON!", comment: ""), detailText: error.localizedDescription)
                toastView.show(in: top)
            }
        }
        #endif
    }
    
    private func exportAccountJSON(password: String) {
        guard let top = UIApplication.shared.topViewController() else { return }
        guard let account = ImportExport.exportAccountJSON(password: password) else {
            let toastView = ToastView(text: NSLocalizedString("Failed to export account!", comment: ""), detailText: "Account not found or missing credentials.")
            toastView.show(in: top)
            return
        }
        
        guard let accountData = try? Foundation.JSONEncoder().encode(account) else {
            let toastView = ToastView(text: NSLocalizedString("Failed to export account data!", comment: ""), detailText: "Account malformed.")
            toastView.show(in: top)
            return
        }
        
        let tmpPath = FileManager.default.temporaryDirectory.appendingPathComponent("\(account.email).sideconf")
        do {
            try accountData.write(to: tmpPath)
            #if !os(tvOS)
            let exportVC = UIDocumentPickerViewController(forExporting: [tmpPath], asCopy: false)
            top.present(exportVC, animated: true)
            #else
            TVWebFileTransferManager.shared.startExport(fileURL: tmpPath, title: "Export Account", presentingVC: top)
            #endif
        } catch {
            let toastView = ToastView(text: NSLocalizedString("Failed to export account!", comment: ""), detailText: error.localizedDescription)
            toastView.show(in: top)
        }
    }
    #endif
    
    private func clearRefreshAttempts() {
        let context = DatabaseManager.shared.persistentContainer.newBackgroundContext()
        context.perform {
            let fetchRequest: NSFetchRequest<NSFetchRequestResult> = RefreshAttempt.fetchRequest()
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            _ = try? context.execute(deleteRequest)
            try? context.save()
        }
    }
    
    private func toggleRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(.green)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 50)
    }
    
    private var divider: some View {
        Rectangle()
            .fill(Color.settingsDivider)
            .frame(height: 0.5)
            .padding(.horizontal, 16)
    }
    
    private func exportDatabase() {
        guard !isExportingDB else { return }
        isExportingDB = true
        
        Task {
            do {
                let exportedURL = try await CoreDataHelper.exportCoreDataStore()
                debugLog("[DeveloperOptionsView] ExportedURL: \(exportedURL)")
                await MainActor.run {
                    isExportingDB = false
                }
            } catch {
                debugLog("[DeveloperOptionsView] Export error: \(error)")
                await MainActor.run {
                    isExportingDB = false
                }
            }
        }
    }

    
    private func triggerStartEMProxy() {
        guard let top = UIApplication.shared.topViewController() else { return }
        Task {
            do {
                try await startEMProxy()
                await MainActor.run {
                    let toastView = ToastView(text: NSLocalizedString("Started EMProxy", comment: ""), detailText: "EMProxy loopback server is running.")
                    toastView.show(in: top)
                }
            } catch {
                await MainActor.run {
                    let toastView = ToastView(text: NSLocalizedString("Failed to start EMProxy!", comment: ""), detailText: error.localizedDescription)
                    toastView.show(in: top)
                }
            }
        }
    }
    
    private func triggerStopEMProxy() {
        guard let top = UIApplication.shared.topViewController() else { return }
        Task {
            do {
                try await stopEMProxy()
                await MainActor.run {
                    let toastView = ToastView(text: NSLocalizedString("Stopped EMProxy", comment: ""), detailText: "EMProxy loopback server stopped.")
                    toastView.show(in: top)
                }
            } catch {
                await MainActor.run {
                    let toastView = ToastView(text: NSLocalizedString("Failed to stop EMProxy!", comment: ""), detailText: error.localizedDescription)
                    toastView.show(in: top)
                }
            }
        }
    }
    
    private func triggerReloadAllWidgets() {
        #if !os(tvOS)
        WidgetCenter.shared.reloadAllTimelines()
        let title = NSLocalizedString("Reloaded All Widgets", comment: "")
        let detail = "Triggered timeline refresh for all widgets."
        #else
        NotificationCenter.default.post(name: .TVTopShelfItemsDidChange, object: nil)
        let title = NSLocalizedString("Reloaded Top Shelf", comment: "")
        let detail = "Triggered Top Shelf refresh."
        #endif
        if let top = UIApplication.shared.topViewController() {
            let toastView = ToastView(text: title, detailText: detail)
            toastView.show(in: top)
        }
    }
    
    private func triggerRotateWidgetLog() {
        guard let top = UIApplication.shared.topViewController() else { return }
        #if !os(tvOS)
        let logName = "Widget"
        #else
        let logName = "Top Shelf"
        #endif
        do {
            if let rotatedURL = try WidgetLogManager.rotateLog() {
                let toastView = ToastView(text: String(format: NSLocalizedString("Rotated %@ Log", comment: ""), logName), detailText: "Saved to WidgetLogs/\(rotatedURL.lastPathComponent)")
                toastView.show(in: top)
            } else {
                let toastView = ToastView(text: String(format: NSLocalizedString("%@ Log Empty", comment: ""), logName), detailText: "Nothing to rotate.")
                toastView.show(in: top)
            }
        } catch {
            let toastView = ToastView(text: NSLocalizedString("Failed to Rotate Log", comment: ""), detailText: error.localizedDescription)
            toastView.show(in: top)
        }
    }
}
