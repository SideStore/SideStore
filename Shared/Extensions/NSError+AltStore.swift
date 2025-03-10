//
//  NSError+AltStore.swift
//  AltStore
//
//  Created by Riley Testut on 3/11/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation

#if canImport(UIKit)
import UIKit
public typealias ALTFont = UIFont
#elseif canImport(AppKit)
import AppKit
public typealias ALTFont = NSFont
#endif

import AltSign

public extension NSError
{
    @objc(alt_localizedFailure)
    var localizedFailure: String? {
        let localizedFailure = (self.userInfo[NSLocalizedFailureErrorKey] as? String) ?? (NSError.userInfoValueProvider(forDomain: self.domain)?(self, NSLocalizedFailureErrorKey) as? String)
        return localizedFailure
    }
    
    @objc(alt_localizedDebugDescription)
    var localizedDebugDescription: String? {
        let debugDescription = (self.userInfo[NSDebugDescriptionErrorKey] as? String) ?? (NSError.userInfoValueProvider(forDomain: self.domain)?(self, NSDebugDescriptionErrorKey) as? String)
        return debugDescription
    }

    @objc(alt_localizedTitle)
    var localizedTitle: String? {
        let localizedTitle = self.userInfo[ALTLocalizedTitleErrorKey] as? String
        return localizedTitle
    }

    @objc(alt_errorWithLocalizedFailure:)
    func withLocalizedFailure(_ failure: String) -> NSError
    {
        switch self
        {
        case var error as any ALTLocalizedError:
            error.errorFailure = failure
            return error as NSError

        default:
            var userInfo = self.userInfo
            userInfo[NSLocalizedFailureErrorKey] = failure

            let error = ALTWrappedError(error: self, userInfo: userInfo)
            return error
        }
    }

    @objc(alt_errorWithLocalizedTitle:)
    func withLocalizedTitle(_ title: String) -> NSError
    {
        switch self
        {
        case var error as any ALTLocalizedError:
            error.errorTitle = title
            return error as NSError

        default:
            var userInfo = self.userInfo
            userInfo[ALTLocalizedTitleErrorKey] = title

            let error = ALTWrappedError(error: self, userInfo: userInfo)
            return error
        }
    }
    
    func sanitizedForSerialization() -> NSError
    {
        var userInfo = self.userInfo
        userInfo[NSLocalizedDescriptionKey] = self.localizedDescription
        userInfo[NSLocalizedFailureErrorKey] = self.localizedFailure
        userInfo[NSLocalizedFailureReasonErrorKey] = self.localizedFailureReason
        userInfo[NSLocalizedRecoverySuggestionErrorKey] = self.localizedRecoverySuggestion
        userInfo[NSDebugDescriptionErrorKey] = self.localizedDebugDescription

        // Remove userInfo values that don't conform to NSSecureEncoding.
        userInfo = userInfo.filter { (key, value) in
            guard let secureCodable = value as? NSSecureCoding else { return false }
            
            switch secureCodable
            {
            case let array as NSArray:
                let isSecureCodable = array.allSatisfy({ $0 is NSSecureCoding })
                return isSecureCodable
                
            case let dictionary as NSDictionary:
                let isSecureCodable = dictionary.allValues.allSatisfy({ $0 is NSSecureCoding })
                return isSecureCodable
                
            default: return true
            }
        }
        
        // Sanitize underlying errors.
        if let underlyingError = userInfo[NSUnderlyingErrorKey] as? Error
        {
            let sanitizedError = (underlyingError as NSError).sanitizedForSerialization()
            userInfo[NSUnderlyingErrorKey] = sanitizedError
        }
        
        if #available(iOS 14.5, macOS 11.3, *), let underlyingErrors = userInfo[NSMultipleUnderlyingErrorsKey] as? [Error]
        {
            let sanitizedErrors = underlyingErrors.map { ($0 as NSError).sanitizedForSerialization() }
            userInfo[NSMultipleUnderlyingErrorsKey] = sanitizedErrors
        }
        
        let error = NSError(domain: self.domain, code: self.code, userInfo: userInfo)
        return error
    }

    func formattedDetailedDescription(with font: ALTFont) -> NSAttributedString
    {
        #if canImport(UIKit)
        let boldFontDescriptor = font.fontDescriptor.withSymbolicTraits(.traitBold) ?? font.fontDescriptor
        let boldFont = ALTFont(descriptor: boldFontDescriptor, size: font.pointSize)
        #else
        let boldFontDescriptor = font.fontDescriptor.withSymbolicTraits(.bold)
        let boldFont = ALTFont(descriptor: boldFontDescriptor, size: font.pointSize) ?? font
        #endif

        var preferredKeyOrder = [
            NSDebugDescriptionErrorKey,
            NSLocalizedDescriptionKey,
            NSLocalizedFailureErrorKey,
            NSLocalizedFailureReasonErrorKey,
            NSLocalizedRecoverySuggestionErrorKey,
            ALTLocalizedTitleErrorKey,
            ALTSourceFileErrorKey,
            ALTSourceLineErrorKey,
            NSUnderlyingErrorKey
        ]

        if #available(iOS 14.5, macOS 11.3, *)
        {
            preferredKeyOrder.append(NSMultipleUnderlyingErrorsKey)
        }

        var userInfo = self.userInfo
        userInfo[NSDebugDescriptionErrorKey] = self.localizedDebugDescription
        userInfo[NSLocalizedDescriptionKey] = self.localizedDescription
        userInfo[NSLocalizedFailureErrorKey] = self.localizedFailure
        userInfo[NSLocalizedFailureReasonErrorKey] = self.localizedFailureReason
        userInfo[NSLocalizedRecoverySuggestionErrorKey] = self.localizedRecoverySuggestion

        let sortedUserInfo = userInfo.sorted { (a, b) in
            let indexA = preferredKeyOrder.firstIndex(of: a.key)
            let indexB = preferredKeyOrder.firstIndex(of: b.key)

            switch (indexA, indexB)
            {
            case (let indexA?, let indexB?): return indexA < indexB
            case (_?, nil): return true // indexA exists, indexB is nil, so A should come first.
            case (nil, _?): return false  // indexA is nil, indexB exists, so B should come first.
            case (nil, nil): return a.key < b.key // both indexes are nil, so sort alphabetically.
            }
        }

        let detailedDescription = NSMutableAttributedString()

        for (key, value) in sortedUserInfo
        {
            let keyName: String
            switch key
            {
            case NSDebugDescriptionErrorKey: keyName = NSLocalizedString("Debug Description", comment: "")
            case NSLocalizedDescriptionKey: keyName = NSLocalizedString("Error Description", comment: "")
            case NSLocalizedFailureErrorKey: keyName = NSLocalizedString("Failure", comment: "")
            case NSLocalizedFailureReasonErrorKey: keyName = NSLocalizedString("Failure Reason", comment: "")
            case NSLocalizedRecoverySuggestionErrorKey: keyName = NSLocalizedString("Recovery Suggestion", comment: "")
            case ALTLocalizedTitleErrorKey: keyName = NSLocalizedString("Title", comment: "")
            case ALTSourceFileErrorKey: keyName = NSLocalizedString("Source File", comment: "")
            case ALTSourceLineErrorKey: keyName = NSLocalizedString("Source Line", comment: "")
            case NSUnderlyingErrorKey: keyName = NSLocalizedString("Underlying Error", comment: "")
            default:
                if #available(iOS 14.5, macOS 11.3, *), key == NSMultipleUnderlyingErrorsKey
                {
                    keyName = NSLocalizedString("Underlying Errors", comment: "")
                }
                else
                {
                    keyName = key
                }
            }

            let attributedKey = NSAttributedString(string: keyName, attributes: [.font: boldFont])
            let attributedValue = NSAttributedString(string: String(describing: value), attributes: [.font: font])

            let attributedString = NSMutableAttributedString(attributedString: attributedKey)
            attributedString.mutableString.append("\n")
            attributedString.append(attributedValue)

            if !detailedDescription.string.isEmpty
            {
                detailedDescription.mutableString.append("\n\n")
            }

            detailedDescription.append(attributedString)
        }

        // Support dark mode
		#if canImport(UIKit)
        if #available(iOS 13, *)
        {
            detailedDescription.addAttribute(.foregroundColor, value: UIColor.label, range: NSMakeRange(0, detailedDescription.length))
        }
		#else
        detailedDescription.addAttribute(.foregroundColor, value: NSColor.labelColor, range: NSMakeRange(0, detailedDescription.length))
		#endif

        return detailedDescription
    }
}

public extension NSError
{
    typealias UserInfoProvider = (Error, String) -> Any?

    @objc
    class func alt_setUserInfoValueProvider(forDomain domain: String, provider: UserInfoProvider?)
    {
        NSError.setUserInfoValueProvider(forDomain: domain) { (error, key) in
			let nsError = error as NSError

            switch key
            {
            case NSLocalizedDescriptionKey:
                if nsError.localizedFailure != nil
                {
                    // Error has localizedFailure, so return nil to construct localizedDescription from it + localizedFailureReason.
                    return nil
                }
                else if let localizedDescription = provider?(error, NSLocalizedDescriptionKey) as? String
                {
                    // Only call provider() if there is no localizedFailure.
                    return localizedDescription
                }

                // Otherwise, return failureReason for localizedDescription to avoid system prepending "Operation Failed" message.
                // Do NOT return provider(NSLocalizedFailureReason), which might be unexpectedly nil if unrecognized error code.
                return nsError.localizedFailureReason

            default:
                let value = provider?(error, key)
                return value
            }
        }
    }
}

public extension Error
{
    var underlyingError: Error? {
        let underlyingError = (self as NSError).userInfo[NSUnderlyingErrorKey] as? Error
        return underlyingError
    }

    var localizedErrorCode: String {
        let nsError = self as NSError
        let localizedErrorCode = String(format: NSLocalizedString("%@ %@", comment: ""), nsError.domain, self.displayCode as NSNumber)
        return localizedErrorCode
    }

    var displayCode: Int {
        guard let serverError = self as? ALTServerError else {
            // Not ALTServerError, so display regular code.
            return (self as NSError).code
        }

        // We want ALTServerError codes to start at 2000,
        // but we can't change them without breaking AltServer compatibility.
        // Instead, we just add 2000 when displaying code to user
        // to make it appear as if codes start at 2000 normally.
        let code = 2000 + serverError.code.rawValue
        return code
    }
}
