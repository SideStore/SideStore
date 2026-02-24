//
//  MinimuxerWrapper.swift
//
//  Created by Magesh K on 22/02/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
private import minimuxer

var isMinimuxerReady: Bool {
    #if targetEnvironment(simulator)
    print("isMinimuxerReady property is always true on simulator")
    return true
    #else
    return minimuxer.ready()
    #endif
}

func minimuxerStartWithLogger(_ pairingFile: String,_ logPath: String,_ loggingEnabled: Bool) throws {
    #if targetEnvironment(simulator)
    print("minimuxerStartWithLogger(\(pairingFile), \(logPath), \(loggingEnabled) is no-op on simulator")
    #else
    try minimuxer.startWithLogger(pairingFile, logPath, loggingEnabled)
    #endif
}

func targetMinimuxerAddress() {
    #if targetEnvironment(simulator)
    print("targetMinimuxerAddress() is no-op on simulator")
    #else
    minimuxer.target_minimuxer_address()
    #endif
}

func installProvisioningProfiles(_ profileData: Data) throws {
    #if targetEnvironment(simulator)
    print("installProvisioningProfiles(\(profileData)) is no-op on simulator")
    #else
    try minimuxer.install_provisioning_profile(profileData.toRustByteSlice().forRust())
    #endif
}


func removeApp(_ bundleId: String) throws {
    #if targetEnvironment(simulator)
    print("removeApp(\(bundleId)) is no-op on simulator")
    #else
    try minimuxer.remove_app(bundleId)
    #endif
}


func yeetAppAFC(_ bundleId: String, _ rawBytes: Data) throws {
    #if targetEnvironment(simulator)
    print("yeetAppAFC(\(bundleId), \(rawBytes)) is no-op on simulator")
    #else
    let slice = rawBytes.toRustByteSlice()
    try minimuxer.yeet_app_afc(bundleId, slice.forRust())
    #endif
}


func installIPA(_ bundleId: String) throws {
    #if targetEnvironment(simulator)
    print("installIPA(\(bundleId)) is no-op on simulator")
    #else
    try minimuxer.install_ipa(bundleId)
    #endif
}


func fetchUDID() -> String? {
    #if targetEnvironment(simulator)
    print("fetchUDID() is no-op on simulator")
    return "XXXXX-XXXX-XXXXX-XXXX"
    #else
    return minimuxer.fetch_udid()?.toString()
    #endif
}



extension MinimuxerError: @retroactive LocalizedError {
    public var failureReason: String? {
        switch self {
        case .NoDevice:
            return NSLocalizedString("Cannot fetch the device from the muxer", comment: "")
        case .NoConnection:
            return NSLocalizedString("Unable to connect to the device, make sure LocalDevVPN is enabled and you're connected to Wi-Fi. This could mean an invalid pairing.", comment: "")
        case .PairingFile:
            return NSLocalizedString("Invalid pairing file. Your pairing file either didn't have a UDID, or it wasn't a valid plist. Please use iloader to replace it.", comment: "")
            
        case .CreateDebug:
            return self.createService(name: "debug")
        case .LookupApps:
            return self.getFromDevice(name: "installed apps")
        case .FindApp:
            return self.getFromDevice(name: "path to the app")
        case .BundlePath:
            return self.getFromDevice(name: "bundle path")
        case .MaxPacket:
            return self.setArgument(name: "max packet")
        case .WorkingDirectory:
            return self.setArgument(name: "working directory")
        case .Argv:
            return self.setArgument(name: "argv")
        case .LaunchSuccess:
            return self.getFromDevice(name: "launch success")
        case .Detach:
            return NSLocalizedString("Unable to detach from the app's process", comment: "")
        case .Attach:
            return NSLocalizedString("Unable to attach to the app's process", comment: "")
            
        case .CreateInstproxy:
            return self.createService(name: "instproxy")
        case .CreateAfc:
            return self.createService(name: "AFC")
        case .RwAfc:
            return NSLocalizedString("AFC was unable to manage files on the device. Ensure Wi-Fi and LocalDevVPN are connected. If they both are, replace your pairing using iloader.", comment: "")
        case .InstallApp(let message):
            return NSLocalizedString("Unable to install the app: \(message.toString())", comment: "")
        case .UninstallApp:
            return NSLocalizedString("Unable to uninstall the app", comment: "")

        case .CreateMisagent:
            return self.createService(name: "misagent")
        case .ProfileInstall:
            return NSLocalizedString("Unable to manage profiles on the device", comment: "")
        case .ProfileRemove:
            return NSLocalizedString("Unable to manage profiles on the device", comment: "")
        case .CreateLockdown:
            return NSLocalizedString("Unable to connect to lockdown", comment: "")
        case .CreateCoreDevice:
            return NSLocalizedString("Unable to connect to core device proxy", comment: "")
        case .CreateSoftwareTunnel:
            return NSLocalizedString("Unable to create software tunnel", comment: "")
        case .CreateRemoteServer:
            return NSLocalizedString("Unable to connect to remote server", comment: "")
        case .CreateProcessControl:
            return NSLocalizedString("Unable to connect to process control", comment: "")
        case .GetLockdownValue:
            return NSLocalizedString("Unable to get value from lockdown", comment: "")
        case .Connect:
            return NSLocalizedString("Unable to connect to TCP port", comment: "")
        case .Close:
            return NSLocalizedString("Unable to close TCP port", comment: "")
        case .XpcHandshake:
            return NSLocalizedString("Unable to get services from XPC", comment: "")
        case .NoService:
            return NSLocalizedString("Device did not contain service", comment: "")
        case .InvalidProductVersion:
            return NSLocalizedString("Service version was in an unexpected format", comment: "")
        case .CreateFolder:
            return NSLocalizedString("Unable to create DDI folder", comment: "")
        case .DownloadImage:
            return NSLocalizedString("Unable to download DDI", comment: "")
        case .ImageLookup:
            return NSLocalizedString("Unable to lookup DDI images", comment: "")
        case .ImageRead:
            return NSLocalizedString("Unable to read images to memory", comment: "")
        case .Mount:
            return NSLocalizedString("Mount failed", comment: "")
        }
    }
    
    fileprivate func createService(name: String) -> String {
        return String(format: NSLocalizedString("Cannot start a %@ server on the device.", comment: ""), name)
    }
    
    fileprivate func getFromDevice(name: String) -> String {
        return String(format: NSLocalizedString("Cannot fetch %@ from the device.", comment: ""), name)
    }
    
    fileprivate func setArgument(name: String) -> String {
        return String(format: NSLocalizedString("Cannot set %@ on the device.", comment: ""), name)
    }
}
