//
//  CertificateValidationContext.swift
//  SideStore
//

import Foundation

/// Describes the certificate actually checked, independently of the app's database record.
public struct CertificateValidationContext: Equatable, Sendable {
    static let purposeErrorKey = "SideStoreCertificateValidationPurpose"

    /// Toasts and resign alerts otherwise display only the description/failure reason.
    static func message(for error: NSError, description: String? = nil) -> String {
        let description = description ?? error.localizedDescription
        guard error.userInfo[purposeErrorKey] != nil, let recovery = error.localizedRecoverySuggestion else {
            return description
        }
        return description + "\n\n" + recovery
    }

    public enum Purpose: String, Sendable {
        case existingSignature
        case defaultSigningIdentity
        case appSpecificSigningIdentity
    }

    let purpose: Purpose
    let checkedCertificateSerial: String
    let installedAppSerial: String?
    let activeCertificateSerial: String?
    let overrideCertificateSerial: String?
    let isPresentOnPortal: Bool

    init(willResign: Bool, checkedCertificateSerial: String, installedAppSerial: String?,
         activeCertificateSerial: String?, overrideCertificateSerial: String?,
         portalCertificateSerials: Set<String>) {
        self.purpose = !willResign ? .existingSignature :
            (overrideCertificateSerial != nil ? .appSpecificSigningIdentity : .defaultSigningIdentity)
        self.checkedCertificateSerial = checkedCertificateSerial
        self.installedAppSerial = installedAppSerial
        self.activeCertificateSerial = activeCertificateSerial
        self.overrideCertificateSerial = overrideCertificateSerial
        self.isPresentOnPortal = portalCertificateSerials.contains(checkedCertificateSerial)
    }

    /// Portal membership is diagnostic evidence only. Validation has already decided the status.
    func error(for status: CertificateStatus, appName: String, customTeam: String?) -> OperationError? {
        switch status {
        case .valid:
            return nil
        case .revoked:
            if let customTeam {
                return .customCertificateRevoked(appName: appName, activeTeam: customTeam, context: self)
            }
            return .certificateRevoked(appName: appName, context: self)
        case .expired:
            if let customTeam {
                return .customCertificateExpired(appName: appName, activeTeam: customTeam, context: self)
            }
            return .certificateExpired(appName: appName, context: self)
        }
    }

    func failureReason(appName: String, expired: Bool) -> String {
        let format: String
        switch (purpose, expired) {
        case (.defaultSigningIdentity, false):
            format = NSLocalizedString("The default local signing certificate selected to sign “%@” has been revoked.", comment: "Certificate selected for a signing operation")
        case (.defaultSigningIdentity, true):
            format = NSLocalizedString("The default local signing certificate selected to sign “%@” has expired.", comment: "Certificate selected for a signing operation")
        case (.appSpecificSigningIdentity, false):
            format = NSLocalizedString("The app-specific signing certificate selected to sign “%@” has been revoked.", comment: "Certificate override selected for a signing operation")
        case (.appSpecificSigningIdentity, true):
            format = NSLocalizedString("The app-specific signing certificate selected to sign “%@” has expired.", comment: "Certificate override selected for a signing operation")
        case (.existingSignature, false):
            format = NSLocalizedString("The certificate in the existing signature of “%@” has been revoked.", comment: "Certificate checked in the target app bundle")
        case (.existingSignature, true):
            format = NSLocalizedString("The certificate in the existing signature of “%@” has expired.", comment: "Certificate checked in the target app bundle")
        }
        return String(format: format, appName)
    }

    static let dataWarning = NSLocalizedString("Deleting the app does not repair the selected signing identity and can erase its local data.", comment: "Certificate recovery data loss warning")

    static let certificateManagement = NSLocalizedString("Open Settings → Advanced → Certificates. Signing requires a valid certificate with its private key; a certificate listed on the Developer Portal alone is not enough.", comment: "Local certificate management recovery")

    static let existingSignatureRecovery = NSLocalizedString("Before using Resign, check Settings → Advanced → Certificates for a valid signing identity with its private key, and check this app's Change Certificate selection. Then re-sign the app in place. If reinstalling is needed, install over the existing app without deleting it first.", comment: "Recovery for a failed existing signature")

    var recoverySuggestion: String {
        let nextStep: String
        switch purpose {
        case .defaultSigningIdentity:
            nextStep = Self.certificateManagement + " " + NSLocalizedString("Use Activate on a valid local certificate with its private key to change the default, then retry.", comment: "Default signing identity recovery")
        case .appSpecificSigningIdentity:
            nextStep = Self.certificateManagement + " " + NSLocalizedString("Use this app's Change Certificate menu to select a valid signing identity with its private key before retrying. Changing only the default may leave the app-specific selection in use.", comment: "App-specific signing identity recovery")
        case .existingSignature:
            nextStep = Self.existingSignatureRecovery
        }
        return Self.dataWarning + "\n\n" + nextStep
    }

    /// Keep identifiers in Error Details, not the main message. Never include certificate
    /// subjects, account information, device identifiers, private keys, or passwords here.
    var diagnosticDetails: String {
        """
        certificateValidationPurpose: \(purpose.rawValue)
        checkedCertificateSerial: \(checkedCertificateSerial)
        installedAppSerial: \(installedAppSerial ?? "nil")
        activeCertificateSerial: \(activeCertificateSerial ?? "nil")
        overrideCertificateSerial: \(overrideCertificateSerial ?? "nil")
        checkedCertificatePresentOnPortal: \(isPresentOnPortal)
        """
    }
}
