//
//  SettingsView.swift
//  AltStore
//
//  Created by Magesh K on 14/01/25.
//  Copyright © 2025 SideStore. All rights reserved.
//


import SwiftUI
import AltStoreCore


private final class DummyConformance: EnableJITContext
{
    private init(){} // non instantiatable
    var installedApp: AltStoreCore.InstalledApp?
    var error: (any Error)?
}


struct OperationsLoggingControlView: View {
    let TITLE = "Operations Logging"
    let BACKGROUND_COLOR = Color(.settingsBackground)
    
    var viewModel = OperationsLoggingControl()

    var body: some View {
        NavigationView {
            ZStack {
//                BACKGROUND_COLOR.ignoresSafeArea() // Force background to cover the entire screen
                VStack{
                    Group{}.padding(12)
                    
                    CustomList {
                        CustomSection(header: Text("Install Operations"))
                        {
                            CustomToggle("1. Authentication", isOn: Binding(
                                get: { self.viewModel.getFromDatabase(for: AuthenticationOperation.self) },
                                set: { value in
                                    self.viewModel.updateDatabase(for: AuthenticationOperation.self, value: value)
                                }
                            ))
                            
                            CustomToggle("2. VerifyAppPledge", isOn: Binding(
                                get: { self.viewModel.getFromDatabase(for: VerifyAppPledgeOperation.self) },
                                set: { value in
                                    self.viewModel.updateDatabase(for: VerifyAppPledgeOperation.self, value: value)
                                }
                            ))
                            
                            CustomToggle("3. DownloadApp", isOn: Binding(
                                get: { self.viewModel.getFromDatabase(for: DownloadAppOperation.self) },
                                set: { value in
                                    self.viewModel.updateDatabase(for: DownloadAppOperation.self, value: value)
                                }
                            ))
                            
                            CustomToggle("4. VerifyApp", isOn: Binding(
                                get: { self.viewModel.getFromDatabase(for: VerifyAppOperation.self) },
                                set: { value in
                                    self.viewModel.updateDatabase(for: VerifyAppOperation.self, value: value)
                                }
                            ))
                            
                            CustomToggle("5. RemoveAppExtensions", isOn: Binding(
                                get: { self.viewModel.getFromDatabase(for: RemoveAppExtensionsOperation.self) },
                                set: { value in
                                    self.viewModel.updateDatabase(for: RemoveAppExtensionsOperation.self, value: value)
                                }
                            ))
                            
                            CustomToggle("6. FetchAnisetteData", isOn: Binding(
                                get: { self.viewModel.getFromDatabase(for: FetchAnisetteDataOperation.self) },
                                set: { value in
                                    self.viewModel.updateDatabase(for: FetchAnisetteDataOperation.self, value: value)
                                }
                            ))
                            
                            CustomToggle("7. FetchProvisioningProfiles(I)", isOn: Binding(
                                get: { self.viewModel.getFromDatabase(for: FetchProvisioningProfilesInstallOperation.self) },
                                set: { value in
                                    self.viewModel.updateDatabase(for: FetchProvisioningProfilesInstallOperation.self, value: value)
                                }
                            ))
                            
                            CustomToggle("8. ResignApp", isOn: Binding(
                                get: { self.viewModel.getFromDatabase(for: ResignAppOperation.self) },
                                set: { value in
                                    self.viewModel.updateDatabase(for: ResignAppOperation.self, value: value)
                                }
                            ))
                            
                            CustomToggle("9. SendApp", isOn: Binding(
                                get: { self.viewModel.getFromDatabase(for: SendAppOperation.self) },
                                set: { value in
                                    self.viewModel.updateDatabase(for: SendAppOperation.self, value: value)
                                }
                            ))
                            
                            CustomToggle("10. InstallApp", isOn: Binding(
                                get: { self.viewModel.getFromDatabase(for: InstallAppOperation.self) },
                                set: { value in
                                    self.viewModel.updateDatabase(for: InstallAppOperation.self, value: value)
                                }
                            ))
                        }
                        
                        CustomSection(header: Text("Refresh Operations"))
                        {
                            CustomToggle("1. FetchProvisioningProfiles(R)", isOn: Binding(
                                get: { self.viewModel.getFromDatabase(for: FetchProvisioningProfilesRefreshOperation.self) },
                                set: { value in
                                    self.viewModel.updateDatabase(for: FetchProvisioningProfilesRefreshOperation.self, value: value)
                                }
                            ))

                            CustomToggle("2. RefreshApp", isOn: Binding(
                                get: { self.viewModel.getFromDatabase(for: RefreshAppOperation.self) },
                                set: { value in
                                    self.viewModel.updateDatabase(for: RefreshAppOperation.self, value: value)
                                }
                            ))
                        }
                        
                        CustomSection(header: Text("AppIDs related Operations"))
                        {
                            CustomToggle("1. FetchAppIDs", isOn: Binding(
                                get: { self.viewModel.getFromDatabase(for: FetchAppIDsOperation.self) },
                                set: { value in
                                    self.viewModel.updateDatabase(for: FetchAppIDsOperation.self, value: value)
                                }
                            ))
                        }
                        
                        CustomSection(header: Text("Sources related Operations"))
                        {
                            CustomToggle("1. FetchSource", isOn: Binding(
                                get: { self.viewModel.getFromDatabase(for: FetchSourceOperation.self) },
                                set: { value in
                                    self.viewModel.updateDatabase(for: FetchSourceOperation.self, value: value)
                                }
                            ))
                            
                            CustomToggle("2. UpdateKnownSources", isOn: Binding(
                                get: { self.viewModel.getFromDatabase(for: UpdateKnownSourcesOperation.self) },
                                set: { value in
                                    self.viewModel.updateDatabase(for: UpdateKnownSourcesOperation.self, value: value)
                                }
                            ))
                        }
                        
                        CustomSection(header: Text("Backup Operations"))
                        {
                            CustomToggle("1. BackupApp", isOn: Binding(
                                get: { self.viewModel.getFromDatabase(for: BackupAppOperation.self) },
                                set: { value in
                                    self.viewModel.updateDatabase(for: BackupAppOperation.self, value: value)
                                }
                            ))
                            
                            CustomToggle("2. RemoveAppBackup", isOn: Binding(
                                get: { self.viewModel.getFromDatabase(for: RemoveAppBackupOperation.self) },
                                set: { value in
                                    self.viewModel.updateDatabase(for: RemoveAppBackupOperation.self, value: value)
                                }
                            ))
                        }
                        
                        CustomSection(header: Text("Activate/Deactive Operations"))
                        {
                            CustomToggle("1. RemoveApp", isOn: Binding(
                                get: { self.viewModel.getFromDatabase(for: RemoveAppOperation.self) },
                                set: { value in
                                    self.viewModel.updateDatabase(for: RemoveAppOperation.self, value: value)
                                }
                            ))
                            CustomToggle("2. DeactivateApp", isOn: Binding(
                                get: { self.viewModel.getFromDatabase(for: DeactivateAppOperation.self) },
                                set: { value in
                                    self.viewModel.updateDatabase(for: DeactivateAppOperation.self, value: value)
                                }
                            ))
                        }
                        
                        CustomSection(header: Text("Background refresh Operations"))
                        {
                            CustomToggle("1. BackgroundRefreshApps", isOn: Binding(
                                get: { self.viewModel.getFromDatabase(for: BackgroundRefreshAppsOperation.self) },
                                set: { value in
                                    self.viewModel.updateDatabase(for: BackgroundRefreshAppsOperation.self, value: value)
                                }
                            ))
                        }
                        
                        CustomSection(header: Text("Enable JIT Operations"))
                        {
                            CustomToggle("1. EnableJIT", isOn: Binding(
                                get: { self.viewModel.getFromDatabase(for: EnableJITOperation<DummyConformance>.self) },
                                set: { value in
                                    self.viewModel.updateDatabase(for: EnableJITOperation<DummyConformance>.self, value: value)
                                }
                            ))
                        }
                        
                        CustomSection(header: Text("Patrons Operations"))
                        {
                            CustomToggle("1. UpdatePatrons", isOn: Binding(
                                get: { self.viewModel.getFromDatabase(for: UpdatePatronsOperation.self) },
                                set: { value in
                                    self.viewModel.updateDatabase(for: UpdatePatronsOperation.self, value: value)
                                }
                            ))
                        }
                        
                        CustomSection(header: Text("Cache Operations"))
                        {
                            CustomToggle("1. ClearAppCache", isOn: Binding(
                                get: { self.viewModel.getFromDatabase(for: ClearAppCacheOperation.self) },
                                set: { value in
                                    self.viewModel.updateDatabase(for: ClearAppCacheOperation.self, value: value)
                                }
                            ))
                        }
                        
                        CustomSection(header: Text("Misc Logging"))
                        {
                            CustomToggle("1. Anisette Internal Logging", isOn: Binding(
                                // enable anisette internal logging by default since it was already printing before
                                get: { OperationsLoggingControl.getUpdatedFromDatabase(
                                    for: ANISETTE_VERBOSITY.self, defaultVal: false
                                )},
                                set: { value in
                                    self.viewModel.updateDatabase(for: ANISETTE_VERBOSITY.self, value: value)
                                }
                            ))
                        }
                    }
                }
            }
            .navigationTitle(TITLE)
        }
        .ignoresSafeArea(edges: .all)
    }
    
    private func CustomList<Content: View>(@ViewBuilder content: () -> Content) -> some View {
//        ScrollView {
        List {
            content()
        }
//        .listStyle(.plain)
//        .listStyle(InsetGroupedListStyle()) // Or PlainListStyle for iOS 15
//        .background(Color.clear)
//        .background(Color(.settingsBackground))
//        .onAppear(perform: {
//            // cache the current background color
//            UITableView.appearance().backgroundColor = UIColor.red
//        })
//        .onDisappear(perform: {
//            // reset the background color to the cached value
//            UITableView.appearance().backgroundColor = UIColor.systemBackground
//        })
    }

    private func CustomSection<Content: View>(header: Text, @ViewBuilder content: () -> Content) -> some View {
        Section(header: header) {
            content()
        }
//        .listRowBackground(Color.clear)
    }
    
    private func CustomToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .padding(3)
//            .foregroundColor(.white)  // Ensures text color is always white
//            .font(.headline)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        OperationsLoggingControlView()
    }
}
