//
//  WirelessPairViewModel.swift
//  SideStore
//
//  Created by Magesh K on 04/07/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import SwiftUI
import Combine
import Network
import Minimuxer

enum SelectedEndpointOption: Equatable {
    case discovered(WirelessPairTarget)
    case configuredFallback
}

enum PairingMode: String {
    case server
    case client
}

struct WirelessPairTarget: Identifiable, Hashable {
    var id: String { service.id }
    let service: DiscoveredService
    var ipv4: String?
    var ipv6: String?
    var port: UInt16
    
    var name: String {
        if case .bonjour(let txt) = service.result.metadata,
           let customName = txt.dictionary["name"], !customName.isEmpty {
            return customName
        }
        return service.name
    }
    
    var rawType: String { service.type }
    
    var model: String? {
        if case .bonjour(let txt) = service.result.metadata {
            return txt.dictionary["model"]
        }
        return nil
    }
    
    var uuid: String? {
        if case .bonjour(let txt) = service.result.metadata {
            return txt.dictionary["uuid"] ?? txt.dictionary["deviceid"]
        }
        return nil
    }
    
    var typeBadge: String {
        if service.type.contains("manual-pairing") { return "Apple TV / Manual" }
        if service.type.contains("pairable-host") { return "Pairable Host" }
        if service.type.contains("remotepairing") { return "Remote Device" }
        return BonjourDiscoveryManager.friendlyName(for: service.type) ?? service.type
    }
    
    var iconName: String {
        if service.type.contains("manual-pairing") { return "appletv.fill" }
        if service.type.contains("pairable-host") { return "macbook.and.iphone" }
        return "antenna.radiowaves.left.and.right"
    }
}

@MainActor
final class WirelessPairViewModel: ObservableObject {
    // Server Advertising State
    @Published var statusText = NSLocalizedString("Ready to pair", comment: "")
    @Published var subStatusText = NSLocalizedString("Tap Start to advertise this device on the local network.", comment: "")
    @Published var pinCode: String? = nil
    @Published var isAdvertising = false
    @Published var pairedDevice: MinimuxerPairedDevice? = nil
    @Published var errorMessage: String? = nil
    @Published var serviceID: String? = nil
    @Published var port: Int? = nil
    
    // Sheet / Dialog State
    @Published var isTargetDialogPresented = false
    @Published var dialogMode: PairingMode = .server
    @Published var selectedServerInterfaceId: String? = nil
    @Published var selectedOption: SelectedEndpointOption = .configuredFallback
    
    // Discovery State
    @Published var discoveredTargets: [WirelessPairTarget] = []
    @Published var isScanning = false
    @Published var activeInterfaces: [LocalInterfaceInfo] = []
    
    // Client PIN Prompt State
    @Published var isPinPromptPresented = false
    @Published var enteredPin = ""
    private var pinPromptCallback: ((String) -> Void)?
    
    // Share Sheet State
    @Published var shareSheetURL: URL? = nil
    @Published var isShareSheetPresented = false   
    
    private let pairingServiceTypes = [
        "_remotepairing-manual-pairing._tcp",
        "_remotepairing._tcp",
        "_remotepairing-pairable-host._tcp"
    ]
    
    private let bonjour = BonjourDiscoveryManager.shared
    private var cancellables = Set<AnyCancellable>()
    private var resolvingTasks: [String: Task<Void, Never>] = [:]
    
    var fallbackConfigEndpoint: (ip: String, port: UInt16) {
        let config = ConnectionConfig.shared
        let port = remotePairingPortCache != 0 ? remotePairingPortCache : AppConstants.Minimuxer.remotePairingPort

        guard config.useLocalVPN else {
            let remote = config.remoteServerIp.trimmingCharacters(in: .whitespacesAndNewlines)
            return (ip: !remote.isEmpty ? remote : AppConstants.Connection.defaultRemoteServerIP, port: port)
        }

        guard let ip = [config.overrideTunnelPeerIp, config.tunnelPeerIp]
            .compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) else {
            return (ip: AppConstants.Connection.defaultOverrideIP, port: port)
        }

        return (ip: ip, port: port)
    }
    
    init() {
        debugLog("[WirelessPairViewModel] init() initializing...")
        activeInterfaces = minimuxer.network.activeInterfaces
        
        // Setup closures once
        wirelessPairing.onReadyToPair = { [weak self] (serviceID: String, port: Int) in
            debugLog("[WirelessPairViewModel] onReadyToPair callback received: serviceID='\(serviceID)', port=\(port)")
            Task { @MainActor in
                guard let self = self else { return }
                self.serviceID = serviceID
                self.port = port
                self.statusText = NSLocalizedString("Advertising server...", comment: "")
                self.subStatusText = NSLocalizedString("Ensure both devices are on the same Wi-Fi.", comment: "")
            }
        }
        
        wirelessPairing.onPinReceived = { [weak self] (pin: String) in
            debugLog("[WirelessPairViewModel] onPinReceived callback received: pin='\(pin)'")
            Task { @MainActor in
                guard let self = self else { return }
                self.pinCode = pin
                self.statusText = NSLocalizedString("Device Connected", comment: "")
                self.subStatusText = NSLocalizedString("Enter the pairing code shown below on your other device settings screen.", comment: "")
            }
        }
        
        wirelessPairing.onRequestPin = { [weak self] (submitPin: @escaping (String) -> Void) in
            debugLog("[WirelessPairViewModel] onRequestPin callback received from wirelessPairing")
            Task { @MainActor in
                guard let self = self else { return }
                self.pinPromptCallback = submitPin
                self.enteredPin = ""
                self.isPinPromptPresented = true
                self.statusText = NSLocalizedString("Enter Pairing PIN", comment: "")
                self.subStatusText = NSLocalizedString("Enter the 6-digit code shown on your Apple TV / device screen.", comment: "")
            }
        }
    }
    
    func submitEnteredPin() {
        let pin = enteredPin.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalPin = pin.isEmpty ? "000000" : pin
        debugLog("[WirelessPairViewModel] submitEnteredPin() sending PIN '\(finalPin)' to gateway")
        pinPromptCallback?(finalPin)
        pinPromptCallback = nil
        isPinPromptPresented = false
        enteredPin = ""
    }
    
    func cancelPinPrompt() {
        debugLog("[WirelessPairViewModel] cancelPinPrompt() cancelling PIN prompt")
        pinPromptCallback?("000000")
        pinPromptCallback = nil
        isPinPromptPresented = false
        enteredPin = ""
    }
    
    private var discoveryTask: Task<Void, Never>?
    
    func refreshInterfaces() {
        debugLog("[WirelessPairViewModel] refreshInterfaces() scanning active interfaces...")
        activeInterfaces = minimuxer.network.activeInterfaces
        debugLog("[WirelessPairViewModel] refreshInterfaces() scan completed, found \(activeInterfaces.count) active interfaces:")
        for iface in activeInterfaces {
            debugLog("[WirelessPairViewModel]  -> \(iface.name) [\(iface.type.rawValue)]: ip=\(iface.ip), ipv6=\(iface.ipv6 ?? "none"), subnet=\(iface.subnet)")
        }
    }
    
    func selectDefaultServerInterface() {
        selectedServerInterfaceId = activeInterfaces
            .first(where: { $0.type == .wifi })?.id 
            ?? activeInterfaces
            .first(where: { $0.type.isVPN })?.id 
            ?? activeInterfaces.first?.id
        debugLog("[WirelessPairViewModel] selectDefaultServerInterface() selected: \(selectedServerInterfaceId ?? "none")")
    }
    
    func selectServerInterface(id: String) {
        debugLog("[WirelessPairViewModel] selectServerInterface(id: '\(id)')")
        selectedServerInterfaceId = id
    }
    
    func selectTarget(_ target: WirelessPairTarget) {
        debugLog("[WirelessPairViewModel] selectTarget() selected: '\(target.name)' (\(target.rawType)) -> v4=\(target.ipv4 ?? "none"), v6=\(target.ipv6 ?? "none"), port=\(target.port)")
        selectedOption = .discovered(target)
    }
    
    func selectFallbackEndpoint() {
        let fallback = fallbackConfigEndpoint
        debugLog("[WirelessPairViewModel] selectFallbackEndpoint() selected fallback: \(fallback.ip):\(fallback.port)")
        selectedOption = .configuredFallback
    }
    
    func isTargetSelected(_ target: WirelessPairTarget) -> Bool {
        if case .discovered(let selected) = selectedOption {
            return selected.id == target.id
        }
        return false
    }
    
    var isFallbackSelected: Bool {
        if case .configuredFallback = selectedOption {
            return true
        }
        return false
    }
    
    func openClientDialog() {
        debugLog("[WirelessPairViewModel] openClientDialog() opening client target pairing sheet")
        dialogMode = .client
        selectedOption = .configuredFallback
        startDiscovery()
        isTargetDialogPresented = true
    }
    
    func openServerDialog() {
        debugLog("[WirelessPairViewModel] openServerDialog() opening server interface selection sheet")
        if isAdvertising {
            debugLog("[WirelessPairViewModel] openServerDialog() already advertising, stopping pairing instead")
            stopPairing()
        } else {
            dialogMode = .server
            refreshInterfaces()
            selectDefaultServerInterface()
            isTargetDialogPresented = true
        }
    }
    
    func onDialogAppear() {
        debugLog("[WirelessPairViewModel] onDialogAppear (mode=\(dialogMode.rawValue), isPresented=\(isTargetDialogPresented))")
        if dialogMode == .server {
            refreshInterfaces()
            if selectedServerInterfaceId == nil {
                selectDefaultServerInterface()
            }
        } else {
            if discoveredTargets.isEmpty && !isScanning {
                debugLog("[WirelessPairViewModel] onDialogAppear discoveredTargets is empty and not scanning -> triggering startDiscovery()")
                startDiscovery()
            }
        }
    }
    
    func onDialogDisappear() {
        debugLog("[WirelessPairViewModel] onDialogDisappear (mode=\(dialogMode.rawValue))")
        if dialogMode == .client {
            stopDiscovery()
        }
    }
    
    func refreshDialog() {
        debugLog("[WirelessPairViewModel] refreshDialog (pull-to-refresh invoked for mode=\(dialogMode.rawValue))")
        if dialogMode == .client {
            startDiscovery()
        } else {
            refreshInterfaces()
        }
    }
    
    func dismissDialog() {
        debugLog("[WirelessPairViewModel] dismissDialog (mode=\(dialogMode.rawValue))")
        if dialogMode == .client {
            stopDiscovery()
        }
        isTargetDialogPresented = false
    }
    
    func confirmSelection() {
        debugLog("[WirelessPairViewModel] confirmSelection() invoked (mode=\(dialogMode.rawValue), option=\(selectedOption))")
        dismissDialog()
        
        if dialogMode == .client {
            switch selectedOption {
            case .discovered(let target):
                let targetIp = target.ipv4 ?? target.ipv6 ?? target.service.name
                let targetPort = target.port > 0 ? target.port : AppConstants.Minimuxer.remotePairingPort
                debugLog("[WirelessPairViewModel] confirmSelection -> Connecting to target '\(target.name)' at \(targetIp):\(targetPort)")
                triggerPairing(targetIp: targetIp, targetPort: targetPort, targetName: target.name)
            case .configuredFallback:
                let fallback = fallbackConfigEndpoint
                debugLog("[WirelessPairViewModel] confirmSelection -> Connecting to configured fallback at \(fallback.ip):\(fallback.port)")
                triggerPairing(targetIp: fallback.ip, targetPort: fallback.port, targetName: "configured_host")
            }
        } else {
            debugLog("[WirelessPairViewModel] confirmSelection -> Starting server advertising (selectedInterfaceId=\(selectedServerInterfaceId ?? "none"))")
            startPairing()
        }
    }
    
    private func resolveEndpoint(for service: DiscoveredService) async -> (ipv4: String?, ipv6: String?, port: UInt16) {
        debugLog("[WirelessPairViewModel] resolveEndpoint() starting for '\(service.name)' (\(service.type))...")
        return await withCheckedContinuation { continuation in
            let isTCP = service.type.contains("_tcp")
            let params = isTCP ? NWParameters.tcp : NWParameters.udp
            params.includePeerToPeer = true
            
            let conn = NWConnection(to: service.result.endpoint, using: params)
            let lock = NSLock()
            var didResume = false
            
            let resumeOnce: ((ipv4: String?, ipv6: String?, port: UInt16)) -> Void = { result in
                lock.withLock {
                    guard !didResume else { return }
                    didResume = true
                    conn.cancel()
                    debugLog("[WirelessPairViewModel] resolveEndpoint() resolved '\(service.name)': v4=\(result.ipv4 ?? "none"), v6=\(result.ipv6 ?? "none"), port=\(result.port)")
                    continuation.resume(returning: result)
                }
            }
            
            conn.pathUpdateHandler = { path in
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
                        resolvedHost = service.name
                    }
                    
                    guard portVal > 0 else { return }
                    let ips = BonjourDiscoveryManager.resolveHostToIPs(resolvedHost)
                    let v4 = ips.first(where: { !$0.contains(":") && $0 != "0.0.0.0" })
                        ?? (!resolvedHost.contains(":") && resolvedHost.filter({ $0 == "." }).count == 3 ? resolvedHost : nil)
                    let v6 = ips.first(where: { $0.contains(":") })
                        ?? (resolvedHost.contains(":") ? resolvedHost : nil)
                    
                    resumeOnce((v4, v6, portVal))
                }
            }
            
            conn.stateUpdateHandler = { state in
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
                        resolvedHost = service.name
                    }
                    
                    guard portVal > 0 else { return }
                    let ips = BonjourDiscoveryManager.resolveHostToIPs(resolvedHost)
                    let v4 = ips.first(where: { !$0.contains(":") && $0 != "0.0.0.0" })
                        ?? (!resolvedHost.contains(":") && resolvedHost.filter({ $0 == "." }).count == 3 ? resolvedHost : nil)
                    let v6 = ips.first(where: { $0.contains(":") })
                        ?? (resolvedHost.contains(":") ? resolvedHost : nil)
                    
                    resumeOnce((v4, v6, portVal))
                case .failed:
                    debugLog("[WirelessPairViewModel] resolveEndpoint() NWConnection state .failed for '\(service.name)'")
                    resumeOnce((nil, nil, 0))
                default:
                    break
                }
            }
            
            DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
                debugLog("[WirelessPairViewModel] resolveEndpoint() timeout (2.0s) reached for '\(service.name)'")
                resumeOnce((nil, nil, 0))
            }
            
            conn.start(queue: .global(qos: .userInitiated))
        }
    }
    
    func startDiscovery() {
        discoveryTask?.cancel()
        isScanning = true
        discoveredTargets.removeAll()
        
        discoveryTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            debugLog("[WirelessPairViewModel] startDiscovery() one-shot pass starting for types: \(self.pairingServiceTypes)")
            
            self.bonjour.discoverInstances(ofTypes: self.pairingServiceTypes, inDomain: "local.", clearExisting: true)
            
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else {
                debugLog("[WirelessPairViewModel] startDiscovery() Task was cancelled before instance snapshot")
                return
            }
            
            let instancesSnapshot = self.bonjour.instances
            debugLog("[WirelessPairViewModel] one-shot: gathered \(instancesSnapshot.count) Bonjour instances from BonjourDiscoveryManager:")
            for s in instancesSnapshot {
                debugLog("[WirelessPairViewModel]  -> instance: name='\(s.name)', type='\(s.type)', domain='\(s.domain)', id='\(s.id)'")
            }
            
            self.bonjour.stopInstanceSearch()
            debugLog("[WirelessPairViewModel] Bonjour search stopped, resolving \(instancesSnapshot.count) endpoints in parallel...")
            
            var finalTargets: [WirelessPairTarget] = []
            await withTaskGroup(of: WirelessPairTarget.self) { group in
                for service in instancesSnapshot {
                    group.addTask {
                        let (ipv4, ipv6, port) = await self.resolveEndpoint(for: service)
                        return WirelessPairTarget(service: service, ipv4: ipv4, ipv6: ipv6, port: port)
                    }
                }
                for await target in group {
                    finalTargets.append(target)
                }
            }
            
            guard !Task.isCancelled else {
                debugLog("[WirelessPairViewModel] startDiscovery() Task was cancelled during endpoint resolution")
                return
            }
            finalTargets.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            self.discoveredTargets = finalTargets
            self.isScanning = false
            debugLog("[WirelessPairViewModel] one-shot pass complete: \(self.discoveredTargets.count) targets ready:")
            for t in self.discoveredTargets {
                debugLog("[WirelessPairViewModel]  -> Target: '\(t.name)' [\(t.rawType)] - IPv4: \(t.ipv4 ?? "none"), IPv6: \(t.ipv6 ?? "none"), Port: \(t.port)")
            }
        }
    }
    
    func stopDiscovery() {
        debugLog("[WirelessPairViewModel] stopDiscovery() invoked")
        discoveryTask?.cancel()
        discoveryTask = nil
        isScanning = false
        bonjour.stopInstanceSearch()
    }
    
    func togglePairing() {
        debugLog("[WirelessPairViewModel] togglePairing() invoked (currently isAdvertising=\(isAdvertising))")
        if isAdvertising {
            stopPairing()
        } else {
            openServerDialog()
        }
    }
    
    func startPairing() {
        let pairingFile = pairingFilePath()
        debugLog("[WirelessPairViewModel] startPairing() starting advertisement with outPath: '\(pairingFile)'")
        isAdvertising = true
        pinCode = nil
        errorMessage = nil
        serviceID = nil
        port = nil
        statusText = NSLocalizedString("Waiting for connection...", comment: "")
        subStatusText = NSLocalizedString("Open Remote Pairing on your Apple TV / Vision Pro / host device to discover this server.", comment: "")
        
        wirelessPairing.start(outPath: pairingFile) { [weak self] (result: Result<MinimuxerPairedDevice, Swift.Error>) in
            Task { @MainActor in
                guard let self = self else { return }
                debugLog("[WirelessPairViewModel] startPairing() completion received: result=\(result), wasAdvertising=\(self.isAdvertising)")
                guard self.isAdvertising else { return }
                self.isAdvertising = false
                self.pinCode = nil
                self.serviceID = nil
                self.port = nil
                
                switch result {
                case .success(let device):
                    debugLog("[WirelessPairViewModel] startPairing() SUCCESS with device: name='\(device.name)', model='\(device.model)'")
                    self.pairedDevice = device
                    self.statusText = NSLocalizedString("Success!", comment: "")
                    self.subStatusText = String(format: NSLocalizedString("Successfully paired with %@ (%@)!\nPairing file saved to documents.", comment: ""), device.name, device.model)
                    self.shareSheetURL = URL(fileURLWithPath: device.pairingFilePath)
                    self.isShareSheetPresented = true
                case .failure(let error):
                    debugLog("[WirelessPairViewModel] startPairing() FAILURE: error='\(error.localizedDescription)'")
                    self.errorMessage = error.localizedDescription
                    self.statusText = NSLocalizedString("Pairing Failed", comment: "")
                    self.subStatusText = NSLocalizedString("An error occurred during pairing.", comment: "")
                }
            }
        }
    }

    func stopPairing() {
        debugLog("[WirelessPairViewModel] stopPairing() stopping advertisement and tearing down session")
        wirelessPairing.stop()
        
        isAdvertising = false
        statusText = NSLocalizedString("Ready to pair", comment: "")
        subStatusText = NSLocalizedString("Tap Start to advertise this device on the local network.", comment: "")
        pinCode = nil
        errorMessage = nil
        serviceID = nil
        port = nil
    }
    
    func triggerPairing(
        targetIp: String,
        targetPort: UInt16,
        targetName: String? = nil,
        completion: ((Result<MinimuxerPairedDevice, Swift.Error>) -> Void)? = nil
    ) {
        let pairingFile = pairingFilePath(for: targetName)
        debugLog("[WirelessPairViewModel] triggerPairing() initiating handshake to \(targetIp):\(targetPort), outPath: '\(pairingFile)'")
        isAdvertising = true
        pinCode = nil
        errorMessage = nil
        serviceID = nil
        port = nil
        statusText = NSLocalizedString("Connecting to device...", comment: "")
        subStatusText = String(format: NSLocalizedString("Initiating pairing handshake on %@:%@...", comment: ""), targetIp, targetPort)
        
        wirelessPairing.trigger(
            targetIp: targetIp,
            targetPort: targetPort,
            outPath: pairingFile
        ) { [weak self] (result: Result<MinimuxerPairedDevice, Swift.Error>) in
            Task { @MainActor in
                guard let self = self else { return }
                debugLog("[WirelessPairViewModel] triggerPairing() completion received: result=\(result)")
                self.isAdvertising = false
                self.pinCode = nil
                self.serviceID = nil
                self.port = nil
                
                switch result {
                case .success(let device):
                    debugLog("[WirelessPairViewModel] triggerPairing() SUCCESS with device: name='\(device.name)', model='\(device.model)'")
                    self.pairedDevice = device
                    self.statusText = NSLocalizedString("Success!", comment: "")
                    self.subStatusText = String(format: NSLocalizedString("Successfully paired with %@ (%@)!\nPairing file saved to documents.", comment: ""), device.name, device.model)
                    self.shareSheetURL = URL(fileURLWithPath: device.pairingFilePath)
                    self.isShareSheetPresented = true
                case .failure(let error):
                    debugLog("[WirelessPairViewModel] triggerPairing() FAILURE: error='\(error.localizedDescription)'")
                    self.errorMessage = error.localizedDescription
                    self.statusText = NSLocalizedString("Pairing Failed", comment: "")
                    self.subStatusText = String(format: NSLocalizedString("An error occurred during pairing: %@", comment: ""), error.localizedDescription)
                }
                completion?(result)
            }
        }
    }
    
    private func pairingFilePath(for deviceName: String? = nil) -> String {
        let docs = FileManager.default.documentsDirectory
        if let deviceName = deviceName, !deviceName.isEmpty {
            let spaceReplaced = deviceName
                .replacingOccurrences(of: " ", with: "_")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: ":", with: "_")
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
            let sanitized = spaceReplaced.unicodeScalars.filter { allowed.contains($0) }.map(String.init).joined()
            let finalName = sanitized.isEmpty ? "device" : sanitized
            return docs.appendingPathComponent("\(finalName)_rp.plist").path
        }
        return docs.appendingPathComponent("rp_pairing_file.plist").path
    }
}
