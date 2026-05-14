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

extension OperationError
{
    enum Code: Int, ALTErrorCode, CaseIterable {
        typealias Error = OperationError
        
        // General
        case unknown = 1000
        case unknownResult = 1001
//        case cancelled = 1002
        case timedOut = 1003
        case notAuthenticated = 1004
        case appNotFound = 1005
        case unknownUDID = 1006
        case invalidApp = 1007
        case invalidParameters = 1008
        case maximumAppIDLimitReached = 1009
        case noSources = 1010
        case openAppFailed = 1011
        case missingAppGroup = 1012
        case forbidden = 1013
        case sourceNotAdded = 1014


        // Connection
        
        /* Connection */
        case serverNotFound = 1200
        case connectionFailed = 1201
        case connectionDropped = 1202
        
        /* Pledges */
        case pledgeRequired = 1401
        case pledgeInactive = 1402

        /* SideStore Only */
        case unableToConnectSideJIT
        case unableToRespondSideJITDevice
        case wrongSideJITIP
        case SideJITIssue // (error: String)
        case refreshsidejit
        case refreshAppFailed
        case tooNewError
        case anisetteV1Error//(message: String)
        case provisioningError//(result: String, message: String?)
        case anisetteV3Error//(message: String)
        case cacheClearError//(errors: [String])
        case noWiFi
        
        case invalidOperationContext
    }
    
    static var cancelled: CancellationError { CancellationError() }
    
    static let unknownResult: OperationError = .init(code: .unknownResult)
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
    static let domain = OperationError(code: .unknown)._domain
    
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
    
    static func invalidOperationContext(_ message: String? = nil) -> OperationError {
        OperationError(code: .invalidOperationContext, failureReason: message)
    }
    
    static func forbidden(failureReason: String? = nil, file: String = #fileID, line: UInt = #line) -> OperationError {
        OperationError(code: .forbidden, failureReason: failureReason, sourceFile: file, sourceLine: line)
    }
    
    static func sourceNotAdded(@Managed _ source: Source, file: String = #fileID, line: UInt = #line) -> OperationError {
        OperationError(code: .sourceNotAdded, sourceName: $source.name, sourceFile: file, sourceLine: line)
    }
    
    static func pledgeRequired(appName: String, file: String = #fileID, line: UInt = #line) -> OperationError {
        OperationError(code: .pledgeRequired, appName: appName, sourceFile: file, sourceLine: line)
    }
    
    static func pledgeInactive(appName: String, file: String = #fileID, line: UInt = #line) -> OperationError {
        OperationError(code: .pledgeInactive, appName: appName, sourceFile: file, sourceLine: line)
    }
}


struct OperationError: ALTLocalizedError {

    let code: Code

    var errorTitle: String?
    var errorFailure: String?
    
    @UserInfoValue
    var appName: String?
    
    @UserInfoValue
    var sourceName: String?
    
    var requiredAppIDs: Int?
    var availableAppIDs: Int?
    var expirationDate: Date?

    var sourceFile: String?
    var sourceLine: UInt?

    private var _failureReason: String?

    private init(code: Code, failureReason: String? = nil,
                 appName: String? = nil, sourceName: String? = nil, requiredAppIDs: Int? = nil,
                 availableAppIDs: Int? = nil, expirationDate: Date? = nil, sourceFile: String? = nil, sourceLine: UInt? = nil){
        self.code = code
        self._failureReason = failureReason

        self.appName = appName
        self.sourceName = sourceName
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
        case .timedOut: return NSLocalizedString("The operation timed out.", comment: "")
        case .notAuthenticated: return NSLocalizedString("You are not signed in.", comment: "")
        case .unknownUDID: return NSLocalizedString("SideStore could not determine this device's UDID. Please replace your pairing using iloader.", comment: "")
        case .invalidApp: return NSLocalizedString("The app is in an invalid format.", comment: "")
        case .maximumAppIDLimitReached: return NSLocalizedString("Cannot register more than 10 App IDs within a 7 day period.", comment: "")
        case .noSources: return NSLocalizedString("There are no SideStore sources.", comment: "")
        case .missingAppGroup: return NSLocalizedString("SideStore's shared app group could not be accessed.", comment: "")
        case .forbidden:
            guard let failureReason = self._failureReason else { return NSLocalizedString("The operation is forbidden.", comment: "") }
            return failureReason
            
        case .sourceNotAdded:
            let sourceName = self.sourceName.map { String(format: NSLocalizedString("The source “%@”", comment: ""), $0) } ?? NSLocalizedString("The source", comment: "")
            return String(format: NSLocalizedString("%@ is not added to SideStore.", comment: ""), sourceName)

        case .appNotFound:
            let appName = self.appName ?? NSLocalizedString("The app", comment: "")
            return String(format: NSLocalizedString("%@ could not be found.", comment: ""), appName)
        case .openAppFailed:
            let appName = self.appName ?? NSLocalizedString("The app", comment: "")
            return String(format: NSLocalizedString("SideStore was denied permission to launch %@.", comment: ""), appName)
        case .noWiFi: return NSLocalizedString("You do not appear to be connected to Wi-Fi and/or LocalDevVPN!\nSideStore cannot install or refresh applications without Wi-Fi and LocalDevVPN. If both are connected, replace your pairing with iloader.", comment: "")
        case .tooNewError: return NSLocalizedString("iOS 17.0-17.3.1 changed how JIT is enabled so SideStore cannot enable JIT without SideJITServer on these versions, sorry for any inconvenience.", comment: "")
        case .unableToConnectSideJIT: return NSLocalizedString("Unable to connect to SideJITServer. Please check that you are on the same Wi-Fi of and your Firewall has been set correctly on your server.", comment: "")
        case .unableToRespondSideJITDevice: return NSLocalizedString("SideJITServer is unable to connect to your iDevice. Please make sure you have paired your iDevice by running 'SideJITServer -y', or try refreshing SideJITServer from Settings.", comment: "")
        case .wrongSideJITIP: return NSLocalizedString("Incorrect SideJITServer IP. Please make sure that you are on the same Wi-Fi as SideJITServer", comment: "")
        case .refreshsidejit: return NSLocalizedString("Unable to find app; Please try refreshing SideJITServer from Settings.", comment: "")
        case .anisetteV1Error: return NSLocalizedString("An error occurred while getting anisette data from a V1 server: %@. Try using another anisette server.", comment: "")
        case .provisioningError: return NSLocalizedString("An error occurred while provisioning: %@ %@. Please try again. If the issue persists, report it on GitHub Issues!", comment: "")
        case .anisetteV3Error: return NSLocalizedString("An error occurred while getting anisette data from a V3 server: %@. Please try again. If the issue persists, report it on GitHub Issues!", comment: "")
        case .cacheClearError: return NSLocalizedString("An error occurred while clearing the cache: %@", comment: "")
        case .SideJITIssue: return NSLocalizedString("An error occurred while using SideJIT: %@", comment: "")
            
        case .refreshAppFailed:
            let message = self._failureReason ?? ""
            return String(format: NSLocalizedString("Unable to refresh App\n%@", comment: ""), message)

        case .invalidParameters:
            let message = self._failureReason.map { ": \n\($0)" } ?? "."
            return String(format: NSLocalizedString("Invalid parameters%@", comment: ""), message)
        case .invalidOperationContext:
            let message = self._failureReason.map { ": \n\($0)" } ?? "."
            return String(format: NSLocalizedString("Invalid Operation Context%@", comment: ""), message)
        case .serverNotFound: return NSLocalizedString("AltServer could not be found.", comment: "")
        case .connectionFailed: return NSLocalizedString("A connection to AltServer could not be established.", comment: "")
        case .connectionDropped: return NSLocalizedString("The connection to AltServer was dropped.", comment: "")
            
        case .pledgeRequired:
            let appName = self.appName ?? NSLocalizedString("This app", comment: "")
            return String(format: NSLocalizedString("%@ requires an active pledge in order to be installed.", comment: ""), appName)
            
        case .pledgeInactive:
            let appName = self.appName ?? NSLocalizedString("this app", comment: "")
            return String(format: NSLocalizedString("Your pledge is no longer active. Please renew it to continue using %@ normally.", comment: ""), appName)
        }
        
    }
    
    var recoverySuggestion: String? {
        switch self.code
        {
        case .noWiFi: return NSLocalizedString("Make sure LocalDevVPN is connected and that you are connected to any Wi-Fi network!", comment: "")
        case .serverNotFound: return NSLocalizedString("Make sure you're on the same Wi-Fi network as a computer running AltServer, or try connecting this device to your computer via USB.", comment: "")
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
