//
//  NSError+AltStore.swift
//  AltStore
//
//  Created by Riley Testut on 3/11/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation

public extension NSError {
    @objc(alt_localizedFailure)
    var localizedFailure: String? {
        let localizedFailure = (userInfo[NSLocalizedFailureErrorKey] as? String) ?? (NSError.userInfoValueProvider(forDomain: domain)?(self, NSLocalizedFailureErrorKey) as? String)
        return localizedFailure
    }

    @objc(alt_localizedDebugDescription)
    var localizedDebugDescription: String? {
        let debugDescription = (userInfo[NSDebugDescriptionErrorKey] as? String) ?? (NSError.userInfoValueProvider(forDomain: domain)?(self, NSDebugDescriptionErrorKey) as? String)
        return debugDescription
    }

    @objc(alt_errorWithLocalizedFailure:)
    func withLocalizedFailure(_ failure: String) -> NSError {
        var userInfo = self.userInfo
        userInfo[NSLocalizedFailureErrorKey] = failure

        if let failureReason = localizedFailureReason {
            userInfo[NSLocalizedFailureReasonErrorKey] = failureReason
        } else if localizedFailure == nil && localizedFailureReason == nil && localizedDescription.contains(localizedErrorCode) {
            // Default localizedDescription, so replace with just the localized error code portion.
            userInfo[NSLocalizedFailureReasonErrorKey] = "(\(localizedErrorCode).)"
        } else {
            userInfo[NSLocalizedFailureReasonErrorKey] = localizedDescription
        }

        if let localizedDescription = NSError.userInfoValueProvider(forDomain: domain)?(self, NSLocalizedDescriptionKey) as? String {
            userInfo[NSLocalizedDescriptionKey] = localizedDescription
        }

        // Don't accidentally remove localizedDescription from dictionary
        // userInfo[NSLocalizedDescriptionKey] = NSError.userInfoValueProvider(forDomain: self.domain)?(self, NSLocalizedDescriptionKey) as? String

        if let recoverySuggestion = localizedRecoverySuggestion {
            userInfo[NSLocalizedRecoverySuggestionErrorKey] = recoverySuggestion
        }

        let error = NSError(domain: domain, code: code, userInfo: userInfo)
        return error
    }

    func sanitizedForCoreData() -> NSError {
        var userInfo = self.userInfo
        userInfo[NSLocalizedFailureErrorKey] = localizedFailure
        userInfo[NSLocalizedDescriptionKey] = localizedDescription
        userInfo[NSLocalizedFailureReasonErrorKey] = localizedFailureReason
        userInfo[NSLocalizedRecoverySuggestionErrorKey] = localizedRecoverySuggestion

        // Remove userInfo values that don't conform to NSSecureEncoding.
        userInfo = userInfo.filter { _, value in
            (value as AnyObject) is NSSecureCoding
        }

        // Sanitize underlying errors.
        if let underlyingError = userInfo[NSUnderlyingErrorKey] as? Error {
            let sanitizedError = (underlyingError as NSError).sanitizedForCoreData()
            userInfo[NSUnderlyingErrorKey] = sanitizedError
        }

        if #available(iOS 14.5, macOS 11.3, *), let underlyingErrors = userInfo[NSMultipleUnderlyingErrorsKey] as? [Error] {
            let sanitizedErrors = underlyingErrors.map { ($0 as NSError).sanitizedForCoreData() }
            userInfo[NSMultipleUnderlyingErrorsKey] = sanitizedErrors
        }

        let error = NSError(domain: domain, code: code, userInfo: userInfo)
        return error
    }
}

public extension Error {
    var underlyingError: Error? {
        let underlyingError = (self as NSError).userInfo[NSUnderlyingErrorKey] as? Error
        return underlyingError
    }

    var localizedErrorCode: String {
        let localizedErrorCode = String(format: NSLocalizedString("%@ error %@", comment: ""), (self as NSError).domain, (self as NSError).code as NSNumber)
        return localizedErrorCode
    }
}

public protocol ALTLocalizedError: LocalizedError, CustomNSError {
    var failure: String? { get }

    var underlyingError: Error? { get }
}

public extension ALTLocalizedError {
    var errorUserInfo: [String: Any] {
        let userInfo = ([
            NSLocalizedDescriptionKey: errorDescription,
            NSLocalizedFailureReasonErrorKey: failureReason,
            NSLocalizedFailureErrorKey: failure,
            NSUnderlyingErrorKey: underlyingError
        ] as [String: Any?]).compactMapValues { $0 }
        return userInfo
    }

    var underlyingError: Error? {
        // Error's default implementation calls errorUserInfo,
        // but ALTLocalizedError.errorUserInfo calls underlyingError.
        // Return nil to prevent infinite recursion.
        nil
    }

    var errorDescription: String? {
        guard let errorFailure = failure else { return (underlyingError as NSError?)?.localizedDescription }
        guard let failureReason = failureReason else { return errorFailure }

        let errorDescription = errorFailure + " " + failureReason
        return errorDescription
    }

    var failureReason: String? { (underlyingError as NSError?)?.localizedDescription }
    var recoverySuggestion: String? { (underlyingError as NSError?)?.localizedRecoverySuggestion }
    var helpAnchor: String? { (underlyingError as NSError?)?.helpAnchor }
}
