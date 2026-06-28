//
//  ALTWrappedError.swift
//  AltStoreCore
//
//  Created by Magesh K on 2026-06-28.
//

import Foundation

@objc(ALTWrappedError)
public class ALTWrappedError: NSError {
    
    @objc public let wrappedError: NSError
    
    @objc public init(error: NSError, userInfo: [String: Any]?) {
        if let wrapped = error as? ALTWrappedError {
            self.wrappedError = wrapped.wrappedError
        } else {
            self.wrappedError = error
        }
        super.init(domain: error.domain, code: error.code, userInfo: userInfo)
    }
    
    public required init?(coder: NSCoder) {
        if let wrapped = coder.decodeObject(of: NSError.self, forKey: "wrappedError") {
            self.wrappedError = wrapped
        } else {
            self.wrappedError = NSError(domain: "", code: 0)
        }
        super.init(coder: coder)
    }
    
    public override class var supportsSecureCoding: Bool {
        return true
    }
    
    public override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(wrappedError, forKey: "wrappedError")
    }
    
    public override var localizedDescription: String {
        let localizedFailureReason = self.wrappedError.localizedFailureReason ?? self.wrappedError.localizedDescription
        
        if let wrappedLocalizedDescription = self.wrappedError.userInfo[NSLocalizedDescriptionKey] as? String {
            let localizedFailure = self.wrappedError.userInfo[NSLocalizedFailureErrorKey] as? String
            let fallbackDescription = localizedFailure != nil ? "\(localizedFailure!) \(localizedFailureReason)" : localizedFailureReason
            if wrappedLocalizedDescription != fallbackDescription {
                return wrappedLocalizedDescription
            }
        }
        
        if let localizedFailure = self.userInfo[NSLocalizedFailureErrorKey] as? String {
            let wrappedLocalizedDescription = self.wrappedError.userInfo[NSLocalizedDescriptionKey] as? String
            let failureReason = wrappedLocalizedDescription ?? self.wrappedError.localizedFailureReason ?? self.wrappedError.localizedDescription
            return "\(localizedFailure) \(failureReason)"
        }
        
        return self.wrappedError.localizedDescription
    }
    
    public override var localizedFailureReason: String? {
        return self.wrappedError.localizedFailureReason
    }
    
    public override var localizedRecoverySuggestion: String? {
        return self.wrappedError.localizedRecoverySuggestion
    }
    
    public override var debugDescription: String {
        return self.wrappedError.debugDescription
    }
    
    public override var helpAnchor: String? {
        return self.wrappedError.helpAnchor
    }
}
