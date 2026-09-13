//
//  VerifyCertificateOperation.swift
//  SideStore
//
//  Created by Magesh K on 1/8/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

@preconcurrency import UIKit
import Foundation
import CoreData
import SideSign

final class VerifyCertificateOperation: BasePipelineOperation<InstallAppOperationContext, Void>, @unchecked Sendable {
    private let willResign: Bool
    
    init(context: InstallAppOperationContext, willResign: Bool = true) throws {
        self.willResign = willResign
        try super.init(context: context)
    }
    
    override func execute(parentProgress: Progress?) async throws {
        let startTime = CFAbsoluteTimeGetCurrent()
        debugLog("[VerifyCertificateOperation] execute() started (willResign: \(self.willResign))")
        defer {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            debugLog("[VerifyCertificateOperation] execute() took: \(String(format: "%.3fs", elapsed))")
        }
        try await super.executePreconditionCheck(parentProgress: parentProgress)
        self.setProgress(10)
        
        let team = try await AuthManager.shared.getAuthenticatedTeam()
        
        let bundleID = self.context.targetBundleIdentifier
        let (appName, installedAppSerial, initialStatus) = await self.fetchInstalledAppInitialState(bundleID: bundleID)
        var finalStatus = initialStatus
        
        do {
            // 2. Obtain active portal certificates directly from Apple Developer Portal
            let portalCertificates = try await DeveloperPortalProxy.shared.fetchCertificates(team: team)
            
            self.setProgress(30)
            
            let portalCertificateSerials = Set(portalCertificates.compactMap { $0.serialNumber })
            let signingCertificateSerial = self.context.targetSigningCertificate?.serialNumber
            
            debugLog("""
            [VerifyCertificateOperation] Parameter Accountability for '\(appName)' (\(bundleID)):
              • installedAppSerial           : \(installedAppSerial ?? "nil")
              • overrideCertSerial           : \(self.context.overrideSigningCertificate?.serialNumber ?? "nil")
              • activeCertSerial             : \(self.context.activeSigningCertificate?.serialNumber ?? "nil")
              • targetSigningCertSerial      : \(signingCertificateSerial ?? "nil")
              • portalCertificateSerials (\(portalCertificateSerials.count))  : \(Array(portalCertificateSerials))
              • willResign                   : \(self.willResign)
            """)
            
            if !willResign {
                debugLog("[VerifyCertificateOperation] Running in verification-only mode (!willResign) for '\(appName)'...")
                
                guard let appBundle = self.context.targetAppBundle else {
                    throw OperationError.invalidParameters("VerifyCertificateOperation: targetAppBundle is missing in context.")
                }
                guard let binaryCert = CertificateManager.shared.getSigningCertificate(at: appBundle.fileURL) else {
                    throw OperationError.invalidParameters("Could not locate signing certificate for '\(appName)'.")
                }
                
                let result = await validateCertificate(binaryCert, portalCertificateSerials: portalCertificateSerials, signingCertificateSerial: signingCertificateSerial)
                finalStatus = result
                self.context.targetCertStatus = result
                try processValidationResult(result, certificate: binaryCert, appName: appName, installedAppSerial: installedAppSerial, portalCertificateSerials: portalCertificateSerials, team: team)
                
            } else {
                // resigning branch
                debugLog("[VerifyCertificateOperation] Running in signing mode (resigning) for '\(appName)'...")
                
                let certType = self.context.overrideSigningCertificate != nil ? "Override" : "Active"
                guard let target = self.context.targetSigningCertificate else {
                    throw OperationError.invalidParameters("\(certType) certificate is missing.")
                }
                
                let result = await validateCertificate(target.x509, portalCertificateSerials: portalCertificateSerials, signingCertificateSerial: signingCertificateSerial)
                finalStatus = result
                self.context.targetCertStatus = result
                try processValidationResult(result, certificate: target.x509, appName: appName, installedAppSerial: installedAppSerial, portalCertificateSerials: portalCertificateSerials, team: team)
            }
            
            await self.persistStateIfChanged(bundleID: bundleID, status: finalStatus, initialStatus: initialStatus)
            self.setProgress(100)
        } catch {
            await self.persistStateIfChanged(bundleID: bundleID, status: finalStatus, initialStatus: initialStatus)
            throw error
        }
    }

    private func validateCertificate(_ certificate: ALTX509Certificate,
                                     portalCertificateSerials: Set<String>,
                                     signingCertificateSerial: String?) async -> CertificateStatus {
        if portalCheck(certificate, portalCertificateSerials: portalCertificateSerials) 
        {
            let isCrossSigned = (signingCertificateSerial != nil && !signingCertificateSerial!.isEmpty && certificate.serialNumber != signingCertificateSerial)
            debugLog("[VerifyCertificateOperation] validateCertificate: Found in portal (isCrossSigned: \(isCrossSigned)).")
            return .valid(isCrossSigned: isCrossSigned)
        }
        
        debugLog("[VerifyCertificateOperation] validateCertificate: Not in portal active list. Falling back to OCSP check...")
        return await ocspCheck(certificate)
    }

    private func portalCheck(_ certificate: ALTX509Certificate, portalCertificateSerials: Set<String>) -> Bool {
        return portalCertificateSerials.contains(certificate.serialNumber)
    }

    private func ocspCheck(_ certificate: ALTX509Certificate) async -> CertificateStatus {
        do {
            try await OCSPValidator.validate(certificate)
            debugLog("[VerifyCertificateOperation] ocspCheck: Certificate \(certificate.serialNumber) is valid (assuming cross-signed).")
            return .valid(isCrossSigned: true)
        } catch OCSPValidationError.expired {
            debugLog("[VerifyCertificateOperation] ocspCheck: Certificate \(certificate.serialNumber) is EXPIRED.")
            return .expired
        } catch OCSPValidationError.revoked {
            debugLog("[VerifyCertificateOperation] ocspCheck: Certificate \(certificate.serialNumber) is REVOKED.")
            return .revoked
        } catch {
            debugLog("[VerifyCertificateOperation] ocspCheck: OCSP validation error (\(error)). Assuming cross-signed.")
            return .valid(isCrossSigned: true)
        }
    }
    
    private func fetchInstalledAppInitialState(bundleID: String) async -> (name: String, serial: String?, status: CertificateStatus) {
         await DatabaseManager.shared.persistentContainer.performBackgroundTask { context in
             let predicate = NSPredicate(format: "%K == %@", #keyPath(InstalledApp.bundleIdentifier), bundleID)
             if let installedApp = InstalledApp.first(satisfying: predicate, in: context) {
                 return (installedApp.name, installedApp.certificateSerialNumber, installedApp.certificateStatus)
             }
             return (bundleID, nil, .valid(isCrossSigned: false))
         }
    }
    
    private func persistStateIfChanged(bundleID: String, status: CertificateStatus, initialStatus: CertificateStatus) async {
        guard status != initialStatus else { return }
        
        if let installedApp = self.context.installedApp {
            installedApp.certificateStatus = status
        }
        
        await DatabaseManager.shared.persistentContainer.performBackgroundTask { context in
            let predicate = NSPredicate(format: "%K == %@", #keyPath(InstalledApp.bundleIdentifier), bundleID)
            guard let installedApp = InstalledApp.first(satisfying: predicate, in: context) else {
                self.debugLog("[VerifyCertificateOperation] persistStateIfChanged: App with bundleID '\(bundleID)' not found in database.")
                return
            }
            
            if installedApp.certificateStatus != status {
                self.debugLog("[VerifyCertificateOperation] State changed in database context for \(installedApp.name). New Status: \(status)")
                installedApp.certificateStatus = status
                do {
                    try context.save()
                    self.debugLog("[VerifyCertificateOperation] Saved background context successfully.")
                } catch {
                    self.debugLog("[VerifyCertificateOperation] Failed to save background context: \(error)")
                }
            }
        }
    }
    
    private func processValidationResult(_ result: CertificateStatus, certificate: ALTX509Certificate,
                                         appName: String, installedAppSerial: String?,
                                         portalCertificateSerials: Set<String>, team: ALTTeam) throws {
        let validationContext = CertificateValidationContext(
            willResign: self.willResign,
            checkedCertificateSerial: certificate.serialNumber,
            installedAppSerial: installedAppSerial,
            activeCertificateSerial: self.context.activeSigningCertificate?.serialNumber,
            overrideCertificateSerial: self.context.overrideSigningCertificate?.serialNumber,
            portalCertificateSerials: portalCertificateSerials
        )

        // Classify the certificate we actually checked, not a possibly unrelated global identity.
        var customTeam: String?
        if let data = certificate.data {
            let details = parseCertificate(derData: data)
            let belongsToAuthenticatedTeam = details.subject.contains(team.identifier) || details.issuer.contains(team.identifier)
            if !belongsToAuthenticatedTeam {
                let ouPart = details.subject.components(separatedBy: ", ").first { $0.hasPrefix("Organizational Unit=") }
                customTeam = ouPart?.replacingOccurrences(of: "Organizational Unit=", with: "") ?? "Unknown Custom Team"
            }
        }

        debugLog("[VerifyCertificateOperation] \(validationContext.purpose.rawValue): \(result)")
        if let error = validationContext.error(for: result, appName: appName, customTeam: customTeam) {
            throw error
        }
    }
}
