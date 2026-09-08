//
//  BonjourDiscoveryView.swift
//  SideStore
//
//  Created by Magesh K on 4/7/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import Network

// MARK: - Root View (Domains List)

// Entry point: discovers and lists browsable Bonjour domains.
// Tapping a domain navigates to its service types.
struct BonjourDiscoveryView: View {
    @StateObject private var viewModel = BonjourDiscoveryViewModel()
    @State private var selectedDomain: String? = nil
    @State private var isAutoRefreshEnabled = true
    @State private var refreshTask: Task<Void, Never>? = nil
    #if os(tvOS)
    @State private var showFilterDialog = false
    #endif
    
    var body: some View {
        ZStack {
            #if !os(tvOS)
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            #else
            Color.clear
                .ignoresSafeArea()
            #endif
            
            if viewModel.isSearching && viewModel.domains.isEmpty {
                ProgressView("Searching for domains…")
            } else if !viewModel.isSearching && viewModel.domains.isEmpty {
                emptyState
            } else {
                domainsList
            }
        }
        .navigationTitle("Discovery")
        #if !os(tvOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                SwiftUI.Button {
                    isAutoRefreshEnabled.toggle()
                    debugLog("[BonjourDiscoveryView] Auto-refresh toggled: \(isAutoRefreshEnabled ? "ON" : "OFF")")
                    if isAutoRefreshEnabled {
                        startAutoRefresh(triggerImmediateScan: true)
                    } else {
                        stopAutoRefresh()
                    }
                } label: {
                    Image(systemName: isAutoRefreshEnabled ? "antenna.radiowaves.left.and.right.circle.fill" : "antenna.radiowaves.left.and.right.circle")
                        .foregroundColor(isAutoRefreshEnabled ? .blue : .secondary)
                }
                
                #if !os(tvOS)
                Menu {
                    Menu {
                        SwiftUI.Button {
                            viewModel.domainGroupByFirstLetter = false
                        } label: {
                            Label("None", systemImage: !viewModel.domainGroupByFirstLetter ? "checkmark" : "")
                        }
                        SwiftUI.Button {
                            viewModel.domainGroupByFirstLetter = true
                        } label: {
                            Label("First Letter", systemImage: viewModel.domainGroupByFirstLetter ? "checkmark" : "")
                        }
                    } label: {
                        Label("Group By", systemImage: "rectangle.3.group")
                    }
                    
                    Menu {
                        SwiftUI.Button {
                            viewModel.domainSortAscending = true
                        } label: {
                            Label("Name (A to Z)", systemImage: viewModel.domainSortAscending ? "checkmark" : "")
                        }
                        SwiftUI.Button {
                            viewModel.domainSortAscending = false
                        } label: {
                            Label("Name (Z to A)", systemImage: !viewModel.domainSortAscending ? "checkmark" : "")
                        }
                    } label: {
                        Label("Sort By", systemImage: "arrow.up.arrow.down")
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                #else
                SwiftUI.Button {
                    showFilterDialog = true
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                .confirmationDialog("Filter & Sort", isPresented: $showFilterDialog) {
                    SwiftUI.Button(viewModel.domainGroupByFirstLetter ? "Group: None" : "Group: First Letter") {
                        viewModel.domainGroupByFirstLetter.toggle()
                    }
                    SwiftUI.Button(viewModel.domainSortAscending ? "Sort: Name (Z to A)" : "Sort: Name (A to Z)") {
                        viewModel.domainSortAscending.toggle()
                    }
                }
                #endif
            }
        }
        .onAppear {
            selectedDomain = nil
            debugLog("[BonjourDiscoveryView] onAppear (domainsCount=\(viewModel.domains.count), autoRefresh=\(isAutoRefreshEnabled))")
            startAutoRefresh()
        }
        .onDisappear {
            debugLog("[BonjourDiscoveryView] onDisappear")
            stopAutoRefresh()
        }
    }
    
    private func startAutoRefresh(triggerImmediateScan: Bool = false) {
        refreshTask?.cancel()
        refreshTask = viewModel.startDomainAutoRefresh(isAutoRefreshEnabled: isAutoRefreshEnabled, triggerImmediateScan: triggerImmediateScan)
    }
    
    private func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
        viewModel.stopDomainSearch()
    }
    
    private func performManualRefresh() async {
        await viewModel.performManualDomainRefresh(isAutoRefreshEnabled: isAutoRefreshEnabled) {
            startAutoRefresh(triggerImmediateScan: true)
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "network")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No Domains Found")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Make sure you're connected to a local network.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            SwiftUI.Button {
                startAutoRefresh()
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.medium))
            }
            .padding(.top, 4)
            
            VStack(spacing: 8) {
                Text("Ensure **Local Network Access** is provided otherwise this function may not work as intended since it is based on L N A...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Text("**Settings -> apps -> SideStore -> LocalNetworkAccess = toggle on**")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 12)
            .padding(.horizontal, 24)
        }
    }
    
    private var domainsList: some View {
        List {
            ForEach(viewModel.processedDomains) { section in
                Section(header: Text(section.title)) {
                    ForEach(section.items, id: \.self) { domain in
                        NavigationLink {
                            ServiceTypesView(domain: domain, viewModel: viewModel)
                        } label: {
                            HStack {
                                Image(systemName: "globe")
                                    .foregroundColor(.accentColor)
                                    .frame(width: 28)
                                Text(domain)
                                    .font(.body)
                            }
                        }
                        .id(domain)
                    }
                }
            }
        }
        #if !os(tvOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.grouped)
        #endif
        .refreshable {
            await performManualRefresh()
        }
    }
}


// MARK: - Service Types View

// Lists all service types discovered in a given domain.
// Tapping a type navigates to its instances.
struct ServiceTypesView: View {
    let domain: String
    @ObservedObject var viewModel: BonjourDiscoveryViewModel
    @State private var selectedType: String? = nil
    @State private var isAutoRefreshEnabled = true
    @State private var refreshTask: Task<Void, Never>? = nil
    #if os(tvOS)
    @State private var showGroupDialog = false
    @State private var showSortDialog = false
    #endif
    
    var body: some View {
        ZStack {
            #if !os(tvOS)
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            #else
            Color.clear
                .ignoresSafeArea()
            #endif
            
            if viewModel.isSearching && viewModel.serviceTypes.isEmpty {
                ProgressView("Searching for service types…")
            } else if !viewModel.isSearching && viewModel.serviceTypes.isEmpty {
                emptyState
            } else {
                serviceTypesList
            }
        }
        .navigationTitle(domain)
        #if !os(tvOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                SwiftUI.Button {
                    isAutoRefreshEnabled.toggle()
                    debugLog("[ServiceTypesView] Auto-refresh for '\(domain)' toggled: \(isAutoRefreshEnabled ? "ON" : "OFF")")
                    if isAutoRefreshEnabled {
                        startAutoRefresh(triggerImmediateScan: true)
                    } else {
                        stopAutoRefresh()
                    }
                } label: {
                    Image(systemName: isAutoRefreshEnabled ? "antenna.radiowaves.left.and.right.circle.fill" : "antenna.radiowaves.left.and.right.circle")
                        .foregroundColor(isAutoRefreshEnabled ? .blue : .secondary)
                }
                
                #if !os(tvOS)
                Menu {
                    Menu {
                        ForEach(ServiceTypeGroupOption.allCases, id: \.self) { opt in
                            SwiftUI.Button {
                                viewModel.serviceTypeGroupOption = opt
                            } label: {
                                Label(opt.rawValue, systemImage: viewModel.serviceTypeGroupOption == opt ? "checkmark" : "")
                            }
                        }
                    } label: {
                        Label("Group By", systemImage: "rectangle.3.group")
                    }
                    
                    Menu {
                        ForEach(ServiceTypeSortOption.allCases, id: \.self) { opt in
                            SwiftUI.Button {
                                viewModel.serviceTypeSortOption = opt
                            } label: {
                                Label(opt.rawValue, systemImage: viewModel.serviceTypeSortOption == opt ? "checkmark" : "")
                            }
                        }
                    } label: {
                        Label("Sort By", systemImage: "arrow.up.arrow.down")
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                #else
                SwiftUI.Button {
                    showGroupDialog = true
                } label: {
                    Image(systemName: "rectangle.3.group")
                }
                .confirmationDialog("Group By", isPresented: $showGroupDialog) {
                    ForEach(ServiceTypeGroupOption.allCases, id: \.self) { opt in
                        SwiftUI.Button(opt.rawValue) {
                            viewModel.serviceTypeGroupOption = opt
                        }
                    }
                }
                
                SwiftUI.Button {
                    showSortDialog = true
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .confirmationDialog("Sort By", isPresented: $showSortDialog) {
                    ForEach(ServiceTypeSortOption.allCases, id: \.self) { opt in
                        SwiftUI.Button(opt.rawValue) {
                            viewModel.serviceTypeSortOption = opt
                        }
                    }
                }
                #endif
            }
        }
        .onAppear {
            selectedType = nil
            debugLog("[ServiceTypesView] onAppear for '\(domain)' (serviceTypesCount=\(viewModel.serviceTypes.count), autoRefresh=\(isAutoRefreshEnabled))")
            startAutoRefresh()
        }
        .onDisappear {
            debugLog("[ServiceTypesView] onDisappear for '\(domain)'")
            stopAutoRefresh()
        }
    }
    
    private func startAutoRefresh(triggerImmediateScan: Bool = false) {
        refreshTask?.cancel()
        refreshTask = viewModel.startServiceTypeAutoRefresh(in: domain, isAutoRefreshEnabled: isAutoRefreshEnabled, triggerImmediateScan: triggerImmediateScan)
    }
    
    private func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
        viewModel.stopTypeSearch()
    }
    
    private func performManualRefresh() async {
        await viewModel.performManualServiceTypeRefresh(in: domain, isAutoRefreshEnabled: isAutoRefreshEnabled) {
            startAutoRefresh(triggerImmediateScan: true)
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No Services Found")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("No Bonjour services are currently advertised in this domain.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            SwiftUI.Button {
                startAutoRefresh()
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.medium))
            }
            .padding(.top, 4)
            
            VStack(spacing: 8) {
                Text("Ensure **Local Network Access** is provided otherwise this function may not work as intended since it is based on L N A...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Text("**Settings -> apps -> SideStore -> LocalNetworkAccess = toggle on**")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 12)
            .padding(.horizontal, 24)
        }
    }
    
    private var serviceTypesList: some View {
        List {
            ForEach(viewModel.processedServiceTypes) { section in
                Section(
                    header: Text(section.title),
                    footer: (section.id == viewModel.processedServiceTypes.last?.id) ? searchingFooter : nil
                ) {
                    ForEach(section.items) { typeInfo in
                        NavigationLink {
                            ServiceInstancesView(
                                serviceType: typeInfo.rawType,
                                domain: domain,
                                friendlyName: typeInfo.friendlyName,
                                viewModel: viewModel
                            )
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: typeInfo.friendlyName != nil ? "checkmark.seal.fill" : "questionmark.circle")
                                    .foregroundColor(typeInfo.friendlyName != nil ? .green : .orange)
                                    .frame(width: 28)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    if let friendly = typeInfo.friendlyName {
                                        Text(friendly)
                                            .font(.body)
                                            .lineLimit(1)
                                        Text(typeInfo.rawType)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    } else {
                                        Text(typeInfo.rawType)
                                            .font(.body)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .id(typeInfo.rawType)
                    }
                }
            }
        }
        #if !os(tvOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.grouped)
        #endif
        .refreshable {
            await performManualRefresh()
        }
    }
    
    @ViewBuilder
    private var searchingFooter: some View {
        if viewModel.isSearching {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Searching…")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}


// MARK: - Service Instances View

// Lists all discovered instances of a specific service type.
// Tapping an instance navigates to its resolved details.
struct ServiceInstancesView: View {
    let serviceType: String
    let domain: String
    let friendlyName: String?
    @ObservedObject var viewModel: BonjourDiscoveryViewModel
    @State private var selectedInstanceId: String? = nil
    @State private var isAutoRefreshEnabled = true
    @State private var refreshTask: Task<Void, Never>? = nil
    #if os(tvOS)
    @State private var showGroupDialog = false
    @State private var showSortDialog = false
    #endif
    
    var body: some View {
        ZStack {
            #if !os(tvOS)
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            #else
            Color.clear
                .ignoresSafeArea()
            #endif
            
            if viewModel.isSearching && viewModel.instances.isEmpty {
                ProgressView("Searching for instances…")
            } else if !viewModel.isSearching && viewModel.instances.isEmpty {
                emptyState
            } else {
                instancesList
            }
        }
        .navigationTitle(friendlyName ?? serviceType)
        #if !os(tvOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                SwiftUI.Button {
                    isAutoRefreshEnabled.toggle()
                    debugLog("[ServiceInstancesView] Auto-refresh for '\(serviceType)' toggled: \(isAutoRefreshEnabled ? "ON" : "OFF")")
                    if isAutoRefreshEnabled {
                        startAutoRefresh(triggerImmediateScan: true)
                    } else {
                        stopAutoRefresh()
                    }
                } label: {
                    Image(systemName: isAutoRefreshEnabled ? "antenna.radiowaves.left.and.right.circle.fill" : "antenna.radiowaves.left.and.right.circle")
                        .foregroundColor(isAutoRefreshEnabled ? .blue : .secondary)
                }
                
                #if !os(tvOS)
                Menu {
                    Menu {
                        ForEach(ServiceInstanceGroupOption.allCases, id: \.self) { opt in
                            SwiftUI.Button {
                                viewModel.instanceGroupOption = opt
                            } label: {
                                Label(opt.rawValue, systemImage: viewModel.instanceGroupOption == opt ? "checkmark" : "")
                            }
                        }
                    } label: {
                        Label("Group By", systemImage: "rectangle.3.group")
                    }
                    
                    Menu {
                        ForEach(ServiceInstanceSortOption.allCases, id: \.self) { opt in
                            SwiftUI.Button {
                                viewModel.instanceSortOption = opt
                            } label: {
                                Label(opt.rawValue, systemImage: viewModel.instanceSortOption == opt ? "checkmark" : "")
                            }
                        }
                    } label: {
                        Label("Sort By", systemImage: "arrow.up.arrow.down")
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                #else
                SwiftUI.Button {
                    showGroupDialog = true
                } label: {
                    Image(systemName: "rectangle.3.group")
                }
                .confirmationDialog("Group By", isPresented: $showGroupDialog) {
                    ForEach(ServiceInstanceGroupOption.allCases, id: \.self) { opt in
                        SwiftUI.Button(opt.rawValue) {
                            viewModel.instanceGroupOption = opt
                        }
                    }
                }
                
                SwiftUI.Button {
                    showSortDialog = true
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .confirmationDialog("Sort By", isPresented: $showSortDialog) {
                    ForEach(ServiceInstanceSortOption.allCases, id: \.self) { opt in
                        SwiftUI.Button(opt.rawValue) {
                            viewModel.instanceSortOption = opt
                        }
                    }
                }
                #endif
            }
        }
        .onAppear {
            selectedInstanceId = nil
            debugLog("[ServiceInstancesView] onAppear for '\(serviceType)' in '\(domain)' (instancesCount=\(viewModel.instances.count), autoRefresh=\(isAutoRefreshEnabled))")
            startAutoRefresh()
        }
        .onDisappear {
            debugLog("[ServiceInstancesView] onDisappear for '\(serviceType)' in '\(domain)'")
            stopAutoRefresh()
        }
    }
    
    private func startAutoRefresh(triggerImmediateScan: Bool = false) {
        refreshTask?.cancel()
        refreshTask = viewModel.startInstanceAutoRefresh(ofType: serviceType, in: domain, isAutoRefreshEnabled: isAutoRefreshEnabled, triggerImmediateScan: triggerImmediateScan)
    }
    
    private func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
        viewModel.stopInstanceSearch()
    }
    
    private func performManualRefresh() async {
        await viewModel.performManualInstanceRefresh(ofType: serviceType, in: domain, isAutoRefreshEnabled: isAutoRefreshEnabled) {
            startAutoRefresh(triggerImmediateScan: true)
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No Instances Found")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("No devices are currently advertising this service.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            SwiftUI.Button {
                startAutoRefresh()
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.medium))
            }
            .padding(.top, 4)
            
            VStack(spacing: 8) {
                Text("Ensure **Local Network Access** is provided otherwise this function may not work as intended since it is based on L N A...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Text("**Settings -> apps -> SideStore -> LocalNetworkAccess = toggle on**")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 12)
            .padding(.horizontal, 24)
        }
    }
    
    private var instancesList: some View {
        List {
            ForEach(viewModel.processedInstances) { section in
                Section(
                    header: Text(section.title),
                    footer: (section.id == viewModel.processedInstances.last?.id) ? searchingFooter : nil
                ) {
                    ForEach(section.items) { instance in
                        NavigationLink {
                            ServiceDetailView(service: instance, viewModel: viewModel, autoRefreshEnabled: isAutoRefreshEnabled)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "desktopcomputer")
                                    .foregroundColor(.accentColor)
                                    .frame(width: 28)
                                
                                Text(instance.name)
                                    .font(.body)
                                    .lineLimit(2)
                            }
                            .padding(.vertical, 2)
                        }
                        .id(instance.id)
                    }
                }
            }
        }
        #if !os(tvOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.grouped)
        #endif
        .refreshable {
            await performManualRefresh()
        }
    }
    
    @ViewBuilder
    private var searchingFooter: some View {
        if viewModel.isSearching {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Searching…")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}


// MARK: - Service Detail View

// Shows full resolved details of a service: hostname, port, IP addresses, TXT records.
struct ServiceDetailView: View {
    let service: DiscoveredService
    @ObservedObject var viewModel: BonjourDiscoveryViewModel
    let autoRefreshEnabled: Bool
    
    @State private var isAutoRefreshEnabled: Bool
    @State private var refreshTask: Task<Void, Never>? = nil
    @State private var showCopyConfirmation = false
    
    init(service: DiscoveredService, viewModel: BonjourDiscoveryViewModel, autoRefreshEnabled: Bool = true) {
        self.service = service
        self.viewModel = viewModel
        self.autoRefreshEnabled = autoRefreshEnabled
        self._isAutoRefreshEnabled = State(initialValue: autoRefreshEnabled)
    }
    
    var body: some View {
        ZStack {
            #if !os(tvOS)
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            #else
            Color.clear
                .ignoresSafeArea()
            #endif
            
            if let resolved = viewModel.resolvedService {
                resolvedContent(resolved)
            } else if let error = viewModel.resolveError {
                errorState(error)
            } else {
                loadingState
            }
        }
        .navigationTitle("Service Details")
        #if !os(tvOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                SwiftUI.Button {
                    isAutoRefreshEnabled.toggle()
                    debugLog("[ServiceDetailView] Auto-refresh for '\(service.name)' toggled: \(isAutoRefreshEnabled ? "ON" : "OFF")")
                    if isAutoRefreshEnabled {
                        startAutoRefresh(triggerImmediateScan: true)
                    } else {
                        stopAutoRefresh()
                    }
                } label: {
                    Image(systemName: isAutoRefreshEnabled ? "antenna.radiowaves.left.and.right.circle.fill" : "antenna.radiowaves.left.and.right.circle")
                        .foregroundColor(isAutoRefreshEnabled ? .blue : .secondary)
                }
                
                #if !os(tvOS)
                Menu {
                    SwiftUI.Button {
                        viewModel.sortAddressesV4First = true
                    } label: {
                        Label("IPv4 First", systemImage: viewModel.sortAddressesV4First ? "checkmark" : "")
                    }
                    SwiftUI.Button {
                        viewModel.sortAddressesV4First = false
                    } label: {
                        Label("IPv6 First", systemImage: !viewModel.sortAddressesV4First ? "checkmark" : "")
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .disabled(viewModel.resolvedService == nil)
                #else
                SwiftUI.Button {
                    viewModel.sortAddressesV4First.toggle()
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .disabled(viewModel.resolvedService == nil)
                #endif
            }
        }
        .onAppear {
            debugLog("[ServiceDetailView] onAppear: Resolving '\(service.name)' (\(service.type)) (autoRefresh=\(isAutoRefreshEnabled))")
            startAutoRefresh(triggerImmediateScan: true)
        }
        .onDisappear {
            debugLog("[ServiceDetailView] onDisappear: Stopped resolving '\(service.name)'")
            stopAutoRefresh()
        }
        .refreshable {
            await performManualRefresh()
        }
    }
    
    private func startAutoRefresh(triggerImmediateScan: Bool = false) {
        refreshTask?.cancel()
        refreshTask = viewModel.startDetailAutoRefresh(for: service, isAutoRefreshEnabled: isAutoRefreshEnabled, triggerImmediateScan: triggerImmediateScan)
    }
    
    private func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
        viewModel.stopResolving()
    }
    
    private func performManualRefresh() async {
        await viewModel.performManualDetailRefresh(for: service, isAutoRefreshEnabled: isAutoRefreshEnabled) {
            startAutoRefresh(triggerImmediateScan: true)
        }
    }
    
    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Resolving service…")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            Text("Resolution Failed")
                .font(.headline)
                .foregroundColor(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            SwiftUI.Button {
                viewModel.resolveService(service)
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.medium))
            }
            .padding(.top, 4)
        }
    }
    
    private func iconForInterfaceType(_ type: NWInterface.InterfaceType) -> String {
        switch type {
        case .wifi: return "wifi"
        case .loopback: return "arrow.triangle.2.circlepath"
        case .wiredEthernet: return "cable.connector"
        case .cellular: return "antenna.radiowaves.left.and.right"
        default: return "network"
        }
    }
    
    private func nameForInterfaceType(_ type: NWInterface.InterfaceType) -> String {
        switch type {
        case .wifi: return "Wi-Fi"
        case .loopback: return "Loopback"
        case .wiredEthernet: return "Ethernet"
        case .cellular: return "Cellular"
        default: return "\(type)"
        }
    }
    
    private func resolvedContent(_ resolved: ResolvedServiceInfo) -> some View {
        List {
            // Service Name Header
            Section {
                VStack(alignment: .center, spacing: 8) {
                    Image(systemName: "bonjour")
                        .font(.system(size: 36))
                        .foregroundColor(.accentColor)
                    
                    Text(resolved.name)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    
                    if let purpose = BonjourDiscoveryManager.friendlyName(for: resolved.type) {
                        Text(purpose)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                    }
                    
                    HStack(spacing: 8) {
                        Text(resolved.type.contains("_tcp") ? "TCP" : "UDP")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(resolved.type.contains("_tcp") ? Color.blue : Color.orange))
                        
                        Text(BonjourDiscoveryViewModel.portCategory(for: resolved.port))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            #if !os(tvOS)
                            .background(Capsule().fill(Color(.tertiarySystemFill)))
                            #else
                            .background(Capsule().fill(Color.white.opacity(0.15)))
                            #endif
                    }
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            
            // Connection Info (Hostname, Addresses, Port, Type, Domain)
            Section(header: Text("Connection")) {
                DetailRow(label: "Hostname", value: resolved.hostname, onCopy: copyWithFeedback)
                
                if !viewModel.resolvedAddressItems.isEmpty {
                    ForEach(viewModel.resolvedAddressItems) { item in
                        DetailRow(label: item.label, value: item.address, tag: item.interfaceTag, onCopy: copyWithFeedback)
                    }
                }
                
                DetailRow(label: "Port", value: "\(resolved.port)", onCopy: copyWithFeedback)
                DetailRow(label: "Type", value: resolved.type, onCopy: copyWithFeedback)
                DetailRow(label: "Domain", value: resolved.domain, onCopy: copyWithFeedback)
            }
            
            // Interfaces
            if !service.interfaces.isEmpty {
                Section(header: Text(String(format: NSLocalizedString("Discovered Interfaces (%d)", comment: ""), service.interfaces.count))) {
                    ForEach(service.interfaces, id: \.index) { iface in
                        HStack {
                            Image(systemName: iconForInterfaceType(iface.type))
                                .foregroundColor(.secondary)
                                .frame(width: 24)
                            Text(iface.name)
                                .font(.body)
                            Spacer()
                            Text(nameForInterfaceType(iface.type))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                        #if !os(tvOS)
                        .onTapGesture {
                            copyWithFeedback("\(iface.name) (\(nameForInterfaceType(iface.type)))")
                        }
                        #endif
                        .contextMenu {
                            SwiftUI.Button {
                                copyWithFeedback("\(iface.name) (\(nameForInterfaceType(iface.type)))")
                            } label: {
                                Label("Copy Interface", systemImage: "doc.on.doc")
                            }
                        }
                    }
                }
            }
            
            // Decoded Device / Software Information
            let modelRecord = resolved.txtRecords.first(where: { $0.key.lowercased() == "model" })?.value
            let decodedModel = modelRecord != nil ? BonjourDiscoveryViewModel.decodeDeviceModel(modelRecord!) : nil
            let osRecord = resolved.txtRecords.first(where: { $0.key.lowercased() == "osvers" || $0.key.lowercased() == "os" })?.value
            
            if decodedModel != nil || osRecord != nil {
                Section(header: Text("Device Info")) {
                    if let model = decodedModel {
                        DetailRow(label: "Model", value: "\(model) (\(modelRecord ?? ""))", onCopy: copyWithFeedback)
                    }
                    if let os = osRecord {
                        DetailRow(label: "OS Version", value: os, onCopy: copyWithFeedback)
                    }
                }
            }
            
            // TXT Records
            if !resolved.txtRecords.isEmpty {
                Section(header: Text(String(format: NSLocalizedString("TXT Record (%d)", comment: ""), resolved.txtRecords.count))) {
                    ForEach(resolved.txtRecords, id: \.key) { record in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.key)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.primary)
                            Text(record.value)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(nil)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .padding(.vertical, 2)
                        #if !os(tvOS)
                        .onTapGesture {
                            copyWithFeedback("\(record.key) = \(record.value)")
                        }
                        #endif
                        .contextMenu {
                            SwiftUI.Button {
                                copyWithFeedback("\(record.key) = \(record.value)")
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                        }
                    }
                }
            }
            
            // DNS-SD Raw Records
            let dnsRecords = viewModel.dnsSDRawRecords(resolved: resolved)
            Section(header: Text("DNS-SD Records")) {
                ForEach(dnsRecords, id: \.content) { rec in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(rec.recordType)
                            .font(.caption.weight(.bold))
                            .foregroundColor(.accentColor)
                        Text(rec.content)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(nil)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .padding(.vertical, 2)
                    #if !os(tvOS)
                    .onTapGesture {
                        copyWithFeedback(rec.content)
                    }
                    #endif
                    .contextMenu {
                        SwiftUI.Button {
                            copyWithFeedback(rec.content)
                        } label: {
                            Label(String(format: NSLocalizedString("Copy %@ Record", comment: ""), rec.recordType), systemImage: "doc.on.doc")
                        }
                    }
                }
            }
            
            // Quick Actions (Moved to Bottom)
            Section(header: Text("Quick Actions")) {
                let isWeb = resolved.type.contains("_http") || resolved.type.contains("_https") || resolved.port == 80 || resolved.port == 443 || resolved.port == 8080
                let isSSH = resolved.type.contains("_ssh") || resolved.port == 22
                let endpointStr = "\(resolved.hostname):\(resolved.port)"
                
                if isWeb {
                    let scheme = resolved.type.contains("_https") || resolved.port == 443 ? "https" : "http"
                    if let url = URL(string: "\(scheme)://\(resolved.hostname):\(resolved.port)") {
                        Link(destination: url) {
                            Label(String(format: NSLocalizedString("Open in Safari (%@://)", comment: ""), scheme), systemImage: "safari")
                        }
                    }
                }
                
                if isSSH {
                    SwiftUI.Button {
                        copyWithFeedback("ssh \(resolved.hostname) -p \(resolved.port)")
                    } label: {
                        Label("Copy SSH Command", systemImage: "terminal")
                    }
                }
                
                SwiftUI.Button {
                    copyWithFeedback(endpointStr)
                } label: {
                    Label("Copy Host:Port Endpoint", systemImage: "link")
                }
                
                SwiftUI.Button {
                    if let jsonStr = viewModel.copyAsJSON(service: service, resolved: resolved) {
                        copyWithFeedback(jsonStr)
                    }
                } label: {
                    Label("Copy Details as JSON", systemImage: "curlybraces")
                }
            }
        }
        #if !os(tvOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.grouped)
        #endif
        .refreshable {
            viewModel.resolveService(service)
        }
        .overlay(alignment: .bottom) {
            if showCopyConfirmation {
                copiedBanner
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
    
    private func copyWithFeedback(_ string: String) {
        #if !os(tvOS)
        UIPasteboard.general.string = string
        #endif
        withAnimation(.spring(response: 0.3)) {
            showCopyConfirmation = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.spring(response: 0.3)) {
                showCopyConfirmation = false
            }
        }
    }
    
    private var copiedBanner: some View {
        Text("Copied to Clipboard")
            .font(.subheadline.weight(.medium))
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color.accentColor)
            )
            .padding(.bottom, 16)
    }
}


// MARK: - Detail Row

// A simple key-value row with tap-to-copy and context menu
private struct DetailRow: View {
    let label: String
    let value: String
    var tag: String? = nil
    var onCopy: ((String) -> Void)? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let tag = tag, !tag.isEmpty {
                    Text(tag)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        #if !os(tvOS)
                        .background(Capsule().fill(Color(.tertiarySystemFill)))
                        #else
                        .background(Capsule().fill(Color.white.opacity(0.15)))
                        #endif
                }
            }
            Text(value)
                .font(.body)
                .lineLimit(nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.vertical, 2)
        #if !os(tvOS)
        .onTapGesture {
            onCopy?(value)
        }
        #endif
        .contextMenu {
            SwiftUI.Button {
                onCopy?(value)
            } label: {
                Label(String(format: NSLocalizedString("Copy %@", comment: ""), label), systemImage: "doc.on.doc")
            }
        }
    }
}
