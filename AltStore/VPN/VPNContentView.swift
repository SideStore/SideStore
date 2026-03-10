//
//  VPNContentView.swift
//  SideStore
//
//  Ported from LocalDevVPN by Stossy11.
//  Embedded as the VPN tab in SideStore.
//

import Foundation
import NetworkExtension
import SwiftUI

// MARK: - Bundle helpers

private extension Bundle {
    var shortVersion: String { object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0" }
    /// The tunnel provider bundle ID is the app bundle ID + ".TunnelProv"
    var tunnelBundleID: String { bundleIdentifier!.appending(".TunnelProv") }
}

// MARK: - Logging

class VPNLogger: ObservableObject {
    @Published var logs: [String] = []

    static let shared = VPNLogger()
    private init() {}

    func log(_ message: Any, file: String = #file, function: String = #function, line: Int = #line) {
#if DEBUG
        let fileName = (file as NSString).lastPathComponent
        print("[\(fileName):\(line)] \(function): \(message)")
#endif
        logs.append("\(message)")
    }
}

// MARK: - Tunnel Manager

class TunnelManager: ObservableObject {
    @Published var hasLocalDeviceSupport = false
    @Published var tunnelStatus: TunnelStatus = .disconnected
    @Published var waitingOnSettings: Bool = false
    @Published var vpnManager: NETunnelProviderManager?

    static let shared = TunnelManager()

    private var vpnObserver: NSObjectProtocol?
    private var isProcessingStatusChange = false
    private let isSimulator: Bool = {
#if targetEnvironment(simulator)
        return true
#else
        return false
#endif
    }()

    private var tunnelDeviceIp: String {
        UserDefaults.standard.string(forKey: "TunnelDeviceIP") ?? "10.7.0.0"
    }
    private var tunnelFakeIp: String {
        UserDefaults.standard.string(forKey: "TunnelFakeIP") ?? "10.7.0.1"
    }
    private var tunnelSubnetMask: String {
        UserDefaults.standard.string(forKey: "TunnelSubnetMask") ?? "255.255.255.0"
    }
    private var tunnelBundleId: String {
        Bundle.main.bundleIdentifier!.appending(".TunnelProv")
    }

    enum TunnelStatus: Equatable {
        case disconnected, connecting, connected, disconnecting, error

        var color: Color {
            switch self {
            case .disconnected:  return .gray
            case .connecting:    return .orange
            case .connected:     return .green
            case .disconnecting: return .orange
            case .error:         return .red
            }
        }
        var systemImage: String {
            switch self {
            case .disconnected:  return "network.slash"
            case .connecting:    return "network.badge.shield.half.filled"
            case .connected:     return "checkmark.shield.fill"
            case .disconnecting: return "network.badge.shield.half.filled"
            case .error:         return "exclamationmark.shield.fill"
            }
        }
        var localizedTitle: LocalizedStringKey {
            switch self {
            case .disconnected:  return "disconnected"
            case .connecting:    return "connecting"
            case .connected:     return "connected"
            case .disconnecting: return "disconnecting"
            case .error:         return "error"
            }
        }
    }

    private init() {
        if isSimulator {
            loadTunnelPreferences()
            VPNLogger.shared.log("Running on Simulator – VPN calls are mocked")
            DispatchQueue.main.async { [weak self] in
                self?.waitingOnSettings = true
            }
        } else {
            setupStatusObserver()
            loadTunnelPreferences()
        }
    }

    // MARK: Private

    private func loadTunnelPreferences() {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            guard let self else { return }
            DispatchQueue.main.async {
                if let error {
                    VPNLogger.shared.log("Error loading preferences: \(error.localizedDescription)")
                    self.tunnelStatus = .error
                    self.waitingOnSettings = true
                    return
                }
                self.hasLocalDeviceSupport = true
                self.waitingOnSettings = true
                guard let managers, !managers.isEmpty else {
                    VPNLogger.shared.log("No existing tunnel configurations found")
                    return
                }
                let mine = managers.filter { ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == self.tunnelBundleId }
                if mine.isEmpty {
                    VPNLogger.shared.log("No LocalDevVPN tunnel configuration found")
                } else if mine.count > 1 {
                    self.cleanupDuplicateManagers(mine)
                } else if let manager = mine.first {
                    self.vpnManager = manager
                    self.updateTunnelStatus(from: manager.connection.status)
                }
            }
        }
    }

    private func cleanupDuplicateManagers(_ managers: [NETunnelProviderManager]) {
        VPNLogger.shared.log("Found \(managers.count) LocalDevVPN configurations. Cleaning up duplicates…")
        let keep = managers.first { $0.connection.status == .connected || $0.connection.status == .connecting } ?? managers[0]
        DispatchQueue.main.async { [weak self] in
            self?.vpnManager = keep
            self?.updateTunnelStatus(from: keep.connection.status)
        }
        for m in managers where m !== keep {
            m.removeFromPreferences { error in
                if let error { VPNLogger.shared.log("Error removing duplicate VPN: \(error.localizedDescription)") }
            }
        }
    }

    private func setupStatusObserver() {
        vpnObserver = NotificationCenter.default.addObserver(forName: .NEVPNStatusDidChange, object: nil, queue: .main) { [weak self] notification in
            guard let self, let connection = notification.object as? NEVPNConnection else { return }
            if let manager = self.vpnManager, connection == manager.connection {
                self.updateTunnelStatus(from: connection.status)
            }
            self.handleVPNStatusChange(notification: notification)
        }
    }

    private func updateTunnelStatus(from status: NEVPNStatus) {
        let new: TunnelStatus
        switch status {
        case .invalid, .disconnected: new = .disconnected
        case .connecting:             new = .connecting
        case .connected:              new = .connected
        case .disconnecting:          new = .disconnecting
        case .reasserting:            new = .connecting
        @unknown default:             new = .error
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.tunnelStatus != new else { return }
            self.tunnelStatus = new
        }
    }

    private func createLocalDevVPNConfiguration(completion: @escaping (NETunnelProviderManager?) -> Void) {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            guard let self else { completion(nil); return }
            if let error { VPNLogger.shared.log("Error: \(error.localizedDescription)"); completion(nil); return }
            if let existing = managers?.first(where: { ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == self.tunnelBundleId }) {
                completion(existing); return
            }
            let manager = NETunnelProviderManager()
            manager.localizedDescription = "LocalDevVPN"
            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = self.tunnelBundleId
            proto.serverAddress = "LocalDevVPN's Local Network Tunnel"
            manager.protocolConfiguration = proto
            let rule = NEOnDemandRuleEvaluateConnection()
            rule.interfaceTypeMatch = .any
            rule.connectionRules = [NEEvaluateConnectionRule(matchDomains: ["10.7.0.0", "10.7.0.1"], andAction: .connectIfNeeded)]
            manager.onDemandRules = [rule]
            manager.isOnDemandEnabled = true
            manager.isEnabled = true
            manager.saveToPreferences { error in
                DispatchQueue.main.async {
                    if let error { VPNLogger.shared.log("Error creating config: \(error.localizedDescription)"); completion(nil); return }
                    completion(manager)
                }
            }
        }
    }

    private func getActiveVPNManager(completion: @escaping (NETunnelProviderManager?) -> Void) {
        NETunnelProviderManager.loadAllFromPreferences { managers, error in
            if let error { VPNLogger.shared.log("Error: \(error.localizedDescription)"); completion(nil); return }
            completion(managers?.first { $0.connection.status == .connected || $0.connection.status == .connecting })
        }
    }

    // MARK: Public

    func toggleVPNConnection() {
        tunnelStatus == .connected || tunnelStatus == .connecting ? stopVPN() : startVPN()
    }

    func startVPN() {
        if isSimulator { simulateStartVPN(); return }
        if let manager = vpnManager {
            let s = manager.connection.status
            if s == .connected { DispatchQueue.main.async { self.tunnelStatus = .connected }; return }
            if s == .connecting { DispatchQueue.main.async { self.tunnelStatus = .connecting }; return }
        }
        getActiveVPNManager { [weak self] active in
            guard let self else { return }
            if let active, (active.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier != self.tunnelBundleId {
                UserDefaults.standard.set(true, forKey: "ShouldStartLocalDevVPNAfterDisconnect")
                active.connection.stopVPNTunnel()
                return
            }
            self.initializeAndStartLocalDevVPN()
        }
    }

    private func initializeAndStartLocalDevVPN() {
        if let manager = vpnManager {
            manager.loadFromPreferences { [weak self] error in
                guard let self else { return }
                if let error { VPNLogger.shared.log("Error reloading manager: \(error.localizedDescription)"); self.createAndStartVPN(); return }
                self.startExistingVPN(manager: manager)
            }
        } else {
            createAndStartVPN()
        }
    }

    private func createAndStartVPN() {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            guard let self else { return }
            if let error { VPNLogger.shared.log("Error: \(error.localizedDescription)") }
            if let mine = managers?.filter({ ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == self.tunnelBundleId }), !mine.isEmpty {
                DispatchQueue.main.async { self.vpnManager = mine.first }
                if mine.count > 1 { self.cleanupDuplicateManagers(mine) }
                if let m = mine.first { self.startExistingVPN(manager: m) }
                return
            }
            self.createLocalDevVPNConfiguration { [weak self] manager in
                guard let self, let manager else { return }
                DispatchQueue.main.async { self.vpnManager = manager }
                self.startExistingVPN(manager: manager)
            }
        }
    }

    private func startExistingVPN(manager: NETunnelProviderManager) {
        let current = manager.connection.status
        if current == .connected  { DispatchQueue.main.async { self.tunnelStatus = .connected  }; return }
        if current == .connecting { DispatchQueue.main.async { self.tunnelStatus = .connecting }; return }
        manager.isEnabled = true
        manager.saveToPreferences { [weak self] error in
            guard let self else { return }
            if let error { VPNLogger.shared.log("Error saving: \(error.localizedDescription)"); DispatchQueue.main.async { self.tunnelStatus = .error }; return }
            manager.loadFromPreferences { [weak self] error in
                guard let self else { return }
                if let error { VPNLogger.shared.log("Error reloading: \(error.localizedDescription)"); DispatchQueue.main.async { self.tunnelStatus = .error }; return }
                if manager.connection.status == .connected { DispatchQueue.main.async { self.tunnelStatus = .connected }; return }
                DispatchQueue.main.async { self.tunnelStatus = .connecting }
                let opts: [String: NSObject] = [
                    "TunnelDeviceIP": self.tunnelDeviceIp as NSObject,
                    "TunnelFakeIP":   self.tunnelFakeIp   as NSObject,
                    "TunnelSubnetMask": self.tunnelSubnetMask as NSObject,
                ]
                do {
                    try manager.connection.startVPNTunnel(options: opts)
                } catch {
                    DispatchQueue.main.async { self.tunnelStatus = .error }
                    VPNLogger.shared.log("Failed to start tunnel: \(error.localizedDescription)")
                }
            }
        }
    }

    func stopVPN() {
        if isSimulator { simulateStopVPN(); return }
        guard let manager = vpnManager else { return }
        DispatchQueue.main.async { self.tunnelStatus = .disconnecting }
        manager.connection.stopVPNTunnel()
        UserDefaults.standard.removeObject(forKey: "ShouldStartLocalDevVPNAfterDisconnect")
    }

    func handleVPNStatusChange(notification: Notification) {
        guard let connection = notification.object as? NEVPNConnection else { return }
        if let manager = vpnManager, connection == manager.connection {
            updateTunnelStatus(from: connection.status)
        }
        if connection.status == .disconnected && UserDefaults.standard.bool(forKey: "ShouldStartLocalDevVPNAfterDisconnect") {
            UserDefaults.standard.removeObject(forKey: "ShouldStartLocalDevVPNAfterDisconnect")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.initializeAndStartLocalDevVPN() }
            return
        }
        guard !isProcessingStatusChange else { return }
        isProcessingStatusChange = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, _ in
                guard let self, let managers, !managers.isEmpty else {
                    DispatchQueue.main.async { self?.isProcessingStatusChange = false }
                    return
                }
                let mine = managers.filter { ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == self.tunnelBundleId }
                if mine.count > 1 { DispatchQueue.main.async { self.cleanupDuplicateManagers(mine) } }
                DispatchQueue.main.async { self.isProcessingStatusChange = false }
            }
        }
    }

    func cleanupAllVPNConfigurations() {
        if isSimulator { return }
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            guard let self else { return }
            if let error { VPNLogger.shared.log("Error: \(error.localizedDescription)"); return }
            for m in managers ?? [] {
                guard (m.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == self.tunnelBundleId else { continue }
                if m.connection.status == .connected || m.connection.status == .connecting { m.connection.stopVPNTunnel() }
                m.removeFromPreferences { _ in }
            }
            DispatchQueue.main.async { self.vpnManager = nil; self.tunnelStatus = .disconnected }
        }
    }

    deinit {
        if let observer = vpnObserver { NotificationCenter.default.removeObserver(observer) }
    }

    // MARK: Simulator stubs
    private func simulateStartVPN() {
        DispatchQueue.main.async { self.tunnelStatus = .connecting }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.tunnelStatus = .connected }
    }
    private func simulateStopVPN() {
        DispatchQueue.main.async { self.tunnelStatus = .disconnecting }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.tunnelStatus = .disconnected }
    }
}

// MARK: - Views

struct VPNRootView: View {
    @StateObject private var tunnelManager = TunnelManager.shared
    @State private var showSettings = false
    @AppStorage("autoConnect") private var autoConnect = false
    @AppStorage("hasNotCompletedVPNSetup") private var hasNotCompletedSetup = true
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                VPNStatusOverviewCard()
                VPNConnectivityControlsCard(autoConnect: $autoConnect) {
                    tunnelManager.tunnelStatus == .connected ? tunnelManager.stopVPN() : tunnelManager.startVPN()
                }
                if tunnelManager.tunnelStatus == .connected {
                    VPNConnectionStatsView()
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 24)
        }
        .background(vpnBackgroundColor.ignoresSafeArea())
        .navigationTitle("LocalDevVPN")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: {
                    Image(systemName: "gear").foregroundColor(.primary)
                }
            }
        }
        .onChange(of: tunnelManager.waitingOnSettings) { finished in
            if tunnelManager.tunnelStatus != .connected && autoConnect && finished {
                tunnelManager.startVPN()
            }
        }
        .sheet(isPresented: $showSettings) { VPNSettingsView() }
        .sheet(isPresented: $hasNotCompletedSetup) { VPNSetupView() }
    }

    private var vpnBackgroundColor: Color {
        colorScheme == .dark ? Color(.systemBackground) : Color(.systemGroupedBackground)
    }
}

// MARK: Status card

struct VPNStatusOverviewCard: View {
    @StateObject private var tunnelManager = TunnelManager.shared

    var body: some View {
        VPNDashboardCard {
            VStack(alignment: .leading, spacing: 18) {
                Text("current_status").font(.headline)
                HStack(spacing: 18) {
                    VPNStatusGlyphView()
                    Text(tunnelManager.tunnelStatus.localizedTitle)
                        .font(.title3).fontWeight(.semibold)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                Divider()
                HStack {
                    Label { Text(statusTip) } icon: { Image(systemName: "info.circle") }
                        .font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Text(Date(), style: .time).font(.caption).foregroundColor(.secondary)
                }
            }
        }
    }

    private var statusTip: String {
        switch tunnelManager.tunnelStatus {
        case .connected:     return NSLocalizedString("connected_to_10.7.0.1", comment: "")
        case .connecting:    return NSLocalizedString("macos_might_ask_you_to_approve_the_vpn", comment: "")
        case .disconnecting: return NSLocalizedString("disconnecting_safely", comment: "")
        case .error:         return NSLocalizedString("open_settings_to_review_details", comment: "")
        default:             return NSLocalizedString("tap_connect_to_create_the_tunnel", comment: "")
        }
    }
}

struct VPNStatusGlyphView: View {
    @StateObject private var tunnelManager = TunnelManager.shared
    @State private var animate = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(tunnelManager.tunnelStatus.color.opacity(0.25), lineWidth: 6)
                .scaleEffect(animate ? 1.05 : 0.95)
                .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: animate)
            Circle().fill(tunnelManager.tunnelStatus.color.opacity(0.15))
            Image(systemName: tunnelManager.tunnelStatus.systemImage)
                .font(.title)
                .foregroundColor(tunnelManager.tunnelStatus.color)
        }
        .frame(width: 92, height: 92)
        .onAppear { animate = true }
        .onChange(of: tunnelManager.tunnelStatus) { _ in
            animate.toggle()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { animate = true }
        }
    }
}

// MARK: Controls card

struct VPNConnectivityControlsCard: View {
    @Binding var autoConnect: Bool
    let action: () -> Void

    var body: some View {
        VPNDashboardCard {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("connection").font(.headline)
                    Text("start_or_stop_the_secure_local_tunnel").font(.footnote).foregroundColor(.secondary)
                }
                VPNConnectionButton(action: action)
                Toggle(isOn: $autoConnect) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("auto-connect_on_launch").fontWeight(.semibold)
                        Text("resume_your_last_state_automatically").font(.caption).foregroundColor(.secondary)
                    }
                }
                .toggleStyle(SwitchToggleStyle(tint: .accentColor))
            }
        }
    }
}

struct VPNConnectionButton: View {
    @StateObject private var tunnelManager = TunnelManager.shared
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack {
                Text(buttonText).font(.headline).fontWeight(.semibold)
                if tunnelManager.tunnelStatus == .connecting || tunnelManager.tunnelStatus == .disconnecting {
                    ProgressView().progressViewStyle(CircularProgressViewStyle()).padding(.leading, 5)
                }
            }
            .frame(maxWidth: .infinity).frame(height: 56)
            .background(buttonBackground)
            .foregroundColor(.white)
            .clipShape(Capsule())
            .shadow(color: shadowColor, radius: 10, x: 0, y: 5)
        }
        .disabled(tunnelManager.tunnelStatus == .connecting || tunnelManager.tunnelStatus == .disconnecting)
    }

    private var buttonText: String {
        switch tunnelManager.tunnelStatus {
        case .connected:     return NSLocalizedString("disconnect", comment: "")
        case .connecting:    return NSLocalizedString("connecting_ellipsis", comment: "")
        case .disconnecting: return NSLocalizedString("disconnecting_ellipsis", comment: "")
        default:             return NSLocalizedString("connect", comment: "")
        }
    }
    private var buttonBackground: some View {
        Group {
            if tunnelManager.tunnelStatus == .connected {
                LinearGradient(colors: [Color.red.opacity(0.8), Color.red], startPoint: .leading, endPoint: .trailing)
            } else {
                LinearGradient(colors: [Color.blue.opacity(0.8), Color.blue], startPoint: .leading, endPoint: .trailing)
            }
        }
    }
    private var shadowColor: Color { colorScheme == .dark ? Color.black.opacity(0.5) : Color.black.opacity(0.15) }
}

// MARK: Stats view

struct VPNConnectionStatsView: View {
    @StateObject private var tunnelManager = TunnelManager.shared
    @State private var time = 0
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @AppStorage("TunnelDeviceIP")    private var deviceIP    = "10.7.0.0"
    @AppStorage("TunnelFakeIP")      private var fakeIP      = "10.7.0.1"
    @AppStorage("TunnelSubnetMask")  private var subnetMask  = "255.255.255.0"

    var body: some View {
        VPNDashboardCard {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("session_details").font(.headline)
                    Text("live_stats_while_the_tunnel_is_connected").font(.footnote).foregroundColor(.secondary)
                }
                HStack(spacing: 16) {
                    VPNStatItemView(title: "time_connected", value: formattedTime, icon: "clock.fill")
                    VPNStatItemView(title: "status",         value: statusValue,   icon: tunnelManager.tunnelStatus.systemImage)
                }
                Divider()
                Text("network_configuration").font(.caption).foregroundColor(.secondary)
                VPNConnectionInfoRow(title: "local_device_ip", value: deviceIP,   icon: "desktopcomputer")
                VPNConnectionInfoRow(title: "tunnel_ip",       value: fakeIP,     icon: "point.3.filled.connected.trianglepath.dotted")
                VPNConnectionInfoRow(title: "subnet_mask",     value: subnetMask, icon: "network")
            }
        }
        .onReceive(timer) { _ in time += 1 }
    }

    private var formattedTime: String {
        let h = time / 3600; let m = (time / 60) % 60; let s = time % 60
        return h > 0 ? String(format: "%02d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
    private var statusValue: String {
        switch tunnelManager.tunnelStatus {
        case .connected:     return NSLocalizedString("Active", comment: "")
        case .connecting:    return NSLocalizedString("Connecting", comment: "")
        case .disconnecting: return NSLocalizedString("Disconnecting", comment: "")
        case .error:         return NSLocalizedString("Error", comment: "")
        default:             return NSLocalizedString("Idle", comment: "")
        }
    }
}

// MARK: Sub-components

struct VPNConnectionInfoRow: View {
    let title: String; let value: String; let icon: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.body).foregroundColor(.accentColor).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundColor(.secondary)
                Text(value).font(.body).foregroundColor(.primary)
            }
            Spacer()
        }
    }
}

struct VPNStatItemView: View {
    let title: LocalizedStringKey; let value: String; let icon: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundColor(.accentColor).font(.caption)
                Text(title).font(.caption).foregroundColor(.secondary)
            }
            Text(value).font(.headline).foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct VPNDashboardCard<Content: View>: View {
    private let content: () -> Content
    @Environment(\.colorScheme) private var colorScheme
    init(@ViewBuilder content: @escaping () -> Content) { self.content = content }

    var body: some View {
        content()
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(.secondarySystemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(borderColor))
            .shadow(color: shadowColor, radius: 12, x: 0, y: 6)
    }
    private var borderColor: Color { colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06) }
    private var shadowColor:  Color { colorScheme == .dark ? Color.black.opacity(0.5) : Color.black.opacity(0.12) }
}

// MARK: - Settings

struct VPNSettingsView: View {
    @Environment(\.presentationMode) var presentationMode
    @AppStorage("TunnelDeviceIP")   private var deviceIP   = "10.7.0.0"
    @AppStorage("TunnelFakeIP")     private var fakeIP     = "10.7.0.1"
    @AppStorage("TunnelSubnetMask") private var subnetMask = "255.255.255.0"
    @AppStorage("autoConnect")      private var autoConnect = false
    @AppStorage("shownTunnelAlert") private var shownTunnelAlert = false
    @StateObject private var tunnelManager = TunnelManager.shared
    @State private var showNetworkWarning = false
    @State private var showRestartPopUp = false

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("connection_settings")) {
                    Toggle("auto_connect_on_launch", isOn: $autoConnect)
                    NavigationLink(destination: VPNConnectionLogView()) {
                        Label("connection_logs", systemImage: "doc.text")
                    }
                }
                Section(header: Text("network_configuration")) {
                    vpnConfigRow(label: "tunnel_ip",    text: $deviceIP)
                    vpnConfigRow(label: "device_ip",    text: $fakeIP)
                    vpnConfigRow(label: "subnet_mask",  text: $subnetMask)
                }
                Section(header: Text("app_information")) {
                    Button {
                        UIApplication.shared.open(URL(string: "https://jkcoxson.com/cdn/LocalDevVPN/LocalDevVPNPrivacyPolicy.md")!, options: [:])
                    } label: {
                        Label("privacy_policy", systemImage: "lock.shield")
                    }
                    HStack {
                        Text("app_version")
                        Spacer()
                        Text(Bundle.main.shortVersion).foregroundColor(.secondary)
                    }
                }
            }
            .alert(isPresented: $showNetworkWarning) {
                Alert(
                    title: Text("warning_alert"),
                    message: Text("warning_message"),
                    dismissButton: .cancel(Text("understand_button")) {
                        shownTunnelAlert = true
                        deviceIP = "10.7.0.0"; fakeIP = "10.7.0.1"; subnetMask = "255.255.255.0"
                    }
                )
            }
            .navigationTitle(Text("settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("done") { presentationMode.wrappedValue.dismiss() }
                }
            }
        }
    }

    private func vpnConfigRow(label: LocalizedStringKey, text: Binding<String>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField(label, text: text)
                .multilineTextAlignment(.trailing)
                .foregroundColor(.secondary)
                .keyboardType(.numbersAndPunctuation)
                .onChange(of: text.wrappedValue) { _ in
                    if !shownTunnelAlert { showNetworkWarning = true }
                    tunnelManager.vpnManager?.saveToPreferences { _ in }
                }
        }
    }
}

// MARK: - Log View

struct VPNConnectionLogView: View {
    @StateObject var logger = VPNLogger.shared
    var body: some View {
        List(logger.logs, id: \.self) { log in
            Text(log).font(.system(.body, design: .monospaced))
        }
        .navigationTitle(Text("logs_nav"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Setup View

struct VPNSetupView: View {
    @Environment(\.presentationMode) var presentationMode
    @AppStorage("hasNotCompletedVPNSetup") private var hasNotCompletedSetup = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 72))
                        .foregroundColor(.accentColor)
                        .padding(.top, 40)

                    VStack(spacing: 8) {
                        Text("Welcome to LocalDevVPN")
                            .font(.title).fontWeight(.bold)
                        Text("LocalDevVPN creates a local network tunnel so SideStore can refresh and install apps without needing a Mac or PC on the same network.")
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        SetupStepRow(icon: "network", title: "Local tunnel", description: "Routes traffic between 10.7.0.0 and 10.7.0.1 on-device — no data leaves your iPhone.")
                        SetupStepRow(icon: "arrow.clockwise.circle", title: "App refresh", description: "Tap Connect before refreshing or installing apps in SideStore.")
                        SetupStepRow(icon: "gear", title: "Auto-connect", description: "Enable auto-connect in settings so the tunnel is always ready.")
                    }
                    .padding(.horizontal)

                    Button {
                        hasNotCompletedSetup = false
                        presentationMode.wrappedValue.dismiss()
                    } label: {
                        Text("Get Started")
                            .font(.headline).fontWeight(.semibold)
                            .frame(maxWidth: .infinity).frame(height: 56)
                            .background(LinearGradient(colors: [.blue.opacity(0.8), .blue], startPoint: .leading, endPoint: .trailing))
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct SetupStepRow: View {
    let icon: String; let title: String; let description: String
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2).foregroundColor(.accentColor)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).fontWeight(.semibold)
                Text(description).font(.footnote).foregroundColor(.secondary)
            }
        }
    }
}
