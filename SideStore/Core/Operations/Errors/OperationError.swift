//
//  OperationError.swift
//  SideStore
//
//  Created by Magesh K on 3/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation

public enum OperationError: LocalizedError, CustomNSError, Sendable, Equatable {
    case noInstalledApps
    case noSources
    case notAuthenticated
    case timedOut
    case unableToConnectSideJIT
    case unableToRespondSideJITDevice
    case unknownResult

    case cacheClearError(errors: [String])
    case certificateExpired(appName: String, context: CertificateValidationContext? = nil)
    case certificateRevoked(appName: String, context: CertificateValidationContext? = nil)
    case customCertificateExpired(appName: String, activeTeam: String, context: CertificateValidationContext? = nil)
    case customCertificateRevoked(appName: String, activeTeam: String, context: CertificateValidationContext? = nil)
    case forbidden(failureReason: String, file: String = #fileID, line: UInt = #line)
    case invalidApp(reason: String)
    case invalidPairingFile(reason: String)
    case invalidParameters(String)
    case invalidResponse(reason: String)
    case invalidVPN(reason: String)
    case minimuxerNotStarted(reason: String)
    case missingAppBundle(reason: String)
    case missingAppGroup(name: String)
    case missingInfoPlist(reason: String)
    case missingProvisioningProfile(reason: String)
    case missingUpdate(appName: String)
    case noConnection(reason: String)
    case noDevice(reason: String)
    case noVPN(reason: String)
    case notReachable(reason: String)
    case openAppFailed(name: String)
    case pairingNotComplete(reason: String)
    case pledgeInactive(appName: String)
    case SideJITIssue(error: String)
    case unknownUDID(reason: String)

    public static var cancelled: CancellationError { CancellationError() }

    public var rawDescription: String {
        switch self {
        case .noInstalledApps:
            return "There are no active sideloaded apps to refresh."
        case .noSources:
            return "There are no SideStore sources."
        case .notAuthenticated:
            return "You are not signed in."
        case .timedOut:
            return "The operation timed out."
        case .unableToConnectSideJIT:
            return "Unable to connect to SideJITServer. Please check that you are on the same Wi-Fi of and your Firewall has been set correctly on your server."
        case .unableToRespondSideJITDevice:
            return "SideJITServer is unable to connect to your iDevice. Please make sure you have paired your iDevice by running 'SideJITServer -y', or try refreshing SideJITServer from Settings."
        case .unknownResult:
            return "The operation returned an unknown result."

        case .cacheClearError(let errors):
            return "An error occurred while clearing the cache: \(errors.joined(separator: "\n"))"
        case .certificateExpired(let appName, let context):
            return context?.failureReason(appName: appName, expired: true) ?? String(format: NSLocalizedString("The certificate in the existing signature of “%@” has expired.", comment: "Existing app signature failure"), appName)
        case .certificateRevoked(let appName, let context):
            return context?.failureReason(appName: appName, expired: false) ?? String(format: NSLocalizedString("The certificate in the existing signature of “%@” has been revoked.", comment: "Existing app signature failure"), appName)
        case .customCertificateExpired(let appName, _, let context):
            return context?.failureReason(appName: appName, expired: true) ?? NSLocalizedString("The custom signing certificate has expired.", comment: "Custom certificate failure")
        case .customCertificateRevoked(let appName, _, let context):
            return context?.failureReason(appName: appName, expired: false) ?? NSLocalizedString("The custom signing certificate has been revoked.", comment: "Custom certificate failure")
        case .forbidden(let reason, _, _):
            return reason
        case .invalidApp(let reason):
            return "The app is in an invalid format: \(reason)"
        case .invalidPairingFile(let reason):
            return "The current pairing file is invalid or missing. Reason: \(reason)\n\nPlease make sure to input a valid pairing file! If the issue persists, replace your pairing with iloader."
        case .invalidParameters(let msg):
            return "Invalid parameters: \n\(msg)"
        case .invalidResponse(let reason):
            return "Invalid server response: \(reason)"
        case .invalidVPN(let reason):
            return "VPN Connection Error:\n\(reason)\n\nPlease make sure LocalDevVPN is connected and running properly."
        case .minimuxerNotStarted(let reason):
            return "Minimuxer has not been started yet: \(reason)\n\nPlease complete pairing or start minimuxer before performing operations."
        case .missingAppBundle(let reason):
            return "The app bundle could not be found: \(reason)"
        case .missingAppGroup(let name):
            return "SideStore's shared app group “\(name)” could not be accessed."
        case .missingInfoPlist(let reason):
            return "The app's Info.plist could not be found: \(reason)"
        case .missingProvisioningProfile(let reason):
            return "A provisioning profile for the app could not be found: \(reason)"
        case .missingUpdate(let appName):
            return "No supported update could be found for “\(appName)”."
        case .noConnection(let reason):
            return "Network Connection Error:\n\(reason)\n\nPlease connect to Wi-Fi before attempting further operations."
        case .noDevice(let reason):
            return "SideStore is unable to reach the device endpoint:\n\(reason)\n\nPlease check your Connection Configuration in Settings."
        case .noVPN(let reason):
            return "VPN Connection Error:\n\(reason)\n\nPlease make sure LocalDevVPN is connected and running properly."
        case .notReachable(let reason):
            return reason.isEmpty ? "Device is not reachable at the specified IP or Endpoint." : reason
        case .openAppFailed(let name):
            return "SideStore was denied permission to launch \(name)."
        case .pairingNotComplete(let reason):
            return "Pairing Required: \(reason)\n\nWithout a valid pairing file, SideStore operations cannot connect to your device. Please pair your device or import a valid pairing file."
        case .pledgeInactive(let appName):
            return "Your pledge is no longer active. Please renew it to continue using \(appName) normally."
        case .SideJITIssue(let error):
            return "An error occurred while using SideJIT: \(error)"
        case .unknownUDID(let reason):
            return "SideStore could not determine this device's UDID: \(reason)\n\nPlease replace your pairing using iloader."
        }
    }

    public var errorDescription: String? {
        return self.failureReason
    }

    public var failureReason: String? {
        // Certificate messages use static format keys before substituting the app name.
        switch self {
        case .certificateExpired, .certificateRevoked, .customCertificateExpired, .customCertificateRevoked:
            return self.rawDescription
        default:
            return NSLocalizedString(self.rawDescription, comment: "")
        }
    }

    private var certificateContext: CertificateValidationContext? {
        switch self {
        case .certificateExpired(_, let context), .certificateRevoked(_, let context),
             .customCertificateExpired(_, _, let context), .customCertificateRevoked(_, _, let context):
            return context
        default:
            return nil
        }
    }

    public var errorUserInfo: [String: Any] {
        // CustomNSError needs explicit localized values for the certificate error to survive
        // NSError bridging and LoggedError persistence. Leave unrelated error cases unchanged.
        switch self {
        case .certificateExpired, .certificateRevoked, .customCertificateExpired, .customCertificateRevoked:
            break
        default:
            return [:]
        }
        var info: [String: Any] = [:]
        info[NSLocalizedDescriptionKey] = errorDescription
        info[NSLocalizedFailureReasonErrorKey] = failureReason
        info[NSLocalizedRecoverySuggestionErrorKey] = recoverySuggestion
        if let context = certificateContext {
            info[CertificateValidationContext.purposeErrorKey] = context.purpose.rawValue
            var details = context.diagnosticDetails
            switch self {
            case .certificateExpired, .customCertificateExpired:
                details += "\ncertificateValidationStatus: expired"
            case .certificateRevoked, .customCertificateRevoked:
                details += "\ncertificateValidationStatus: revoked"
            default:
                break
            }
            switch self {
            case .customCertificateExpired(_, let team, _), .customCertificateRevoked(_, let team, _):
                details += "\ncheckedCertificateCustomTeam: \(team)"
            default:
                break
            }
            info[NSDebugDescriptionErrorKey] = details
        }
        return info
    }

    public var recoverySuggestion: String? {
        switch self {
        case .certificateExpired(_, let context), .certificateRevoked(_, let context):
            return context?.recoverySuggestion ?? CertificateValidationContext.dataWarning + "\n\n" + CertificateValidationContext.existingSignatureRecovery
        case .customCertificateExpired(_, _, let context), .customCertificateRevoked(_, _, let context):
            return context?.recoverySuggestion ?? CertificateValidationContext.dataWarning + "\n\n" + CertificateValidationContext.certificateManagement
        case .invalidPairingFile:
            return NSLocalizedString("Import a valid mobiledevicepairing file.", comment: "")
        case .invalidVPN, .noVPN:
            return NSLocalizedString("Make sure LocalDevVPN is connected and running!", comment: "")
        case .noConnection:
            return NSLocalizedString("Connect to a Wi-Fi network, Bridge or a Wired network connection!", comment: "")
        default:
            return nil
        }
    }
}
