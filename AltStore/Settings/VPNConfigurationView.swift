//
//  VPNConfiguration.swift
//  AltStore
//
//  Created by Magesh K on 02/03/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import Combine

private typealias SButton = SwiftUI.Button

struct VPNConfigurationView: View {
    @Environment(\.presentationMode) var presentationMode
    @StateObject private var config = TunnelConfig.shared

    var body: some View {
        List {
            Section(header: Text("Discovered from network")) {
                Group {
                    networkConfigRow(label: "Tunnel IP", text: $config.deviceIP, editable: false)
                    networkConfigRow(label: "Device IP", text: $config.fakeIP, editable: false)
                    networkConfigRow(label: "Subnet Mask", text: $config.subnetMask, editable: false)
                }
            }
            
            Section {
                networkConfigRow(
                    label: "Device IP",
                    text: Binding<String?>(get: { config.overrideFakeIP }, set: { config.overrideFakeIP = $0 ?? "" }),
                    editable: true
                )
                networkConfigRow(
                    label: "Active",
                    text: Binding<String?>(get: { config.overrideActive }, set: { _ in }),
                    editable: false
                )
            } header: {
                Text("User Configuration")
            } footer: {
                HStack(alignment: .top, spacing: 0) {
                    Text("Note: ")
                    Text("'Device IP' is mandatory and should match exactly as in the VPN's configuration")
                }
            }
        }
        .navigationTitle("VPN Configuration")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SButton("Confirm") {
                    commitChanges()
                }
            }
        }
    }

    private func commitChanges() {
        bindTunnelConfig()
    }
    
    private func dismiss() {
        presentationMode.wrappedValue.dismiss()
    }

    private func networkConfigRow(
        label: LocalizedStringKey,
        text: Binding<String?>,
        editable: Bool
    ) -> some View {

        let proxy = Binding<String>(
            get: { text.wrappedValue ?? "N/A" },
            set: { text.wrappedValue = $0.isEmpty || $0 == "N/A" ? nil : $0 }
        )

        return HStack {
            Text(label)
                .foregroundColor(editable ? .primary : .gray)
            Spacer()
            TextField(label, text: proxy)
                .multilineTextAlignment(.trailing)
                .foregroundColor(editable ? .secondary : .gray)
                .disabled(!editable)
                .keyboardType(.numbersAndPunctuation)
                .onChange(of: proxy.wrappedValue) { newValue in
                    guard editable else { return }
                    proxy.wrappedValue =
                        newValue.filter { "0123456789.".contains($0) }
                }
        }
    }
}


final class TunnelConfig: ObservableObject {

    static let shared = TunnelConfig()

    private static let defaultOverrideIP: String = {
        if #available(iOS 26.4, *) { return "192.168.1.50" }
        return "10.7.0.1"
    }()

    @Published var deviceIP: String?
    @Published var subnetMask: String?
    @Published var fakeIP: String?
    @Published var overrideFakeIP: String = overrideIPStorage {
        didSet { Self.overrideIPStorage = overrideFakeIP }
    }
    @Published var overrideEffective: Bool = false
 
    private static var overrideIPStorage: String {
        get { UserDefaults.standard.string(forKey: "TunnelOverrideFakeIP") ?? defaultOverrideIP }
        set { UserDefaults.standard.set(newValue, forKey: "TunnelOverrideFakeIP") }
    }

    var overrideActive: String { overrideEffective ? "Yes" : "No" }
}
