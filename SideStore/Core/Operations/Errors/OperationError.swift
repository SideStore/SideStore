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
    case certificateExpired(appName: String)
    case certificateRevoked(appName: String)
    case customCertificateExpired(appName: String, activeTeam: String)
    case customCertificateRevoked(appName: String, activeTeam: String)
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
        case .certificateExpired(let appName):
            return "The signing certificate used to install “\(appName)” has expired. Please re-sign or reinstall the app."
        case .certificateRevoked(let appName):
            return "The signing certificate used to install “\(appName)” was revoked on the Apple Developer portal. Please re-sign or reinstall the app."
        case .customCertificateExpired(_, let activeTeam):
            return "Your active custom/third-party signing certificate (Team: \(activeTeam)) has expired.\n\nIf you did not intend to use a custom certificate, please reset it in Settings -> Advanced -> Certificates."
        case .customCertificateRevoked(_, let activeTeam):
            return "Your active custom/third-party signing certificate (Team: \(activeTeam)) was revoked on the Developer Portal.\n\nIf you did not intend to use a custom certificate, please reset it in Settings -> Advanced -> Certificates."
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
        return NSLocalizedString(self.rawDescription, comment: "")
    }

    public var recoverySuggestion: String? {
        switch self {
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
