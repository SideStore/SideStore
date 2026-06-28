//
//  NSError+ALTServerError.swift
//  AltStoreCore
//
//  Created by Magesh K on 2026-06-28.
//

import Foundation

public let AltServerErrorDomain = "AltServer.ServerError"
public let AltServerInstallationErrorDomain = "Apple.InstallationError"
public let AltServerConnectionErrorDomain = "AltServer.ConnectionError"

public let ALTUnderlyingErrorDomainErrorKey = "underlyingErrorDomain"
public let ALTUnderlyingErrorCodeErrorKey = "underlyingErrorCode"
public let ALTProvisioningProfileBundleIDErrorKey = "bundleIdentifier"
public let ALTDeviceNameErrorKey = "deviceName"
public let ALTOperatingSystemNameErrorKey = "ALTOperatingSystemName"
public let ALTOperatingSystemVersionErrorKey = "ALTOperatingSystemVersion"

public let ALTNSCodingPathKey = "NSCodingPath"
public let ALTAppNameErrorKey = "appName"

@objc(ALTServerError)
public enum ALTServerErrorEnum: Int, Codable {
    case underlyingError = -1
    case unknown = 0
    case connectionFailed = 1
    case lostConnection = 2
    case deviceNotFound = 3
    case deviceWriteFailed = 4
    case invalidRequest = 5
    case invalidResponse = 6
    case invalidApp = 7
    case installationFailed = 8
    case maximumFreeAppLimitReached = 9
    case unsupportediOSVersion = 10
    case unknownRequest = 11
    case unknownResponse = 12
    case invalidAnisetteData = 13
    case pluginNotFound = 14
    case profileNotFound = 15
    case appDeletionFailed = 16
    case requestedAppNotRunning = 100
    case incompatibleDeveloperDisk = 101
}

public struct ALTServerError: Error, CustomNSError, Hashable, RawRepresentable, Codable {
    public typealias Code = ALTServerErrorEnum
    
    public let rawValue: Int
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    public var userInfo: [String: Any] = [:]
    
    public init(_ code: Code, userInfo: [String: Any]? = nil) {
        self.rawValue = code.rawValue
        self.userInfo = userInfo ?? [:]
    }
    
    public var code: Code {
        return Code(rawValue: rawValue) ?? .unknown
    }
    
    public static var errorDomain: String {
        return AltServerErrorDomain
    }
    
    public var errorCode: Int {
        return rawValue
    }
    
    public var errorUserInfo: [String: Any] {
        return userInfo
    }
    
    private enum CodingKeys: String, CodingKey {
        case rawValue
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.rawValue = try container.decode(Int.self, forKey: .rawValue)
        self.userInfo = [:]
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rawValue, forKey: .rawValue)
    }
}

extension ALTServerError {
    public static let underlyingError = Code.underlyingError
    public static let unknown = Code.unknown
    public static let connectionFailed = Code.connectionFailed
    public static let lostConnection = Code.lostConnection
    public static let deviceNotFound = Code.deviceNotFound
    public static let deviceWriteFailed = Code.deviceWriteFailed
    public static let invalidRequest = Code.invalidRequest
    public static let invalidResponse = Code.invalidResponse
    public static let invalidApp = Code.invalidApp
    public static let installationFailed = Code.installationFailed
    public static let maximumFreeAppLimitReached = Code.maximumFreeAppLimitReached
    public static let unsupportediOSVersion = Code.unsupportediOSVersion
    public static let unknownRequest = Code.unknownRequest
    public static let unknownResponse = Code.unknownResponse
    public static let invalidAnisetteData = Code.invalidAnisetteData
    public static let pluginNotFound = Code.pluginNotFound
    public static let profileNotFound = Code.profileNotFound
    public static let appDeletionFailed = Code.appDeletionFailed
    public static let requestedAppNotRunning = Code.requestedAppNotRunning
    public static let incompatibleDeveloperDisk = Code.incompatibleDeveloperDisk
}

@objc(ALTServerConnectionError)
public enum ALTServerConnectionErrorEnum: Int, Codable {
    case unknown = 0
    case deviceLocked = 1
    case invalidRequest = 2
    case invalidResponse = 3
    case usbmuxd = 4
    case ssl = 5
    case timedOut = 6
}

public struct ALTServerConnectionError: Error, CustomNSError, Hashable, RawRepresentable, Codable {
    public typealias Code = ALTServerConnectionErrorEnum
    
    public let rawValue: Int
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    public var userInfo: [String: Any] = [:]
    
    public init(_ code: Code, userInfo: [String: Any]? = nil) {
        self.rawValue = code.rawValue
        self.userInfo = userInfo ?? [:]
    }
    
    public var code: Code {
        return Code(rawValue: rawValue) ?? .unknown
    }
    
    public static var errorDomain: String {
        return AltServerConnectionErrorDomain
    }
    
    public var errorCode: Int {
        return rawValue
    }
    
    public var errorUserInfo: [String: Any] {
        return userInfo
    }
    
    private enum CodingKeys: String, CodingKey {
        case rawValue
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.rawValue = try container.decode(Int.self, forKey: .rawValue)
        self.userInfo = [:]
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rawValue, forKey: .rawValue)
    }
}

extension ALTServerConnectionError {
    public static let unknown = Code.unknown
    public static let deviceLocked = Code.deviceLocked
    public static let invalidRequest = Code.invalidRequest
    public static let invalidResponse = Code.invalidResponse
    public static let usbmuxd = Code.usbmuxd
    public static let ssl = Code.ssl
    public static let timedOut = Code.timedOut
}

// MARK: - NSError Extension

extension NSError {
    @objc public var altserver_localizedDescription: String? {
        guard self.domain == AltServerErrorDomain else { return nil }
        let code = ALTServerError.Code(rawValue: self.code) ?? .unknown
        switch code {
        case .underlyingError:
            let underlyingError = self.userInfo[NSUnderlyingErrorKey] as? NSError
            return underlyingError?.localizedDescription
            
        case .invalidRequest, .invalidResponse:
            let underlyingError = self.userInfo[NSUnderlyingErrorKey] as? NSError
            if let underlyingError {
                return underlyingError.localizedDescription
            }
            return nil
            
        default:
            return nil
        }
    }
    
    @objc public var altserver_localizedFailure: String? {
        guard self.domain == AltServerErrorDomain else { return nil }
        let code = ALTServerError.Code(rawValue: self.code) ?? .unknown
        switch code {
        case .underlyingError:
            let underlyingError = self.userInfo[NSUnderlyingErrorKey] as? NSError
            return underlyingError?.localizedFailure
            
        case .connectionFailed:
            let underlyingError = self.userInfo[NSUnderlyingErrorKey] as? NSError
            if underlyingError?.localizedFailureReason != nil {
                #if os(macOS)
                return NSLocalizedString("There was an error connecting to the device.", comment: "")
                #else
                return NSLocalizedString("AltServer could not establish a connection to SideStore.", comment: "")
                #endif
            }
            return nil
            
        default:
            return nil
        }
    }
    
    @objc public var altserver_localizedFailureReason: String? {
        guard self.domain == AltServerErrorDomain else { return nil }
        let code = ALTServerError.Code(rawValue: self.code) ?? .unknown
        switch code {
        case .underlyingError:
            let underlyingError = self.userInfo[NSUnderlyingErrorKey] as? NSError
            if let reason = underlyingError?.localizedFailureReason {
                return reason
            }
            if let underlyingErrorCode = self.userInfo[ALTUnderlyingErrorCodeErrorKey] as? String {
                return String(format: NSLocalizedString("Error code: %@", comment: ""), underlyingErrorCode)
            }
            return nil
            
        case .unknown:
            return NSLocalizedString("An unknown error occured.", comment: "")
            
        case .connectionFailed:
            let underlyingError = self.userInfo[NSUnderlyingErrorKey] as? NSError
            if let reason = underlyingError?.localizedFailureReason {
                return reason
            }
            #if os(macOS)
            return NSLocalizedString("There was an error connecting to the device.", comment: "")
            #else
            return NSLocalizedString("Could not connect to SideStore.", comment: "")
            #endif
            
        case .lostConnection:
            return NSLocalizedString("Lost connection to SideStore.", comment: "")
            
        case .deviceNotFound:
            return NSLocalizedString("SideStore could not find this device.", comment: "")
            
        case .deviceWriteFailed:
            return NSLocalizedString("SideStore could not write data to this device.", comment: "")
            
        case .invalidRequest:
            let underlyingError = self.userInfo[NSUnderlyingErrorKey] as? NSError
            return underlyingError?.localizedFailureReason ?? NSLocalizedString("SideStore received an invalid request.", comment: "")
            
        case .invalidResponse:
            let underlyingError = self.userInfo[NSUnderlyingErrorKey] as? NSError
            return underlyingError?.localizedFailureReason ?? NSLocalizedString("SideStore sent an invalid response.", comment: "")
            
        case .invalidApp:
            return NSLocalizedString("The app is in an invalid format.", comment: "")
            
        case .installationFailed:
            let underlyingError = self.userInfo[NSUnderlyingErrorKey] as? NSError
            if let underlyingError {
                return underlyingError.localizedFailureReason ?? underlyingError.localizedDescription
            }
            return NSLocalizedString("An error occurred while installing the app.", comment: "")
            
        case .maximumFreeAppLimitReached:
            return NSLocalizedString("You cannot activate more than 3 apps with a non-developer Apple ID.", comment: "")
            
        case .unsupportediOSVersion:
            let appName = self.userInfo[ALTAppNameErrorKey] as? String
            let osVersion = self.altserver_osVersion
            if appName == nil || osVersion == nil {
                return NSLocalizedString("Your device must be running iOS 15.0 or later to install SideStore.", comment: "")
            }
            return String(format: NSLocalizedString("%@ requires %@ or later.", comment: ""), appName!, osVersion!)
            
        case .unknownRequest:
            return NSLocalizedString("SideStore does not support this request.", comment: "")
            
        case .unknownResponse:
            return NSLocalizedString("SideStore received an unknown response from SideStore.", comment: "")
            
        case .invalidAnisetteData:
            return NSLocalizedString("The provided anisette data is invalid.", comment: "")
            
        case .pluginNotFound:
            return NSLocalizedString("AltServer could not connect to Mail plug-in.", comment: "")
            
        case .profileNotFound:
            return self.profileErrorLocalizedDescription(baseDescription: NSLocalizedString("Could not find profile", comment: ""))
            
        case .appDeletionFailed:
            return NSLocalizedString("An error occured while removing the app.", comment: "")
            
        case .requestedAppNotRunning:
            let appName = (self.userInfo[ALTAppNameErrorKey] as? String) ?? NSLocalizedString("The requested app", comment: "")
            let deviceName = (self.userInfo[ALTDeviceNameErrorKey] as? String) ?? NSLocalizedString("the device", comment: "")
            return String(format: NSLocalizedString("%@ is not currently running on %@.", comment: ""), appName, deviceName)
            
        case .incompatibleDeveloperDisk:
            let osVersion = self.altserver_osVersion ?? NSLocalizedString("this device's OS version", comment: "")
            return String(format: NSLocalizedString("The disk is incompatible with %@.", comment: ""), osVersion)
        }
    }
    
    @objc public var altserver_localizedRecoverySuggestion: String? {
        guard self.domain == AltServerErrorDomain else { return nil }
        let code = ALTServerError.Code(rawValue: self.code) ?? .unknown
        switch code {
        case .underlyingError:
            let underlyingError = self.userInfo[NSUnderlyingErrorKey] as? NSError
            return underlyingError?.localizedRecoverySuggestion
            
        case .connectionFailed:
            let underlyingError = self.userInfo[NSUnderlyingErrorKey] as? NSError
            if let suggestion = underlyingError?.localizedRecoverySuggestion {
                return suggestion
            }
            fallthrough
            
        case .deviceNotFound:
            return NSLocalizedString("Make sure you have trusted this device with your computer and Wi-Fi sync is enabled.", comment: "")
            
        case .pluginNotFound:
            return NSLocalizedString("Mail has been automatically opened, try again in a moment. Otherwise, make sure plug-in is enabled in Mail's preferences.", comment: "")
            
        case .maximumFreeAppLimitReached:
            #if os(macOS)
            return NSLocalizedString("Please deactivate a sideloaded app with SideStore in order to install another app.\n\nIf you're running iOS 13.5 or later, make sure 'Offload Unused Apps' is disabled in Settings > iTunes & App Stores, then install or delete all offloaded apps to prevent them from erroneously counting towards this limit.", comment: "")
            #else
            return NSLocalizedString("Please deactivate a sideloaded app in order to install another one.\n\nIf you're running iOS 13.5 or later, make sure “Offload Unused Apps” is disabled in Settings > iTunes & App Stores, then install or delete all offloaded apps.", comment: "")
            #endif
            
        case .requestedAppNotRunning:
            let deviceName = (self.userInfo[ALTDeviceNameErrorKey] as? String) ?? NSLocalizedString("your device", comment: "")
            return String(format: NSLocalizedString("Make sure the app is running in the foreground on %@ then try again.", comment: ""), deviceName)
            
        default:
            return nil
        }
    }
    
    @objc public var altserver_localizedDebugDescription: String? {
        guard self.domain == AltServerErrorDomain else { return nil }
        let code = ALTServerError.Code(rawValue: self.code) ?? .unknown
        switch code {
        case .underlyingError, .invalidRequest, .invalidResponse:
            let underlyingError = self.userInfo[NSUnderlyingErrorKey] as? NSError
            return underlyingError?.localizedDebugDescription
            
        case .incompatibleDeveloperDisk:
            guard let path = self.userInfo[NSFilePathErrorKey] as? String else { return nil }
            let osVersion = self.altserver_osVersion ?? NSLocalizedString("this device's OS version", comment: "")
            return String(format: NSLocalizedString("The Developer disk located at %@ is incompatible with %@.", comment: ""), path, osVersion)
            
        default:
            return nil
        }
    }
    
    private func profileErrorLocalizedDescription(baseDescription: String) -> String {
        if let bundleID = self.userInfo[ALTProvisioningProfileBundleIDErrorKey] as? String {
            return String(format: "%@ “%@”", baseDescription, bundleID)
        } else {
            return String(format: "%@.", baseDescription)
        }
    }
    
    @objc public var altserver_osVersion: String? {
        guard let osName = self.userInfo[ALTOperatingSystemNameErrorKey] as? String,
              let versionString = self.userInfo[ALTOperatingSystemVersionErrorKey] as? String else { return nil }
        return "\(osName) \(versionString)"
    }
    
    // Connection Error Providers
    @objc public var altserver_connection_localizedFailureReason: String? {
        guard self.domain == AltServerConnectionErrorDomain else { return nil }
        let code = ALTServerConnectionError.Code(rawValue: self.code) ?? .unknown
        switch code {
        case .unknown:
            let underlyingErrorDomain = self.userInfo[ALTUnderlyingErrorDomainErrorKey] as? String
            let underlyingErrorCode = self.userInfo[ALTUnderlyingErrorCodeErrorKey] as? String
            if let underlyingErrorDomain, let underlyingErrorCode {
                return String(format: NSLocalizedString("%@ error %@.", comment: ""), underlyingErrorDomain, underlyingErrorCode)
            } else if let underlyingErrorCode {
                return String(format: NSLocalizedString("Connection error code: %@", comment: ""), underlyingErrorCode)
            }
            return nil
            
        case .deviceLocked:
            let deviceName = (self.userInfo[ALTDeviceNameErrorKey] as? String) ?? NSLocalizedString("The device", comment: "")
            return String(format: NSLocalizedString("%@ is currently locked.", comment: ""), deviceName)
            
        case .invalidRequest:
            let deviceName = (self.userInfo[ALTDeviceNameErrorKey] as? String) ?? NSLocalizedString("The device", comment: "")
            return String(format: NSLocalizedString("%@ received an invalid request from SideStore.", comment: ""), deviceName)
            
        case .invalidResponse:
            let deviceName = (self.userInfo[ALTDeviceNameErrorKey] as? String) ?? NSLocalizedString("the device", comment: "")
            return String(format: NSLocalizedString("SideStore received an invalid response from %@.", comment: ""), deviceName)
            
        case .usbmuxd:
            return NSLocalizedString("There was an issue communicating with the usbmuxd daemon.", comment: "")
            
        case .ssl:
            let deviceName = (self.userInfo[ALTDeviceNameErrorKey] as? String) ?? NSLocalizedString("the device", comment: "")
            return String(format: NSLocalizedString("SideStore could not establish a secure connection to %@.", comment: ""), deviceName)
            
        case .timedOut:
            let deviceName = (self.userInfo[ALTDeviceNameErrorKey] as? String) ?? NSLocalizedString("the device", comment: "")
            return String(format: NSLocalizedString("SideStore's connection to %@ timed out.", comment: ""), deviceName)
        }
    }
    
    @objc public var altserver_connection_localizedRecoverySuggestion: String? {
        guard self.domain == AltServerConnectionErrorDomain else { return nil }
        let code = ALTServerConnectionError.Code(rawValue: self.code) ?? .unknown
        switch code {
        case .deviceLocked:
            return NSLocalizedString("Please unlock the device with your passcode and try again.", comment: "")
        default:
            return nil
        }
    }
}

// MARK: - Registration of UserInfo Providers

private let _installALTServerErrorProviders: Void = {
    NSError.setUserInfoValueProvider(forDomain: AltServerErrorDomain) { error, key in
        let nsError = error as NSError
        switch key {
        case NSLocalizedDescriptionKey:
            return nsError.altserver_localizedDescription
        case NSLocalizedFailureErrorKey:
            return nsError.altserver_localizedFailure
        case NSLocalizedFailureReasonErrorKey:
            return nsError.altserver_localizedFailureReason
        case NSLocalizedRecoverySuggestionErrorKey:
            return nsError.altserver_localizedRecoverySuggestion
        case NSDebugDescriptionErrorKey:
            return nsError.altserver_localizedDebugDescription
        default:
            return nil
        }
    }
    
    NSError.setUserInfoValueProvider(forDomain: AltServerConnectionErrorDomain) { error, key in
        let nsError = error as NSError
        switch key {
        case NSLocalizedFailureReasonErrorKey:
            return nsError.altserver_connection_localizedFailureReason
        case NSLocalizedRecoverySuggestionErrorKey:
            return nsError.altserver_connection_localizedRecoverySuggestion
        default:
            return nil
        }
    }
}()

private let __installServerErrorHelper: Void = { _ = _installALTServerErrorProviders }()

public func ~= (lhs: ALTServerError.Code, rhs: Error) -> Bool {
    let error = rhs as NSError
    guard error.domain == AltServerErrorDomain else { return false }
    return error.code == lhs.rawValue
}

public func ~= (lhs: ALTServerError, rhs: Error) -> Bool {
    let error = rhs as NSError
    guard error.domain == AltServerErrorDomain else { return false }
    return error.code == lhs.rawValue
}

public func ~= (lhs: ALTServerConnectionError.Code, rhs: Error) -> Bool {
    let error = rhs as NSError
    guard error.domain == AltServerConnectionErrorDomain else { return false }
    return error.code == lhs.rawValue
}
