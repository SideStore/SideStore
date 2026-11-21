//
//  OperationError.swift
//  SideStore
//
//  Created by Magesh K on 3/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import SideSign

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
    case anisetteServerUnavailable(attempted: Int, lastStatusCode: Int?)
    case anisetteIdentityRejected
    case anisetteIdentityMismatch
    case signInRateLimited
    case signInEndpointUnavailable(statusCode: Int?)
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
            return "The current pairing file is invalid. Reason: \(reason)\n\nPlease make sure to input a valid pairing file! If the issue persists, replace your pairing with iloader or idevice_pair."
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
        case .anisetteServerUnavailable(let attempted, let lastStatusCode):
            let status = lastStatusCode.map { " (last HTTP \($0))" } ?? ""
            let headline = attempted > 1
                ? "Every Anisette server failed\(status)."
                : "The Anisette server failed\(status)."
            return headline + "\n\n"
                + "A server returned an error page instead of Anisette data, which is normally a server-side "
                + "outage rather than a problem with your Apple ID.\n\n"
                + "Pick a different server in Settings -> Anisette Servers, or try again in a few minutes."
        case .anisetteIdentityRejected:
            return "Apple rejected the machine identity used for this sign-in (-80046).\n\n"
                + "The Anisette server produced identity data Apple no longer accepts, which is typical of "
                + "Android-based Anisette servers.\n\n"
                + "Switch to a macOS-ADI Anisette server (or On-Device Anisette) in Settings -> Anisette Servers, "
                + "keep the same server, and try again."
        case .anisetteIdentityMismatch:
            return "Apple rejected this sign-in because the Anisette data does not match the machine it claims to be (-80045).\n\n"
                + "This happens when identity data and client info come from different sources, for example an "
                + "identity provisioned by one library but announced with another library's client info.\n\n"
                + "Use one Anisette server consistently, reset the Anisette identity in Settings -> Anisette Servers, "
                + "and try again."
        case .signInRateLimited:
            return "Apple is rate-limiting this account or device right now (-22411).\n\n"
                + "Too many sign-in or verification-code attempts were made in a short window. "
                + "Repeatedly retrying extends the block.\n\n"
                + "Wait roughly an hour before trying again."
        case .signInEndpointUnavailable(let statusCode):
            let status = statusCode.map { " (HTTP \($0))" } ?? ""
            return "Apple's sign-in service returned an error page instead of a response\(status).\n\n"
                + "This is usually a temporary outage on Apple's side, or an Anisette server that is down.\n\n"
                + "Wait a moment and retry, or pick a different server in Settings -> Anisette Servers."
        case .unknownUDID(let reason):
            return "SideStore could not determine this device's UDID: \(reason)\n\nPlease replace your pairing using iloader or idevice_pair."
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
        case .anisetteServerUnavailable:
            return NSLocalizedString("Choose another Anisette server, or try again shortly.", comment: "")
        case .anisetteIdentityRejected, .anisetteIdentityMismatch:
            return NSLocalizedString("Use a macOS-ADI Anisette server or On-Device Anisette, and stop rotating identity.", comment: "")
        case .signInRateLimited:
            return NSLocalizedString("Wait about an hour before signing in again.", comment: "")
        case .signInEndpointUnavailable:
            return NSLocalizedString("Retry shortly, or switch Anisette server.", comment: "")
        default:
            return nil
        }
    }
}

/// Apple GrandSlam / Anisette rejection codes that deserve their own explanation
/// instead of a bare "(-80046)" in an alert.
public enum AppleSignInErrorCodes {
    public static let anisetteRejected        = -80046
    public static let machineIdentityMismatch = -80045
    public static let rateLimited             = -22411
}

/// The single interpreter for sign-in failures.
///
/// `classify(_:)` is the only place that decides what an error means: which
/// failures are worth retrying on another Anisette server, and which message the
/// user should see. The failover loop and every alert read it, so the rules
/// cannot drift apart and no raw server payload reaches the UI.
public enum SignInFailure {
    public enum Classification: Equatable {
        /// One server failed: bad status, HTML where JSON was expected, or an
        /// unusable payload. Another server may answer differently.
        case serverUnavailable(statusCode: Int?)
        /// Something answered with an error page instead of a response.
        case endpointUnavailable(statusCode: Int?)
        /// -80046: Apple no longer accepts the machine identity.
        case identityRejected
        /// -80045: Anisette data does not match the machine it claims to be.
        case identityMismatch
        /// -22411: Apple is throttling sign-in for this account or device.
        case rateLimited

        public var statusCode: Int? {
            switch self {
            case .serverUnavailable(let statusCode), .endpointUnavailable(let statusCode):
                return statusCode
            case .identityRejected, .identityMismatch, .rateLimited:
                return nil
            }
        }
    }

    /// True when a payload is really an error page (proxy, CDN or Apple 503)
    /// rather than the JSON/plist we asked for.
    public static func looksLikeMarkup(_ text: String) -> Bool {
        let head = text.prefix(512).lowercased()
        return head.contains("<html") || head.contains("<!doctype")
            || head.contains("<body") || head.contains("<head")
    }

    /// nil means "this is not a sign-in failure" — leave the error untouched.
    public static func classify(_ error: Error) -> Classification? {
        // withLocalizedTitle(_:) and withLocalizedFailure(_:) wrap the real
        // error, so look inside before giving up.
        if let wrappedError = error as? ALTWrappedError {
            return classify(wrappedError.wrappedError)
        }

        if let serverError = error as? ServerError {
            switch serverError {
            case .underlyingError(let code, _):
                switch code {
                case AppleSignInErrorCodes.anisetteRejected:
                    return .identityRejected
                case AppleSignInErrorCodes.machineIdentityMismatch:
                    return .identityMismatch
                case AppleSignInErrorCodes.rateLimited:
                    return .rateLimited
                default:
                    return nil
                }
            case .invalidResponseFormat(let raw) where looksLikeMarkup(raw):
                return .endpointUnavailable(statusCode: statusCode(in: raw))
            case .badServerResponse(_, let payload) where looksLikeMarkup(payload):
                return .endpointUnavailable(statusCode: statusCode(in: payload))
            default:
                return nil
            }
        }

        if let anisetteError = error as? SideSign.AnisetteError {
            switch anisetteError {
            case .badServerResponse(let statusCode, let payload):
                let serverSideOnly = statusCode >= 500 || statusCode == 429 || statusCode <= 0
                guard serverSideOnly || looksLikeMarkup(payload) else { return nil }
                return .serverUnavailable(statusCode: statusCode > 0 ? statusCode : nil)
            case .invalidAnisetteData:
                return .serverUnavailable(statusCode: nil)
            default:
                return nil
            }
        }

        return nil
    }

    /// Whether another Anisette server could plausibly succeed where this one
    /// failed. Server-specific problems say nothing about the next server;
    /// account-level rejections would repeat everywhere.
    public static func shouldRetryOnAnotherServer(_ error: Error) -> Bool {
        if error is URLError {
            return true
        }

        if let anisetteError = error as? SideSign.AnisetteError {
            switch anisetteError {
            case .outdatedV1Server, .invalidURL:
                return true
            default:
                break
            }
        }

        guard let classification = classify(error) else { return false }
        switch classification {
        case .serverUnavailable, .endpointUnavailable:
            return true
        case .identityRejected, .identityMismatch, .rateLimited:
            return false
        }
    }

    /// Maps an error onto actionable text. Returns the error unchanged when it
    /// is not a sign-in failure.
    public static func normalized(_ error: Error) -> Error {
        guard let classification = classify(error) else { return error }

        switch classification {
        case .serverUnavailable(let statusCode):
            return OperationError.anisetteServerUnavailable(attempted: 1, lastStatusCode: statusCode)
        case .endpointUnavailable(let statusCode):
            return OperationError.signInEndpointUnavailable(statusCode: statusCode)
        case .identityRejected:
            return OperationError.anisetteIdentityRejected
        case .identityMismatch:
            return OperationError.anisetteIdentityMismatch
        case .rateLimited:
            return OperationError.signInRateLimited
        }
    }

    /// `normalized(_:)` for display: keeps any title the caller attached with
    /// `withLocalizedTitle(_:)` so alerts keep their heading.
    public static func normalizedForDisplay(_ error: Error) -> NSError {
        let originalError = error as NSError
        guard classify(error) != nil else { return originalError }

        let normalizedError = normalized(error) as NSError
        guard let title = originalError.localizedTitle else { return normalizedError }
        return normalizedError.withLocalizedTitle(title)
    }

    /// Log-safe description: an HTML error page is never written out verbatim.
    public static func logSummary(for error: Error) -> String {
        if let anisetteError = error as? SideSign.AnisetteError,
           case .badServerResponse(let statusCode, let payload) = anisetteError {
            let kind = looksLikeMarkup(payload) ? "HTML error page" : String(payload.prefix(120))
            return "HTTP \(statusCode) (\(kind))"
        }
        return error.localizedDescription
    }

    /// Pulls the first plausible HTTP status out of an error page so the
    /// message can say "HTTP 503" instead of nothing.
    static func statusCode(in payload: String) -> Int? {
        var digits = ""
        for character in payload {
            if character.isNumber {
                digits.append(character)
                if digits.count == 3, let value = Int(digits), (100...599).contains(value) {
                    return value
                }
            } else {
                digits.removeAll(keepingCapacity: true)
            }
        }
        return nil
    }
}
