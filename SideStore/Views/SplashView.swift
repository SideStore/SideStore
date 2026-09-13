//
//  SplashView.swift
//  SideStore
//
//  Created by Magesh K on 14/8/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI

@MainActor
final class SplashViewModel: ObservableObject {
    @Published var status: String = ""

    func updateStatus(_ text: String) {
        status = text
    }
}

struct SplashView: View {
    @ObservedObject var viewModel: SplashViewModel
    @State private var isBreathing = false

    var body: some View {
        ZStack {
            #if !os(tvOS)
                Color(.systemBackground)
                    .ignoresSafeArea()
            #else
                Color.black
                    .ignoresSafeArea()
            #endif

            VStack(spacing: 16) {
                Spacer()

                Image(uiImage: UIImage(named: "AppIcon") ?? UIImage(named: "AppIcon60x60") ?? UIImage(systemName: "app.fill")!)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 104, height: 104)
                    .cornerRadius(24)
                    .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
                    .scaleEffect(isBreathing ? 1.05 : 1.0)
                    .animation(
                        .easeInOut(duration: 1.8).repeatForever(autoreverses: true),
                        value: isBreathing
                    )
                    .onAppear {
                        isBreathing = true
                    }

                Text(Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String ?? "SideStore")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.primary)

                Spacer()

                if !viewModel.status.isEmpty {
                    Text(viewModel.status)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .transition(.opacity)
                }
            }
            .padding(.bottom, 48)
        }
    }
}
