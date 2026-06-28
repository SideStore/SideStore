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

enum ActiveState: String {
    case yes = "Yes"
    case no = "No"
}

struct AnimatedCheckmarkView: View {
    @State private var outerCircleTrim: CGFloat = 0.0
    @State private var checkmarkTrim: CGFloat = 0.0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.green.opacity(0.2), lineWidth: 4)
                .frame(width: 70, height: 70)
            
            Circle()
                .trim(from: 0.0, to: outerCircleTrim)
                .stroke(Color.green, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 70, height: 70)
                .rotationEffect(.degrees(-90))
            
            Path { path in
                path.move(to: CGPoint(x: 21, y: 35))
                path.addLine(to: CGPoint(x: 30, y: 44))
                path.addLine(to: CGPoint(x: 49, y: 25))
            }
            .trim(from: 0.0, to: checkmarkTrim)
            .stroke(Color.green, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            .frame(width: 70, height: 70)
        }
        .onAppear {
            withAnimation(.easeIn(duration: 0.4)) {
                outerCircleTrim = 1.0
            }
            withAnimation(.easeIn(duration: 0.3).delay(0.4)) {
                checkmarkTrim = 1.0
            }
        }
    }
}

struct VPNConfigurationView: View {
    @Environment(\.presentationMode) var presentationMode
    @StateObject private var config = TunnelConfig.shared
    @State private var showConfirmDialog = false

    var body: some View {
        ZStack {
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
                        text: Binding<String?>(get: { config.overrideActive.rawValue }, set: { _ in }),
                        editable: false,
                        textColor: config.overrideActive == .yes ? .green : .red
                    )
                } header: {
                    Text("User Configuration")
                } footer: {
                    HStack(alignment: .top, spacing: 0) {
                        Text("Note: ")
                        Text("'Device IP' is mandatory and should match exactly as in the target VPN's config")
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
            .disabled(showConfirmDialog)
            
            if showConfirmDialog {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showConfirmDialog = false
                    }
                
                VStack(spacing: 24) {
                    AnimatedCheckmarkView()
                        .padding(.top, 10)
                    
                    Text("Changes saved")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white)
                    
                    SwiftUI.Button(action: {
                        showConfirmDialog = false
                    }) {
                        Text("OK")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(24)
                .frame(width: 320)
                .background(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeInOut, value: showConfirmDialog)
    }

    private func commitChanges() {
        bindTunnelConfig()
        showConfirmDialog = true
    }
    
    private func dismiss() {
        presentationMode.wrappedValue.dismiss()
    }

    private func networkConfigRow(
        label: LocalizedStringKey,
        text: Binding<String?>,
        editable: Bool,
        textColor: Color? = nil
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
                .foregroundColor(textColor ?? (editable ? .secondary : .gray))
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
//        if #available(iOS 26.4, *) { return "192.168.1.50" }
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

    var overrideActive: ActiveState { overrideEffective ? .yes : .no }
}
