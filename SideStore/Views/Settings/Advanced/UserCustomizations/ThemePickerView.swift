//
//  ThemePickerView.swift
//  SideStore
//
//  Created by Magesh K on 9/8/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI

private extension Color {
    static let settingsRowBackground = Color.white.opacity(0.15)
    static let settingsDivider = Color.white.opacity(0.15)
}

struct ThemePickerView: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    @State private var selectedColor: Color = Color(uiColor: ThemeManager.shared.primaryColor)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Section 1: LIVE INTERFACE PREVIEW
                previewSection

                // Section 2: FULL SPECTRUM COLOR WHEEL & SELECTION
                #if !os(tvOS)
                colorWheelSection
                #endif

                // Section 3: PRESET THEME PALETTES
                presetsSection

                // Section 4: PRECISE COLOR METRICS
                metricsSection

                // Section 5: RESET BUTTON
                resetButtonSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .background(Color(uiColor: .settingsBackground).ignoresSafeArea())
        .navigationTitle("Theme Manager")
        #if !os(tvOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            selectedColor = Color(uiColor: themeManager.primaryColor)
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LIVE INTERFACE PREVIEW")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.6))
                .padding(.horizontal, 16)
            
            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SideStore")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                        Text("v0.6.0 • Installed")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.6))
                    }
                    Spacer()
                    
                    // Mock Pill Button
                    Text("7 DAYS")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(selectedColor)
                        .cornerRadius(16)
                }
                
                // Mock Progress Bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.2))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(selectedColor)
                            .frame(width: geo.size.width * 0.7)
                    }
                }
                .frame(height: 6)
                
                HStack {
                    Text("Active Theme Accent")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.7))
                    Spacer()
                    Circle()
                        .fill(selectedColor)
                        .frame(width: 14, height: 14)
                }
            }
            .padding(16)
            .background(Color.settingsRowBackground)
            .cornerRadius(14)
        }
    }

    #if !os(tvOS)
    private var colorWheelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("COLOR SELECTION & WHEEL")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.6))
                .padding(.horizontal, 16)

            VStack(spacing: 0) {
                HStack {
                    Text("Full Spectrum Color Wheel")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    ColorPicker("", selection: $selectedColor, supportsOpacity: false)
                        .labelsHidden()
                        .onChange(of: selectedColor) { newColor in
                            let uiColor = UIColor(newColor)
                            themeManager.primaryColor = uiColor
                        }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color.settingsRowBackground)
            .cornerRadius(14)
        }
    }
    #endif

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PRESET THEMES")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.6))
                .padding(.horizontal, 16)

            VStack(spacing: 0) {
                let presets = ThemePreset.presets
                ForEach(0..<presets.count, id: \.self) { index in
                    let preset = presets[index]
                    presetRow(preset: preset, isLast: index == presets.count - 1)
                }
            }
            .background(Color.settingsRowBackground)
            .cornerRadius(14)
        }
    }

    private func presetRow(preset: ThemePreset, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            SwiftUI.Button(action: {
                let uiColor = preset.color
                selectedColor = Color(uiColor: uiColor)
                themeManager.primaryColor = uiColor
            }) {
                HStack {
                    Circle()
                        .fill(Color(uiColor: preset.color))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        )

                    Text(preset.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.leading, 8)

                    Spacer()

                    Text(preset.hex)
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.6))

                    if isPresetSelected(preset) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(selectedColor)
                            .padding(.leading, 8)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

            if !isLast {
                Rectangle()
                    .fill(Color.settingsDivider)
                    .frame(height: 0.5)
                    .padding(.horizontal, 16)
            }
        }
    }

    private var metricsSection: some View {
        let uiColor = UIColor(selectedColor)
        let rgb = uiColor.rgbComponents
        let hsl = uiColor.hslComponents

        return VStack(alignment: .leading, spacing: 8) {
            Text("PRECISE COLOR METRICS")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.6))
                .padding(.horizontal, 16)

            VStack(spacing: 0) {
                metricRow(label: NSLocalizedString("HEX Code", comment: ""), value: uiColor.hexString)
                Rectangle().fill(Color.settingsDivider).frame(height: 0.5).padding(.horizontal, 16)
                metricRow(label: NSLocalizedString("RGB Format", comment: ""), value: "R: \(rgb.r)  G: \(rgb.g)  B: \(rgb.b)")
                Rectangle().fill(Color.settingsDivider).frame(height: 0.5).padding(.horizontal, 16)
                metricRow(label: NSLocalizedString("HSL Format", comment: ""), value: "H: \(hsl.h)°  S: \(hsl.s)%  L: \(hsl.l)%")
            }
            .background(Color.settingsRowBackground)
            .cornerRadius(14)
        }
    }

    private var resetButtonSection: some View {
        SwiftUI.Button(action: {
            themeManager.resetToDefault()
            selectedColor = Color(uiColor: themeManager.primaryColor)
        }) {
            HStack {
                Spacer()
                Text("Reset to SideStore Classic")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.red)
                Spacer()
            }
            .padding(.vertical, 14)
            .background(Color.settingsRowBackground)
            .cornerRadius(14)
        }
    }

    private func isPresetSelected(_ preset: ThemePreset) -> Bool {
        return themeManager.primaryColor.hexString.uppercased() == preset.hex.uppercased()
    }

    private func metricRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Color.white.opacity(0.8))
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
