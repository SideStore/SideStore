//
//  PairingFileManagementView.swift
//  SideStore
//
//  Created by Magesh K on 19/09/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI

private extension Color {
    static let settingsRowBackground = Color.white.opacity(0.15)
    static let settingsDivider = Color.white.opacity(0.15)
}

struct PairingFileManagementView: View {
    @State private var showingResetAlert = false
    @State private var showingResetCompletedAlert = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("PAIRING METHODS")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.6))
                        .padding(.horizontal, 16)
                    
                    VStack(spacing: 0) {
                        NavigationLink(destination: WirelessPairView()) {
                            HStack(spacing: 12) {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                                Text("Wireless Pairing")
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

                VStack(alignment: .leading, spacing: 8) {
                    Text("MANAGEMENT")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.6))
                        .padding(.horizontal, 16)
                    
                    VStack(spacing: 0) {
                        SwiftUI.Button(action: {
                            showingResetAlert = true
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "arrow.counterclockwise.circle")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.red)
                                Text("Reset Pairing File")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(.red)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 50)
                        }
                    }
                    .background(Color.settingsRowBackground)
                    .cornerRadius(14)
                    
                    Text("Resetting the pairing file removes the currently stored pairing credentials. You will need to re-pair or re-import a pairing file and restart SideStore.")
                        .font(.system(size: 12))
                        .foregroundColor(Color.white.opacity(0.5))
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .background(Color(uiColor: .settingsBackground).ignoresSafeArea())
        .navigationTitle("Pairing File Management")
        #if !os(tvOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .alert(isPresented: $showingResetAlert) {
            Alert(
                title: Text("Are you sure to reset the pairing file?"),
                message: Text("You can reset the pairing file when you cannot sideload apps or enable JIT. You need to restart SideStore."),
                primaryButton: .destructive(Text("Delete and Reset")) {
                    resetPairingFile()
                },
                secondaryButton: .cancel()
            )
        }
        .alert("Pairing File Reset", isPresented: $showingResetCompletedAlert) {
            SwiftUI.Button("OK", role: .cancel) { }
        } message: {
            Text("Please restart SideStore.")
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.settingsDivider)
            .frame(height: 1)
            .padding(.leading, 16)
    }

    private func resetPairingFile() {
        let filename = "ALTPairingFile.mobiledevicepairing"
        let fm = FileManager.default
        let documentsPath = fm.documentsDirectory.appendingPathComponent("/\(filename)")
        if fm.fileExists(atPath: documentsPath.path) {
            try? fm.removeItem(atPath: documentsPath.path)
        }
        UserDefaults.standard.isPairingReset = true
        showingResetCompletedAlert = true
    }
}
