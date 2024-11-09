//
//  VerifyAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 5/2/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation

import AltStoreCore
import AltSign
import Roxas

extension VerificationError
{
    enum Code: Int, ALTErrorCode, CaseIterable {
        typealias Error = VerificationError

        case privateEntitlements
        case mismatchedBundleIdentifiers
        case iOSVersionNotSupported
    }

    static func privateEntitlements(_ entitlements: [String: Any], app: ALTApplication) -> VerificationError {
        VerificationError(code: .privateEntitlements, app: app, entitlements: entitlements)
    }

    static func mismatchedBundleIdentifiers(sourceBundleID: String, app: ALTApplication) -> VerificationError {
        VerificationError(code: .mismatchedBundleIdentifiers, app: app, sourceBundleID: sourceBundleID)
    }

    static func iOSVersionNotSupported(app: AppProtocol, osVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion, requiredOSVersion: OperatingSystemVersion?) -> VerificationError {
        VerificationError(code: .iOSVersionNotSupported, app: app)
    }
}

struct VerificationError: ALTLocalizedError {
    let code: Code

    var errorTitle: String?
    var errorFailure: String?

    @Managed var app: AppProtocol?
    var entitlements: [String: Any]?
    var sourceBundleID: String?
    var deviceOSVersion: OperatingSystemVersion?
    var requiredOSVersion: OperatingSystemVersion?
    
    var errorDescription: String? {
        switch self.code {
        case .iOSVersionNotSupported:
            guard let deviceOSVersion else { return nil }

            var failureReason = self.errorFailureReason
            if self.app == nil {
                let firstLetter = failureReason.prefix(1).lowercased()
                failureReason = firstLetter + failureReason.dropFirst()
            }

            return String(formatted: "This device is running iOS %@, but %@", deviceOSVersion.stringValue, failureReason)
        default: return nil
        }
    }

    var errorFailureReason: String {
        switch self.code
        {
        case .privateEntitlements:
            let appName = self.$app.name ?? NSLocalizedString("The app", comment: "")
            return String(formatted: "“%@” requires private permissions.", appName)

        case .mismatchedBundleIdentifiers:
            if let appBundleID = self.$app.bundleIdentifier, let bundleID = self.sourceBundleID {
                return String(formatted: "The bundle ID '%@' does not match the one specified by the source ('%@').", appBundleID, bundleID)
            } else {
                return NSLocalizedString("The bundle ID does not match the one specified by the source.", comment: "")
            }

        case .iOSVersionNotSupported:
            let appName = self.$app.name ?? NSLocalizedString("The app", comment: "")
            let deviceOSVersion = self.deviceOSVersion ?? ProcessInfo.processInfo.operatingSystemVersion

            guard let requiredOSVersion else {
                return String(formatted: "%@ does not support iOS %@.", appName, deviceOSVersion.stringValue)
            }
            if deviceOSVersion > requiredOSVersion {
                return String(formatted: "%@ requires iOS %@ or earlier", appName, requiredOSVersion.stringValue)
            } else {
                return String(formatted: "%@ requires iOS %@ or later", appName, requiredOSVersion.stringValue)
            }
        }
    }
}

@objc(VerifyAppOperation)
final class VerifyAppOperation: ResultOperation<Void>
{
    let context: AppOperationContext
    var verificationHandler: ((VerificationError) -> Bool)?
    
    init(context: AppOperationContext)
    {
        self.context = context
        
        super.init()
    }
    
    override func main()
    {
        super.main()
        
        do
        {
            if let error = self.context.error
            {
                throw error
            }
            
            guard let app = self.context.app else {
                throw OperationError.invalidParameters("VerifyAppOperation.main: self.context.app is nil")
            }
            
            if !["ny.litritt.ignited", "com.litritt.ignited"].contains(where: { $0 == app.bundleIdentifier }) {
                guard app.bundleIdentifier == self.context.bundleIdentifier else {
                    throw VerificationError.mismatchedBundleIdentifiers(sourceBundleID: self.context.bundleIdentifier, app: app)
                }
            }
            
            guard ProcessInfo.processInfo.isOperatingSystemAtLeast(app.minimumiOSVersion) else {
                throw VerificationError.iOSVersionNotSupported(app: app, requiredOSVersion: app.minimumiOSVersion)
            }
            
            if #available(iOS 13.5, *)
            {
                // No psychic paper, so we can ignore private entitlements
                app.hasPrivateEntitlements = false
            }
            else
            {
                // Make sure this goes last, since once user responds to alert we don't do any more app verification.
                if let commentStart = app.entitlementsString.range(of: "<!---><!-->"), let commentEnd = app.entitlementsString.range(of: "<!-- -->")
                {
                    // Psychic Paper private entitlements.
                    
                    let entitlementsStart = app.entitlementsString.index(after: commentStart.upperBound)
                    let rawEntitlements = String(app.entitlementsString[entitlementsStart ..< commentEnd.lowerBound])
                    
                    let plistTemplate = """
                        <?xml version="1.0" encoding="UTF-8"?>
                        <!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
                        <plist version="1.0">
                            <dict>
                            %@
                            </dict>
                        </plist>
                        """
                    let entitlementsPlist = String(format: plistTemplate, rawEntitlements)
                    let entitlements = try PropertyListSerialization.propertyList(from: entitlementsPlist.data(using: .utf8)!, options: [], format: nil) as! [String: Any]
                    
                    app.hasPrivateEntitlements = true
                    let error = VerificationError.privateEntitlements(entitlements, app: app)
                    self.process(error) { (result) in
                        self.finish(result.mapError { $0 as Error })
                    }
                    
                    return
                }
                else
                {
                    app.hasPrivateEntitlements = false
                }
            }
            
            self.finish(.success(()))
        }
        catch
        {
            self.finish(.failure(error))
        }
    }
}

private extension VerifyAppOperation
{
    func process(_ error: VerificationError, completion: @escaping (Result<Void, VerificationError>) -> Void)
    {
        guard let presentingViewController = self.context.presentingViewController else { return completion(.failure(error)) }
        
        DispatchQueue.main.async {
            switch error.code
            {
            case .privateEntitlements:
                guard let entitlements = error.entitlements else { return completion(.failure(error)) }
                let permissions = entitlements.keys.sorted().joined(separator: "\n")
                let message = String(format: NSLocalizedString("""
                    You must allow access to these private permissions before continuing:

                    %@

                    Private permissions allow apps to do more than normally allowed by iOS, including potentially accessing sensitive private data. Make sure to only install apps from sources you trust.
                    """, comment: ""), permissions)
                
                let alertController = UIAlertController(title: error.failureReason ?? error.localizedDescription, message: message, preferredStyle: .alert)
                alertController.addAction(UIAlertAction(title: NSLocalizedString("Allow Access", comment: ""), style: .destructive) { (action) in
                    completion(.success(()))
                })
                alertController.addAction(UIAlertAction(title: NSLocalizedString("Deny Access", comment: ""), style: .default, handler: { (action) in
                    completion(.failure(error))
                }))
                presentingViewController.present(alertController, animated: true, completion: nil)
                
            case .mismatchedBundleIdentifiers, .iOSVersionNotSupported: return completion(.failure(error))
            }
        }
    }
}
