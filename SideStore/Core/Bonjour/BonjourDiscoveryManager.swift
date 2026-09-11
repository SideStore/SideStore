//
//  BonjourDiscoveryManager.swift
//  SideStore
//
//  Created by Magesh K on 4/7/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import Network
import Combine
import Minimuxer

struct ServiceTypeInfo: Identifiable, Hashable {
    var id: String { rawType }
    let rawType: String
    let friendlyName: String?
    
    var displayName: String {
        friendlyName ?? rawType
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(rawType)
    }
    
    static func == (lhs: ServiceTypeInfo, rhs: ServiceTypeInfo) -> Bool {
        lhs.rawType == rhs.rawType
    }
}

struct DiscoveredService: Identifiable, Hashable {
    var id: String { "\(domain)/\(type)/\(name)" }
    let name: String
    let type: String
    let domain: String
    let result: NWBrowser.Result
    let txtRecords: [(key: String, value: String)]
    let interfaces: [NWInterface]
    
    init(name: String, type: String, domain: String, result: NWBrowser.Result, txtRecords: [(key: String, value: String)] = [], interfaces: [NWInterface] = []) {
        self.name = name
        self.type = type
        self.domain = domain
        self.result = result
        self.txtRecords = txtRecords
        self.interfaces = interfaces
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: DiscoveredService, rhs: DiscoveredService) -> Bool {
        lhs.id == rhs.id
    }
}

struct ResolvedServiceInfo: Identifiable, Equatable {
    var id: String { "\(domain)/\(type)/\(name)/\(hostname):\(port)" }
    let name: String
    let type: String
    let domain: String
    let hostname: String
    let port: UInt16
    let addresses: [String]
    let txtRecords: [(key: String, value: String)]
    
    static func == (lhs: ResolvedServiceInfo, rhs: ResolvedServiceInfo) -> Bool {
        lhs.name == rhs.name &&
        lhs.type == rhs.type &&
        lhs.domain == rhs.domain &&
        lhs.hostname == rhs.hostname &&
        lhs.port == rhs.port &&
        lhs.addresses == rhs.addresses &&
        lhs.txtRecords.count == rhs.txtRecords.count &&
        zip(lhs.txtRecords, rhs.txtRecords).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
    }
}

final class BonjourDiscoveryManager: NSObject, ObservableObject, NetServiceDelegate, NetServiceBrowserDelegate {
    static let shared = BonjourDiscoveryManager()
    
    // Published State
    @Published var domains: [String] = []
    @Published var serviceTypes: [ServiceTypeInfo] = []
    @Published var instances: [DiscoveredService] = []
    @Published var resolvedService: ResolvedServiceInfo? = nil
    @Published var isSearching = false
    @Published var isResolving = false
    @Published var resolveError: String? = nil
    
    // Private State
    private var domainBrowser: NetServiceBrowser?
    private var typeBrowser: NetServiceBrowser?
    private var fallbackTypeBrowsers: [NWBrowser] = []
    private var instanceBrowsers: [NWBrowser] = []
    private var activeConnection: NWConnection?
    private var resolvingNetService: NetService?
    private var activeTxtRecords: [(key: String, value: String)] = []
    private var currentResolvingService: DiscoveredService?
    private var timeoutTask: Task<Void, Never>?
    
    private var discoveredDomains = Set<String>()
    private var discoveredTypes = Set<String>()
    private var discoveredInstances = Set<DiscoveredService>()
    
    override init() {
        super.init()
    }
    
    // Domain Discovery
    func discoverDomains(clearExisting: Bool = false) {
        debugLog("[BonjourDiscovery] Starting domain discovery...")
        stopDomainSearch()
        if clearExisting {
            discoveredDomains.removeAll()
            domains.removeAll()
        }
        isSearching = true
        
        let browser = NetServiceBrowser()
        browser.delegate = self
        browser.searchForRegistrationDomains()
        domainBrowser = browser
        
        if !domains.contains("local") {
            domains.append("local")
            discoveredDomains.insert("local")
        }
    }
    
    func stopDomainSearch() {
        domainBrowser?.stop()
        domainBrowser = nil
        isSearching = false
    }
    
    // Service Type Discovery
    func discoverServiceTypes(in domain: String = "local.", probeTypes: [String]? = nil, clearExisting: Bool = false) {
        let domainWithDot = domain.hasSuffix(".") ? domain : domain + "."
        debugLog("[BonjourDiscovery] Starting service type discovery in domain '\(domainWithDot)'...")
        stopTypeSearch()
        if clearExisting {
            discoveredTypes.removeAll()
            serviceTypes.removeAll()
        }
        isSearching = true
        
        let browser = NetServiceBrowser()
        browser.delegate = self
        browser.searchForServices(ofType: "_services._dns-sd._udp.", inDomain: domainWithDot)
        typeBrowser = browser
        
        let typesToProbe = probeTypes ?? commonServiceTypesToBrowse
        if !typesToProbe.isEmpty {
            startFallbackSearches(types: typesToProbe, in: domainWithDot)
        }
        
        timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self = self, !Task.isCancelled else { return }
            self.isSearching = false
        }
    }
    
    private func startFallbackSearches(types: [String], in domain: String) {
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            
            for t in types {
                let typeWithoutDot = t.hasSuffix(".") ? String(t.dropLast()) : t
                let parameters = typeWithoutDot.contains("_tcp") ? NWParameters.tcp : NWParameters.udp
                parameters.includePeerToPeer = true
                
                let descriptor = NWBrowser.Descriptor.bonjour(type: typeWithoutDot, domain: domain)
                let browser = NWBrowser(for: descriptor, using: parameters)
                
                browser.browseResultsChangedHandler = { [weak self] results, _ in
                    guard let self = self else { return }
                    if !results.isEmpty {
                        Task { @MainActor in
                            if self.discoveredTypes.insert(t).inserted {
                                let info = ServiceTypeInfo(
                                    rawType: t,
                                    friendlyName: Self.friendlyName(for: t)
                                )
                                if !self.serviceTypes.contains(where: { $0.rawType == t }) {
                                    self.serviceTypes.append(info)
                                    self.serviceTypes.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
                                }
                            }
                        }
                    }
                }
                
                browser.start(queue: .global(qos: .userInitiated))
                
                Task { @MainActor in
                    self.fallbackTypeBrowsers.append(browser)
                }
            }
        }
    }
    
    func stopTypeSearch() {
        typeBrowser?.stop()
        typeBrowser = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        for b in fallbackTypeBrowsers {
            b.cancel()
        }
        fallbackTypeBrowsers.removeAll()
        isSearching = false
    }
    
    // Service Instance Discovery
    func discoverInstances(ofType type: String, inDomain domain: String = "local.", clearExisting: Bool = false) {
        discoverInstances(ofTypes: [type], inDomain: domain, clearExisting: clearExisting)
    }
    
    func discoverInstances(ofTypes types: [String], inDomain domain: String = "local.", clearExisting: Bool = false) {
        let domainWithDot = domain.hasSuffix(".") ? domain : domain + "."
        debugLog("[BonjourDiscovery] Starting instance discovery for types: \(types) in '\(domainWithDot)'...")
        stopInstanceSearch()
        if clearExisting {
            discoveredInstances.removeAll()
            instances.removeAll()
        }
        isSearching = true
        
        for type in types {
            let typeWithoutDot = type.hasSuffix(".") ? String(type.dropLast()) : type
            let descriptor = NWBrowser.Descriptor.bonjour(type: typeWithoutDot, domain: domainWithDot)
            let parameters = typeWithoutDot.contains("_tcp") ? NWParameters.tcp : NWParameters.udp
            parameters.includePeerToPeer = true
            
            let browser = NWBrowser(for: descriptor, using: parameters)
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                self?.handleInstanceResults(results, forType: type, domain: domain)
            }
            
            browser.stateUpdateHandler = { [weak self] state in
                if case .failed = state {
                    Task { @MainActor in
                        self?.isSearching = false
                    }
                }
            }
            
            instanceBrowsers.append(browser)
            browser.start(queue: .global(qos: .userInitiated))
        }
        
        timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard let self = self, !Task.isCancelled else { return }
            self.isSearching = false
        }
    }
    
    private func handleInstanceResults(_ results: Set<NWBrowser.Result>, forType type: String, domain: String) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            
            var currentTypeInstances: [DiscoveredService] = []
            for result in results {
                if case .service(let name, _, _, let iface) = result.endpoint {
                    let ifaceNames = result.interfaces.map { "\($0.name)(\($0.type))" }.joined(separator: ", ")
                    let epIface = iface?.name ?? "none"
                    var txtRecords: [(key: String, value: String)] = []
                    if case .bonjour(let txt) = result.metadata {
                        for (k, v) in txt.dictionary {
                            txtRecords.append((key: k, value: v))
                        }
                        txtRecords.sort { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
                    }
                    let txtSummary = txtRecords.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
                    debugLog("[BonjourDiscovery] Discovered '\(name)' (\(type)): ifaces=[\(ifaceNames)], epIface=\(epIface), txt=[\(txtSummary)]")
                    
                    let discovered = DiscoveredService(
                        name: name,
                        type: type,
                        domain: domain,
                        result: result,
                        txtRecords: txtRecords,
                        interfaces: Array(result.interfaces)
                    )
                    currentTypeInstances.append(discovered)
                }
            }
            
            var otherInstances = self.instances.filter { $0.type != type }
            otherInstances.append(contentsOf: currentTypeInstances)
            otherInstances.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            self.instances = otherInstances
            debugLog("[BonjourDiscovery] Live NWBrowser results updated for '\(type)': \(currentTypeInstances.count) active instance(s)")
        }
    }
    
    func stopInstanceSearch() {
        debugLog("[BonjourDiscovery] Stopping instance discovery.")
        timeoutTask?.cancel()
        timeoutTask = nil
        for b in instanceBrowsers {
            b.cancel()
        }
        instanceBrowsers.removeAll()
        isSearching = false
    }
    
    // Service Resolution
    func resolveService(_ service: DiscoveredService, clearExisting: Bool = false) {
        debugLog("[BonjourDiscovery] Resolving service '\(service.name)'...")
        stopResolving()
        
        if clearExisting || resolvedService?.name != service.name {
            resolvedService = nil
            resolveError = nil
        }
        isResolving = true
        currentResolvingService = service
        
        var txtRecords: [(key: String, value: String)] = []
        if case .bonjour(let txtRecord) = service.result.metadata {
            let dict = txtRecord.dictionary
            for (key, value) in dict {
                txtRecords.append((key: key, value: value))
            }
            txtRecords.sort { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
        }
        activeTxtRecords = txtRecords
        
        let isTCP = service.type.contains("_tcp")
        let parameters = isTCP ? NWParameters.tcp : NWParameters.udp
        parameters.includePeerToPeer = true
        
        let connection = NWConnection(to: service.result.endpoint, using: parameters)
        activeConnection = connection
        
        connection.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            debugLog("[BonjourDiscovery] NWConnection path update for '\(service.name)': status=\(path.status), remoteEndpoint=\(String(describing: path.remoteEndpoint))")
            if let remote = path.remoteEndpoint, case .hostPort(let host, let port) = remote {
                let rawHost = "\(host)"
                var resolvedHost = rawHost
                if let percentIndex = resolvedHost.firstIndex(of: "%") {
                    resolvedHost = String(resolvedHost[..<percentIndex])
                }
                let portVal = port.rawValue
                var directIPs: [String] = []
                if rawHost.contains(":") {
                    directIPs.append(rawHost)
                }
                if !directIPs.contains(resolvedHost) {
                    if resolvedHost.contains(":") || resolvedHost.filter({ $0 == "." }).count == 3 {
                        directIPs.append(resolvedHost)
                    } else {
                        directIPs.append(contentsOf: Self.resolveHostToIPs(resolvedHost))
                    }
                }
                
                self.finishResolution(
                    service: service,
                    hostname: resolvedHost,
                    port: portVal,
                    addresses: directIPs,
                    txtRecords: txtRecords
                )
            }
        }
        
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            debugLog("[BonjourDiscovery] NWConnection state for '\(service.name)': \(state)")
            
            switch state {
            case .ready:
                if let path = connection.currentPath, let remote = path.remoteEndpoint {
                    var resolvedHost = ""
                    var portVal: UInt16 = 0
                    
                    switch remote {
                    case .hostPort(let host, let port):
                        resolvedHost = "\(host)"
                        if let percentIndex = resolvedHost.firstIndex(of: "%") {
                            resolvedHost = String(resolvedHost[..<percentIndex])
                        }
                        portVal = port.rawValue
                    case .service(let sName, _, let sDomain, _):
                        let cleanDomain = sDomain.isEmpty ? "local" : (sDomain.hasSuffix(".") ? String(sDomain.dropLast()) : sDomain)
                        resolvedHost = "\(sName).\(cleanDomain)"
                        if let localEndpoint = path.localEndpoint, case .hostPort(_, let p) = localEndpoint {
                            portVal = p.rawValue
                        }
                    default:
                        resolvedHost = service.name
                    }
                    
                    let directIPs: [String]
                    if resolvedHost.contains(":") || resolvedHost.filter({ $0 == "." }).count == 3 {
                        directIPs = [resolvedHost]
                    } else {
                        directIPs = Self.resolveHostToIPs(resolvedHost)
                    }
                    
                    self.finishResolution(
                        service: service,
                        hostname: resolvedHost,
                        port: portVal,
                        addresses: directIPs,
                        txtRecords: txtRecords
                    )
                }
            case .waiting:
                if let path = connection.currentPath,
                   let remote = path.remoteEndpoint,
                   case .hostPort(let host, let port) = remote {
                    
                    var resolvedHost = "\(host)"
                    if let percentIndex = resolvedHost.firstIndex(of: "%") {
                        resolvedHost = String(resolvedHost[..<percentIndex])
                    }
                    let portVal = port.rawValue
                    let directIPs: [String]
                    if resolvedHost.contains(":") || resolvedHost.filter({ $0 == "." }).count == 3 {
                        directIPs = [resolvedHost]
                    } else {
                        directIPs = Self.resolveHostToIPs(resolvedHost)
                    }
                    
                    self.finishResolution(
                        service: service,
                        hostname: resolvedHost,
                        port: portVal,
                        addresses: directIPs,
                        txtRecords: txtRecords
                    )
                }
            case .failed(let error):
                debugLog("[BonjourDiscovery] NWConnection resolution failed: \(error)")
                Task { @MainActor [weak self] in
                    guard let self = self, self.isResolving, self.resolvedService == nil else { return }
                    self.resolveError = "Connection failed: \(error.localizedDescription)"
                    self.stopResolving()
                }
            default:
                break
            }
        }
        connection.start(queue: .global(qos: .userInitiated))
        
        let netType = service.type.hasSuffix(".") ? String(service.type.dropLast()) : service.type
        let netDomain = service.domain.isEmpty ? "local." : (service.domain.hasSuffix(".") ? service.domain : service.domain + ".")
        let ns = NetService(domain: netDomain, type: netType, name: service.name)
        ns.delegate = self
        ns.schedule(in: .main, forMode: .common)
        resolvingNetService = ns
        ns.resolve(withTimeout: 3.5)
        
        timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard let self = self, !Task.isCancelled else { return }
            if self.isResolving && self.resolvedService == nil {
                debugLog("[BonjourDiscovery] Resolution timed out for '\(service.name)'")
                self.resolveError = "Resolution timed out (no response from endpoint)"
                self.stopResolving()
            }
        }
    }
    
    private func finishResolution(
        service: DiscoveredService,
        hostname: String,
        port: UInt16,
        addresses: [String],
        txtRecords: [(key: String, value: String)]
    ) {
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            
            var allAddresses = addresses
            let cleanHost = hostname.strippingInterfaceScope
            if !cleanHost.isEmpty && !cleanHost.contains(":") && cleanHost.filter({ $0 == "." }).count < 3 {
                let resolved = Self.resolveHostToIPs(cleanHost)
                for ip in resolved {
                    if !allAddresses.contains(ip) {
                        allAddresses.append(ip)
                    }
                }
            }
            
            // If this is the local device (lo0 present), append local interface IPs (including IPv6 link-local on Wi-Fi)
            if service.interfaces.contains(where: { $0.type == .loopback }) {
                for localIp in Self.localInterfaceAddresses(matchingInterfaces: service.interfaces) {
                    if !allAddresses.contains(localIp) {
                        allAddresses.append(localIp)
                    }
                }
            }
            
            await MainActor.run {
                guard self.isResolving, self.resolvedService == nil else { return }
                
                self.resolvedService = ResolvedServiceInfo(
                    name: service.name,
                    type: service.type,
                    domain: service.domain,
                    hostname: cleanHost.isEmpty ? service.name : cleanHost,
                    port: port,
                    addresses: allAddresses,
                    txtRecords: txtRecords
                )
                self.isResolving = false
                self.stopResolving()
            }
        }
    }
    
    func stopResolving() {
        timeoutTask?.cancel()
        timeoutTask = nil
        activeConnection?.cancel()
        activeConnection = nil
        resolvingNetService?.stop()
        resolvingNetService = nil
        currentResolvingService = nil
        isResolving = false
    }
    
    func stopAll() {
        stopDomainSearch()
        stopTypeSearch()
        stopInstanceSearch()
        stopResolving()
    }
    
    // NetServiceBrowserDelegate
    func netServiceBrowser(_ browser: NetServiceBrowser, didFindDomain domainString: String, moreComing: Bool) {
        let cleanDomain = domainString.hasSuffix(".") ? String(domainString.dropLast()) : domainString
        Task { @MainActor in
            if self.discoveredDomains.insert(cleanDomain).inserted {
                self.domains.append(cleanDomain)
            }
            if !moreComing {
                self.isSearching = false
            }
        }
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        let rawType = "\(service.name).\(service.type)"
        Task { @MainActor in
            if self.discoveredTypes.insert(rawType).inserted {
                let info = ServiceTypeInfo(
                    rawType: rawType,
                    friendlyName: Self.friendlyName(for: rawType)
                )
                self.serviceTypes.append(info)
                self.serviceTypes.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            }
        }
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        Task { @MainActor in
            self.isSearching = false
        }
    }
    
    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        Task { @MainActor in
            self.isSearching = false
        }
    }
    
    // NetServiceDelegate
    func netServiceDidResolveAddress(_ sender: NetService) {
        let hostname = sender.hostName ?? ""
        let port = UInt16(sender.port)
        
        var cleanHost = hostname
        if cleanHost.hasSuffix(".") {
            cleanHost = String(cleanHost.dropLast())
        }
        
        var txtRecords: [(key: String, value: String)] = []
        if let txtData = sender.txtRecordData() {
            let dict = NetService.dictionary(fromTXTRecord: txtData)
            for (k, v) in dict {
                let valStr = String(data: v, encoding: .utf8) ?? ""
                txtRecords.append((key: k, value: valStr))
            }
        }
        
        let netAddresses = Self.addressesFromNetService(sender)
        let resolvedAddresses = netAddresses.isEmpty ? Self.resolveHostToIPs(cleanHost) : netAddresses
        
        Task { @MainActor in
            guard let service = self.currentResolvingService else { return }
            let finalRecords = self.activeTxtRecords.isEmpty ? txtRecords : self.activeTxtRecords
            let addrsSummary = resolvedAddresses.joined(separator: ", ")
            let txtSummary = finalRecords.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            debugLog("[BonjourDiscovery] Resolved '\(sender.name)' -> \(cleanHost):\(port) | IPs: [\(addrsSummary)] | TXT: [\(txtSummary)]")
            self.finishResolution(
                service: service,
                hostname: cleanHost.isEmpty ? service.name : cleanHost,
                port: port,
                addresses: resolvedAddresses,
                txtRecords: finalRecords
            )
        }
    }
    
    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        debugLog("[BonjourDiscovery] NetService failed to resolve: \(errorDict)")
        let errorCode = errorDict[NetService.errorCode]?.intValue ?? -1
        Task { @MainActor in
            guard self.isResolving, self.resolvedService == nil else { return }
            self.resolveError = errorCode == -72007 ? "Resolution timed out (no response from endpoint)" : "NetService resolution failed (error \(errorCode))"
            self.stopResolving()
        }
    }
    
    // Helpers
    static func addressesFromNetService(_ netService: NetService) -> [String] {
        var results: [String] = []
        guard let addresses = netService.addresses else { return results }
        
        for addressData in addresses {
            addressData.withUnsafeBytes { rawBuffer in
                guard let socketAddress = rawBuffer.baseAddress?.assumingMemoryBound(to: sockaddr.self) else { return }
                var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let sockLen: socklen_t
                if socketAddress.pointee.sa_family == sa_family_t(AF_INET) {
                    sockLen = socklen_t(MemoryLayout<sockaddr_in>.size)
                } else if socketAddress.pointee.sa_family == sa_family_t(AF_INET6) {
                    sockLen = socklen_t(MemoryLayout<sockaddr_in6>.size)
                } else {
                    return
                }
                
                if getnameinfo(socketAddress, sockLen, &hostBuffer, socklen_t(hostBuffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let ip = String(cString: hostBuffer)
                    if !ip.isEmpty && !results.contains(ip) {
                        results.append(ip)
                    }
                }
            }
        }
        return results
    }
    static func friendlyName(for rawType: String) -> String? {
        let normalized = rawType.hasSuffix(".") ? rawType : rawType + "."
        return commonKnownServiceTypes[normalized]
    }
    
    static func resolveHostToIPs(_ host: String) -> [String] {
        var addresses: [String] = []
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_flags = AI_DEFAULT
        
        var results: UnsafeMutablePointer<addrinfo>?
        let rc = getaddrinfo(host, nil, &hints, &results)
        if rc == 0, let firstAddr = results {
            var ptr: UnsafeMutablePointer<addrinfo>? = firstAddr
            while ptr != nil {
                if let addr = ptr?.pointee {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    let saLen = socklen_t(addr.ai_addrlen)
                    let nameInfoResult = getnameinfo(
                        addr.ai_addr,
                        saLen,
                        &hostname,
                        socklen_t(hostname.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    )
                    if nameInfoResult == 0 {
                        let ipStr = String(cString: hostname)
                        if !ipStr.isEmpty && !addresses.contains(ipStr) {
                            addresses.append(ipStr)
                        }
                    }
                }
                ptr = ptr?.pointee.ai_next
            }
            freeaddrinfo(results)
        }
        return addresses
    }
    
    static func localInterfaceAddresses(matchingInterfaces: [NWInterface]? = nil) -> [String] {
        let targetNames: Set<String>? = matchingInterfaces.map { Set($0.map { $0.name.lowercased() }) }
        let interfaces = Minimuxer.shared().network.activeInterfaces
        
        var addresses: [String] = []
        for iface in interfaces {
            let lowerName = iface.name.lowercased()
            let shouldInclude = targetNames?.contains(lowerName) ?? (lowerName.hasPrefix("en") || lowerName.hasPrefix("lo"))
            guard shouldInclude else { continue }
            
            if !iface.ip.isEmpty && !addresses.contains(iface.ip) {
                addresses.append(iface.ip)
            }
            if let v6 = iface.ipv6, !v6.isEmpty && !addresses.contains(v6) {
                addresses.append(v6)
            }
        }
        return addresses
    }
    
    private final class OneShotResolver: @unchecked Sendable {
        private let lock = NSLock()
        private var isResumed = false
        private var browser: NWBrowser?
        private var activeConnection: NWConnection?
        private var continuation: CheckedContinuation<(host: String, port: UInt16)?, Never>?
        
        init(continuation: CheckedContinuation<(host: String, port: UInt16)?, Never>) {
            self.continuation = continuation
        }
        
        func setBrowser(_ browser: NWBrowser) {
            lock.lock()
            self.browser = browser
            lock.unlock()
        }
        
        func setActiveConnection(_ connection: NWConnection) {
            lock.lock()
            self.activeConnection = connection
            lock.unlock()
        }
        
        func resumeOnce(_ result: (host: String, port: UInt16)?) {
            lock.lock()
            guard !isResumed else {
                lock.unlock()
                return
            }
            isResumed = true
            let continuation = self.continuation
            self.continuation = nil
            let browser = self.browser
            self.browser = nil
            let connection = self.activeConnection
            self.activeConnection = nil
            lock.unlock()
            
            browser?.cancel()
            connection?.cancel()
            continuation?.resume(returning: result)
        }
    }
    
    static func resolveFirstService(
        ofType rawType: String,
        namePrefix: String = "",
        domain: String? = nil,
        timeout: TimeInterval = AppConstants.Bonjour.defaultDiscoveryTimeout
    ) async -> (host: String, port: UInt16)? {
        let typeWithoutDot = rawType.hasSuffix(".") ? String(rawType.dropLast()) : rawType
        let descriptor = NWBrowser.Descriptor.bonjour(type: typeWithoutDot, domain: domain)
        let parameters = typeWithoutDot.contains("_tcp") ? NWParameters.tcp : NWParameters.udp
        parameters.includePeerToPeer = true
        
        debugLog("[BonjourDiscovery] resolveFirstService: starting NWBrowser for type='\(typeWithoutDot)', namePrefix='\(namePrefix)', domain=\(domain ?? "nil") (timeout: \(timeout)s)")
        let browser = NWBrowser(for: descriptor, using: parameters)
        
        return await withCheckedContinuation { continuation in
            let resolver = OneShotResolver(continuation: continuation)
            resolver.setBrowser(browser)
            
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                debugLog("[BonjourDiscovery] resolveFirstService: timeout reached after \(timeout)s")
                resolver.resumeOnce(nil)
            }
            
            browser.browseResultsChangedHandler = { results, changes in
                debugLog("[BonjourDiscovery] resolveFirstService: received \(results.count) results (changes: \(changes.count))")
                for res in results {
                    debugLog("[BonjourDiscovery] resolveFirstService: found endpoint '\(res.endpoint)' (interfaces: \(res.interfaces.map { $0.name }))")
                }
                
                let exactMatch = results.first(where: {
                    guard case .service(let name, _, _, _) = $0.endpoint else { return false }
                    return name.localizedCaseInsensitiveCompare(namePrefix) == .orderedSame
                })
                
                guard let target = exactMatch ?? results.first(where: {
                    guard case .service(let name, _, _, _) = $0.endpoint else { return false }
                    return namePrefix.isEmpty || name.localizedCaseInsensitiveContains(namePrefix)
                }), case .service(let name, _, _, _) = target.endpoint else {
                    debugLog("[BonjourDiscovery] resolveFirstService: no result matched prefix '\(namePrefix)'")
                    return
                }
                
                debugLog("[BonjourDiscovery] resolveFirstService: matched service '\(name)', initiating NWConnection")
                let conn = NWConnection(to: target.endpoint, using: parameters)
                resolver.setActiveConnection(conn)
                
                conn.pathUpdateHandler = { path in
                    debugLog("[BonjourDiscovery] resolveFirstService: conn pathUpdate status=\(path.status), remote=\(String(describing: path.remoteEndpoint))")
                    if path.status == .satisfied, let remote = path.remoteEndpoint {
                        var resolvedHost = ""
                        var portVal: UInt16 = 0
                        
                        switch remote {
                        case .hostPort(let host, let port):
                            resolvedHost = "\(host)".strippingInterfaceScope
                            portVal = port.rawValue
                        case .service(let sName, _, let sDomain, _):
                            let cleanDomain = sDomain.isEmpty ? "local" : (sDomain.hasSuffix(".") ? String(sDomain.dropLast()) : sDomain)
                            resolvedHost = "\(sName).\(cleanDomain)"
                            if let localEndpoint = path.localEndpoint, case .hostPort(_, let p) = localEndpoint {
                                portVal = p.rawValue
                            }
                        default:
                            resolvedHost = name
                        }
                        
                        guard portVal > 0 else { return }
                        let ips = resolveHostToIPs(resolvedHost)
                        let finalHost = ips.first ?? resolvedHost
                        debugLog("[BonjourDiscovery] Auto-resolved '\(name)' via pathUpdate to \(finalHost):\(portVal)")
                        resolver.resumeOnce((host: finalHost, port: portVal))
                    }
                }
                
                conn.stateUpdateHandler = { state in
                    debugLog("[BonjourDiscovery] resolveFirstService: conn stateUpdate -> \(state)")
                    switch state {
                    case .ready, .waiting:
                        guard let remote = conn.currentPath?.remoteEndpoint else { return }
                        var resolvedHost = ""
                        var portVal: UInt16 = 0
                        
                        switch remote {
                        case .hostPort(let host, let port):
                            resolvedHost = "\(host)".strippingInterfaceScope
                            portVal = port.rawValue
                        case .service(let sName, _, let sDomain, _):
                            let cleanDomain = sDomain.isEmpty ? "local" : (sDomain.hasSuffix(".") ? String(sDomain.dropLast()) : sDomain)
                            resolvedHost = "\(sName).\(cleanDomain)"
                            if let localEndpoint = conn.currentPath?.localEndpoint, case .hostPort(_, let p) = localEndpoint {
                                portVal = p.rawValue
                            }
                        default:
                            resolvedHost = name
                        }
                        
                        guard portVal > 0 else { return }
                        let ips = resolveHostToIPs(resolvedHost)
                        let finalHost = ips.first ?? resolvedHost
                        debugLog("[BonjourDiscovery] Auto-resolved '\(name)' to \(finalHost):\(portVal)")
                        resolver.resumeOnce((host: finalHost, port: portVal))
                        
                    case .failed(let err):
                        debugLog("[BonjourDiscovery] resolveFirstService: conn failed with error: \(err)")
                        resolver.resumeOnce(nil)
                        
                    default:
                        break
                    }
                }
                
                conn.start(queue: .global(qos: .userInitiated))
            }
            
            browser.stateUpdateHandler = { state in
                debugLog("[BonjourDiscovery] resolveFirstService: browser stateUpdate -> \(state)")
                if case .failed(let err) = state {
                    debugLog("[BonjourDiscovery] resolveFirstService: browser failed with error: \(err)")
                    resolver.resumeOnce(nil)
                }
            }
            
            browser.start(queue: .global(qos: .userInitiated))
        }
    }
}
