//  
//  URLHandler.swift
//  SideStore
//
//  Created by Magesh K on 2/7/26.
//  Copyright © 2026 SideStore. All rights reserved.

@preconcurrency import UIKit

@MainActor
class URLHandler {
    static let shared = URLHandler()
    
    private init() {}
    
    @discardableResult
    func handle(_ url: URL) -> Bool {
        debugLog("[URLHandler] handle(_:) called with URL: \(url.absoluteString)")
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            debugLog("[URLHandler] Failed to parse URLComponents for \(url)")
            return false
        }
        guard let host = components.host?.lowercased() else {
            debugLog("[URLHandler] Host is nil for \(url)")
            return false
        }
        debugLog("[URLHandler] Matched host: \(host), path: \(url.path.lowercased())")
        
        switch host {
        case "appbackupresponse":
            let result: Result<Void, Error>
            switch url.path.lowercased() {
            case "/success": 
                result = .success(())
            case "/failure":
                let queryItems = components.queryItems?.reduce(into: [String: String]()) { $0[$1.name] = $1.value } ?? [:]
                guard
                    let errorDomain = queryItems["errorDomain"],
                    let errorCodeString = queryItems["errorCode"], let errorCode = Int(errorCodeString),
                    let errorDescription = queryItems["errorDescription"]
                else { return false }
                
                let error = NSError(domain: errorDomain, code: errorCode, userInfo: [NSLocalizedDescriptionKey: errorDescription])
                result = .failure(error)
                
            default: 
                return false
            }
            
            Task {
                NotificationCenter.default.post(name: AppDelegate.appBackupDidFinish, object: nil, userInfo: [AppDelegate.appBackupResultKey: result])
            }
            return true
            
        case "install":
            let queryItems = components.queryItems?.reduce(into: [String: String]()) { $0[$1.name.lowercased()] = $1.value } ?? [:]
            guard let downloadURLString = queryItems["url"], let downloadURL = URL(string: downloadURLString) else { return false }
            
            Task {
                NotificationCenter.default.post(name: AppDelegate.importAppDeepLinkNotification, object: nil, userInfo: [AppDelegate.importAppDeepLinkURLKey: downloadURL])
            }
            return true
            
        case "source":
            let queryItems = components.queryItems?.reduce(into: [String: String]()) { $0[$1.name.lowercased()] = $1.value } ?? [:]
            guard let sourceURLString = queryItems["url"], let sourceURL = URL(string: sourceURLString) else { return false }
            
            Task {
                NotificationCenter.default.post(name: AppDelegate.addSourceDeepLinkNotification, object: nil, userInfo: [AppDelegate.addSourceDeepLinkURLKey: sourceURL])
            }
            return true
            
        case "pairing":
            let queryItems = components.queryItems?.reduce(into: [String: String]()) { $0[$1.name.lowercased()] = $1.value } ?? [:]
            guard let callbackTemplate = queryItems["urlname"]?.removingPercentEncoding ?? queryItems["urlName"]?.removingPercentEncoding else { return false }
            
            Task {
                exportPairingFile(callbackTemplate)
            }
            return true
            
        case "certificate":
            let queryItems = components.queryItems?.reduce(into: [String: String]()) { $0[$1.name.lowercased()] = $1.value } ?? [:]
            guard let callbackTemplate = queryItems["callback_template"]?.removingPercentEncoding else { return false }
            
            Task {
                ExportCertificateDialog.present(callbackTemplate: callbackTemplate)
            }
            return true
            
        default:
            return false
        }
    }
}
