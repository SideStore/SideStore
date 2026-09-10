//
//  HealthCheckView.swift
//  SideStore
//
//  Created by Magesh K on 11/07/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import Minimuxer

struct HealthCheckView: View {
    @StateObject private var viewModel = HealthCheckViewModel()
    
    var body: some View {
        List {
            // Section 1: Connection Status Header
            Section {
                VStack(spacing: 12) {
                    if let result = viewModel.minimuxerReadyResult {
                        switch result {
                        case .success:
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 44))
                                .foregroundColor(.green)
                            Text("SideStore Ready")
                                .font(.title2)
                                .fontWeight(.bold)
                            Text(viewModel.connectionMode == .localVPN
                                 ? "All requirements met. Local device pairing & VPN tunnel active."
                                 : "All requirements met. Local device pairing & Remote server connection active."
                            )
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        case .failure(let err):
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 44))
                                .foregroundColor(.orange)
                            Text("Action Required")
                                .font(.title2)
                                .fontWeight(.bold)
                            Text(err.localizedDescription)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    } else {
                        ProgressView("Performing Diagnostic Check...")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            
            // Section 2: Core Dependencies
            Section(header: Text("Core Requirements")) {
                DependencyRow(
                    title: "Network Connectivity",
                    subtitle: viewModel.networkSatisfied == nil ? "Unknown" : (viewModel.isWifiSatisfied ? "Wi-Fi Active" : "No Connection"),
                    isSatisfied: viewModel.networkSatisfied
                )
                
                if viewModel.connectionMode == .localVPN {
                    DependencyRow(
                        title: "VPN Tunnel (utun)",
                        subtitle: viewModel.vpnSatisfied == nil ? "Unknown" : (viewModel.isUTunAvailable ? "Connected" : "Disconnected"),
                        isSatisfied: viewModel.vpnSatisfied
                    )
                    
                    if !viewModel.isRPPairing {
                        if #available(iOS 26.4, *) {
                            DependencyRow(
                                title: "IPSec/IKEv2 Tunnel",
                                subtitle: viewModel.ipsecSatisfied == nil ? "Unknown" : (viewModel.isIKEv2IPSecAvailable ? "Connected" : "Disconnected"),
                                isSatisfied: viewModel.ipsecSatisfied
                            )
                        }
                    }
                }
                
                DependencyRow(
                    title: "Device Reachability (Ping)",
                    subtitle: viewModel.pingSatisfied == nil ? "Unknown" : (viewModel.isPingSuccessful ? "Reachable" : "Unreachable"),
                    isSatisfied: viewModel.pingSatisfied
                )
                
                DependencyRow(
                    title: "Pairing file",
                    subtitle: viewModel.isPairingFileVerified ? "Verified" : (viewModel.isPairingFileLoaded ? "Loaded (Connection down)" : "Unverified / Missing"),
                    isSatisfied: viewModel.pairingSatisfied
                )
            }
            
            // Section 3: JIT Dependencies
            Section(header: Text("JIT Requirements")) {
                DependencyRow(
                    title: "Developer Disk Image (DDI)",
                    subtitle: viewModel.isDDIMounted ? "Mounted" : "Not Mounted (JIT unavailable)",
                    isSatisfied: viewModel.ddiSatisfied,
                    isOptional: true
                )
            }
            
            // Section 4: Connection Configuration
            Section(header: Text("Connection Configuration")) {
                HStack {
                    Text("Connection Mode")
                    Spacer()
                    Text(viewModel.connectionMode == .localVPN ? NSLocalizedString("Local VPN", comment: "") : NSLocalizedString("Remote Server", comment: ""))
                        .foregroundColor(.secondary)
                }
                
                if viewModel.connectionMode == .localVPN {
                    ConfigRow(label: "Tunnel Iface IP", value: viewModel.tunnelIfaceIp)
                    ConfigRow(label: "Tunnel Peer IP", value: viewModel.tunnelPeerIp)
                    ConfigRow(label: "Override Peer IP", value: viewModel.overrideTunnelPeerIp.isEmpty ? nil : viewModel.overrideTunnelPeerIp)
                    HStack {
                        Text("Override Status")
                        Spacer()
                        Text(viewModel.overrideTunnelPeerEffective ? NSLocalizedString("Active", comment: "") : NSLocalizedString("Inactive", comment: ""))
                            .foregroundColor(viewModel.overrideTunnelPeerEffective ? .green : .secondary)
                    }
                    HStack {
                        Text("Active Protocol")
                        Spacer()
                        Text(viewModel.activeProtocol)
                            .foregroundColor(.secondary)
                    }
                } else {
                    ConfigRow(label: "Remote Endpoint IP", value: viewModel.remoteServerIp.isEmpty ? nil : viewModel.remoteServerIp)
                    HStack {
                        Text("Active Protocol")
                        Spacer()
                        Text(viewModel.activeProtocol)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Section 4: All Active Interfaces
            Section(header: Text("Active Network Interfaces")) {
                if viewModel.availableInterfaces.isEmpty {
                    Text("No active interfaces scanned.")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    let vpnInterfaces = viewModel.availableInterfaces.filter { $0.type.isVPN }
                    let localInterfaces = viewModel.availableInterfaces.filter { !$0.type.isVPN }
                    
                    if !vpnInterfaces.isEmpty {
                        ForEach(vpnInterfaces) { iface in
                            InterfaceRow(iface: iface)
                        }
                    }
                    
                    if !localInterfaces.isEmpty {
                        ForEach(localInterfaces) { iface in
                            InterfaceRow(iface: iface)
                        }
                    }
                }
            }
        }
        .navigationTitle("Health Check")
        #if !os(tvOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await viewModel.observeMetrics()
        }
    }
}

struct DependencyRow: View {
    let title: String
    let subtitle: String
    let isSatisfied: Bool?
    var isOptional: Bool = false
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if let satisfied = isSatisfied {
                if satisfied {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title3)
                } else if isOptional {
                    Image(systemName: "minus.circle.fill")
                        .foregroundColor(.orange)
                        .font(.title3)
                } else {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                        .font(.title3)
                }
            } else {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundColor(.gray)
                    .font(.title3)
            }
        }
    }
}

struct ConfigRow: View {
    let label: String
    let value: String?
    
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value ?? "N/A")
                .foregroundColor(.secondary)
        }
    }
}

struct InterfaceRow: View {
    let iface: LocalInterfaceInfo
    
    private var hasIPv4: Bool {
        !iface.subnet.isEmpty && !iface.ip.contains(":")
    }
    
    private var ipv4Host: String {
        hasIPv4 ? iface.ip : "N/A"
    }
    
    private var ipv4Mask: String {
        !iface.subnet.isEmpty ? iface.subnet : "N/A"
    }
    
    private var ipv6Address: String {
        if let v6 = iface.ipv6, !v6.isEmpty {
            return v6
        }
        if iface.ip.contains(":") {
            return iface.ip
        }
        return "N/A"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Iface:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 36, alignment: .leading)
                
                Text(iface.name)
                    .fontWeight(.semibold)
                
                Text(iface.type.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(iface.type.isVPN ? Color.blue.opacity(0.15) : Color.gray.opacity(0.15))
                    .foregroundColor(iface.type.isVPN ? .blue : .primary)
                    .cornerRadius(4)
                
                Spacer()
            }
            .padding(.bottom, 2)
            
            HStack(alignment: .top, spacing: 8) {
                Text("IPv4:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 36, alignment: .leading)
                
                Text(ipv4Host)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(hasIPv4 ? .primary : .secondary)
                
                if hasIPv4 {
                    Text(String(format: NSLocalizedString("(%@)", comment: ""), ipv4Mask))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            HStack(alignment: .top, spacing: 8) {
                Text("IPv6:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 36, alignment: .leading)
                
                Text(ipv6Address)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(ipv6Address != "N/A" ? .primary : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}
