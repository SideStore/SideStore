//
//  MinimuxerWrapper.swift
//
//  Created by Magesh K on 22/02/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import Network
import Minimuxer
import Combine

public var selectedGatewayBackendCache: GatewayBackend = .idevice
public var remotePairingPortCache: UInt16 = AppConstants.Minimuxer.remotePairingPort
public var deviceProbeTimeoutCache: Int = AppConstants.Minimuxer.defaultTCPProbeTimeoutMs

public func syncMinimuxerBackendFromUserDefaults() {
    let raw = UserDefaults.standard.minimuxerGatewayBackend
    selectedGatewayBackendCache = GatewayBackend(rawValue: raw) ?? .idevice

    let overridePort = UserDefaults.standard.remotePairingPortOverride
    if overridePort > 0 && overridePort <= 65535 {
        remotePairingPortCache = UInt16(overridePort)
    } else {
        remotePairingPortCache = AppConstants.Minimuxer.remotePairingPort
    }

    let overrideTimeout = UserDefaults.standard.deviceProbeTimeoutOverride
    if overrideTimeout > 0 {
        deviceProbeTimeoutCache = overrideTimeout
    } else {
        deviceProbeTimeoutCache = AppConstants.Minimuxer.defaultTCPProbeTimeoutMs
    }
}

var minimuxer: any MinimuxerFacade {
    Minimuxer.shared(
        backend: selectedGatewayBackendCache,
        remotePairingPort: remotePairingPortCache,
        deviceProbeTimeout: deviceProbeTimeoutCache
    )
}

private func resolveDiscoveredRemotePairingPort() async -> UInt16? {
    let overridePort = UserDefaults.standard.remotePairingPortOverride
    if overridePort > 0 && overridePort <= 65535 {
        return UInt16(overridePort)
    }
    if let resolved = await BonjourDiscoveryManager.resolveFirstService(
        ofType: AppConstants.Minimuxer.remotePairingDaemonServiceType,
        timeout: AppConstants.Bonjour.defaultDiscoveryTimeout
    ) {
        debugLog("[SideStore] Discovered RemotePairing port via Bonjour: \(resolved.port)")
        return resolved.port
    }
    return nil
}

private var lastRemotePairingPortResolveTime: Date = .distantPast
private var activeRemotePairingPortResolveTask: Task<UInt16?, Never>?

private func resolveDiscoveredRemotePairingPortThrottled() async -> UInt16? {
    let overridePort = UserDefaults.standard.remotePairingPortOverride
    if overridePort > 0 && overridePort <= 65535 {
        return UInt16(overridePort)
    }

    let now = Date()
    guard now.timeIntervalSince(lastRemotePairingPortResolveTime) > 5.0 else {
        return nil
    }

    if let inFlight = activeRemotePairingPortResolveTask {
        return await inFlight.value
    }

    let task = Task<UInt16?, Never> {
        defer {
            activeRemotePairingPortResolveTask = nil
            lastRemotePairingPortResolveTime = Date()
        }
        return await resolveDiscoveredRemotePairingPort()
    }
    activeRemotePairingPortResolveTask = task
    return await task.value
}

private func withRemotePairingRetry<T>(_ operation: () async throws -> T) async throws -> T {
    do {
        return try await operation()
    } catch {
        guard minimuxer.gateway.pairingFileType == .rppairing else { throw error }

        if let newPort = await resolveDiscoveredRemotePairingPortThrottled(), newPort != remotePairingPortCache {
            debugLog("[SideStore] Operation failed, updating RemotePairing port from \(remotePairingPortCache) -> \(newPort) and retrying...")
            remotePairingPortCache = newPort
            _ = Minimuxer.shared(backend: selectedGatewayBackendCache, remotePairingPort: newPort)
            return try await operation()
        }
        throw error
    }
}

public var minimuxerStatusPublisher: AnyPublisher<Result<Bool, Error>, Never> {
    minimuxer.core.statusPublisher
        .map { result in
            result.mapError { $0 as Error }
        }
        .eraseToAnyPublisher()
}

func bindConnectionConfig() async {
    defer { debugLog("[SideStore] bindTunnelConfig() completed") }

    debugLog("[SideStore] bindTunnelConfig() invoked")
    let config = ConnectionConfig.shared
    let configBinding = ConnectionConfigBinding(
        setTunnelIfaceIp: { value in Task { @MainActor in config.tunnelIfaceIp = value } },
        setTunnelPeerIp: { value in Task { @MainActor in config.tunnelPeerIp = value } },
        setTunnelPeerSubnetMask: { value in Task { @MainActor in config.tunnelPeerSubnetMask = value } },
        setTunnelPeerReachable: { value in Task { @MainActor in config.tunnelPeerReachable = value } },
        setTunnelIfaceSubnetMask: { value in Task { @MainActor in config.tunnelIfaceSubnetMask = value } },
        getRemoteServerIp: { config.remoteServerIp },
        setRemoteReachable: { value in Task { @MainActor in config.remoteReachable = value } },
        getOverrideTunnelPeerIp: { config.overrideTunnelPeerIp },
        setOverrideTunnelPeerReachable: { value in Task { @MainActor in config.overrideTunnelPeerReachable = value } },
        getConnectionMode: { config.useLocalVPN ? .localVPN : .remoteServer }
    )
    await minimuxer.core.bindConnectionConfig(configBinding)
}

func getDeviceConnectionMode() async -> DeviceConnectionMode {
    return await minimuxer.core.getConnectionMode()
}

public func isMinimuxerReady() async -> Result<Bool, MinimuxerError> {
    let isEnabled = CellularRefreshManager.shared.isEnabled
    return await minimuxer.core.isReady(withNetworkCheck: !isEnabled)
}

extension MinimuxerError {
    var asOperationError: OperationError {
        switch self {
        case .noDevice(let reason):             return .noDevice(reason: reason)
        case .noConnection(let reason):         return .noConnection(reason: reason)
        case .notReachable(let reason):         return .notReachable(reason: reason)
        case .noVPN(let reason):                return .noVPN(reason: reason)
        case .invalidVPN(let reason):           return .invalidVPN(reason: reason)
        case .invalidPairing(_, let reason):    return .invalidPairingFile(reason: reason)
        case .notStarted(let reason):           return .minimuxerNotStarted(reason: reason)
        case .pairingNotLoaded(let reason):     return .pairingNotComplete(reason: reason)
        default:                                return .unknown(failureReason: self.localizedDescription)
        }
    }
}

func reinitializePairingData(_ pairingFile: String) async throws {
    defer { debugLog("[SideStore] reinitializePairingData(pairingFile) completed") }
    #if targetEnvironment(simulator)
    debugLog("[SideStore] reinitializePairingData(pairingFile) is no-op on simulator")
    #else
    debugLog("[SideStore] reinitializePairingData(pairingFile) invoked")
    try await withRemotePairingRetry {
        try await minimuxer.core.reinitializePairingData(pairingFile: pairingFile)
    }
    #endif
}

func minimuxerStart(_ pairingFile: String, mountPath: String) async throws {
    defer { debugLog("[SideStore] minimuxerStart(pairingFile) completed") }
    #if targetEnvironment(simulator)
    debugLog("[SideStore] minimuxerStart(pairingFile) is no-op on simulator")
    await bindConnectionConfig()
    await minimuxer.network.start()
    #else
    await bindConnectionConfig()
    debugLog("[SideStore] minimuxerStart(pairingFile) invoked")
    try await withRemotePairingRetry {
        try await minimuxer.core.start(pairingFile: pairingFile, mountPath: mountPath)
    }
    #endif
}


func reinitializePairingData(pairingFile: String) async throws {
    defer { debugLog("[SideStore] reinitializePairingData(pairingFile) completed") }
    #if targetEnvironment(simulator)
    debugLog("[SideStore] reinitializePairingData(pairingFile) is no-op on simulator")
    #else
    debugLog("[SideStore] reinitializePairingData(pairingFile) invoked")
    try await withRemotePairingRetry {
        try await minimuxer.core.reinitializePairingData(pairingFile: pairingFile)
    }
    #endif
}

func installProvisioningProfiles(_ profileData: Data) async throws {
    defer { debugLog("[SideStore] installProvisioningProfiles(profileData) completed") }
    #if targetEnvironment(simulator)
    debugLog("[SideStore] installProvisioningProfiles(profileData) is no-op on simulator")
    #else
    debugLog("[SideStore] installProvisioningProfiles(profileData) invoked")
    try await withRemotePairingRetry {
        try await minimuxer.core.installProvisioningProfile(profile: profileData)
    }
    #endif
}

func removeProvisioningProfile(_ id: String) async throws {
    defer { debugLog("[SideStore] removeProvisioningProfile(id) completed") }
    #if targetEnvironment(simulator)
    debugLog("[SideStore] removeProvisioningProfile(id) is no-op on simulator")
    #else
    debugLog("[SideStore] removeProvisioningProfile(id) invoked")
    try await withRemotePairingRetry {
        try await minimuxer.core.removeProvisioningProfile(id: id)
    }
    #endif
}

func removeApp(_ bundleId: String) async throws {
    defer { debugLog("[SideStore] removeApp(bundleId) completed") }
    #if targetEnvironment(simulator)
    debugLog("[SideStore] removeApp(bundleId) is no-op on simulator")
    #else
    debugLog("[SideStore] removeApp(bundleId) invoked")
    try await withRemotePairingRetry {
        try await minimuxer.core.removeApp(bundleId: bundleId)
    }
    #endif
}

func sendIpaAfc(_ bundleId: String, _ rawBytes: Data) async throws {
    defer { debugLog("[SideStore] sendIpaAfc(bundleId, rawBytes) completed") }
    #if targetEnvironment(simulator)
    debugLog("[SideStore] sendIpaAfc(bundleId, rawBytes) is no-op on simulator")
    #else
    debugLog("[SideStore] sendIpaAfc(bundleId, rawBytes) invoked")
    try await withRemotePairingRetry {
        try await minimuxer.core.sendIpaAfc(bundleId: bundleId, ipaBytes: rawBytes)
    }
    #endif
}

func sendAppBundleAfc(_ bundleId: String, at appURL: URL) async throws {
    defer { debugLog("[SideStore] sendAppBundleAfc(bundleId, appURL) completed") }
    #if targetEnvironment(simulator)
    debugLog("[SideStore] sendAppBundleAfc(bundleId, appURL) is no-op on simulator")
    #else
    debugLog("[SideStore] sendAppBundleAfc(bundleId, appURL) invoked")
    try await withRemotePairingRetry {
        try await minimuxer.core.sendAppBundleAfc(bundleId: bundleId, appURL: appURL)
    }
    #endif
}

func installIPA(_ bundleId: String) async throws {
    defer { debugLog("[SideStore] installIPA(bundleId) completed") }
    #if targetEnvironment(simulator)
    debugLog("[SideStore] installIPA(bundleId) is no-op on simulator")
    #else
    debugLog("[SideStore] installIPA(bundleId) invoked")
    try await withRemotePairingRetry {
        try await minimuxer.core.installIpa(bundleId: bundleId)
    }
    #endif
}

func installAppBundle(_ bundleId: String, appName: String) async throws {
    defer { debugLog("[SideStore] installAppBundle(bundleId, appName) completed") }
    #if targetEnvironment(simulator)
    debugLog("[SideStore] installAppBundle(bundleId, appName) is no-op on simulator")
    #else
    debugLog("[SideStore] installAppBundle(bundleId, appName) invoked")
    try await withRemotePairingRetry {
        try await minimuxer.core.installAppBundle(bundleId: bundleId, appName: appName)
    }
    #endif
}

@discardableResult
func fetchUDID(useStatic: Bool = false) async throws -> String? {
    defer { debugLog("[SideStore] fetchUDID() completed") }
    #if targetEnvironment(simulator)
    debugLog("[SideStore] fetchUDID() is no-op on simulator")
    return "XXXXX-XXXX-XXXXX-XXXX"
    #else
    debugLog("[SideStore] fetchUDID() invoked")
    let result = try? await withRemotePairingRetry {
        try await minimuxer.core.fetchUDID()
    }
    if let udid = result ?? nil, !udid.isEmpty, udid != "XXXXX-XXXX-XXXXX-XXXX" {
        return udid
    }
    if useStatic {
        return PairingFileManager.shared.pairingUDID
    }
    return nil
    #endif
}

func debugApp(_ appId: String) async throws {
    defer { debugLog("[SideStore] debugApp(appId) completed") }
    #if targetEnvironment(simulator)
    debugLog("[SideStore] debugApp(appId) is no-op on simulator")
    #else
    debugLog("[SideStore] debugApp(appId) invoked")
    try await withRemotePairingRetry {
        try await minimuxer.core.debugApp(appId: appId)
    }
    #endif
}

func attachDebugger(_ pid: UInt32) async throws {
    defer { debugLog("[SideStore] attachDebugger(pid) completed") }
    #if targetEnvironment(simulator)
    debugLog("[SideStore] attachDebugger(pid) is no-op on simulator")
    #else
    debugLog("[SideStore] attachDebugger(pid) invoked")
    try await withRemotePairingRetry {
        try await minimuxer.core.attachDebugger(pid: pid)
    }
    #endif
}


func dumpProfiles(_ docsPath: String) async throws -> String {
    defer { debugLog("[SideStore] dumpProfiles(docsPath) completed") }
    #if targetEnvironment(simulator)
    debugLog("[SideStore] dumpProfiles(docsPath) is no-op on simulator")
    return ""
    #else
    debugLog("[SideStore] dumpProfiles(docsPath) invoked")
    return try await withRemotePairingRetry {
        try await minimuxer.core.dumpProfiles(docsPath: docsPath)
    }
    #endif
}

func minimuxerSetLogging(_ enabled: Bool) {
    defer { debugLog("[SideStore] minimuxerSetLogging(enabled) completed") }
    debugLog("[SideStore] minimuxerSetLogging(enabled) invoked")
    #if !targetEnvironment(simulator)
    minimuxer.core.setLogging(enabled)
    #endif
}

public func minimuxerGetDeviceProbeTimeout() -> Int {
    #if targetEnvironment(simulator)
    return deviceProbeTimeoutCache
    #else
    return minimuxer.core.deviceProbeTimeout
    #endif
}

public func minimuxerSetDeviceProbeTimeout(_ timeoutMs: Int) {
    defer { debugLog("[SideStore] minimuxerSetDeviceProbeTimeout(\(timeoutMs)) completed") }
    debugLog("[SideStore] minimuxerSetDeviceProbeTimeout(\(timeoutMs)) invoked")
    deviceProbeTimeoutCache = timeoutMs
    UserDefaults.standard.deviceProbeTimeoutOverride = (timeoutMs == AppConstants.Minimuxer.defaultTCPProbeTimeoutMs) ? 0 : timeoutMs
    #if !targetEnvironment(simulator)
    minimuxer.core.setDeviceProbeTimeout(timeoutMs)
    #endif
}

extension Result {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}


func minimuxerRestart() async throws {
    #if !targetEnvironment(simulator)
    try await withRemotePairingRetry {
        try await minimuxer.core.restart()
    }
    #endif
}

public struct MinimuxerPairedDevice: Codable, Sendable {
    public let name: String
    public let model: String
    public let pairingFilePath: String
    
    public init(name: String, model: String, pairingFilePath: String) {
        self.name = name
        self.model = model
        self.pairingFilePath = pairingFilePath
    }
}

public final class WirelessPairWrapper {
    public static let shared = WirelessPairWrapper()
    
    private init() {}
    
    public var onPinReceived: ((String) -> Void)? {
        get {
            #if !targetEnvironment(simulator)
            return minimuxer.wirelessPair.onPinReceived
            #else
            return nil
            #endif
        }
        set {
            #if !targetEnvironment(simulator)
            minimuxer.wirelessPair.onPinReceived = newValue
            #endif
        }
    }
    
    public var onReadyToPair: ((String, Int) -> Void)? {
        get {
            #if !targetEnvironment(simulator)
            return minimuxer.wirelessPair.onReadyToPair
            #else
            return nil
            #endif
        }
        set {
            #if !targetEnvironment(simulator)
            minimuxer.wirelessPair.onReadyToPair = newValue
            #endif
        }
    }
    
    public var onRequestPin: ((@escaping (String) -> Void) -> Void)? {
        get {
            #if !targetEnvironment(simulator)
            return minimuxer.wirelessPair.onRequestPin
            #else
            return nil
            #endif
        }
        set {
            #if !targetEnvironment(simulator)
            minimuxer.wirelessPair.onRequestPin = newValue
            #endif
        }
    }
    
    public func start(
        outPath: String,
        completion: @escaping (Result<MinimuxerPairedDevice, Error>) -> Void
    ) {
        debugLog("[WirelessPairWrapper] start(outPath: '\(outPath)')")
        #if !targetEnvironment(simulator)
        minimuxer.wirelessPair.start(outPath: outPath) { result in
            debugLog("[WirelessPairWrapper] start callback received: result=\(result)")
            switch result {
            case .success(let device):
                completion(.success(MinimuxerPairedDevice(
                    name: device.name,
                    model: device.model,
                    pairingFilePath: device.pairingFilePath
                )))
            case .failure(let error):
                completion(.failure(error))
            }
        }
        #else
        completion(.failure(OperationError.invalidPairingFile()))
        #endif
    }

    public func trigger(
        targetIp: String,
        targetPort: UInt16,
        hostName: String = AppConstants.Minimuxer.defaultHostName,
        hostModel: String = AppConstants.Minimuxer.defaultHostModel,
        outPath: String,
        completion: @escaping (Result<MinimuxerPairedDevice, Error>) -> Void
    ) {
        debugLog("[WirelessPairWrapper] trigger(targetIp: '\(targetIp)', targetPort: \(targetPort), hostName: '\(hostName)', hostModel: '\(hostModel)', outPath: '\(outPath)')")
        #if !targetEnvironment(simulator)
        minimuxer.wirelessPair.trigger(
            targetIp: targetIp,
            targetPort: targetPort,
            hostName: hostName,
            hostModel: hostModel,
            outPath: outPath
        ) { result in
            debugLog("[WirelessPairWrapper] trigger callback received: result=\(result)")
            switch result {
            case .success(let device):
                completion(.success(MinimuxerPairedDevice(
                    name: device.name,
                    model: device.model,
                    pairingFilePath: device.pairingFilePath
                )))
            case .failure(let error):
                completion(.failure(error))
            }
        }
        #else
        completion(.failure(OperationError.invalidPairingFile()))
        #endif
    }
    
    public func stop() {
        debugLog("[WirelessPairWrapper] stop() invoked")
        #if !targetEnvironment(simulator)
        minimuxer.wirelessPair.stop()
        #endif
    }
}

let wirelessPairing = WirelessPairWrapper.shared
