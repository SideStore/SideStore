//
//  WirelessPairTargetDialog.swift
//  SideStore
//
//  Created by Magesh K on 24/08/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import Minimuxer

struct WirelessPairTargetDialog: View {
    @ObservedObject var viewModel: WirelessPairViewModel
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if viewModel.dialogMode == .client {
                        clientModeContent
                    } else {
                        serverModeContent
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .refreshable {
                viewModel.refreshDialog()
            }
            #if !os(tvOS)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationBarTitle(viewModel.dialogMode == .client ? "Select Device To Pair" : "Select Server Interface", displayMode: .inline)
            #else
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(viewModel.dialogMode == .client ? "Select Device To Pair" : "Select Server Interface")
            #endif
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    SwiftUI.Button {
                        debugLog("[WirelessPairTargetDialog] xmark close button tapped")
                        viewModel.dismissDialog()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 30, height: 30)
                            .background(Color.white.opacity(0.18))
                            .clipShape(Circle())
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    SwiftUI.Button("Select") {
                        debugLog("[WirelessPairTargetDialog] Select button tapped (mode=\(viewModel.dialogMode.rawValue))")
                        viewModel.confirmSelection()
                    }
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.accentColor)
                }
            }
        }
        .onAppear {
            viewModel.onDialogAppear()
        }
        .onDisappear {
            viewModel.onDialogDisappear()
        }
    }
    
    // MARK: - Server Mode Views
    
    @ViewBuilder
    private var serverModeContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LOCAL NETWORK INTERFACES")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
            
            if viewModel.activeInterfaces.isEmpty {
                Text("No active local interfaces detected.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 4)
            } else {
                VStack(spacing: 12) {
                    ForEach(viewModel.activeInterfaces) { iface in
                        localInterfaceRow(for: iface)
                    }
                }
            }
        }
    }
    
    private func interfaceTypeTag(name: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            
            Text(name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule()
                #if !os(tvOS)
                .fill(Color(.tertiarySystemFill))
                #else
                .fill(Color.white.opacity(0.15))
                #endif
        )
    }
    
    private func localInterfaceRow(for iface: LocalInterfaceInfo) -> some View {
        let isIpV4 = !iface.ip.contains(":")
        let v4 = isIpV4 ? iface.ip : nil
        let v6 = iface.ipv6 ?? (!isIpV4 ? iface.ip : nil)
        let isSelected = viewModel.selectedServerInterfaceId == iface.id
        let tagColor: Color = iface.type.isVPN ? .green : (iface.type == .wifi ? .accentColor : .secondary)
        
        return SwiftUI.Button {
            debugLog("[WirelessPairTargetDialog] Tapped local interface row: '\(iface.name)' [\(iface.type.rawValue)] (id=\(iface.id))")
            viewModel.selectServerInterface(id: iface.id)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: iface.type.symbolName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                        .frame(width: 20)
                    
                    Text(iface.name)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    interfaceTypeTag(name: iface.type.rawValue, color: tagColor)
                    
                    Spacer()
                    
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 19))
                        #if !os(tvOS)
                        .foregroundColor(isSelected ? .green : Color(.tertiaryLabel))
                        #else
                        .foregroundColor(isSelected ? .green : Color.secondary)
                        #endif
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    if let v4 = v4, !v4.isEmpty {
                        Text("IPv4: \(v4)")
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    if let v6 = v6, !v6.isEmpty {
                        Text("IPv6: \(v6)")
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    #if !os(tvOS)
                    .fill(isSelected ? Color.accentColor.opacity(0.16) : Color(.secondarySystemGroupedBackground))
                    #else
                    .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.white.opacity(0.1))
                    #endif
                    .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1.5)
                )
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Client Mode Views
    
    @ViewBuilder
    private var clientModeContent: some View {
        // Section: Configured Fallback Endpoint
        VStack(alignment: .leading, spacing: 10) {
            Text("CONFIGURED ENDPOINT")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
            
            fallbackEndpointRow
        }
        
        // Section: Discovered Devices
        VStack(alignment: .leading, spacing: 10) {
            Text("DISCOVERED NEARBY")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
            
            if viewModel.discoveredTargets.isEmpty {
                HStack(spacing: 10) {
                    if viewModel.isScanning {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Searching local network for devices…")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    } else {
                        Text("No pairing targets found via Bonjour.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
            } else {
                VStack(spacing: 12) {
                    ForEach(viewModel.discoveredTargets) { target in
                        discoveredTargetRow(for: target)
                    }
                }
            }
        }
    }
    
    private func discoveredTargetRow(for target: WirelessPairTarget) -> some View {
        let isSelected = viewModel.isTargetSelected(target)
        let portString = target.port > 0 ? String(format: "%u", target.port) : ""
        
        return SwiftUI.Button {
            debugLog("[WirelessPairTargetDialog] Tapped discovered target row: '\(target.name)' [\(target.rawType)] (id=\(target.id))")
            viewModel.selectTarget(target)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: target.iconName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                        .frame(width: 20)
                    
                    interfaceTypeTag(name: target.rawType, color: .accentColor)
                    
                    Spacer()
                    
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 19))
                        .foregroundColor(isSelected ? .green : Color(.tertiaryLabel))
                }
                
                Text(target.name)
                    .font(.footnote)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                VStack(alignment: .leading, spacing: 3) {
                    if let v4 = target.ipv4, !v4.isEmpty {
                        let formattedV4 = portString.isEmpty ? v4 : "\(v4):\(portString)"
                        Text("IPv4: \(formattedV4)")
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    if let v6 = target.ipv6, !v6.isEmpty {
                        let formattedV6 = portString.isEmpty ? v6 : "[\(v6)]:\(portString)"
                        Text("IPv6: \(formattedV6)")
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    
                    if (target.ipv4 == nil || target.ipv4?.isEmpty == true) && (target.ipv6 == nil || target.ipv6?.isEmpty == true) {
                        if !portString.isEmpty {
                            Text("Port: \(portString)")
                                .font(.caption.monospaced())
                                .foregroundColor(.secondary)
                        } else if viewModel.isScanning {
                            Text("Resolving IP address…")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Address unavailable")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    #if !os(tvOS)
                    .fill(isSelected ? Color.accentColor.opacity(0.16) : Color(.secondarySystemGroupedBackground))
                    #else
                    .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.white.opacity(0.1))
                    #endif
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    private var fallbackEndpointRow: some View {
        let fallback = viewModel.fallbackConfigEndpoint
        let isSelected = viewModel.isFallbackSelected
        let portString = String(format: "%u", fallback.port)
        
        return SwiftUI.Button {
            debugLog("[WirelessPairTargetDialog] Tapped configured fallback row (\(fallback.ip):\(portString))")
            viewModel.selectFallbackEndpoint()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "network")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                        .frame(width: 20)
                    
                    interfaceTypeTag(name: "Manual", color: .secondary)
                    
                    Spacer()
                    
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 19))
                        .foregroundColor(isSelected ? .green : Color(.tertiaryLabel))
                }
                
                Text("Configured Target")
                    .font(.footnote)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                let isV6 = fallback.ip.contains(":")
                let label = isV6 ? "IPv6" : "IPv4"
                let formattedIp = isV6 ? "[\(fallback.ip)]:\(portString)" : "\(fallback.ip):\(portString)"
                Text("\(label): \(formattedIp)")
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    #if !os(tvOS)
                    .fill(isSelected ? Color.accentColor.opacity(0.16) : Color(.secondarySystemGroupedBackground))
                    #else
                    .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.white.opacity(0.1))
                    #endif
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
