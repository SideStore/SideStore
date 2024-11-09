//
//  OperationError.swift
//  AltStore
//
//  Created by Riley Testut on 6/7/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import AltSign
import AltStoreCore
import minimuxer

extension OperationError
{
    enum Code: Int, ALTErrorCode, CaseIterable {
        typealias Error = OperationError

        // General
        case unknown = 1000
        case unknownResult
        case cancelled
        case timedOut
        case unableToConnectSideJIT
        case unableToRespondSideJITDevice
        case wrongSideJITIP
        case SideJITIssue // (error: String)
        case refreshsidejit
        case notAuthenticated
        case appNotFound
        case unknownUDID
        case invalidApp
        case invalidParameters
        case maximumAppIDLimitReached//((application: ALTApplication, requiredAppIDs: Int, availableAppIDs: Int, nextExpirationDate: Date)
        case noSources
        case openAppFailed//(name: String)
        case missingAppGroup
        case refreshAppFailed

        // Connection
        case noWiFi = 1200
        case tooNewError
        case anisetteV1Error//(message: String)
        case provisioningError//(result: String, message: String?)
        case anisetteV3Error//(message: String)

        case cacheClearError//(errors: [String])
    }

    static let unknownResult: OperationError = .init(code: .unknownResult)
    static let cancelled: OperationError = .init(code: .cancelled)
    static let timedOut: OperationError = .init(code: .timedOut)
    static let unableToConnectSideJIT: OperationError = .init(code: .unableToConnectSideJIT)
    static let unableToRespondSideJITDevice: OperationError = .init(code: .unableToRespondSideJITDevice)
    static let wrongSideJITIP: OperationError = .init(code: .wrongSideJITIP)
    static let notAuthenticated: OperationError = .init(code: .notAuthenticated)
    static let unknownUDID: OperationError = .init(code: .unknownUDID)
    static let invalidApp: OperationError = .init(code: .invalidApp)
    static let noSources: OperationError = .init(code: .noSources)
    static let missingAppGroup: OperationError = .init(code: .missingAppGroup)

    static let noWiFi: OperationError = .init(code: .noWiFi)
    static let tooNewError: OperationError = .init(code: .tooNewError)
    static let provisioningError: OperationError = .init(code: .provisioningError)
    static let anisetteV1Error: OperationError = .init(code: .anisetteV1Error)
    static let anisetteV3Error: OperationError = .init(code: .anisetteV3Error)

    static let cacheClearError: OperationError = .init(code: .cacheClearError)

    static func unknown(failureReason: String? = nil, file: String = #fileID, line: UInt = #line) -> OperationError {
        OperationError(code: .unknown, failureReason: failureReason, sourceFile: file, sourceLine: line)
    }

    static func appNotFound(name: String?) -> OperationError {
        OperationError(code: .appNotFound, appName: name)
    }

    static func openAppFailed(name: String?) -> OperationError {
        OperationError(code: .openAppFailed, appName: name)
    }
    
    static func SideJITIssue(error: String?) -> OperationError {
        var o = OperationError(code: .SideJITIssue)
        o.errorFailure = error
        return o
    }
    
    static func maximumAppIDLimitReached(appName: String, requiredAppIDs: Int, availableAppIDs: Int, expirationDate: Date) -> OperationError {
        OperationError(code: .maximumAppIDLimitReached, appName: appName, requiredAppIDs: requiredAppIDs, availableAppIDs: availableAppIDs, expirationDate: expirationDate)
    }

    static func provisioningError(result: String, message: String?) -> OperationError {
        var o = OperationError(code: .provisioningError, failureReason: result)
        o.errorTitle = message
        return o
    }

    static func cacheClearError(errors: [String]) -> OperationError {
        OperationError(code: .cacheClearError, failureReason: errors.joined(separator: "\n"))
    }

    static func anisetteV1Error(message: String) -> OperationError {
        OperationError(code: .anisetteV1Error, failureReason: message)
    }

    static func anisetteV3Error(message: String) -> OperationError {
        OperationError(code: .anisetteV3Error, failureReason: message)
    }

    static func refreshAppFailed(message: String) -> OperationError {
        OperationError(code: .refreshAppFailed, failureReason: message)
    }

    static func invalidParameters(_ message: String? = nil) -> OperationError {
        OperationError(code: .invalidParameters, failureReason: message)
    }
}


struct OperationError: ALTLocalizedError {

    let code: Code

    var errorTitle: String?
    var errorFailure: String?

    var appName: String?

    var requiredAppIDs: Int?
    var availableAppIDs: Int?
    var expirationDate: Date?

    var sourceFile: String?
    var sourceLine: UInt?

    private var _failureReason: String?

    private init(code: Code, failureReason: String? = nil,
                 appName: String? = nil, requiredAppIDs: Int? = nil, availableAppIDs: Int? = nil,
                 expirationDate: Date? = nil, sourceFile: String? = nil, sourceLine: UInt? = nil){
        self.code = code
        self._failureReason = failureReason

        self.appName = appName
        self.requiredAppIDs = requiredAppIDs
        self.availableAppIDs = availableAppIDs
        self.expirationDate = expirationDate
        self.sourceFile = sourceFile
        self.sourceLine = sourceLine
    }

    var errorFailureReason: String {
        switch self.code {
        case .unknown:
            var failureReason = self._failureReason ?? NSLocalizedString("An unknown error occurred.", comment: "")
            guard let sourceFile, let sourceLine else { return failureReason }
            failureReason += " (\(sourceFile) line \(sourceLine)"
            return failureReason
        case .unknownResult: return NSLocalizedString("The operation returned an unknown result.", comment: "")
        case .cancelled: return NSLocalizedString("The operation was cancelled.", comment: "")
        case .timedOut: return NSLocalizedString("The operation timed out.", comment: "")
        case .notAuthenticated: return NSLocalizedString("You are not signed in.", comment: "")
        case .unknownUDID: return NSLocalizedString("SideStore could not determine this device's UDID.", comment: "")
        case .invalidApp: return NSLocalizedString("The app is in an invalid format.", comment: "")
        case .maximumAppIDLimitReached: return NSLocalizedString("Cannot register more than 10 App IDs within a 7 day period.", comment: "")
        case .noSources: return NSLocalizedString("There are no SideStore sources.", comment: "")
        case .missingAppGroup: return NSLocalizedString("SideStore's shared app group could not be accessed.", comment: "")
        case .appNotFound:
            let appName = self.appName ?? NSLocalizedString("The app", comment: "")
            return String(format: NSLocalizedString("%@ could not be found.", comment: ""), appName)
        case .openAppFailed:
            let appName = self.appName ?? NSLocalizedString("The app", comment: "")
            return String(format: NSLocalizedString("SideStore was denied permission to launch %@.", comment: ""), appName)
        case .noWiFi: return NSLocalizedString("You do not appear to be connected to WiFi and/or the WireGuard VPN!\nSideStore will never be able to install or refresh applications without WiFi and the WireGuard VPN.", comment: "")
        case .tooNewError: return NSLocalizedString("iOS 17 has changed how JIT is enabled therefore SideStore cannot enable it without SideJITServer at this time, sorry for any inconvenience.\nWe will let everyone know once we have a solution!", comment: "")
        case .unableToConnectSideJIT: return NSLocalizedString("Unable to connect to SideJITServer Please check that you are on the Same Wi-Fi and your Firewall has been set correctly", comment: "")
        case .unableToRespondSideJITDevice: return NSLocalizedString("SideJITServer is unable to connect to your iDevice Please make sure you have paired your Device by doing 'SideJITServer -y' or try Refreshing SideJITServer from Settings", comment: "")
        case .wrongSideJITIP: return NSLocalizedString("Incorrect SideJITServer IP Please make sure that you are on the Samw Wifi as SideJITServer", comment: "")
        case .refreshsidejit: return NSLocalizedString("Unable to find App Please try Refreshing SideJITServer from Settings", comment: "")
        case .anisetteV1Error: return NSLocalizedString("An error occurred when getting anisette data from a V1 server: %@. Try using another anisette server.", comment: "")
        case .provisioningError: return NSLocalizedString("An error occurred when provisioning: %@ %@. Please try again. If the issue persists, report it on GitHub Issues!", comment: "")
        case .anisetteV3Error: return NSLocalizedString("An error occurred when getting anisette data from a V3 server: %@. Please try again. If the issue persists, report it on GitHub Issues!", comment: "")
        case .cacheClearError: return NSLocalizedString("An error occurred while clearing cache: %@", comment: "")
        case .SideJITIssue: return NSLocalizedString("An error occurred while using SideJIT: %@", comment: "")
            
        case .refreshAppFailed:
            let message = self._failureReason ?? ""
            return String(format: NSLocalizedString("Unable to refresh App\n%@", comment: ""), message)

        case .invalidParameters:
            let message = self._failureReason.map { ": \n\($0)" } ?? "."
            return String(format: NSLocalizedString("Invalid parameters%@", comment: ""), message)
        }
        
    }
    
    var recoverySuggestion: String? {
        switch self.code
        {
        case .noWiFi: return NSLocalizedString("Make sure the VPN is toggled on and you are connected to any WiFi network!", comment: "")
        case .maximumAppIDLimitReached:
            let baseMessage = NSLocalizedString("Delete sideloaded apps to free up App ID slots.", comment: "")
            guard let appName, let requiredAppIDs, let availableAppIDs, let expirationDate else { return baseMessage }
            var message: String

            if requiredAppIDs > 1
            {
                let availableText: String
                
                switch availableAppIDs
                {
                case 0: availableText = NSLocalizedString("none are available", comment: "")
                case 1: availableText = NSLocalizedString("only 1 is available", comment: "")
                default: availableText = String(format: NSLocalizedString("only %@ are available", comment: ""), NSNumber(value: availableAppIDs))
                }
                
                let prefixMessage = String(format: NSLocalizedString("%@ requires %@ App IDs, but %@.", comment: ""), appName, NSNumber(value: requiredAppIDs), availableText)
                message = prefixMessage + " " + baseMessage + "\n\n"
            }
            else
            {
                message = baseMessage + " "
            }

            let dateComponents = Calendar.current.dateComponents([.day, .hour, .minute], from: Date(), to: expirationDate)
            let dateFormatter = DateComponentsFormatter()
            dateFormatter.maximumUnitCount = 1
            dateFormatter.unitsStyle = .full

            let remainingTime = dateFormatter.string(from: dateComponents)!

            message += String(format: NSLocalizedString("You can register another App ID in %@.", comment: ""), remainingTime)

            return message
            
        default: return nil
        }
    }
}

extension MinimuxerError: LocalizedError {
    public var failureReason: String? {
        switch self {
        case .NoDevice:
            return NSLocalizedString("Cannot fetch the device from the muxer", comment: "")
        case .NoConnection:
            return NSLocalizedString("Unable to connect to the device, make sure Wireguard is enabled and you're connected to WiFi. This could mean an invalid pairing.", comment: "")
        case .PairingFile:
            return NSLocalizedString("Invalid pairing file. Your pairing file either didn't have a UDID, or it wasn't a valid plist. Please use jitterbugpair to generate it", comment: "")
            
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
            return NSLocalizedString("AFC was unable to manage files on the device. This usually means an invalid pairing.", comment: "")
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
