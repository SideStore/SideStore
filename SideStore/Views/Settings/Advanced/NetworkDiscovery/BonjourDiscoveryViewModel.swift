//
//  BonjourDiscoveryViewModel.swift
//  SideStore
//
//  Created by Magesh K on 24/08/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import SwiftUI
import Combine
import Network

enum ServiceTypeSortOption: String, CaseIterable {
    case nameAscending = "Name (A to Z)"
    case nameDescending = "Name (Z to A)"
    case rawType = "Raw Type Identifier"
}

enum ServiceTypeGroupOption: String, CaseIterable {
    case none = "None"
    case protocolType = "Protocol (TCP / UDP)"
    case category = "Category (Recognized / Other)"
    case firstLetter = "First Letter"
}

enum ServiceInstanceSortOption: String, CaseIterable {
    case nameAscending = "Name (A to Z)"
    case nameDescending = "Name (Z to A)"
}

enum ServiceInstanceGroupOption: String, CaseIterable {
    case ipVersion = "IP Version (v4/v6)"
    case none = "None"
    case firstLetter = "First Letter"
}

struct DomainSection: Identifiable {
    let id: String
    let title: String
    let items: [String]
}

struct ServiceTypeSection: Identifiable {
    let id: String
    let title: String
    let items: [ServiceTypeInfo]
}

struct ServiceInstanceSection: Identifiable {
    let id: String
    let title: String
    let items: [DiscoveredService]
}

struct DiscoveredAddressItem: Identifiable, Hashable {
    var id: String { rawAddress }
    let rawAddress: String
    let address: String
    let label: String
    let interfaceTag: String?
}

@MainActor
final class BonjourDiscoveryViewModel: ObservableObject {
    let manager = BonjourDiscoveryManager.shared
    
    // Scoped Published State
    @Published var domains: [String] = []
    @Published var serviceTypes: [ServiceTypeInfo] = []
    @Published var instances: [DiscoveredService] = []
    @Published var resolvedService: ResolvedServiceInfo? = nil
    @Published var isSearching = false
    @Published var isResolving = false
    @Published var resolveError: String? = nil
    
    // Sort & Group Settings
    @Published var domainSortAscending = true
    @Published var domainGroupByFirstLetter = false
    
    @Published var serviceTypeSortOption: ServiceTypeSortOption = .nameAscending
    @Published var serviceTypeGroupOption: ServiceTypeGroupOption = .none
    
    @Published var instanceSortOption: ServiceInstanceSortOption = .nameAscending
    @Published var instanceGroupOption: ServiceInstanceGroupOption = .ipVersion
    
    @Published var sortAddressesV4First = true
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        self.domains = manager.domains
        self.serviceTypes = manager.serviceTypes
        self.instances = manager.instances
        self.resolvedService = manager.resolvedService
        self.isSearching = manager.isSearching
        self.isResolving = manager.isResolving
        self.resolveError = manager.resolveError
        
        manager.$domains
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .assign(to: &$domains)
            
        manager.$serviceTypes
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .assign(to: &$serviceTypes)
            
        manager.$instances
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .assign(to: &$instances)
            
        manager.$resolvedService
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .assign(to: &$resolvedService)
            
        manager.$isSearching
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .assign(to: &$isSearching)
            
        manager.$isResolving
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .assign(to: &$isResolving)
            
        manager.$resolveError
            .receive(on: DispatchQueue.main)
            .assign(to: &$resolveError)
    }
    
    // Processed Domains
    var processedDomains: [DomainSection] {
        let sorted = domains.sorted {
            domainSortAscending ? $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
                                : $0.localizedCaseInsensitiveCompare($1) == .orderedDescending
        }
        
        if domainGroupByFirstLetter {
            let grouped = Dictionary(grouping: sorted) { domain -> String in
                String(domain.prefix(1)).uppercased()
            }
            let keys = grouped.keys.sorted {
                domainSortAscending ? $0 < $1 : $0 > $1
            }
            return keys.map { DomainSection(id: "group_\($0)", title: "\($0) (\(grouped[$0]?.count ?? 0))", items: grouped[$0] ?? []) }
        } else {
            return [DomainSection(id: "all_domains", title: "Browsable Domains", items: sorted)]
        }
    }
    
    // Processed Service Types
    var processedServiceTypes: [ServiceTypeSection] {
        let sorted = serviceTypes.sorted { lhs, rhs in
            switch serviceTypeSortOption {
            case .nameAscending:
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            case .nameDescending:
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedDescending
            case .rawType:
                return lhs.rawType.localizedCaseInsensitiveCompare(rhs.rawType) == .orderedAscending
            }
        }
        
        switch serviceTypeGroupOption {
        case .none:
            let title = String(format: NSLocalizedString("%d Service(s) Found", comment: ""), serviceTypes.count)
            return [ServiceTypeSection(id: "all_types", title: title, items: sorted)]
            
        case .protocolType:
            let tcpItems = sorted.filter { $0.rawType.contains("_tcp") }
            let udpItems = sorted.filter { $0.rawType.contains("_udp") }
            let otherItems = sorted.filter { !$0.rawType.contains("_tcp") && !$0.rawType.contains("_udp") }
            
            var sections: [ServiceTypeSection] = []
            if !tcpItems.isEmpty {
                sections.append(ServiceTypeSection(id: "tcp_types", title: String(format: NSLocalizedString("TCP Services (%d)", comment: ""), tcpItems.count), items: tcpItems))
            }
            if !udpItems.isEmpty {
                sections.append(ServiceTypeSection(id: "udp_types", title: String(format: NSLocalizedString("UDP Services (%d)", comment: ""), udpItems.count), items: udpItems))
            }
            if !otherItems.isEmpty {
                sections.append(ServiceTypeSection(id: "other_types", title: String(format: NSLocalizedString("Other Services (%d)", comment: ""), otherItems.count), items: otherItems))
            }
            return sections
            
        case .category:
            let recognized = sorted.filter { $0.friendlyName != nil }
            let unknown = sorted.filter { $0.friendlyName == nil }
            
            var sections: [ServiceTypeSection] = []
            if !recognized.isEmpty {
                sections.append(ServiceTypeSection(id: "recognized_types", title: String(format: NSLocalizedString("Recognized Services (%d)", comment: ""), recognized.count), items: recognized))
            }
            if !unknown.isEmpty {
                sections.append(ServiceTypeSection(id: "unknown_types", title: String(format: NSLocalizedString("Other / Raw Services (%d)", comment: ""), unknown.count), items: unknown))
            }
            return sections
            
        case .firstLetter:
            let grouped = Dictionary(grouping: sorted) { item -> String in
                String(item.displayName.prefix(1)).uppercased()
            }
            let keys = grouped.keys.sorted {
                serviceTypeSortOption == .nameDescending ? $0 > $1 : $0 < $1
            }
            return keys.map { ServiceTypeSection(id: "group_\($0)", title: "\($0) (\(grouped[$0]?.count ?? 0))", items: grouped[$0] ?? []) }
        }
    }
    
    // Processed Service Instances
    var processedInstances: [ServiceInstanceSection] {
        let sorted = instances.sorted { lhs, rhs in
            switch instanceSortOption {
            case .nameAscending:
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .nameDescending:
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedDescending
            }
        }
        
        switch instanceGroupOption {
        case .none:
            let title = String(format: NSLocalizedString("%d Instance(s)", comment: ""), instances.count)
            return [ServiceInstanceSection(id: "all_instances", title: title, items: sorted)]
            
        case .ipVersion:
            let grouped = Dictionary(grouping: sorted) { item -> String in
                // 1. Direct hostPort endpoint check
                if case .hostPort(let host, _) = item.result.endpoint {
                    return "\(host)".contains(":") ? "IPv6" : "IPv4"
                }
                
                // 2. Check TXT records
                for record in item.txtRecords {
                    let k = record.key.lowercased()
                    if k.contains("addr") || k.contains("ip") {
                        if record.value.contains(":") { return "IPv6" }
                        if record.value.contains(".") { return "IPv4" }
                    }
                }
                
                // 3. Name check
                if item.name.contains(":") { return "IPv6" }
                
                // 4. Interface link heuristics from discovery
                if item.interfaces.contains(where: { $0.type == .loopback || $0.name.lowercased().contains("lo") || $0.name.lowercased().contains("anpi") }) {
                    return "IPv4"
                }
                if item.interfaces.count == 1 && (item.interfaces.first?.type == .wifi || item.interfaces.first?.name.lowercased().starts(with: "en") == true) {
                    return "IPv6"
                }
                
                return "IPv4"
            }
            let preferredOrder = ["IPv4", "IPv6", "IPv4 & IPv6"]
            let keys = grouped.keys.sorted { k1, k2 in
                let idx1 = preferredOrder.firstIndex(of: k1) ?? 99
                let idx2 = preferredOrder.firstIndex(of: k2) ?? 99
                if idx1 != idx2 {
                    return idx1 < idx2
                }
                return k1 < k2
            }
            let sections = keys.map { ServiceInstanceSection(id: "group_ip_\($0)", title: "\($0) (\(grouped[$0]?.count ?? 0))", items: grouped[$0] ?? []) }
            let summary = sections.map { "\($0.title): [\($0.items.map { $0.name }.joined(separator: ", "))]" }.joined(separator: " | ")
            debugLog("[BonjourDiscoveryViewModel] processedInstances (ipVersion): \(summary)")
            return sections
            
        case .firstLetter:
            let grouped = Dictionary(grouping: sorted) { item -> String in
                String(item.name.prefix(1)).uppercased()
            }
            let keys = grouped.keys.sorted {
                instanceSortOption == .nameDescending ? $0 > $1 : $0 < $1
            }
            return keys.map { ServiceInstanceSection(id: "group_\($0)", title: "\($0) (\(grouped[$0]?.count ?? 0))", items: grouped[$0] ?? []) }
        }
    }
    
    // Sorted & Parsed Addresses
    var sortedAddresses: [String] {
        guard let resolved = resolvedService else { return [] }
        return resolved.addresses.sorted { a, b in
            let aIsV6 = a.contains(":")
            let bIsV6 = b.contains(":")
            if aIsV6 != bIsV6 {
                return sortAddressesV4First ? !aIsV6 : aIsV6
            }
            return a.localizedStandardCompare(b) == .orderedAscending
        }
    }
    
    var resolvedAddressItems: [DiscoveredAddressItem] {
        sortedAddresses.map { raw in
            let tag: String? = {
                if let idx = raw.firstIndex(of: "%") {
                    return String(raw[raw.index(after: idx)...])
                }
                return nil
            }()
            let clean = raw.strippingInterfaceScope
            let label: String = {
                if !clean.contains(":") {
                    return "IPv4 Address"
                } else if raw.lowercased().hasPrefix("fe80:") || raw.contains("%") {
                    return "IPv6 Address (Link-Local)"
                } else if clean.lowercased().hasPrefix("fd") || clean.lowercased().hasPrefix("fc") {
                    return "IPv6 Address (Unique-Local)"
                } else {
                    return "IPv6 Address"
                }
            }()
            return DiscoveredAddressItem(
                rawAddress: raw,
                address: clean,
                label: label,
                interfaceTag: tag
            )
        }
    }
    
    // Search Actions
    func startDomainSearch(clearExisting: Bool = false) {
        manager.discoverDomains(clearExisting: clearExisting)
    }
    
    func startServiceTypeSearch(in domain: String, clearExisting: Bool = false) {
        manager.discoverServiceTypes(in: domain, clearExisting: clearExisting)
    }
    
    func startInstanceSearch(ofType type: String, in domain: String, clearExisting: Bool = false) {
        manager.discoverInstances(ofType: type, inDomain: domain, clearExisting: clearExisting)
    }
    
    func refreshDomains() {
        manager.discoverDomains(clearExisting: false)
    }
    
    func refreshServiceTypes(in domain: String) {
        manager.discoverServiceTypes(in: domain, clearExisting: false)
    }
    
    func refreshInstances(ofType type: String, in domain: String) {
        manager.discoverInstances(ofType: type, inDomain: domain, clearExisting: false)
    }
    
    func stopDomainSearch() {
        manager.stopDomainSearch()
    }
    
    func stopTypeSearch() {
        manager.stopTypeSearch()
    }
    
    func stopInstanceSearch() {
        manager.stopInstanceSearch()
    }
    
    // Auto-Refresh & Manual Refresh Orchestration
    func startDomainAutoRefresh(isAutoRefreshEnabled: Bool, triggerImmediateScan: Bool = false) -> Task<Void, Never>? {
        if domains.isEmpty {
            startDomainSearch(clearExisting: true)
        } else if triggerImmediateScan {
            refreshDomains()
        }
        guard isAutoRefreshEnabled else { return nil }
        return Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(AppConstants.Bonjour.periodicRefreshInterval * 1_000_000_000))
                guard let self = self, !Task.isCancelled else { break }
                self.refreshDomains()
            }
        }
    }
    
    func performManualDomainRefresh(isAutoRefreshEnabled: Bool, restartAutoRefresh: @escaping () -> Void) async {
        debugLog("[BonjourDiscoveryView] Manual refresh triggered (autoRefresh=\(isAutoRefreshEnabled))")
        if isAutoRefreshEnabled {
            restartAutoRefresh()
        } else {
            startDomainSearch(clearExisting: false)
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard let self = self, !isAutoRefreshEnabled else { return }
                self.stopDomainSearch()
            }
        }
        try? await Task.sleep(nanoseconds: 400_000_000)
    }
    
    func startServiceTypeAutoRefresh(in domain: String, isAutoRefreshEnabled: Bool, triggerImmediateScan: Bool = false) -> Task<Void, Never>? {
        if serviceTypes.isEmpty {
            startServiceTypeSearch(in: domain, clearExisting: true)
        } else if triggerImmediateScan {
            refreshServiceTypes(in: domain)
        }
        guard isAutoRefreshEnabled else { return nil }
        return Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(AppConstants.Bonjour.periodicRefreshInterval * 1_000_000_000))
                guard let self = self, !Task.isCancelled else { break }
                self.refreshServiceTypes(in: domain)
            }
        }
    }
    
    func performManualServiceTypeRefresh(in domain: String, isAutoRefreshEnabled: Bool, restartAutoRefresh: @escaping () -> Void) async {
        debugLog("[ServiceTypesView] Manual refresh triggered for '\(domain)' (autoRefresh=\(isAutoRefreshEnabled))")
        if isAutoRefreshEnabled {
            restartAutoRefresh()
        } else {
            startServiceTypeSearch(in: domain, clearExisting: false)
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard let self = self, !isAutoRefreshEnabled else { return }
                self.stopTypeSearch()
            }
        }
        try? await Task.sleep(nanoseconds: 400_000_000)
    }
    
    func startInstanceAutoRefresh(ofType type: String, in domain: String, isAutoRefreshEnabled: Bool, triggerImmediateScan: Bool = false) -> Task<Void, Never>? {
        let needsInitialSearch = instances.isEmpty || instances.first?.type != type
        if needsInitialSearch {
            startInstanceSearch(ofType: type, in: domain, clearExisting: true)
        } else if triggerImmediateScan {
            refreshInstances(ofType: type, in: domain)
        }
        guard isAutoRefreshEnabled else { return nil }
        return Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(AppConstants.Bonjour.periodicRefreshInterval * 1_000_000_000))
                guard let self = self, !Task.isCancelled else { break }
                self.refreshInstances(ofType: type, in: domain)
            }
        }
    }
    
    func performManualInstanceRefresh(ofType type: String, in domain: String, isAutoRefreshEnabled: Bool, restartAutoRefresh: @escaping () -> Void) async {
        debugLog("[ServiceInstancesView] Manual refresh triggered for '\(type)' in '\(domain)' (autoRefresh=\(isAutoRefreshEnabled))")
        if isAutoRefreshEnabled {
            restartAutoRefresh()
        } else {
            startInstanceSearch(ofType: type, in: domain, clearExisting: false)
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard let self = self, !isAutoRefreshEnabled else { return }
                self.stopInstanceSearch()
            }
        }
        try? await Task.sleep(nanoseconds: 400_000_000)
    }
    
    func startDetailAutoRefresh(for service: DiscoveredService, isAutoRefreshEnabled: Bool, triggerImmediateScan: Bool = false) -> Task<Void, Never>? {
        if resolvedService == nil || triggerImmediateScan {
            resolveService(service)
        }
        guard isAutoRefreshEnabled else { return nil }
        return Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(AppConstants.Bonjour.periodicRefreshInterval * 1_000_000_000))
                guard let self = self, !Task.isCancelled else { break }
                self.resolveService(service)
            }
        }
    }
    
    func performManualDetailRefresh(for service: DiscoveredService, isAutoRefreshEnabled: Bool, restartAutoRefresh: @escaping () -> Void) async {
        debugLog("[ServiceDetailView] Manual refresh triggered for '\(service.name)' (autoRefresh=\(isAutoRefreshEnabled))")
        if isAutoRefreshEnabled {
            restartAutoRefresh()
        } else {
            resolveService(service)
        }
        try? await Task.sleep(nanoseconds: 400_000_000)
    }
    
    func resolveService(_ service: DiscoveredService, clearExisting: Bool = false) {
        manager.resolveService(service, clearExisting: clearExisting)
    }
    
    func stopResolving() {
        manager.stopResolving()
    }
    
    func copyAllResolvedInfo() -> String? {
        guard let resolved = resolvedService else { return nil }
        
        var lines: [String] = []
        lines.append("Service: \(resolved.name)")
        lines.append("Type: \(resolved.type)")
        lines.append("Domain: \(resolved.domain)")
        lines.append("Hostname: \(resolved.hostname)")
        lines.append("Port: \(resolved.port)")
        lines.append("")
        
        if !resolved.addresses.isEmpty {
            lines.append("Addresses:")
            for addr in sortedAddresses {
                lines.append("  \(addr)")
            }
            lines.append("")
        }
        
        if !resolved.txtRecords.isEmpty {
            lines.append("TXT Records:")
            for record in resolved.txtRecords {
                lines.append("  \(record.key) = \(record.value)")
            }
        }
        
        let text = lines.joined(separator: "\n")
        #if !os(tvOS)
        UIPasteboard.general.string = text
        #endif
        return text
    }
    
    static func portCategory(for port: UInt16) -> String {
        switch port {
        case 0...1023:
            return "Well-Known Port"
        case 1024...49151:
            return "Registered Port"
        default:
            return "Dynamic / Ephemeral Port"
        }
    }
    
    static func decodeDeviceModel(_ model: String) -> String? {
        let m = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let models: [String: String] = [
            "iPhone14,2": "iPhone 13 Pro",
            "iPhone14,3": "iPhone 13 Pro Max",
            "iPhone14,4": "iPhone 13 mini",
            "iPhone14,5": "iPhone 13",
            "iPhone14,7": "iPhone 14",
            "iPhone14,8": "iPhone 14 Plus",
            "iPhone15,2": "iPhone 14 Pro",
            "iPhone15,3": "iPhone 14 Pro Max",
            "iPhone15,4": "iPhone 15",
            "iPhone15,5": "iPhone 15 Plus",
            "iPhone16,1": "iPhone 15 Pro",
            "iPhone16,2": "iPhone 15 Pro Max",
            "iPhone17,1": "iPhone 16 Pro",
            "iPhone17,2": "iPhone 16 Pro Max",
            "iPhone17,3": "iPhone 16",
            "iPhone17,4": "iPhone 16 Plus",
            "AppleTV5,3": "Apple TV HD",
            "AppleTV6,2": "Apple TV 4K (1st gen)",
            "AppleTV11,1": "Apple TV 4K (2nd gen)",
            "AppleTV14,1": "Apple TV 4K (3rd gen)",
            "MacBookPro18,1": "MacBook Pro (16-inch, 2021)",
            "MacBookPro18,2": "MacBook Pro (16-inch, 2021)",
            "MacBookPro18,3": "MacBook Pro (14-inch, 2021)",
            "Mac14,2": "MacBook Air (M2, 2022)",
            "Mac14,7": "MacBook Pro (13-inch, M2, 2022)",
            "Mac14,6": "MacBook Pro (16-inch, 2023)",
            "Mac14,5": "MacBook Pro (14-inch, 2023)",
            "Mac14,3": "Mac mini (2023)",
            "Mac14,12": "Mac mini (M2 Pro, 2023)",
            "Mac14,15": "MacBook Air (15-inch, M2, 2023)",
            "Mac15,3": "MacBook Pro (14-inch, Nov 2023)",
            "Mac15,6": "MacBook Pro (14-inch, Nov 2023)",
            "Mac15,8": "MacBook Pro (16-inch, Nov 2023)"
        ]
        return models[m]
    }
    
    func copyAsJSON(service: DiscoveredService, resolved: ResolvedServiceInfo) -> String? {
        var dict: [String: Any] = [
            "name": resolved.name,
            "type": resolved.type,
            "domain": resolved.domain,
            "hostname": resolved.hostname,
            "port": resolved.port,
            "addresses": resolved.addresses,
            "interfaces": service.interfaces.map { $0.name }
        ]
        var txtDict: [String: String] = [:]
        for record in resolved.txtRecords {
            txtDict[record.key] = record.value
        }
        dict["txtRecords"] = txtDict
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
           let str = String(data: data, encoding: .utf8) {
            #if !os(tvOS)
            UIPasteboard.general.string = str
            #endif
            return str
        }
        return nil
    }
    
    func dnsSDRawRecords(resolved: ResolvedServiceInfo) -> [(recordType: String, content: String)] {
        var records: [(recordType: String, content: String)] = []
        let cleanType = resolved.type.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let cleanDomain = resolved.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let serviceDomain = "\(cleanType).\(cleanDomain)."
        let fqdn = "\(resolved.name).\(serviceDomain)"
        let hostFqdn = resolved.hostname.hasSuffix(".") ? resolved.hostname : (resolved.hostname.contains(":") || resolved.hostname.filter({ $0 == "." }).count == 3 ? resolved.hostname : "\(resolved.hostname).")
        
        records.append(("PTR", "\(serviceDomain) 120 IN PTR \(fqdn)"))
        records.append(("SRV", "\(fqdn) 120 IN SRV 0 0 \(resolved.port) \(hostFqdn)"))
        
        for addr in resolved.addresses {
            if addr.contains(":") {
                records.append(("AAAA", "\(hostFqdn) 120 IN AAAA \(addr)"))
            } else {
                records.append(("A", "\(hostFqdn) 120 IN A \(addr)"))
            }
        }
        
        if !resolved.txtRecords.isEmpty {
            let txtString = resolved.txtRecords.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
            records.append(("TXT", "\(fqdn) 120 IN TXT \"\(txtString)\""))
        }
        
        return records
    }
    
    static func nameForInterfaceType(_ type: NWInterface.InterfaceType) -> String {
        switch type {
        case .wifi:             return "Wi-Fi"
        case .loopback:         return "Loopback"
        case .wiredEthernet:    return "Ethernet"
        case .cellular:         return "Cellular"
        default:                return "\(type)"
        }
    }
    
    func logDetails(for service: DiscoveredService, trigger: String, resolved: ResolvedServiceInfo? = nil) {
        let activeResolved = resolved ?? self.resolvedService
        let isLocal = service.interfaces.contains { $0.type == .loopback }
        let localityStr = isLocal ? "LOCAL DEVICE (This iPhone / iPad — lo0 loopback present)" : "REMOTE DEVICE (Network peer — external only)"
        let friendlyType = BonjourDiscoveryManager.friendlyName(for: service.type) ?? "Unknown Type"
        
        var lines: [String] = []
        lines.append("===================================================")
        lines.append("[ServiceDetailView] [\(trigger)] Details: '\(service.name)'")
        lines.append("===================================================")
        lines.append("• Name:       \(service.name)")
        lines.append("• Type:       \(service.type) (\(friendlyType))")
        lines.append("• Domain:     \(service.domain)")
        lines.append("• Locality:   \(localityStr)")
        
        let ifaceDesc = service.interfaces.map { "\($0.name) (idx: \($0.index), type: \(Self.nameForInterfaceType($0.type)))" }.joined(separator: ", ")
        lines.append("• Interfaces (\(service.interfaces.count)): [\(ifaceDesc.isEmpty ? "none" : ifaceDesc)]")
        
        if service.txtRecords.isEmpty {
            lines.append("• Browse TXT: (none)")
        } else {
            lines.append("• Browse TXT (\(service.txtRecords.count)):")
            for record in service.txtRecords {
                lines.append("    - \(record.key) = \(record.value)")
            }
        }
        
        if let res = activeResolved {
            lines.append("---------------------------------------------------")
            lines.append("• Resolution: RESOLVED")
            lines.append("• Hostname:   \(res.hostname)")
            lines.append("• Port:       \(res.port) (\(Self.portCategory(for: res.port)))")
            lines.append("• Addresses (\(res.addresses.count)):")
            if res.addresses.isEmpty {
                lines.append("    (No IP addresses resolved)")
            } else {
                for addr in res.addresses {
                    let isV6 = addr.contains(":")
                    let tag: String
                    if isV6 {
                        if addr.lowercased().hasPrefix("fe80:") {
                            tag = "IPv6 Link-Local"
                        } else if addr == "::1" {
                            tag = "IPv6 Loopback"
                        } else {
                            tag = "IPv6 Global/ULA"
                        }
                    } else {
                        if addr.hasPrefix("127.") {
                            tag = "IPv4 Loopback"
                        } else {
                            tag = "IPv4"
                        }
                    }
                    lines.append("    - \(addr) [\(tag)]")
                }
            }
            
            if res.txtRecords.isEmpty {
                lines.append("• Resolved TXT: (none)")
            } else {
                lines.append("• Resolved TXT (\(res.txtRecords.count)):")
                for record in res.txtRecords {
                    lines.append("    - \(record.key) = \(record.value)")
                }
            }
            
            let modelRecord = res.txtRecords.first(where: { $0.key.lowercased() == "model" })?.value
            let decodedModel = modelRecord != nil ? Self.decodeDeviceModel(modelRecord!) : nil
            let osRecord = res.txtRecords.first(where: { $0.key.lowercased() == "osvers" || $0.key.lowercased() == "os" })?.value
            if decodedModel != nil || osRecord != nil {
                lines.append("• Device Info:")
                if let model = decodedModel {
                    lines.append("    - Model: \(model) (\(modelRecord ?? ""))")
                }
                if let os = osRecord {
                    lines.append("    - OS:    \(os)")
                }
            }
            
            lines.append("• Usable Endpoints:")
            lines.append("    - Host:Port: \(res.hostname):\(res.port)")
            for addr in res.addresses {
                if addr.contains(":") {
                    lines.append("    - IPv6:      [\(addr)]:\(res.port)")
                } else {
                    lines.append("    - IPv4:      \(addr):\(res.port)")
                }
            }
        } else if let error = self.resolveError {
            lines.append("---------------------------------------------------")
            lines.append("• Resolution: FAILED (\(error))")
        } else {
            lines.append("---------------------------------------------------")
            lines.append("• Resolution: RESOLVING (awaiting network response)...")
        }
        lines.append("===================================================")
        
        let fullOutput = lines.joined(separator: "\n")
        verboseLog(fullOutput)
    }
}
