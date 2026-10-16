//
//  UserCustomizationsView.swift
//  SideStore
//
//  Created by Magesh K on 8/2/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import Minimuxer

private extension Color {
    static let settingsRowBackground = Color.white.opacity(0.15)
    static let settingsDivider = Color.white.opacity(0.15)
}

struct UserCustomizationsView: View {
    @State private var selectedBackend: GatewayBackend = selectedGatewayBackendCache
    @State private var isBackgroundServiceEnabled: Bool = UserDefaults.standard.isBackgroundServiceEnabled
    @State private var selectedBackgroundServiceMode: BackgroundServiceMode = UserDefaults.standard.backgroundServiceMode
    @State private var useOnDeviceAnisette: Bool = UserDefaults.standard.useOnDeviceAnisette
    @State private var showAnisetteRestartConfirmation: Bool = false
    @State private var customizeInfoPlist: Bool = UserDefaults.standard.customizeInfoPlist
    @State private var preferSheetForInfoPlistCustomization: Bool = UserDefaults.standard.preferSheetForInfoPlistCustomization
    @State private var customizeEntitlements: Bool = UserDefaults.standard.customizeEntitlements
    @State private var preferSheetForEntitlementsCustomization: Bool = UserDefaults.standard.preferSheetForEntitlementsCustomization
    @State private var customizeAppId: Bool = UserDefaults.standard.customizeAppId
    @State private var customizeAppIcon: Bool = UserDefaults.standard.customizeAppIcon
    @State private var customizeProvisioningProfile: Bool = UserDefaults.standard.customizeProvisioningProfile
    @State private var customizeAppExtensions: AppExtensionCustomization = UserDefaults.standard.customizeAppExtensions
    @State private var appImportSourceMode: AppImportSourceMode = UserDefaults.standard.appImportSourceMode
    @State private var isInstallConfirmationEnabled: Bool = UserDefaults.standard.isInstallConfirmationEnabled
    @State private var isClearCustomizationsOnUninstallEnabled: Bool = UserDefaults.standard.isClearCustomizationsOnUninstallEnabled
    @State private var isAutoLaunchAppAfterInstallEnabled: Bool = UserDefaults.standard.isAutoLaunchAppAfterInstallEnabled
    @State private var autoFixAppGroupIDs: Bool = UserDefaults.standard.autoFixAppGroupIDs
    @State private var preferResignedIPA: Bool = UserDefaults.standard.preferResignedIPA
    @State private var pendingPreferIPAOngoing: Bool = false
    @State private var showPreferIPAToggleAlert: Bool = false
    @State private var isExportResignedAppEnabled: Bool = UserDefaults.standard.isExportResignedAppEnabled
    @State private var enableEMPforWireguard: Bool = UserDefaults.standard.enableEMPforWireguard
    @State private var pendingEMPOption: Bool = false
    @State private var showEMPRestartConfirmation: Bool = false
    @State private var pendingBackendOption: GatewayBackend? = nil
    @State private var showBackendRestartConfirmation: Bool = false
    @State private var skipNonCopyableFiles: Bool = UserDefaults.standard.skipNonCopyableBackupFiles
    @State private var appVerificationDisabled: Bool = UserDefaults.standard.appVerificationDisabled
    @State private var isBundleIDVerificationEnabled: Bool = UserDefaults.standard.isBundleIDVerificationEnabled
    @State private var isiOSVersionVerificationEnabled: Bool = UserDefaults.standard.isiOSVersionVerificationEnabled
    @State private var isAppVersionVerificationEnabled: Bool = UserDefaults.standard.isAppVersionVerificationEnabled
    @State private var isChecksumVerificationEnabled: Bool = UserDefaults.standard.isChecksumVerificationEnabled
    @State private var isFileSizeVerificationEnabled: Bool = UserDefaults.standard.isFileSizeVerificationEnabled
    @State private var permissionCheckingDisabled: Bool = UserDefaults.standard.permissionCheckingDisabled
    @State private var isCellularRefreshEnabled: Bool = UserDefaults.standard.isCellularRefreshEnabled
    @State private var turnOnDataShortcutName: String = UserDefaults.standard.turnOnDataShortcutName
    @State private var turnOffDataShortcutName: String = UserDefaults.standard.turnOffDataShortcutName
    @State private var turnOnBaseDelayText: String = {
        let delay = CellularRefreshManager.shared.turnOnDataBaseDelayOverride ?? AppConstants.Shortcuts.defaultTurnOnDataBaseDelay
        return String(delay)
    }()
    @State private var turnOffBaseDelayText: String = {
        let delay = CellularRefreshManager.shared.turnOffDataBaseDelayOverride ?? AppConstants.Shortcuts.defaultTurnOffDataBaseDelay
        return String(delay)
    }()
    @State private var wireGuardExportURL: URL? = nil

    @State private var isFreeAccount: Bool = false

    struct EditDialogState: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let placeholder: String
        let keyboardType: UIKeyboardType
        let onSave: (String) -> Void
    }

    @State private var editDialog: EditDialogState? = nil
    @State private var editingValueText: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Section 0: APPEARANCE & THEMES
                VStack(alignment: .leading, spacing: 8) {
                    Text("APPEARANCE & THEMES")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.6))
                        .padding(.horizontal, 16)
                    
                    NavigationLink(destination: ThemePickerView()) {
                        HStack {
                            Text("Theme Manager")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(.white)
                            Spacer()
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color(uiColor: ThemeManager.shared.primaryColor))
                                    .frame(width: 14, height: 14)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(Color.white.opacity(0.4))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .background(Color.settingsRowBackground)
                    .cornerRadius(14)
                }

                // Section 1: ANISETTE
                VStack(alignment: .leading, spacing: 8) {
                    Text("ANISETTE")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.6))
                        .padding(.horizontal, 16)
                    
                    VStack(spacing: 0) {
                        toggleRow(
                            title: "On-Device Anisette",
                            subtitle: "Run ADI emulation directly on device instead of remote servers",
                            isOn: Binding(
                                get: { useOnDeviceAnisette },
                                set: { newValue in
                                    useOnDeviceAnisette = newValue
                                    showAnisetteRestartConfirmation = true
                                }
                            )
                        )
                        
                        divider
                        
                        NavigationLink(destination: AnisetteDataView()) {
                            HStack {
                                Text("Anisette Client Configuration")
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
                        
                        SwiftUI.Button(role: .destructive) {
                            presentResetAdiDialog()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Reset adi.pb")
                                        .font(.system(size: 17, weight: .bold))
                                        .foregroundColor(.red)
                                    Text("Clear local Anisette provisioning data from Keychain")
                                        .font(.system(size: 12, weight: .regular))
                                        .foregroundColor(Color.white.opacity(0.6))
                                }
                                Spacer()
                                Image(systemName: "trash")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.red)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .frame(minHeight: 50)
                        }
                    }
                    .background(Color.settingsRowBackground)
                    .cornerRadius(14)
                }

                // Section: SIDESIGN
                VStack(alignment: .leading, spacing: 8) {
                    Text("SIDESIGN")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.6))
                        .padding(.horizontal, 16)
                    
                    VStack(spacing: 0) {
                        NavigationLink(destination: SideSignConfigurationView()) {
                            HStack {
                                Text("SideSign Client Configuration")
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

                // Section 2: GENERAL
                generalSection

                // Section 2: APP VERIFICATION
                VStack(alignment: .leading, spacing: 8) {
                    Text("APP VERIFICATION")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.6))
                        .padding(.horizontal, 16)
                    
                    VStack(spacing: 0) {
                        toggleRow(title: "Disable All Verifications", isOn: Binding(
                            get: { appVerificationDisabled },
                            set: { newValue in
                                appVerificationDisabled = newValue
                                UserDefaults.standard.appVerificationDisabled = newValue
                            }
                        ))
                        
                        divider
                        
                        Group {
                            toggleRow(title: "Bundle Identifier Check", isOn: Binding(
                                get: { isBundleIDVerificationEnabled },
                                set: { newValue in
                                    isBundleIDVerificationEnabled = newValue
                                    UserDefaults.standard.isBundleIDVerificationEnabled = newValue
                                }
                            ))
                            
                            divider
                            
                            toggleRow(title: "iOS Version Check", isOn: Binding(
                                get: { isiOSVersionVerificationEnabled },
                                set: { newValue in
                                    isiOSVersionVerificationEnabled = newValue
                                    UserDefaults.standard.isiOSVersionVerificationEnabled = newValue
                                }
                            ))
                            
                            divider
                            
                            toggleRow(title: "App Version Check", isOn: Binding(
                                get: { isAppVersionVerificationEnabled },
                                set: { newValue in
                                    isAppVersionVerificationEnabled = newValue
                                    UserDefaults.standard.isAppVersionVerificationEnabled = newValue
                                }
                            ))
                            
                            divider
                            
                            toggleRow(title: "Checksum (SHA-256) Check", isOn: Binding(
                                get: { isChecksumVerificationEnabled },
                                set: { newValue in
                                    isChecksumVerificationEnabled = newValue
                                    UserDefaults.standard.isChecksumVerificationEnabled = newValue
                                }
                            ))
                            
                            divider
                            
                            toggleRow(title: "App File Size Check", isOn: Binding(
                                get: { isFileSizeVerificationEnabled },
                                set: { newValue in
                                    isFileSizeVerificationEnabled = newValue
                                    UserDefaults.standard.isFileSizeVerificationEnabled = newValue
                                }
                            ))
                            
                            divider
                            
                            toggleRow(title: "Permission Checks", isOn: Binding(
                                get: { !permissionCheckingDisabled },
                                set: { newValue in
                                    permissionCheckingDisabled = !newValue
                                    UserDefaults.standard.permissionCheckingDisabled = !newValue
                                }
                            ))
                        }
                        .disabled(appVerificationDisabled)
                        .opacity(appVerificationDisabled ? 0.5 : 1.0)
                    }
                    .background(Color.settingsRowBackground)
                    .cornerRadius(14)
                }

                // Section 3: EMPROXY & WIREGUARD
                VStack(alignment: .leading, spacing: 8) {
                    Text("EMPROXY & WIREGUARD")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.6))
                        .padding(.horizontal, 16)
                    
                    VStack(spacing: 0) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Export WireGuard Config")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("Exports SideStore.conf to import into WireGuard VPN app")
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(Color.white.opacity(0.6))
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            SwiftUI.Button(action: { exportWireGuardConfig() }) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 55, alignment: .center)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .frame(minHeight: 50)
                        
                        divider
                        
                        toggleRow(
                            title: "EMProxy (WireGuard) Server",
                            subtitle: "Restart required to apply changes",
                            isOn: Binding(
                                get: { enableEMPforWireguard },
                                set: { newValue in
                                    pendingEMPOption = newValue
                                    showEMPRestartConfirmation = true
                                }
                            )
                        )
                    }
                    .background(Color.settingsRowBackground)
                    .cornerRadius(14)
                }

                // Section 4: CELLULAR REFRESH
                cellularRefreshShortcutsSection

                // Section 5: MINIMUXER BACKEND
                VStack(alignment: .leading, spacing: 8) {
                    Text("MINIMUXER BACKEND")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.6))
                        .padding(.horizontal, 16)
                    
                    VStack(spacing: 0) {
                        ForEach(GatewayBackend.allCases, id: \.self) { backend in
                            SwiftUI.Button(action: {
                                if selectedBackend != backend {
                                    pendingBackendOption = backend
                                    showBackendRestartConfirmation = true
                                }
                            }) {
                                HStack {
                                    Text(backend.rawValue)
                                        .font(.system(size: 17, weight: .bold))
                                        .foregroundColor(.white)
                                    Spacer()
                                    if selectedBackend == backend {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundColor(Color(uiColor: ThemeManager.shared.primaryColor))
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                            }
                            if backend != GatewayBackend.allCases.last {
                                divider
                            }
                        }
                    }
                    .background(Color.settingsRowBackground)
                    .cornerRadius(14)
                }

                // Section 6: BACKGROUND SERVICE
                VStack(alignment: .leading, spacing: 8) {
                    Text("BACKGROUND SERVICE")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.6))
                        .padding(.horizontal, 16)
                    
                    VStack(spacing: 0) {
                        toggleRow(title: "Enable Background Keepalive", isOn: Binding(
                            get: { isBackgroundServiceEnabled },
                            set: { newValue in
                                isBackgroundServiceEnabled = newValue
                                BackgroundServiceManager.setEnabled(newValue)
                            }
                        ))
                        
                        divider
                        
                        ForEach(BackgroundServiceMode.allCases, id: \.self) { mode in
                            SwiftUI.Button(action: {
                                selectedBackgroundServiceMode = mode
                                BackgroundServiceManager.switchTo(mode: mode)
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(mode.displayName)
                                            .font(.system(size: 17, weight: .bold))
                                            .foregroundColor(isBackgroundServiceEnabled ? .white : Color.white.opacity(0.4))
                                        Text(mode.subtitle)
                                            .font(.system(size: 13))
                                            .foregroundColor(Color.white.opacity(isBackgroundServiceEnabled ? 0.6 : 0.3))
                                    }
                                    Spacer()
                                    if selectedBackgroundServiceMode == mode {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundColor(isBackgroundServiceEnabled ? Color(uiColor: ThemeManager.shared.primaryColor) : Color.white.opacity(0.3))
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                            }
                            .disabled(!isBackgroundServiceEnabled)
                            
                            if mode != BackgroundServiceMode.allCases.last {
                                divider
                            }
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
        .navigationTitle("User Customizations")
        #if !os(tvOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .alert("Restart Required", isPresented: $showAnisetteRestartConfirmation) {
            SwiftUI.Button("Restart Now", role: .destructive) {
                Task {
                    await AuthManager.shared.signOut(keepCertificate: true, keepAnisetteData: false)
                    UserDefaults.standard.useOnDeviceAnisette = useOnDeviceAnisette
                    exit(0)
                }
            }
            SwiftUI.Button("Cancel", role: .cancel) {
                useOnDeviceAnisette = UserDefaults.standard.useOnDeviceAnisette
            }
        } message: {
            Text("Changing Anisette config will invalidate your current provisioned Anisette data and you will be signed out.\n\nThis action will require a restart, do you want to proceed?")
        }
        .alert("Restart Required", isPresented: $showEMPRestartConfirmation) {
            SwiftUI.Button("Restart Now", role: .destructive) {
                enableEMPforWireguard = pendingEMPOption
                UserDefaults.standard.enableEMPforWireguard = pendingEMPOption
                exit(0)
            }
            SwiftUI.Button("Cancel", role: .cancel) {}
        } message: {
            Text("Changing the EMProxy setting requires restarting SideStore. If canceled, changes will not be saved.")
        }
        .alert("Restart Required", isPresented: $showBackendRestartConfirmation) {
            SwiftUI.Button("Restart Now", role: .destructive) {
                if let newBackend = pendingBackendOption {
                    selectedBackend = newBackend
                    selectedGatewayBackendCache = newBackend
                    UserDefaults.standard.minimuxerGatewayBackend = newBackend.rawValue
                    UserDefaults.standard.synchronize()
                    exit(0)
                }
            }
            SwiftUI.Button("Cancel", role: .cancel) {
                pendingBackendOption = nil
            }
        } message: {
            Text("Changing the Minimuxer backend requires restarting SideStore. If canceled, changes will not be saved.")
        }
        .alert(pendingPreferIPAOngoing ? "Prefer Resigned IPA" : "Prefer App Bundle", isPresented: $showPreferIPAToggleAlert) {
            SwiftUI.Button("Switch") {
                preferResignedIPA = pendingPreferIPAOngoing
                UserDefaults.standard.preferResignedIPA = pendingPreferIPAOngoing
            }
            SwiftUI.Button("Cancel", role: .cancel) {
                pendingPreferIPAOngoing = preferResignedIPA
            }
        } message: {
            if pendingPreferIPAOngoing {
                Text("Switching to Resigned IPA prioritizes install speed (~40% faster) by packaging an uncompressed IPA for fast transfer, but temporarily uses additional disk space during packaging.")
            } else {
                Text("Switching to App Bundle prioritizes storage efficiency by transferring the app bundle directly without packaging a temporary IPA, but transfer speeds will be noticeably slower.")
            }
        }
        .sheet(isPresented: Binding<Bool>(
            get: { wireGuardExportURL != nil },
            set: { if !$0 { wireGuardExportURL = nil } }
        )) {
            if let url = wireGuardExportURL {
                ActivityViewController(activityItems: [url])
            }
        }
        .alert(
            editDialog?.title ?? "",
            isPresented: Binding<Bool>(
                get: { editDialog != nil },
                set: { if !$0 { editDialog = nil } }
            )
        ) {
            TextField(editDialog?.placeholder ?? "", text: $editingValueText)
                #if !os(tvOS)
                .keyboardType(editDialog?.keyboardType ?? .default)
                #endif
            SwiftUI.Button("OK") {
                if let dialog = editDialog {
                    dialog.onSave(editingValueText)
                }
                editDialog = nil
            }
            SwiftUI.Button("Cancel", role: .cancel) {
                editDialog = nil
            }
        } message: {
            Text(editDialog?.message ?? "")
        }
        .task {
            isFreeAccount = (try? await AuthManager.shared.getAuthenticatedTeam())?.type == .free
        }
    }

    private func toggleRow(title: String, subtitle: String? = nil, isOn: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(Color.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(.green)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 50)
    }

    private func textFieldRow(
        title: String,
        subtitle: String? = nil,
        placeholder: String,
        value: String,
        unit: String? = nil,
        onTap: @escaping () -> Void
    ) -> some View {
        SwiftUI.Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(Color.white.opacity(0.6))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack {
                    Text(value.isEmpty ? placeholder : (unit != nil ? "\(value) \(unit!)" : value))
                        .font(.system(size: 15))
                        .foregroundColor(value.isEmpty ? Color.white.opacity(0.3) : .white)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.08))
                .cornerRadius(8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private var cellularRefreshShortcutsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CELLULAR REFRESH")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.6))
                .padding(.horizontal, 16)

            VStack(spacing: 0) {
                toggleRow(
                    title: "Cellular Refresh",
                    subtitle: "Automatically toggle cellular data via Shortcuts during refresh",
                    isOn: Binding(
                        get: { isCellularRefreshEnabled },
                        set: { newValue in
                            isCellularRefreshEnabled = newValue
                            CellularRefreshManager.shared.setEnabled(newValue)
                        }
                    )
                )

                divider

                textFieldRow(
                    title: "Turn On Cellular Shortcut",
                    subtitle: "Name of the shortcut in Apple Shortcuts app",
                    placeholder: AppConstants.Shortcuts.defaultTurnOnDataShortcutName,
                    value: turnOnDataShortcutName,
                    onTap: openTurnOnShortcutDialog
                )

                divider

                textFieldRow(
                    title: "Turn Off Cellular Shortcut",
                    subtitle: "Name of the shortcut in Apple Shortcuts app",
                    placeholder: AppConstants.Shortcuts.defaultTurnOffDataShortcutName,
                    value: turnOffDataShortcutName,
                    onTap: openTurnOffShortcutDialog
                )

                divider

                textFieldRow(
                    title: "Turn On Base Delay",
                    subtitle: "Base wait time after turning on data (seconds, ≥ 0)",
                    placeholder: String(AppConstants.Shortcuts.defaultTurnOnDataBaseDelay),
                    value: turnOnBaseDelayText,
                    unit: "s",
                    onTap: openTurnOnBaseDelayDialog
                )

                divider

                textFieldRow(
                    title: "Turn Off Base Delay",
                    subtitle: "Base wait time after turning off data (seconds, ≥ 0)",
                    placeholder: String(AppConstants.Shortcuts.defaultTurnOffDataBaseDelay),
                    value: turnOffBaseDelayText,
                    unit: "s",
                    onTap: openTurnOffBaseDelayDialog
                )

                divider

                SwiftUI.Button(action: resetCellularDefaults) {
                    HStack {
                        Spacer()
                        Text("Reset to Defaults")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.red)
                        Spacer()
                    }
                    .padding(.vertical, 12)
                }
            }
            .background(Color.settingsRowBackground)
            .cornerRadius(14)
        }
    }

    private func openTurnOnShortcutDialog() {
        editingValueText = turnOnDataShortcutName
        editDialog = EditDialogState(
            title: "Turn On Cellular Shortcut",
            message: "Name of the shortcut in Apple Shortcuts app",
            placeholder: AppConstants.Shortcuts.defaultTurnOnDataShortcutName,
            keyboardType: .default,
            onSave: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                let resolved = trimmed.isEmpty ? AppConstants.Shortcuts.defaultTurnOnDataShortcutName : trimmed
                let sanitized = CellularRefreshManager.sanitizeShortcutName(resolved, fallback: AppConstants.Shortcuts.defaultTurnOnDataShortcutName)
                turnOnDataShortcutName = sanitized
                CellularRefreshManager.shared.setTurnOnDataShortcutName(sanitized)
            }
        )
    }

    private func openTurnOffShortcutDialog() {
        editingValueText = turnOffDataShortcutName
        editDialog = EditDialogState(
            title: "Turn Off Cellular Shortcut",
            message: "Name of the shortcut in Apple Shortcuts app",
            placeholder: AppConstants.Shortcuts.defaultTurnOffDataShortcutName,
            keyboardType: .default,
            onSave: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                let resolved = trimmed.isEmpty ? AppConstants.Shortcuts.defaultTurnOffDataShortcutName : trimmed
                let sanitized = CellularRefreshManager.sanitizeShortcutName(resolved, fallback: AppConstants.Shortcuts.defaultTurnOffDataShortcutName)
                turnOffDataShortcutName = sanitized
                CellularRefreshManager.shared.setTurnOffDataShortcutName(sanitized)
            }
        )
    }

    private func openTurnOnBaseDelayDialog() {
        editingValueText = turnOnBaseDelayText
        editDialog = EditDialogState(
            title: "Turn On Base Delay",
            message: "Base wait time after turning on data (seconds, ≥ 0)",
            placeholder: String(AppConstants.Shortcuts.defaultTurnOnDataBaseDelay),
            keyboardType: .decimalPad,
            onSave: { newValue in
                let filtered = newValue.filter { "0123456789.".contains($0) }
                if let delay = Double(filtered), delay >= 0 {
                    turnOnBaseDelayText = String(delay)
                    CellularRefreshManager.shared.setTurnOnDataBaseDelayOverride(delay)
                } else {
                    turnOnBaseDelayText = String(AppConstants.Shortcuts.defaultTurnOnDataBaseDelay)
                    CellularRefreshManager.shared.setTurnOnDataBaseDelayOverride(nil)
                }
            }
        )
    }

    private func openTurnOffBaseDelayDialog() {
        editingValueText = turnOffBaseDelayText
        editDialog = EditDialogState(
            title: "Turn Off Base Delay",
            message: "Base wait time after turning off data (seconds, ≥ 0)",
            placeholder: String(AppConstants.Shortcuts.defaultTurnOffDataBaseDelay),
            keyboardType: .decimalPad,
            onSave: { newValue in
                let filtered = newValue.filter { "0123456789.".contains($0) }
                if let delay = Double(filtered), delay >= 0 {
                    turnOffBaseDelayText = String(delay)
                    CellularRefreshManager.shared.setTurnOffDataBaseDelayOverride(delay)
                } else {
                    turnOffBaseDelayText = String(AppConstants.Shortcuts.defaultTurnOffDataBaseDelay)
                    CellularRefreshManager.shared.setTurnOffDataBaseDelayOverride(nil)
                }
            }
        )
    }

    private func resetCellularDefaults() {
        CellularRefreshManager.shared.resetToDefaults()
        turnOnDataShortcutName = AppConstants.Shortcuts.defaultTurnOnDataShortcutName
        turnOffDataShortcutName = AppConstants.Shortcuts.defaultTurnOffDataShortcutName
        turnOnBaseDelayText = String(AppConstants.Shortcuts.defaultTurnOnDataBaseDelay)
        turnOffBaseDelayText = String(AppConstants.Shortcuts.defaultTurnOffDataBaseDelay)
    }

    private var customizeAppExtensionsBinding: Binding<AppExtensionCustomization> {
        Binding<AppExtensionCustomization>(
            get: { customizeAppExtensions },
            set: { newValue in
                customizeAppExtensions = newValue
                UserDefaults.standard.customizeAppExtensions = newValue
            }
        )
    }

    private var appImportSourceModeBinding: Binding<AppImportSourceMode> {
        Binding<AppImportSourceMode>(
            get: { appImportSourceMode },
            set: { newValue in
                appImportSourceMode = newValue
                UserDefaults.standard.appImportSourceMode = newValue
            }
        )
    }

    @ViewBuilder
    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("GENERAL")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.6))
                .padding(.horizontal, 16)
            
            VStack(spacing: 0) {
                toggleRow(title: "Customize Info.plist", isOn: Binding(
                    get: { customizeInfoPlist },
                    set: { newValue in
                        customizeInfoPlist = newValue
                        UserDefaults.standard.customizeInfoPlist = newValue
                    }
                ))
                
                divider
                
                toggleRow(title: "Customize AppID", isOn: Binding(
                    get: { customizeInfoPlist ? true : customizeAppId },
                    set: { newValue in
                        customizeAppId = newValue
                        UserDefaults.standard.customizeAppId = newValue
                    }
                ))
                .disabled(customizeInfoPlist)
                .opacity(customizeInfoPlist ? 0.4 : 1.0)
                
                divider
                
                HStack {
                    Text("Customize Extensions")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Picker("", selection: customizeAppExtensionsBinding) {
                        ForEach(AppExtensionCustomization.allCases) { (option: AppExtensionCustomization) in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Color.white.opacity(0.7))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(minHeight: 50)
                
                divider
                
                HStack {
                    Text("Default Import Mode")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Picker("", selection: appImportSourceModeBinding) {
                        ForEach(AppImportSourceMode.allCases) { (option: AppImportSourceMode) in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Color.white.opacity(0.7))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(minHeight: 50)
                
                divider

                toggleRow(
                    title: "Confirm App Installation",
                    subtitle: "Prompt for confirmation before installing or importing an app",
                    isOn: Binding(
                        get: { isInstallConfirmationEnabled },
                        set: { newValue in
                            isInstallConfirmationEnabled = newValue
                            UserDefaults.standard.isInstallConfirmationEnabled = newValue
                        }
                    )
                )
                
                divider

                toggleRow(
                    title: "Clear Customizations on Uninstall",
                    subtitle: "Reset assigned profiles, custom certificates, and metadata when an app is deleted",
                    isOn: Binding(
                        get: { isClearCustomizationsOnUninstallEnabled },
                        set: { newValue in
                            isClearCustomizationsOnUninstallEnabled = newValue
                            UserDefaults.standard.isClearCustomizationsOnUninstallEnabled = newValue
                        }
                    )
                )
                
                divider

                toggleRow(
                    title: "Auto-Launch App After Install",
                    subtitle: "Automatically open apps after installation completes",
                    isOn: Binding(
                        get: { isAutoLaunchAppAfterInstallEnabled },
                        set: { newValue in
                            isAutoLaunchAppAfterInstallEnabled = newValue
                            UserDefaults.standard.isAutoLaunchAppAfterInstallEnabled = newValue
                        }
                    )
                )
                
                divider
                
                toggleRow(title: "Customize Entitlements", isOn: Binding(
                    get: { customizeEntitlements },
                    set: { newValue in
                        customizeEntitlements = newValue
                        UserDefaults.standard.customizeEntitlements = newValue
                    }
                ))
                
                divider
                
                toggleRow(
                    title: "Auto-Fix AppGroup IDs",
                    subtitle: isFreeAccount ? "Required for free developer accounts" : "Automatically fix App Group casing mismatches",
                    isOn: Binding(
                        get: { isFreeAccount ? true : autoFixAppGroupIDs },
                        set: { newValue in
                            guard !isFreeAccount else { return }
                            autoFixAppGroupIDs = newValue
                            UserDefaults.standard.autoFixAppGroupIDs = newValue
                        }
                    )
                )
                .disabled(isFreeAccount)

                divider

                toggleRow(
                    title: "Customize App Icon",
                    subtitle: "Prompt to choose a custom icon before installing",
                    isOn: Binding(
                        get: { customizeAppIcon },
                        set: { newValue in
                            customizeAppIcon = newValue
                            UserDefaults.standard.customizeAppIcon = newValue
                        }
                    )
                )

                divider

                toggleRow(
                    title: "Customize Provisioning Profile",
                    subtitle: "Prompt to select a provisioning profile before installing",
                    isOn: Binding(
                        get: { customizeProvisioningProfile },
                        set: { newValue in
                            customizeProvisioningProfile = newValue
                            UserDefaults.standard.customizeProvisioningProfile = newValue
                        }
                    )
                )
                
                divider
                
                toggleRow(
                    title: "Prefer Resigned IPA",
                    subtitle: "Prefer IPA (speed) vs App (storage) efficiency",
                    isOn: Binding(
                        get: { preferResignedIPA },
                        set: { newValue in
                            pendingPreferIPAOngoing = newValue
                            showPreferIPAToggleAlert = true
                        }
                    )
                )
                
                divider
                
                toggleRow(title: "Export Resigned IPAs", isOn: Binding(
                    get: { isExportResignedAppEnabled },
                    set: { newValue in
                        isExportResignedAppEnabled = newValue
                        UserDefaults.standard.isExportResignedAppEnabled = newValue
                    }
                ))
                
                divider
                
                toggleRow(title: "Skip Uncopyable Backup Files", isOn: Binding(
                    get: { skipNonCopyableFiles },
                    set: { newValue in
                        skipNonCopyableFiles = newValue
                        UserDefaults.standard.skipNonCopyableBackupFiles = newValue
                    }
                ))
                
                divider
                
                toggleRow(
                    title: "Prefer Sheet for Info.plist",
                    subtitle: "Use sheet instead of dialog",
                    isOn: Binding(
                        get: { preferSheetForInfoPlistCustomization },
                        set: { newValue in
                            preferSheetForInfoPlistCustomization = newValue
                            UserDefaults.standard.preferSheetForInfoPlistCustomization = newValue
                        }
                    )
                )
                .disabled(!customizeInfoPlist)
                .opacity(!customizeInfoPlist ? 0.4 : 1.0)
                
                divider
                
                toggleRow(
                    title: "Prefer Sheet for Entitlements",
                    subtitle: "Use sheet instead of dialog",
                    isOn: Binding(
                        get: { preferSheetForEntitlementsCustomization },
                        set: { newValue in
                            preferSheetForEntitlementsCustomization = newValue
                            UserDefaults.standard.preferSheetForEntitlementsCustomization = newValue
                        }
                    )
                )
                .disabled(!customizeEntitlements)
                .opacity(!customizeEntitlements ? 0.4 : 1.0)
            }
            .background(Color.settingsRowBackground)
            .cornerRadius(14)
        }
    }



    private var divider: some View {
        Rectangle()
            .fill(Color.settingsDivider)
            .frame(height: 0.5)
            .padding(.horizontal, 16)
    }

    private func exportWireGuardConfig() {
        guard let url = Bundle.main.url(forResource: "SideStore", withExtension: "conf") else {
            if let top = UIApplication.shared.topViewController() {
                let toastView = ToastView(text: NSLocalizedString("SideStore.conf missing!", comment: ""), detailText: "Unable to locate SideStore.conf in bundle resources.")
                toastView.show(in: top)
            }
            return
        }
        wireGuardExportURL = url
    }

    private func presentResetAdiDialog() {
        guard let top = UIApplication.shared.topViewController() else { return }
        let alertController = UIAlertController(
            title: NSLocalizedString("Reset adi.pb", comment: ""),
            message: NSLocalizedString("This will sign you out of Apple ID in SideStore and clear the provisioned adi.pb data from your Keychain. Your active signing certificate will be preserved.", comment: ""),
            preferredStyle: .alert
        )
        let contentVC = ResetAdiAlertViewController()
        alertController.setValue(contentVC, forKey: "contentViewController")
        
        let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel, handler: nil)
        let resetAction = UIAlertAction(title: NSLocalizedString("Reset & Sign Out", comment: ""), style: .destructive) { _ in
            let keepHeaders = contentVC.isKeepHeadersChecked
            Task {
                await AuthManager.shared.signOut(keepCertificate: true, keepAnisetteData: false, keepAnisetteHeaders: keepHeaders)
                debugLog("Reset adi.pb (keepAnisetteHeaders: \(keepHeaders)) and signed out")
                if let topVC = UIApplication.shared.topViewController() {
                    let detail = keepHeaders
                        ? NSLocalizedString("Signed out of Apple ID. You can now sign back in with fresh provisioning.", comment: "")
                        : NSLocalizedString("Signed out of Apple ID. Reset adi.pb and header configs to defaults.", comment: "")
                    ToastView(
                        text: NSLocalizedString("Cleared adi.pb!", comment: ""),
                        detailText: detail
                    ).show(in: topVC)
                }
            }
        }
        
        alertController.addAction(cancelAction)
        alertController.addAction(resetAction)
        top.present(alertController, animated: true, completion: nil)
    }
}
