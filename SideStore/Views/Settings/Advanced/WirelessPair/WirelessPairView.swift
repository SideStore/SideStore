//
//  WirelessPairView.swift
//  SideStore
//
//  Created by Magesh K on 04/07/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI

struct WirelessPairView: View {
    @StateObject private var viewModel = WirelessPairViewModel()
    
    private let spring = Animation.spring(response: 0.35, dampingFraction: 0.68)
    private let pulse = Animation.interactiveSpring(response: 1.5, dampingFraction: 0.55)
    
    var body: some View {
        VStack(spacing: 24) {
            // Pulsing Status Orb
                ZStack {
                    // Outer breathing glow
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: viewModel.isAdvertising ? [Color.accentColor.opacity(0.25), Color.clear] : [Color.gray.opacity(0.1), Color.clear],
                                center: .center,
                                startRadius: 20,
                                endRadius: 100
                            )
                        )
                        .frame(width: 220, height: 220)
                        .scaleEffect(viewModel.isAdvertising ? 1.2 : 1.0)
                        .opacity(viewModel.isAdvertising ? 1.0 : 0.5)
                        .animation(viewModel.isAdvertising ? pulse.repeatForever(autoreverses: true) : .default, value: viewModel.isAdvertising)
                    
                    // Secondary pulsing ring
                    Circle()
                        .stroke(viewModel.isAdvertising ? Color.accentColor.opacity(0.3) : Color.gray.opacity(0.2), lineWidth: 2)
                        .frame(width: 140, height: 140)
                        .scaleEffect(viewModel.isAdvertising ? 1.15 : 1.0)
                        .opacity(viewModel.isAdvertising ? 0.8 : 0.0)
                        .animation(viewModel.isAdvertising ? pulse.delay(0.2).repeatForever(autoreverses: true) : .default, value: viewModel.isAdvertising)

                    // Central Orb
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: viewModel.isAdvertising ? [Color.accentColor, Color.accentColor.opacity(0.8)] : [Color.gray, Color.gray.opacity(0.8)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 90, height: 90)
                        .shadow(color: viewModel.isAdvertising ? Color.accentColor.opacity(0.5) : Color.clear, radius: 15)
                    
                    Group {
                        if viewModel.isAdvertising {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .transition(.scale.combined(with: .opacity))
                        } else {
                            Image(systemName: "wifi.slash")
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundColor(.white)
                }
                .frame(height: 220)
                .padding(.top, 20)
                .padding(.bottom, 20)
                
                // Status Info
                VStack(spacing: 8) {
                    Text(viewModel.statusText)
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                    
                    if viewModel.serviceID == nil {
                        Text(viewModel.subStatusText)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                
                // Connection Details Card
                if let serviceID = viewModel.serviceID, let port = viewModel.port {
                        ConnectionDetailsCard(serviceID: serviceID, port: port)
                            .transition(.scale(scale: 0.95).combined(with: .opacity))

                    HStack(spacing: 8) {
                            Image(systemName: "wifi")
                                .font(.subheadline)
                                .foregroundColor(.accentColor)
                            Text("Ensure both devices are on the same Wi-Fi network.")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 4)
                }

                
                // PIN Display
                if let pin = viewModel.pinCode {
                    VStack(spacing: 12) {
                        Text("PAIRING CODE")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                            .tracking(3)
                        
                        HStack(spacing: 14) {
                            ForEach(Array(pin.enumerated()), id: \.offset) { _, char in
                                Text(String(char))
                                    .font(.system(size: 34, weight: .bold, design: .monospaced))
                                    .frame(width: 52, height: 68)
                                    #if !os(tvOS)
                                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
                                    #else
                                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.1)))
                                    #endif
                                    .shadow(color: Color.black.opacity(0.15), radius: 5, x: 0, y: 3)
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(LinearGradient(gradient: Gradient(colors: [Color.accentColor.opacity(0.5), Color.clear]), startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5))
                            }
                        }
                    }
                    .padding(.vertical, 16)
                    .transition(.scale.combined(with: .opacity))
                }
                
                // Error Display
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .transition(.opacity)
                }
                
                Spacer()
                
                // Main Button
                SwiftUI.Button(action: togglePairing) {
                    HStack {
                        if viewModel.isAdvertising {
                            Text("Stop Pairing Server")
                                .transition(.scale.combined(with: .opacity))
                        } else {
                            Text("Start Pairing Server")
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(viewModel.isAdvertising ? Color.red : Color.accentColor)
                    .clipShape(Capsule())
                    .shadow(color: (viewModel.isAdvertising ? Color.red : Color.accentColor).opacity(0.3), radius: 10, y: 5)
                }
                .animation(.spring(response: 0.28, dampingFraction: 0.65), value: viewModel.isAdvertising)
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
        }
        .navigationTitle("Wireless Pairing")
        #if !os(tvOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                SwiftUI.Button {
                    debugLog("[WirelessPairView] Trailing toolbar bolt button tapped -> openClientDialog()")
                    viewModel.openClientDialog()
                } label: {
                    Image(systemName: "bolt.horizontal.fill")
                        .font(.system(size: 16, weight: .medium))
                }
                .accessibilityLabel("Connect to Target Device")
            }
        }
        .onAppear {
            debugLog("[WirelessPairView] onAppear (isAdvertising=\(viewModel.isAdvertising), serviceID=\(viewModel.serviceID ?? "nil"), port=\(viewModel.port.map(String.init) ?? "nil"))")
        }
        .onDisappear {
            debugLog("[WirelessPairView] onDisappear (isAdvertising=\(viewModel.isAdvertising))")
        }
        .sheet(isPresented: $viewModel.isTargetDialogPresented) {
            if #available(iOS 16.0, tvOS 16.0, *) {
                WirelessPairTargetDialog(viewModel: viewModel)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            } else {
                WirelessPairTargetDialog(viewModel: viewModel)
            }
        }
        .alert("Enter Pairing PIN", isPresented: $viewModel.isPinPromptPresented) {
            TextField("6-digit PIN", text: $viewModel.enteredPin)
                .keyboardType(.numberPad)
            SwiftUI.Button("Pair") {
                viewModel.submitEnteredPin()
            }
            SwiftUI.Button("Cancel", role: .cancel) {
                viewModel.cancelPinPrompt()
            }
        } message: {
            Text("Enter the 6-digit code displayed on your Apple TV / device screen.")
        }
        .sheet(isPresented: $viewModel.isShareSheetPresented) {
            if let fileURL = viewModel.shareSheetURL {
                ActivityViewController(activityItems: [fileURL])
            }
        }
    }
    
    private func togglePairing() {
        debugLog("[WirelessPairView] togglePairing tapped (currently isAdvertising=\(viewModel.isAdvertising))")
        withAnimation(spring) {
            viewModel.togglePairing()
        }
    }
}


struct ConnectionDetailsCard: View {
    let serviceID: String
    let port: Int
    
    var rows: [(label: String, value: String)] {[
        ("Device ID", serviceID),
        ("Port", String(port))
    ]}
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack{
                Image(systemName: "network")
                    .foregroundColor(.accentColor)
                Text("Connection Details")
                    .font(.headline)
            }
            .padding(.horizontal, 16)

            VStack(alignment: .leading, spacing: 0){
                ForEach(0..<rows.count, id: \.self) { index in
                    let (label, value) = rows[index]
                    let isFirst = index == 0
                    let isLast = index == rows.count - 1
                    
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(label)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text(value)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .lineLimit(1)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        if !isLast {
                            Divider()
                                .padding(.leading, 16)
                        }
                    }
                    #if !os(tvOS)
                    .background(Color(.secondarySystemBackground))
                    #else
                    .background(Color.white.opacity(0.1))
                    #endif
                    .clipShape(
                        RoundedCorner(
                            radius: 20,
                            corners: {
                                var c: UIRectCorner = []
                                if isFirst { c.formUnion([.topLeft, .topRight]) }
                                if isLast { c.formUnion([.bottomLeft, .bottomRight]) }
                                return c
                            }()
                        )
                    )
                    .contentShape(Rectangle())
                    .contextMenu {
                        SwiftUI.Button {
                            #if !os(tvOS)
                            UIPasteboard.general.string = value
                            #endif
                        } label: {
                            Label(String(format: NSLocalizedString("Copy %@", comment: ""), label), systemImage: "doc.on.doc")
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Selective Corner Rounding Shape
private struct RoundedCorner: Shape {
    var radius: CGFloat
    var corners: UIRectCorner
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
