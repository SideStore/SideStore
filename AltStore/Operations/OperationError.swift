//
//  OperationError.swift
//  AltStore
//
//  Created by Riley Testut on 6/7/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import AltSign
import minimuxer
import AltStoreCore

extension OperationError
{
    enum Code: Int, ALTErrorCode, CaseIterable
    {
        typealias Error = OperationError
        
        case unknown
        case unknownResult
        case cancelled
        case timedOut
        case notAuthenticated
        case appNotFound
        case unknownUDID
        case invalidApp
        case invalidParameters
        case maximumAppIDLimitReached
        case noSources
        case openAppFailed
        case missingAppGroup
    }
    
    static let unknown: OperationError = .init(code: .unknown)
    static let unknownResult: OperationError = .init(code: .unknownResult)
    static let cancelled: OperationError = .init(code: .cancelled)
    static let timedOut: OperationError = .init(code: .timedOut)
    static let notAuthenticated: OperationError = .init(code: .notAuthenticated)
    static let unknownUDID: OperationError = .init(code: .unknownUDID)
    static let invalidApp: OperationError = .init(code: .invalidApp)
    static let invalidParameters: OperationError = .init(code: .invalidParameters)
    static let noSources: OperationError = .init(code: .noSources)
    static let missingAppGroup: OperationError = .init(code: .missingAppGroup)
    
    static func appNotFound(name: String?) -> OperationError { OperationError(code: .appNotFound, appName: name) }
    static func openAppFailed(name: String) -> OperationError { OperationError(code: .openAppFailed, appName: name) }
    
    static func maximumAppIDLimitReached(appName: String, requiredAppIDs: Int, availableAppIDs: Int, expirationDate: Date) -> OperationError {
        OperationError(code: .maximumAppIDLimitReached, appName: appName, requiredAppIDs: requiredAppIDs, availableAppIDs: availableAppIDs, expirationDate: expirationDate)
    }
}

struct OperationError: ALTLocalizedError
{
    let code: Code
    
    var errorTitle: String?
    var errorFailure: String?
    
    var appName: String?
    var requiredAppIDs: Int?
    var availableAppIDs: Int?
    var expirationDate: Date?
    
    private init(code: Code, appName: String? = nil, requiredAppIDs: Int? = nil, availableAppIDs: Int? = nil, expirationDate: Date? = nil)
    {
        self.code = code
        self.appName = appName
        self.requiredAppIDs = requiredAppIDs
        self.availableAppIDs = availableAppIDs
        self.expirationDate = expirationDate
    }
    
    case anisetteV1Error(message: String)
    case provisioningError(result: String, message: String?)
    case anisetteV3Error(message: String)
    
    var errorFailureReason: String {
        switch self.code
        {
        case .unknown: return NSLocalizedString("An unknown error occured.", comment: "")
        case .unknownResult: return NSLocalizedString("The operation returned an unknown result.", comment: "")
        case .cancelled: return NSLocalizedString("The operation was cancelled.", comment: "")
        case .timedOut: return NSLocalizedString("The operation timed out.", comment: "")
        case .notAuthenticated: return NSLocalizedString("You are not signed in.", comment: "")
        case .appNotFound: return NSLocalizedString("App not found.", comment: "")
        case .unknownUDID: return NSLocalizedString("Unknown device UDID.", comment: "")
        case .invalidApp: return NSLocalizedString("The app is invalid.", comment: "")
        case .invalidParameters: return NSLocalizedString("Invalid parameters.", comment: "")
        case .noSources: return NSLocalizedString("There are no AltStore sources.", comment: "")
        case .openAppFailed:
            let appName = self.appName ?? NSLocalizedString("the app", comment: "")
            return String(format: NSLocalizedString("AltStore was denied permission to launch %@.", comment: ""), appName)
            
        case .missingAppGroup: return NSLocalizedString("AltStore's shared app group could not be found.", comment: "")
        case .maximumAppIDLimitReached: return NSLocalizedString("Cannot register more than 10 App IDs.", comment: "")
        case .anisetteV1Error(let message): return String(format: NSLocalizedString("An error occurred when getting anisette data from a V1 server: %@. Try using another anisette server.", comment: ""), message)
        case .provisioningError(let result, let message): return String(format: NSLocalizedString("An error occurred when provisioning: %@%@. Please try again. If the issue persists, report it on GitHub Issues!", comment: ""), result, message != nil ? (" (" + message! + ")") : "")
        case .anisetteV3Error(let message): return String(format: NSLocalizedString("An error occurred when getting anisette data from a V3 server: %@. Please try again. If the issue persists, report it on GitHub Issues!", comment: ""), message)
        }
    }
    
    var recoverySuggestion: String? {
        switch self.code
        {
        case .maximumAppIDLimitReached:
            let baseMessage = NSLocalizedString("Delete sideloaded apps to free up App ID slots.", comment: "")
            guard let appName = self.appName, let requiredAppIDs = self.requiredAppIDs, let availableAppIDs = self.availableAppIDs, let date = self.expirationDate else { return baseMessage }
            
            let message: String
            
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
                message = prefixMessage + " " + baseMessage
            }
            else
            {
                let dateComponents = Calendar.current.dateComponents([.day, .hour, .minute], from: Date(), to: date)
                
                let dateComponentsFormatter = DateComponentsFormatter()
                dateComponentsFormatter.maximumUnitCount = 1
                dateComponentsFormatter.unitsStyle = .full
                
                let remainingTime = dateComponentsFormatter.string(from: dateComponents)!
                
                let remainingTimeMessage = String(format: NSLocalizedString("You can register another App ID in %@.", comment: ""), remainingTime)
                message = baseMessage + " " + remainingTimeMessage
            }
            
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
            return NSLocalizedString("Unable to connect to the device, make sure Wireguard is enabled and you're connected to WiFi", comment: "")
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
            return NSLocalizedString("AFC was unable to manage files on the device", comment: "")
        case .InstallApp:
            return NSLocalizedString("Unable to install the app from the staging directory", comment: "")
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
