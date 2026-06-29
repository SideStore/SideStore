//
//  DeveloperPortalService.swift
//  AltStore
//
//  Created by Magesh K on 2026-06-29.
//  Copyright © 2026 SideStore. All rights reserved.
//

import UIKit
import AltSign
import AltStoreCore

struct DeveloperPortalService {
    static let shared = DeveloperPortalService()
    
    func authenticate(presentingViewController: UIViewController?) async throws -> (ALTTeam, ALTAppleAPISession) {
        try await withCheckedThrowingContinuation { continuation in
            AppManager.shared.authenticate(presentingViewController: presentingViewController, skipCertificateProvisioning: true) { result in
                switch result {
                case .success(let (team, _, session)):
                    continuation.resume(returning: (team, session))
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func fetchCertificates(team: ALTTeam, session: ALTAppleAPISession) async throws -> [ALTCertificate] {
        try await withCheckedThrowingContinuation { continuation in
            ALTAppleAPI.shared.fetchCertificates(for: team, session: session) { certs, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let certs = certs {
                    continuation.resume(returning: certs)
                } else {
                    continuation.resume(returning: [])
                }
            }
        }
    }
    
    func createCertificate(machineName: String, team: ALTTeam, session: ALTAppleAPISession) async throws -> ALTCertificate {
        try await withCheckedThrowingContinuation { continuation in
            ALTAppleAPI.shared.addCertificate(machineName: machineName, to: team, session: session) { cert, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let cert = cert {
                    continuation.resume(returning: cert)
                } else {
                    continuation.resume(throwing: NSError(domain: "SideStoreError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create certificate: no certificate returned."]))
                }
            }
        }
    }
    
    func revokeCertificate(_ certificate: ALTCertificate, team: ALTTeam, session: ALTAppleAPISession) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            ALTAppleAPI.shared.revoke(certificate, for: team, session: session) { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }
}
