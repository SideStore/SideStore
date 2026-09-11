//
//  ContentView.swift
//  SideBackup
//
//  Created by Magesh K on 2/7/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var state = AppState()
    
    var body: some View {
        ZStack {
            Color("Background")
                .ignoresSafeArea()
            
            VStack(spacing: 22) {
                if let error = state.bootCheckError {
                    // Hard boot failure — App Group not accessible
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.orange)
                    
                    Text(NSLocalizedString("SideBackup could not start", comment: ""))
                        .font(.title2.bold())
                        .foregroundColor(Color("Text"))
                        .multilineTextAlignment(.center)
                    
                    Text(error.localizedDescription)
                        .font(.callout)
                        .foregroundColor(Color("Text").opacity(0.75))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                    
                } else if let operation = state.currentOperation {
                    Text(operation == .backup ? NSLocalizedString("Backing up app data…", comment: "") : NSLocalizedString("Restoring app data…", comment: ""))
                        .font(.title2)
                        .foregroundColor(Color("Text"))
                        .multilineTextAlignment(.center)
                    
                    VStack(spacing: 10) {
                        ProgressView(value: state.progressFraction)
                            .progressViewStyle(LinearProgressViewStyle(tint: Color("Text")))
                            .frame(height: 8)
                            .clipShape(Capsule())
                        
                        if !state.progressText.isEmpty {
                            Text(state.progressText)
                                .font(.callout.monospacedDigit())
                                .foregroundColor(Color("Text").opacity(0.85))
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.horizontal, 16)
                } else {
                    Text(String(format: NSLocalizedString("%@ is inactive.", comment: ""),
                                Bundle.main.appName ?? NSLocalizedString("App", comment: "")))
                        .font(.title2)
                        .foregroundColor(Color("Text"))
                        .multilineTextAlignment(.center)
                    
                    Text(String(format: NSLocalizedString("Refresh %@ in SideStore to continue using it.", comment: ""),
                                Bundle.main.appName ?? NSLocalizedString("this app", comment: "")))
                        .font(.body)
                        .foregroundColor(Color("Text"))
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
        }
        .preferredColorScheme(.dark)
    }
}

