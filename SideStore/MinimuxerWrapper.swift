//
//  MinimuxerWrapper.swift
//
//  Created by Magesh K on 22/02/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import Minimuxer

func bindConnectionConfig() async {
    defer { debugLog("[SideStore] bindTunnelConfig() completed") }

    debugLog("[SideStore] bindTunnelConfig() invoked")
    let config = ConnectionConfig.shared
    let configBinding = ConnectionConfigBinding(
        setTunnelIfaceIp: { value in Task { @MainActor in config.tunnelIfaceIp = value } },
        setTunnelPeerIp: { value in Task { @MainActor in config.tunnelPeerIp = value } },
        setTunnelIfaceSubnetMask: { value in Task { @MainActor in config.tunnelIfaceSubnetMask = value } },
        getRemoteServerIp: { config.remoteServerIp },
        setRemoteReachable: { value in Task { @MainActor in config.remoteReachable = value } },
        getOverrideTunnelPeerIp: { config.overrideTunnelPeerIp },
        setOverrideTunnelPeerReachable: { value in Task { @MainActor in config.overrideTunnelPeerReachable = value } },
        getConnectionMode: { config.useLocalVPN ? .localVPN : .remoteServer }
    )
    await Minimuxer.shared.bindConnectionConfig(configBinding)
}

func getDeviceConnectionMode() async -> DeviceConnectionMode {
    return await Minimuxer.shared.getConnectionMode()
}

enum MinimuxerStatus: Equatable {
    case ready
    case noDevice
    case noConnection
    case notReachable(String)
    case noVPN
    case invalidVPN
    case pairingFile
    case invalidPairing
    case unknown
    
    var operationError: OperationError? {
        switch self {
        case .unknown:
            return nil
        case .ready:
            return nil
        case .noDevice:
            return .noDevice
        case .noConnection:
            return .noConnection
        case .notReachable(let reason):
            return .notReachable(reason: reason)
        case .noVPN:
            return .noVPN
        case .invalidVPN:
            return .noVPN
        case .pairingFile:
            return .invalidPairingFile
        case .invalidPairing:
            return .invalidPairingFile
        }
    }
}

func getMinimuxerStatus() async -> MinimuxerStatus {
    #if targetEnvironment(simulator)
    debugLog("[SideStore] getMinimuxerStatus() = .ready on simulator")
    return .ready
    #else
    let result = await Minimuxer.shared.isReady()
    switch result {
        case .success:
            return .ready
        case .failure(let error):
            switch error {
                case .noVPN:
                    return .noVPN
                case .invalidVPN:
                    return .invalidVPN
                case .pairingFile:
                    return .pairingFile
                case .invalidPairing:
                    return .invalidPairing
                case .noDevice:
                    return .noDevice
                case .noConnection:
                    return .noConnection
                case .notReachable(let reason):
                    return .notReachable(reason)
                default:
                    return .unknown
            }
    }
    #endif
}

func reinitializePairingData(_ pairingFile: String) async throws {
    defer { debugLog("[SideStore] reinitializePairingData(pairingFile) completed") }
    #if targetEnvironment(simulator)
    debugLog("[SideStore] reinitializePairingData(pairingFile) is no-op on simulator")
    #else
    debugLog("[SideStore] reinitializePairingData(pairingFile) invoked")
    try await Minimuxer.shared.reinitializePairingData(pairingFile: pairingFile)
    #endif
}

func minimuxerStart(_ pairingFile: String, mountPath: String) async throws {
    defer { debugLog("[SideStore] minimuxerStart(pairingFile) completed") }
    #if targetEnvironment(simulator)
    debugLog("[SideStore] minimuxerStart(pairingFile) is no-op on simulator")
    await bindConnectionConfig()
    await Minimuxer.network.start()
    #else
    await bindConnectionConfig()
    debugLog("[SideStore] minimuxerStart(pairingFile) invoked")
    try await Minimuxer.shared.start(pairingFile: pairingFile, mountPath: mountPath)
    #endif
}

func revalidateMinimuxerConnectivityAfterForeground() async {
    #if !targetEnvironment(simulator)
    await Minimuxer.shared.revalidateConnectivitySessionAfterForeground()
    #endif
}


func reinitializePairingData(pairingFile: String) async throws {
    defer { debugLog("[SideStore] reinitializePairingData(pairingFile) completed") }
    #if targetEnvironment(simulator)
    debugLog("[SideStore] reinitializePairingData(pairingFile) is no-op on simulator")
    #else
    debugLog("[SideStore] reinitializePairingData(pairingFile) invoked")
    try await Minimuxer.shared.reinitializePairingData(pairingFile: pairingFile)
    #endif
}

func installProvisioningProfiles(_ profileData: Data) async throws {
    defer { debugLog("[SideStore] installProvisioningProfiles(profileData) completed") }
    #if targetEnvironment(simulator)
    debugLog("[SideStore] installProvisioningProfiles(profileData) is no-op on simulator")
    #else
    debugLog("[SideStore] installProvisioningProfiles(profileData) invoked")
    try await Minimuxer.shared.installProvisioningProfile(profile: profileData)
    #endif
}

func removeProvisioningProfile(_ id: String) async throws {
    defer { debugLog("[SideStore] removeProvisioningProfile(id) completed") }
    #if targetEnvironment(simulator)
    debugLog("[SideStore] removeProvisioningProfile(id) is no-op on simulator")
    #else
    debugLog("[SideStore] removeProvisioningProfile(id) invoked")
    try await Minimuxer.shared.removeProvisioningProfile(id: id)
    #endif
}

func removeApp(_ bundleId: String) async throws {
    defer { debugLog("[SideStore] removeApp(bundleId) completed") }
    #if targetEnvironment(simulator)
    debugLog("[SideStore] removeApp(bundleId) is no-op on simulator")
    #else
    debugLog("[SideStore] removeApp(bundleId) invoked")
    try await Minimuxer.shared.removeApp(bundleId: bundleId)
    #endif
}

func yeetAppAFC(_ bundleId: String, _ rawBytes: Data) async throws {
    defer { debugLog("[SideStore] yeetAppAFC(bundleId, rawBytes) completed") }
    #if targetEnvironment(simulator)
    debugLog("[SideStore] yeetAppAFC(bundleId, rawBytes) is no-op on simulator")
    #else
    debugLog("[SideStore] yeetAppAFC(bundleId, rawBytes) invoked")
    try await Minimuxer.shared.yeetAppAfc(bundleId: bundleId, ipaBytes: rawBytes)
    #endif
}

func installIPA(_ bundleId: String) async throws {
    defer { debugLog("[SideStore] installIPA(bundleId) completed") }
    #if targetEnvironment(simulator)
    debugLog("[SideStore] installIPA(bundleId) is no-op on simulator")
    #else
    debugLog("[SideStore] installIPA(bundleId) invoked")
    try await Minimuxer.shared.installIpa(bundleId: bundleId)
    #endif
}

@discardableResult
func fetchUDID() async throws -> String? {
    defer { debugLog("[SideStore] fetchUDID() completed") }
    #if targetEnvironment(simulator)
    debugLog("[SideStore] fetchUDID() is no-op on simulator")
    return "XXXXX-XXXX-XXXXX-XXXX"
    #else
    debugLog("[SideStore] fetchUDID() invoked")
    return try await Minimuxer.shared.fetchUDID()
    #endif
}

func debugApp(_ appId: String) async throws {
    defer { debugLog("[SideStore] debugApp(appId) completed") }
    #if targetEnvironment(simulator)
    debugLog("[SideStore] debugApp(appId) is no-op on simulator")
    #else
    debugLog("[SideStore] debugApp(appId) invoked")
    try await Minimuxer.shared.debugApp(appId: appId)
    #endif
}

func attachDebugger(_ pid: UInt32) async throws {
    defer { debugLog("[SideStore] attachDebugger(pid) completed") }
    #if targetEnvironment(simulator)
    debugLog("[SideStore] attachDebugger(pid) is no-op on simulator")
    #else
    debugLog("[SideStore] attachDebugger(pid) invoked")
    try await Minimuxer.shared.attachDebugger(pid: pid)
    #endif
}


func dumpProfiles(_ docsPath: String) async throws -> String {
    defer { debugLog("[SideStore] dumpProfiles(docsPath) completed") }
    #if targetEnvironment(simulator)
    debugLog("[SideStore] dumpProfiles(docsPath) is no-op on simulator")
    return ""
    #else
    debugLog("[SideStore] dumpProfiles(docsPath) invoked")
    return try await Minimuxer.shared.dumpProfiles(docsPath: docsPath)
    #endif
}

func minimuxerSetLogging(_ enabled: Bool) {
    defer { debugLog("[SideStore] minimuxerSetLogging(enabled) completed") }
    debugLog("[SideStore] minimuxerSetLogging(enabled) invoked")
    #if !targetEnvironment(simulator)
    Minimuxer.shared.setLogging(enabled)
    #endif
}

extension Result {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

extension MinimuxerError {
    public var failureReason: String? {
        switch self {
        case .noDevice:
            return NSLocalizedString("Cannot fetch the device from the muxer", comment: "")
        case .noConnection:
            return NSLocalizedString("You do not appear to be connected to Wi-Fi or a wired network connection! Please connect to a Wi-Fi or wired connection.", comment: "")
        case .notReachable(let reason):
            return NSLocalizedString(reason, comment: "")
        case .connectionModeNotConfigured(let reason):
            return NSLocalizedString(reason, comment: "")
        case .noVPN(let reason):
            return String(format: NSLocalizedString("Unable to connect to the device via %@ VPN. Please make sure LocalDevVPN is enabled and running! Reason: %@", comment: ""), "LocalDev", reason)
        case .pairingFile(let proto, let reason):
            return String(format: NSLocalizedString("Invalid pairing file (%@ protocol): %@. Please use iloader to replace it.", comment: ""), proto.description, reason)
        case .createDebug:
            return createService(name: "debug")
        case .lookupApps:
            return getFromDevice(name: "installed apps")
        case .findApp:
            return getFromDevice(name: "path to the app")
        case .bundlePath:
            return getFromDevice(name: "bundle path")
        case .maxPacket:
            return setArgument(name: "max packet")
        case .workingDirectory:
            return setArgument(name: "working directory")
        case .argv:
            return setArgument(name: "argv")
        case .launchSuccess:
            return getFromDevice(name: "launch success")
        case .detach:
            return NSLocalizedString("Unable to detach from the app's process", comment: "")
        case .attach:
            return NSLocalizedString("Unable to attach to the app's process", comment: "")
        case .createInstproxy:
            return createService(name: "instproxy")
        case .createAfc:
            return createService(name: "AFC")
        case .rwAfc:
            return NSLocalizedString("AFC was unable to manage files on the device.", comment: "")
        case .installApp(let message):
            return NSLocalizedString("Unable to install the app: \(message)", comment: "")
        case .uninstallApp:
            return NSLocalizedString("Unable to uninstall the app", comment: "")
        case .createMisagent:
            return createService(name: "misagent")
        case .profileInstall:
            return NSLocalizedString("Unable to manage profiles on the device", comment: "")
        case .profileRemove:
            return NSLocalizedString("Unable to manage profiles on the device", comment: "")
        case .createLockdown:
            return NSLocalizedString("Unable to connect to lockdown", comment: "")
        case .createCoreDevice:
            return NSLocalizedString("Unable to connect to core device proxy", comment: "")
        case .createSoftwareTunnel:
            return NSLocalizedString("Unable to create software tunnel", comment: "")
        case .createRemoteServer:
            return NSLocalizedString("Unable to connect to remote server", comment: "")
        case .createProcessControl:
            return NSLocalizedString("Unable to connect to process control", comment: "")
        case .getLockdownValue:
            return NSLocalizedString("Unable to get value from lockdown", comment: "")
        case .connect:
            return NSLocalizedString("Unable to connect to TCP port", comment: "")
        case .close:
            return NSLocalizedString("Unable to close TCP port", comment: "")
        case .xpcHandshake:
            return NSLocalizedString("Unable to get services from XPC", comment: "")
        case .noService:
            return NSLocalizedString("Device did not contain service", comment: "")
        case .invalidProductVersion:
            return NSLocalizedString("Service version was in an unexpected format", comment: "")
        case .createFolder:
            return NSLocalizedString("Unable to create DDI folder", comment: "")
        case .downloadImage:
            return NSLocalizedString("Unable to download DDI", comment: "")
        case .imageLookup:
            return NSLocalizedString("Unable to lookup DDI images", comment: "")
        case .imageRead:
            return NSLocalizedString("Unable to read images to memory", comment: "")
        case .mount(let proto, let reason):
            return String(format: NSLocalizedString("Mount failed (%@ protocol): %@", comment: ""), proto.description, reason)
        case .restartAlreadyInProgressError:
            return NSLocalizedString("Restart already in progress", comment: "")
        case .invalidVPN:
            return NSLocalizedString("Invalid VPN configuration", comment: "")
        case .invalidPairing(let proto, let reason):
            return String(format: NSLocalizedString("Invalid pairing configuration (%@ protocol): %@", comment: ""), proto.description, reason)
        case .muxerNotListening:
            return NSLocalizedString("Usbmuxd server is not listening on the device", comment: "")
        }
    }

    fileprivate func createService(name: String) -> String {
        String(format: NSLocalizedString("Cannot start a %@ server on the device.", comment: ""), name)
    }

    fileprivate func getFromDevice(name: String) -> String {
        String(format: NSLocalizedString("Cannot fetch %@ from the device.", comment: ""), name)
    }

    fileprivate func setArgument(name: String) -> String {
        String(format: NSLocalizedString("Cannot set %@ on the device.", comment: ""), name)
    }
}

public enum MinimuxerWrapperError: Error, LocalizedError {
    case profileInstall
    case restartAlreadyInProgress
    case pairingFile
    
    public var errorDescription: String? {
        switch self {
        case .profileInstall:
            return NSLocalizedString("Unable to manage profiles on the device", comment: "")
        case .restartAlreadyInProgress:
            return NSLocalizedString("Restart already in progress", comment: "")
        case .pairingFile:
            return NSLocalizedString("Invalid pairing file. Your pairing file either didn't have a UDID, or it wasn't a valid plist. Please use iloader to replace it.", comment: "")
        }
    }

    public var failureReason: String? {
        return errorDescription
    }
}

extension Error {
    public var isMinimuxerNoConnection: Bool {
        if let minimuxerErr = self as? MinimuxerError,
           case .noConnection = minimuxerErr { return true }
        return false
    }
    public var isMinimuxerNotReachable: Bool {
        if let minimuxerErr = self as? MinimuxerError,
           case .notReachable = minimuxerErr { return true }
        return false
    }
    public var isMinimuxerNoVPN: Bool {
        if let minimuxerErr = self as? MinimuxerError,
           case .noVPN = minimuxerErr { return true }
        return false
    }
    public var isMinimuxerProfileInstall: Bool {
        if let minimuxerErr = self as? MinimuxerError,
           case .profileInstall = minimuxerErr { return true }
        return (self as? MinimuxerWrapperError) == .profileInstall
    }
    public var isMinimuxerPairingFile: Bool {
        if let minimuxerErr = self as? MinimuxerError,
           case .pairingFile = minimuxerErr { return true }
        return (self as? MinimuxerWrapperError) == .pairingFile
    }
    public var isMinimuxerRestartInProgress: Bool {
        if let minimuxerErr = self as? MinimuxerError,
           case .restartAlreadyInProgressError = minimuxerErr { return true }
        return (self as? MinimuxerWrapperError) == .restartAlreadyInProgress
    }
}

func minimuxerRestart() async throws {
    #if !targetEnvironment(simulator)
    try await Minimuxer.shared.restart()
    #endif
}

public struct MinimuxerPairedDevice: Codable, Sendable {
    public let name: String
    public let model: String
    public let udid: String
    public let pairingFilePath: String
    
    public init(name: String, model: String, udid: String, pairingFilePath: String) {
        self.name = name
        self.model = model
        self.udid = udid
        self.pairingFilePath = pairingFilePath
    }
}

@MainActor
public final class WirelessPairWrapper {
    public static let shared = WirelessPairWrapper()
    
    private init() {}
    
    public var onPinReceived: ((String) -> Void)? {
        get {
            #if !targetEnvironment(simulator)
            return Minimuxer.wirelessPair.onPinReceived
            #else
            return nil
            #endif
        }
        set {
            #if !targetEnvironment(simulator)
            Minimuxer.wirelessPair.onPinReceived = newValue
            #endif
        }
    }
    
    public var onReadyToPair: ((String, Int) -> Void)? {
        get {
            #if !targetEnvironment(simulator)
            return Minimuxer.wirelessPair.onReadyToPair
            #else
            return nil
            #endif
        }
        set {
            #if !targetEnvironment(simulator)
            Minimuxer.wirelessPair.onReadyToPair = newValue
            #endif
        }
    }
    
    public func start(
        outPath: String,
        completion: @escaping (Result<MinimuxerPairedDevice, Error>) -> Void
    ) {
        #if !targetEnvironment(simulator)
        Minimuxer.wirelessPair.start(outPath: outPath) { result in
            switch result {
            case .success(let device):
                completion(.success(MinimuxerPairedDevice(
                    name: device.name,
                    model: device.model,
                    udid: device.udid,
                    pairingFilePath: device.pairingFilePath
                )))
            case .failure(let error):
                completion(.failure(error))
            }
        }
        #else
        completion(.failure(MinimuxerWrapperError.pairingFile))
        #endif
    }
    
    public func stop() {
        #if !targetEnvironment(simulator)
        Minimuxer.wirelessPair.stop()
        #endif
    }
}

@MainActor
let wirelessPairing = WirelessPairWrapper.shared
