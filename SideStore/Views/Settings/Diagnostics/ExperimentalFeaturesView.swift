//
//  ExperimentalFeaturesView.swift
//  SideStore
//
//  Created by Magesh K on 8/2/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI

private extension Color {
    static let settingsRowBackground = Color.white.opacity(0.15)
    static let settingsDivider = Color.white.opacity(0.15)
}

struct ExperimentalFeaturesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Section 1: STANDALONE FEATURES
                VStack(alignment: .leading, spacing: 8) {
                    Text("STANDALONE FEATURES")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.6))
                        .padding(.horizontal, 16)
                    
                    VStack(spacing: 0) {
                        if #available(iOS 26.0, *) {
                            NavigationLink(destination: WirelessPairView()) {
                                HStack {
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
                            
                            divider
                        }
                        
                        NavigationLink(destination: CacheManagementView()) {
                            HStack {
                                Text("Cache Management")
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
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .background(Color(uiColor: .settingsBackground).ignoresSafeArea())
        .navigationTitle("Experimental Features")
        #if !os(tvOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.settingsDivider)
            .frame(height: 1)
            .padding(.leading, 16)
    }
}
