//
//  Keychain.swift
//  AltStore
//
//  Created by Riley Testut on 6/4/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import KeychainAccess

import AltSign

@propertyWrapper
public struct KeychainItem<Value>
{
    public let key: String
    
    public var wrappedValue: Value? {
        get {
            switch Value.self
            {
            case is Data.Type: return try? Keychain.shared.keychain.getData(self.key) as? Value
            case is String.Type: return try? Keychain.shared.keychain.getString(self.key) as? Value
            default: return nil
            }
        }
        set {
            switch Value.self
            {
            case is Data.Type: Keychain.shared.keychain[data: self.key] = newValue as? Data
            case is String.Type: Keychain.shared.keychain[self.key] = newValue as? String
            default: break
            }
        }
    }
    
    public init(key: String)
    {
        self.key = key
    }
}

public class Keychain
{
    public static let shared = Keychain()
    
    public let keychain = KeychainAccess.Keychain(service: Bundle.Info.appbundleIdentifier).accessibility(.afterFirstUnlock).synchronizable(true)
    
    @KeychainItem(key: "appleIDEmailAddress")
    public var appleIDEmailAddress: String?
    
    @KeychainItem(key: "appleIDPassword")
    public var appleIDPassword: String?
    
    @KeychainItem(key: "appleIDAdsid")
    public var appleIDAdsid: String?
    
    @KeychainItem(key: "appleIDXcodeToken")
    public var appleIDXcodeToken: String?
    
    @KeychainItem(key: "signingCertificate")
    public var signingCertificate: Data?
    
    @KeychainItem(key: "signingCertificatePassword")
    public var signingCertificatePassword: String?
    
    // TODO: mahee96: remove legacy keys in later versions coz by now our migrations should be effectively moved all
    // Legacy
    @KeychainItem(key: "signingCertificatePrivateKey")
    public var signingCertificatePrivateKey: Data?
    
    // TODO: mahee96: remove legacy keys in later versions coz by now our migrations should be effectively moved all
    // Legacy
    @KeychainItem(key: "signingCertificateSerialNumber")
    public var signingCertificateSerialNumber: String?
    
    @KeychainItem(key: "identifier")
    public var identifier: String?
    
    @KeychainItem(key: "adiPb")
    public var adiPb: String?
    
    // for some reason authenticated cert/session/team is completely not cached, which result in logging in for every request
    // we save it here so when user logs out we can clear cached account/session/team
    public var certificate: ALTCertificate? = nil
    public var session: ALTAppleAPISession? = nil
    public var team: ALTTeam? = nil
    
    private init()
    {
        self.migrateLegacyKeychainItems()
    }
    
    private func migrateLegacyKeychainItems()
    {
        let signingCertificateKey = "signingCertificate"
        let privateKeyKey = "signingCertificatePrivateKey"
        let serialNumberKey = "signingCertificateSerialNumber"
        
        // 1. Check if signingCertificate contains data and is NOT a PKCS#12 archive
        guard let certData = try? self.keychain.getData(signingCertificateKey), !certData.isPKCS12 else { return }
        
        // 2. Check if we have the private key
        guard let privateKey = try? self.keychain.getData(privateKeyKey) else { return }
        
        // 3. Load the raw certificate
        guard let cert = ALTCertificate(data: certData) else { return }
        cert.privateKey = privateKey
        
        // 4. Create PKCS12 data structure
        if let p12Data = cert.p12Data()
        {
            // 5. Store the new PKCS12 format in signingCertificate slot
            try? self.keychain.set(p12Data, key: signingCertificateKey)
            try? self.keychain.set("", key: "signingCertificatePassword")
            
            // 6. Clear legacy keys
            try? self.keychain.remove(privateKeyKey)
            try? self.keychain.remove(serialNumberKey)
            
            print("[Keychain] Successfully migrated legacy certificate and private key to PKCS12 format and cleared legacy keys.")
        }
    }
    
    public func reset(keepCertificate: Bool = false)
    {
        self.appleIDEmailAddress = nil
        self.appleIDPassword = nil
        self.appleIDAdsid = nil
        self.appleIDXcodeToken = nil
        
        if !keepCertificate {
            // Legacy
            self.signingCertificatePrivateKey = nil
            self.signingCertificateSerialNumber = nil

            self.signingCertificate = nil
            self.signingCertificatePassword = nil
        }
        
        self.certificate = nil
        self.session = nil
        self.team = nil
    }
}
