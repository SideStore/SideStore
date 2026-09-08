//
//  OperationError.swift
//  SideStore
//
//  Created by Magesh K on 3/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation

public enum OperationError: LocalizedError, CustomNSError, Sendable, Equatable {
    // General
    case unknown(failureReason: String? = nil, file: String = #fileID, line: UInt = #line)
    case unknownResult
    case timedOut
    case notAuthenticated
    case appNotFound(name: String? = nil)
    case unknownUDID
    case invalidApp
    case invalidParameters(String? = nil)
    case invalidOperationContext(String? = nil)
    case maximumAppIDLimitReached(appName: String, requiredAppIDs: Int, availableAppIDs: Int, expirationDate: Date)
    case noSources
    case noInstalledApps
    case openAppFailed(name: String? = nil)
    case missingAppGroup
    case forbidden(failureReason: String? = nil, file: String = #fileID, line: UInt = #line)
    case sourceNotAdded(name: String)
    case serverNotFound
    case connectionFailed
    case pledgeInactive(appName: String)

    // SideStore & Connectivity
    case unableToConnectSideJIT
    case unableToRespondSideJITDevice
    case SideJITIssue(error: String?)
    case provisioningError(result: String, message: String? = nil)
    case certificateRevoked(appName: String)
    case customCertificateRevoked(appName: String, activeTeam: String)
    case customCertificateExpired(appName: String, activeTeam: String)
    case certificateExpired(appName: String)
    case certificateChanged(appName: String)
    case cacheClearError(errors: [String])

    // Minimuxer & Device Connection
    case noConnection(reason: String? = nil)
    case noVPN(reason: String? = nil)
    case invalidVPN(reason: String? = nil)
    case noDevice(reason: String? = nil)
    case notReachable(reason: String)
    case invalidPairingFile(reason: String? = nil)
    case minimuxerNotStarted(reason: String? = nil)
    case pairingNotComplete(reason: String? = nil)

    // Packaging / Signing
    case missingAppBundle
    case missingInfoPlist
    case missingProvisioningProfile

    public static var cancelled: CancellationError { CancellationError() }

    public static func sourceNotAdded(_ source: Source, file: String = #fileID, line: UInt = #line) -> OperationError {
        .sourceNotAdded(name: source.name)
    }

    public var rawDescription: String {
        switch self {
        case .unknown(let failureReason, let file, let line):
            let base = failureReason ?? NSLocalizedString("An unknown error occurred.", comment: "")
            return String(format: NSLocalizedString("%@ (%@ line %d)", comment: ""), base, file, line)
        case .unknownResult:
            return NSLocalizedString("The operation returned an unknown result.", comment: "")
        case .timedOut:
            return NSLocalizedString("The operation timed out.", comment: "")
        case .notAuthenticated:
            return NSLocalizedString("You are not signed in.", comment: "")
        case .unknownUDID:
            return NSLocalizedString("SideStore could not determine this device's UDID. Please replace your pairing using iloader.", comment: "")
        case .invalidApp:
            return NSLocalizedString("The app is in an invalid format.", comment: "")
        case .invalidParameters(let msg):
            if let msg {
                return String(format: NSLocalizedString("Invalid parameters: \n%@", comment: ""), msg)
            }
            return NSLocalizedString("Invalid parameters.", comment: "")
        case .invalidOperationContext(let msg):
            if let msg {
                return String(format: NSLocalizedString("Invalid Operation Context: \n%@", comment: ""), msg)
            }
            return NSLocalizedString("Invalid Operation Context.", comment: "")
        case .maximumAppIDLimitReached:
            return NSLocalizedString("Cannot register more than 10 App IDs within a 7 day period.", comment: "")
        case .noSources:
            return NSLocalizedString("There are no SideStore sources.", comment: "")
        case .noInstalledApps:
            return NSLocalizedString("There are no active sideloaded apps to refresh.", comment: "")
        case .openAppFailed(let name):
            let app = name ?? NSLocalizedString("The app", comment: "")
            return String(format: NSLocalizedString("SideStore was denied permission to launch %@.", comment: ""), app)
        case .missingAppGroup:
            return NSLocalizedString("SideStore's shared app group could not be accessed.", comment: "")
        case .forbidden(let reason, _, _):
            return reason ?? NSLocalizedString("The operation is forbidden.", comment: "")
        case .sourceNotAdded(let name):
            return String(format: NSLocalizedString("The source “%@” is not added to SideStore.", comment: ""), name)
        case .appNotFound(let name):
            let app = name ?? NSLocalizedString("The app", comment: "")
            return String(format: NSLocalizedString("%@ could not be found.", comment: ""), app)
        case .serverNotFound:
            return NSLocalizedString("AltServer could not be found.", comment: "")
        case .connectionFailed:
            return NSLocalizedString("A connection to AltServer could not be established.", comment: "")
        case .pledgeInactive(let appName):
            return String(format: NSLocalizedString("Your pledge is no longer active. Please renew it to continue using %@ normally.", comment: ""), appName)
        case .unableToConnectSideJIT:
            return NSLocalizedString("Unable to connect to SideJITServer. Please check that you are on the same Wi-Fi of and your Firewall has been set correctly on your server.", comment: "")
        case .unableToRespondSideJITDevice:
            return NSLocalizedString("SideJITServer is unable to connect to your iDevice. Please make sure you have paired your iDevice by running 'SideJITServer -y', or try refreshing SideJITServer from Settings.", comment: "")
        case .SideJITIssue(let error):
            return String(format: NSLocalizedString("An error occurred while using SideJIT: %@", comment: ""), error ?? "")
        case .provisioningError(let result, let message):
            let combined = (message?.isEmpty ?? true) ? result : "\(result) \(message!)"
            let trimmed = combined.trimmingCharacters(in: CharacterSet(charactersIn: " ."))
            return String(format: NSLocalizedString("An error occurred while provisioning: %@. Please try again. If the issue persists, report it on GitHub Issues!", comment: ""), trimmed)
        case .certificateRevoked(let appName):
            return String(format: NSLocalizedString("The signing certificate used to install “%@” was revoked on the Apple Developer portal. Please re-sign or reinstall the app.", comment: ""), appName)
        case .customCertificateRevoked(_, let activeTeam):
            return String(format: NSLocalizedString("Your active custom/third-party signing certificate (Team: %@) was revoked on the Developer Portal.\n\nIf you did not intend to use a custom certificate, please reset it in Settings -> Advanced -> Certificates.", comment: ""), activeTeam)
        case .customCertificateExpired(_, let activeTeam):
            return String(format: NSLocalizedString("Your active custom/third-party signing certificate (Team: %@) has expired.\n\nIf you did not intend to use a custom certificate, please reset it in Settings -> Advanced -> Certificates.", comment: ""), activeTeam)
        case .certificateExpired(let appName):
            return String(format: NSLocalizedString("The signing certificate used to install “%@” has expired. Please re-sign or reinstall the app.", comment: ""), appName)
        case .certificateChanged(let appName):
            return String(format: NSLocalizedString("The signing certificate used to install “%@” differs from your active signing certificate. Please re-sign or reinstall the app.", comment: ""), appName)
        case .cacheClearError(let errors):
            return String(format: NSLocalizedString("An error occurred while clearing the cache: %@", comment: ""), errors.joined(separator: "\n"))
        case .noConnection(let reason):
            if let reason, !reason.isEmpty {
                return String(format: NSLocalizedString("Network Connection Error:\n%@\n\nPlease connect to Wi-Fi before attempting further operations.", comment: ""), reason)
            }
            return NSLocalizedString("You do not appear to be connected to Wi-Fi!\n\nPlease connect to a Wi-Fi before attempting futher operations", comment: "")
        case .noVPN(let reason), .invalidVPN(let reason):
            if let reason, !reason.isEmpty {
                return String(format: NSLocalizedString("VPN Connection Error:\n%@\n\nPlease make sure LocalDevVPN is connected and running properly.", comment: ""), reason)
            }
            return NSLocalizedString("You do not appear to be connected to VPN.\n\nPlease make sure LocalDevVPN is connected and running! If the issue persists, replace your pairing with iloader or try restarting the device.", comment: "")
        case .noDevice(let reason):
            if let reason, !reason.isEmpty {
                return String(format: NSLocalizedString("SideStore is unable to reach the device endpoint:\n%@\n\nPlease check your Connection Configuration in Settings.", comment: ""), reason)
            }
            return NSLocalizedString("SideStore is unable to reach the device endpoint.\n\nPlease check your Connection Configuration in Settings to ensure the IP and endpoint are correct.", comment: "")
        case .notReachable(let reason):
            return reason.isEmpty ? NSLocalizedString("Device is not reachable at the specified IP or Endpoint.", comment: "") : reason
        case .invalidPairingFile(let reason):
            if let reason, !reason.isEmpty {
                return String(format: NSLocalizedString("The current pairing file is invalid or missing. Reason: %@\n\nPlease make sure to input a valid pairing file! If the issue persists, replace your pairing with iloader.", comment: ""), reason)
            }
            return NSLocalizedString("The current pairing file is invalid or missing.\n\nPlease make sure to input a valid pairing file! If the issue persists, replace your pairing with iloader.", comment: "")
        case .minimuxerNotStarted:
            return NSLocalizedString("Minimuxer has not been started yet.\n\nPlease complete pairing or start minimuxer before performing operations.", comment: "")
        case .pairingNotComplete:
            return NSLocalizedString("Pairing Required:\nWithout a valid pairing file, SideStore operations cannot connect to your device. Please pair your device or import a valid pairing file.", comment: "")
        case .missingAppBundle:
            return NSLocalizedString("The app bundle could not be found.", comment: "")
        case .missingInfoPlist:
            return NSLocalizedString("The app's Info.plist could not be found.", comment: "")
        case .missingProvisioningProfile:
            return NSLocalizedString("A provisioning profile for the app could not be found.", comment: "")
        }
    }

    public var errorDescription: String? {
        return self.failureReason
    }

    public var failureReason: String? {
        return self.rawDescription
    }

    public var recoverySuggestion: String? {
        switch self {
        case .noConnection:
            return NSLocalizedString("Connect to a Wi-Fi network, Bridge or a Wired network connection!", comment: "")
        case .noVPN, .invalidVPN:
            return NSLocalizedString("Make sure LocalDevVPN is connected and running!", comment: "")
        case .invalidPairingFile:
            return NSLocalizedString("Import a valid mobiledevicepairing file.", comment: "")
        case .serverNotFound:
            return NSLocalizedString("Make sure you're on the same Wi-Fi network as a computer running AltServer, or try connecting this device to your computer via USB.", comment: "")
        case .maximumAppIDLimitReached(let appName, let requiredAppIDs, let availableAppIDs, let expirationDate):
            let baseMessage = NSLocalizedString("Delete sideloaded apps to free up App ID slots.", comment: "")
            let availableText: String
            switch availableAppIDs {
            case 0: availableText = NSLocalizedString("none are available", comment: "")
            case 1: availableText = NSLocalizedString("only 1 is available", comment: "")
            default: availableText = String(format: NSLocalizedString("only %@ are available", comment: ""), NSNumber(value: availableAppIDs))
            }

            var message = ""
            if requiredAppIDs > 1 {
                let prefixMessage = String(format: NSLocalizedString("%@ requires %@ App IDs, but %@.", comment: ""), appName, NSNumber(value: requiredAppIDs), availableText)
                message = prefixMessage + " " + baseMessage + "\n\n"
            } else {
                message = baseMessage + " "
            }

            let dateComponents = Calendar.current.dateComponents([.day, .hour, .minute], from: Date(), to: expirationDate)
            let dateFormatter = DateComponentsFormatter()
            dateFormatter.maximumUnitCount = 1
            dateFormatter.unitsStyle = .full

            if let remainingTime = dateFormatter.string(from: dateComponents) {
                message += String(format: NSLocalizedString("You can register another App ID in %@.", comment: ""), remainingTime)
            }
            return message
        default:
            return nil
        }
    }
}
