//
//  SigningCertificateValidator.swift
//  AltStoreCore
//
//  Created by Magesh K on 6/28/26.
//

import Foundation
import AltSign

public enum SigningCertificateMismatchReason: Error {
    /// The certificate used to sign the current installation has expired.
    case expired
    
    /// The certificate was explicitly revoked on the Apple Developer portal.
    case revoked
    
    /// The certificate was automatically revoked because a free account is limited to 1 active certificate.
    case freeAccountLimitRevoked
    
    /// The active developer team has changed.
    case differentTeam
    
    /// The logged-in Apple ID account has changed.
    case differentAccount
    
    /// The private key for the active certificate is missing from the device's keychain.
    case privateKeyLost
    
    /// SideStore was installed by an external tool (e.g., Xcode or AltStore) using a different certificate.
    case externalSigner
    
    /// The current installation's provisioning profile is corrupt or contains no certificates.
    case corruptProfile
}

public struct SigningCertificateValidator {
    
    public static func validate(
        runningProfile: ALTProvisioningProfile?,
        activeCertificates: [ALTCertificate],
        signerCertificate: ALTCertificate,
        signerTeam: ALTTeam
    ) -> Result<Void, SigningCertificateMismatchReason> {
        
        guard let runningProfile = runningProfile else {
            return .failure(.corruptProfile)
        }
        
        guard let runningCert = runningProfile.certificates.first else {
            return .failure(.corruptProfile)
        }
        
        // 1. Expired Certificate / Profile
        if runningProfile.expirationDate <= Date() {
            return .failure(.expired)
        }
        
        // 2. Different Account / Team
        let runningTeamID = runningProfile.teamIdentifier
        if runningTeamID != signerTeam.identifier {
            // Check if the Apple ID email matches.
            if let requesterEmail = runningCert.requesterEmail, !requesterEmail.isEmpty,
               requesterEmail.lowercased() != signerTeam.account.appleID.lowercased() {
                return .failure(.differentAccount)
            } else {
                return .failure(.differentTeam)
            }
        }
        
        // 3. Revoked Certificate
        let isRunningCertActive = runningProfile.certificates.contains { profileCert in
            activeCertificates.contains { activeCert in
                activeCert.serialNumber == profileCert.serialNumber
            }
        }
        if !isRunningCertActive {
            if signerTeam.type == .free {
                return .failure(.freeAccountLimitRevoked)
            } else {
                return .failure(.revoked)
            }
        }
        
        // 4. Mismatch / Private Key Lost / External Signer
        let hasCurrentSignerCert = runningProfile.certificates.contains { $0.serialNumber == signerCertificate.serialNumber }
        if !hasCurrentSignerCert {
            let activeProfileCert = runningProfile.certificates.first { profileCert in
                activeCertificates.contains { $0.serialNumber == profileCert.serialNumber }
            }
            let runningCert = activeProfileCert ?? runningProfile.certificates.first ?? signerCertificate
            if let machineName = runningCert.machineName, (machineName.starts(with: "SideStore") || machineName.starts(with: "AltStore")) {
                return .failure(.privateKeyLost)
            } else {
                return .failure(.externalSigner)
            }
        }
        
        return .success(())
    }
}
