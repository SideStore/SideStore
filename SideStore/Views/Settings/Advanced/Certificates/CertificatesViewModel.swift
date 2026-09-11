//
//  CertificatesViewModel.swift
//  SideStore
//
//  Created by Magesh K on 2026-06-29.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import SideSign

struct PendingImport {
    let url: URL
    let filename: String
}

enum PrivateKeyImportError: LocalizedError {
    case isCertificate
    case invalidKey
    case conversionFailed
    
    var errorDescription: String? {
        switch self {
        case .isCertificate:    return "The selected file is a certificate, not a private key."
        case .invalidKey:       return "The input does not contain a valid private key."
        case .conversionFailed: return "Failed to convert binary private key to PEM format."
        }
    }
}

class CertificatesViewModel: ObservableObject {
    @Published var certificates: [ALTX509Certificate] = []
    @Published var isLoading = false
    @Published var errorMessage: String? = nil {
        didSet { showErrorAlert = errorMessage != nil }
    }
    @Published var showErrorAlert = false
    @Published var activeSerialNumber: String? = nil
    @Published var alertMessage: String? = nil
    @Published var showAlert = false
    @Published var remoteSerials: Set<String> = []
    
    @Published var currentSort: SortOption   = .creationDate
    @Published var isAscending: Bool         = false
    @Published var currentGroup: GroupOption = .none
    
    @Published var isGlobalHideActive = false {
        didSet { revealedSerials.removeAll() }
    }
    @Published var isSectionHideActive = false {
        didSet { revealedSerials.removeAll() }
    }
    @Published var revealedSerials: Set<String> = []
    
    @Published var pendingImports: [PendingImport] = []
    @Published var currentImportIndex = 0
    @Published var showImportProgressSheet = false
    
    @Published var importSuccessCount = 0
    @Published var importFailedCount = 0
    @Published var failedImportsList: [String] = []
    
    @Published var importPasswordInput: String = ""
    @Published var showPasswordPromptForImport: Bool = false
    @Published var showImportSummary: Bool = false
    @Published var showFailuresAlert: Bool = false
    
    var importSummaryMessage: String {
        "Certificate import completed.\nSuccess: \(importSuccessCount)\nFailed: \(importFailedCount)"
    }
    
    var failuresAlertMessage: String {
        failedImportsList.joined(separator: "\n")
    }
    
    var currentImportFilename: String {
        guard currentImportIndex < pendingImports.count else { return "" }
        return pendingImports[currentImportIndex].filename
    }
    
    var lastUsedPassword = ""
    var importedSerialsThisBatch = [String: (hasPrivateKey: Bool, filename: String)]()
    var session: ALTAppleAPISession?
    var team: ALTTeam?
    
    var isPaidAccount: Bool {
        guard let team = self.team else { return false }
        return team.type != .free && team.type != .unknown
    }

    var availableCertificateTypes: [CertificateType] {
        CertificateType.allCases
    }
    
    var isActiveCertThirdParty: Bool {
        guard let activeCert = activeLocalCert,
              let data = activeCert.data,
              let team = self.team else { return false }
        
        let details = parseCertificate(derData: data)
        let subjectContainsTeam = details.subject.contains(team.identifier)
        let issuerContainsTeam = details.issuer.contains(team.identifier)
        
        return !subjectContainsTeam && !issuerContainsTeam
    }
    
    private var activeLocalCert: ALTCertificate? {
        CertificateManager.shared.activeCertificate?.certificate
    }
    
    func fetchActiveSerialNumber() {
        self.activeSerialNumber = activeLocalCert?.serialNumber
    }
    
    func loadLocalCertificates() -> [ALTX509Certificate] {
        return CertificateManager.shared.getAllLocalX509Certificates()
    }
    
    func saveLocalCertificate(_ cert: ALTCertificate) {
        var cert = cert
        if let existing = self.certificates.first(where: { $0.serialNumber == cert.serialNumber }) {
            if cert.machineName == nil { cert.machineName = existing.machineName }
            if cert.machineIdentifier == nil { cert.machineIdentifier = existing.machineIdentifier }
        }
        CertificateManager.shared.saveCertificate(cert)
    }
    
    func deleteLocalCertificate(serialNumber: String) {
        CertificateManager.shared.deleteCertificate(serialNumber: serialNumber)
    }
    
    func loadCertificates(presentingViewController: UIViewController?, isPullToRefresh: Bool = false, completion: (() -> Void)? = nil) {
        if !isPullToRefresh { self.isLoading = true }
        self.errorMessage = nil
        self.fetchActiveSerialNumber()
        
        let localCerts = self.loadLocalCertificates()
        let activeCert = self.activeLocalCert?.x509
        
        var mergedLocal = localCerts
        if let active = activeCert, !mergedLocal.contains(where: { $0.serialNumber == active.serialNumber }) {
            mergedLocal.append(active)
        }
        self.certificates = mergedLocal
        
        Task { @MainActor in
            defer { self.isLoading = false; completion?() }
            guard AuthManager.shared.isAuthenticated else {
                if isPullToRefresh { self.errorMessage = OperationError.notAuthenticated.localizedDescription }
                return
            }
            do {
                self.session = try await AuthManager.shared.getAuthenticatedSession()
                self.team    = try? await AuthManager.shared.getAuthenticatedTeam()
                
                let remoteCerts = try await DeveloperPortalProxy.shared.fetchCertificates()
                var merged = [ALTX509Certificate]()
                var matchedRemoteSerials = Set<String>()
                
                for remoteCert in remoteCerts {
                    if let signable = CertificateManager.shared.getSignableCertificate(for: remoteCert.serialNumber) {
                        self.saveLocalCertificate(signable)
                    } else {
                        CertificateManager.shared.saveX509Certificate(remoteCert)
                    }
                    merged.append(remoteCert)
                    matchedRemoteSerials.insert(remoteCert.serialNumber)
                }
                for localCert in localCerts where !matchedRemoteSerials.contains(localCert.serialNumber) {
                    merged.append(localCert)
                }
                if let active = activeCert, !matchedRemoteSerials.contains(active.serialNumber),
                   !localCerts.contains(where: { $0.serialNumber == active.serialNumber }) {
                    merged.append(active)
                }
                self.certificates  = merged
                self.remoteSerials = matchedRemoteSerials
            } catch {
                if isPullToRefresh && !(error is CancellationError) {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    func startBulkImport(urls: [URL]) {
        self.pendingImports     = urls.map { PendingImport(url: $0, filename: $0.lastPathComponent) }
        self.currentImportIndex = 0
        self.importSuccessCount = 0
        self.importFailedCount  = 0
        self.failedImportsList  = []
        self.importedSerialsThisBatch = [:]
        processNextImport()
    }
    
    func processNextImport() {
        guard currentImportIndex < pendingImports.count else {
            self.pendingImports = []
            self.loadCertificates(presentingViewController: nil)
            showImportSummaryAlert()
            return
        }
        
        let pending = pendingImports[currentImportIndex]
        _ = pending.url.startAccessingSecurityScopedResource()
        defer { pending.url.stopAccessingSecurityScopedResource() }
        
        guard let certData = try? Data(contentsOf: pending.url) else {
            failedImportsList.append("\(pending.filename): Read error.")
            importFailedCount += 1
            currentImportIndex += 1
            processNextImport()
            return
        }
        
        if let rawCert = ALTX509Certificate(data: certData) {
            if isDuplicate(cert: rawCert, importedSerials: importedSerialsThisBatch) {
                failedImportsList.append("\(pending.filename): Duplicate certificate (already imported).")
                importFailedCount += 1
            } else {
                CertificateManager.shared.saveX509Certificate(rawCert)
                recordSuccessfulImport(serial: rawCert.serialNumber, hasPrivateKey: false, filename: pending.filename)
            }
            currentImportIndex += 1
            processNextImport()
            return
        }
        
        if certData.isPKCS12 {
            if !lastUsedPassword.isEmpty {
                do {
                    let altCert = try ALTCertificate(p12Data: certData, password: lastUsedPassword)
                    if isDuplicate(cert: altCert, importedSerials: importedSerialsThisBatch) {
                        failedImportsList.append("\(pending.filename): Duplicate certificate (already imported).")
                        importFailedCount += 1
                    } else {
                        saveLocalCertificate(altCert)
                        recordSuccessfulImport(serial: altCert.serialNumber, hasPrivateKey: true, filename: pending.filename)
                    }
                    currentImportIndex += 1
                    processNextImport()
                    return
                } catch ALTCertificateError.decryptionFailed {
                } catch {
                    failedImportsList.append("\(pending.filename): \(error.localizedDescription)")
                    importFailedCount += 1
                    currentImportIndex += 1
                    processNextImport()
                    return
                }
            }
            
            do {
                let altCert = try ALTCertificate(p12Data: certData)
                if isDuplicate(cert: altCert, importedSerials: importedSerialsThisBatch) {
                    failedImportsList.append("\(pending.filename): Duplicate certificate (already imported).")
                    importFailedCount += 1
                } else {
                    saveLocalCertificate(altCert)
                    recordSuccessfulImport(serial: altCert.serialNumber, hasPrivateKey: true, filename: pending.filename)
                }
                currentImportIndex += 1
                processNextImport()
                return
            } catch ALTCertificateError.decryptionFailed {
                DispatchQueue.main.async {
                    self.importPasswordInput         = ""
                    self.showPasswordPromptForImport = true
                }
                return
            } catch {
                failedImportsList.append("\(pending.filename): \(error.localizedDescription)")
                importFailedCount += 1
                currentImportIndex += 1
                processNextImport()
                return
            }
        }
        
        failedImportsList.append("\(pending.filename): Unsupported certificate or key format.")
        importFailedCount += 1
        currentImportIndex += 1
        processNextImport()
    }
    
    func submitImportPassword() {
        guard currentImportIndex < pendingImports.count else { return }
        let pending  = pendingImports[currentImportIndex]
        
        _ = pending.url.startAccessingSecurityScopedResource()
        defer { pending.url.stopAccessingSecurityScopedResource() }

        guard let certData = try? Data(contentsOf: pending.url) else {
            failedImportsList.append("\(pending.filename): Failed to read file data.")
            importFailedCount += 1
            showPasswordPromptForImport = false
            currentImportIndex += 1
            processNextImport()
            return
        }
        
        do {
            let altCert = try ALTCertificate(p12Data: certData, password: importPasswordInput)
            if isDuplicate(cert: altCert, importedSerials: importedSerialsThisBatch) {
                failedImportsList.append("\(pending.filename): Duplicate certificate (already imported).")
                importFailedCount += 1
            } else {
                saveLocalCertificate(altCert)
                recordSuccessfulImport(serial: altCert.serialNumber, hasPrivateKey: true, filename: pending.filename)
            }
            self.lastUsedPassword = importPasswordInput
            self.showPasswordPromptForImport = false
            currentImportIndex += 1
            processNextImport()
        } catch ALTCertificateError.decryptionFailed {
            self.errorMessage = "Incorrect password for " + pending.filename
        } catch {
            self.showPasswordPromptForImport = false
            failedImportsList.append("\(pending.filename): \(error.localizedDescription)")
            importFailedCount += 1
            currentImportIndex += 1
            processNextImport()
        }
    }
    
    func cancelImport() {
        self.showPasswordPromptForImport = false
        let pending = pendingImports[currentImportIndex]
        failedImportsList.append("\(pending.filename): Password required but skipped.")
        importFailedCount += 1
        currentImportIndex += 1
        processNextImport()
    }
    
    private func showImportSummaryAlert() {
        self.showImportSummary = true
    }
    
    func createCertificate(machineName: String, type: CertificateType = .development, presentingViewController: UIViewController?) {
        self.isLoading = true; self.errorMessage = nil
        Task { @MainActor in
            defer { self.isLoading = false }
            do {
                self.session = try await AuthManager.shared.getAuthenticatedSession()
                self.team    = try? await AuthManager.shared.getAuthenticatedTeam()
                
                let newCert = try await DeveloperPortalProxy.shared.createCertificate(machineName: machineName, type: type)
                self.saveLocalCertificate(newCert)
                self.alertMessage = "\(type.displayName) created successfully."
                self.showAlert    = true
                self.loadCertificates(presentingViewController: presentingViewController)
            } catch {
                if !(error is CancellationError) { self.errorMessage = error.localizedDescription }
            }
        }
    }
    
    func revokeCertificate(_ certificate: ALTX509Certificate, keepLocal: Bool = false, presentingViewController: UIViewController? = nil) {
        guard self.remoteSerials.contains(certificate.serialNumber) else {
            self.errorMessage = "This certificate is already revoked on Apple's servers."
            return
        }
        
        self.isLoading = true; self.errorMessage = nil
        Task { @MainActor in
            defer { self.isLoading = false }
            do {
                self.session = try await AuthManager.shared.getAuthenticatedSession()
                self.team    = try? await AuthManager.shared.getAuthenticatedTeam()
                
                let success = try await DeveloperPortalProxy.shared.revokeCertificate(certificate)
                if success {
                    self.remoteSerials.remove(certificate.serialNumber)
                    if !keepLocal {
                        self.deleteLocalCertificate(serialNumber: certificate.serialNumber)
                        self.certificates.removeAll { $0.serialNumber == certificate.serialNumber }
                        if self.activeSerialNumber == certificate.serialNumber {
                            CertificateManager.shared.clearActiveCertificate()
                            self.activeSerialNumber = nil
                        }
                        self.alertMessage = "Certificate revoked successfully."
                    } else {
                        self.alertMessage = "Certificate revoked on Apple's servers. Local copy preserved."
                    }
                    self.showAlert    = true
                    self.loadCertificates(presentingViewController: presentingViewController)
                } else {
                    self.errorMessage = "Failed to revoke certificate."
                }
            } catch {
                if !(error is CancellationError) { self.errorMessage = error.localizedDescription }
            }
        }
    }
    
    func deleteCertificate(_ certificate: ALTX509Certificate) {
        deleteLocalCertificate(serialNumber: certificate.serialNumber)
        self.certificates.removeAll { $0.serialNumber == certificate.serialNumber }
        if self.activeSerialNumber == certificate.serialNumber {
            CertificateManager.shared.clearActiveCertificate()
            self.activeSerialNumber = nil
        }
        self.alertMessage = "Certificate deleted locally."
        self.showAlert    = true
    }
    
    func makeCertificateActive(_ certificate: ALTX509Certificate) {
        guard let signable = self.getSignableCertificate(for: certificate.serialNumber) else {
            self.errorMessage = "Cannot activate certificate: private key missing."
            return
        }
        do {
            try CertificateManager.shared.setActiveCertificate(signable)
            self.fetchActiveSerialNumber()
            self.alertMessage = "Active signing certificate replaced successfully."
            self.showAlert    = true
        } catch {
            self.errorMessage = "Failed to activate certificate: \(error.localizedDescription)"
        }
    }

    func deactivateActiveCertificate() {
        CertificateManager.shared.clearActiveCertificate()
        self.activeSerialNumber = nil
        self.alertMessage = "Local certificate deactivated."
        self.showAlert    = true
    }
    
    func isCertificateLocallyCached(_ certificate: ALTX509Certificate) -> Bool {
        return CertificateManager.shared.isCertificateLocallyCached(serialNumber: certificate.serialNumber)
    }

    func getSigningCertificate(at url: URL) -> ALTX509Certificate? {
        CertificateManager.shared.getSigningCertificate(at: url)
    }
    
    func getLocalX509Certificate(serialNumber: String) -> ALTX509Certificate? {
        CertificateManager.shared.getLocalX509Certificate(serialNumber: serialNumber)
    }

    func getSignableCertificate(for serialNumber: String) -> ALTCertificate? {
        CertificateManager.shared.getSignableCertificate(for: serialNumber)
    }

    func loadAllSignableLocalCertificates() -> [ALTCertificate] {
        CertificateManager.shared.getAllLocalCertificates()
    }

    func hasPrivateKey(for cert: ALTX509Certificate) -> Bool {
        CertificateManager.shared.getSignableCertificate(for: cert.serialNumber) != nil
    }
    
    func sortCertificates(_ certs: [ALTX509Certificate]) -> [ALTX509Certificate] {
        switch currentSort {
        case .creationDate: return certs.sorted { isAscending ? $0.creationDate < $1.creationDate : $0.creationDate > $1.creationDate }
        case .expiryDate:   return certs.sorted { isAscending ? $0.expiryDate < $1.expiryDate : $0.expiryDate > $1.expiryDate }
        case .name:
            return certs.sorted {
                let cmp = ($0.machineName ?? $0.name).localizedCaseInsensitiveCompare($1.machineName ?? $1.name)
                return isAscending ? cmp == .orderedAscending : cmp == .orderedDescending
            }
        case .keys:
            return certs.sorted {
                let v0 = self.hasPrivateKey(for: $0) ? 1 : 0
                let v1 = self.hasPrivateKey(for: $1) ? 1 : 0
                return isAscending ? v0 < v1 : v0 > v1
            }
        }
    }
    
    var groupedCertificatesList: [GroupedCertificates] {
        let sorted = sortCertificates(certificates)
        switch currentGroup {
        case .none:
            return [GroupedCertificates(name: "Certificates", certificates: sorted)]
        case .keys:
            let withKeys    = sorted.filter { self.hasPrivateKey(for: $0) }
            let withoutKeys = sorted.filter { !self.hasPrivateKey(for: $0) }
            var groups = [GroupedCertificates]()
            if !withKeys.isEmpty    { groups.append(GroupedCertificates(name: "Public + Private Keys", certificates: withKeys)) }
            if !withoutKeys.isEmpty { groups.append(GroupedCertificates(name: "Public Keys Only",      certificates: withoutKeys)) }
            return groups
        case .name:
            let grouped = Dictionary(grouping: sorted) { cert -> String in
                return cert.machineName.flatMap { $0.first.map { String($0).uppercased() } }
                    ?? cert.name.first.map { String($0).uppercased() }
                    ?? "#"
            }
            return grouped.keys.sorted().map { GroupedCertificates(name: $0, certificates: grouped[$0] ?? []) }
        case .creationDate:
            let grouped = Dictionary(grouping: sorted) { cert -> String in
                let year = Calendar.current.component(.year, from: cert.creationDate)
                return year > 1970 ? "Created in \(year)" : "Created (Unknown Date)"
            }
            return grouped.keys.sorted(by: >).map { GroupedCertificates(name: $0, certificates: grouped[$0] ?? []) }
        case .expiryDate:
            let grouped = Dictionary(grouping: sorted) { cert -> String in
                let year = Calendar.current.component(.year, from: cert.expiryDate)
                return year > 1970 ? "Expires in \(year)" : "Expires (Unknown Date)"
            }
            return grouped.keys.sorted(by: <).map { GroupedCertificates(name: $0, certificates: grouped[$0] ?? []) }
        }
    }
    
    func maskPartially(_ string: String) -> String {
        guard string.count > 8 else { return "••••••••" }
        return "\(string.prefix(4))••••••••\(string.suffix(4))"
    }
    
    func displayActiveSerial(_ activeSerial: String) -> String {
        if isActiveSerialMasked(activeSerial) {
            if isGlobalHideActive { return "••••••••••••••••" }
            return maskPartially(activeSerial)
        }
        return activeSerial
    }
    
    func isSerialMasked(for cert: ALTX509Certificate) -> Bool {
        let isRevealed      = revealedSerials.contains(cert.serialNumber)
        let isSectionHidden = isSectionHideActive
        if isGlobalHideActive || isSectionHidden {
            return !isRevealed
        } else {
            return isRevealed
        }
    }
    
    func isActiveSerialMasked(_ activeSerial: String) -> Bool {
        let isRevealed = revealedSerials.contains("active_" + activeSerial)
        if isGlobalHideActive || isSectionHideActive {
            return !isRevealed
        } else {
            return isRevealed
        }
    }
    
    func displaySerial(for cert: ALTX509Certificate) -> String {
        if isSerialMasked(for: cert) {
            if isGlobalHideActive { return "••••••••••••••••" }
            return maskPartially(cert.serialNumber)
        }
        return cert.serialNumber
    }
    
    func displayIdentifier(for cert: ALTX509Certificate) -> String? {
        guard let ident = cert.identifier else { return nil }
        if isSerialMasked(for: cert) { return "••••••••••" }
        return ident
    }
    
    func displayRequester(for cert: ALTX509Certificate) -> String? {
        guard let req = cert.requesterEmail, !req.isEmpty else { return nil }
        if isSerialMasked(for: cert) { return "••••••••••" }
        return req
    }
    
    func displayBriefType(for brief: CertificateBriefInfo, cert: ALTX509Certificate) -> String {
        if isSerialMasked(for: cert) { return "••••••••••" }
        return brief.type
    }
    
    func displayBriefValidity(for brief: CertificateBriefInfo, cert: ALTX509Certificate) -> String {
        if isSerialMasked(for: cert) { return "••••••••••" }
        return "\(brief.validFrom) - \(brief.validUntil)"
    }
    
    private func derToPEM(derData: Data) -> Data? {
        let base64    = derData.base64EncodedString(options: [.lineLength64Characters])
        let pemString = "-----BEGIN PRIVATE KEY-----\n\(base64)\n-----END PRIVATE KEY-----"
        return pemString.data(using: .utf8)
    }
    
    func validateAndFormatPrivateKey(data: Data) throws -> Data {
        if let _ = SecCertificateCreateWithData(nil, data as CFData) { throw PrivateKeyImportError.isCertificate }
        var error: Unmanaged<CFError>?
        let rsaAttr: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA, kSecAttrKeyClass as String: kSecAttrKeyClassPrivate]
        if let _ = SecKeyCreateWithData(data as CFData, rsaAttr as CFDictionary, &error) {
            guard let pem = derToPEM(derData: data) else { throw PrivateKeyImportError.conversionFailed }
            return pem
        }
        let ecAttr: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeEC, kSecAttrKeyClass as String: kSecAttrKeyClassPrivate]
        if let _ = SecKeyCreateWithData(data as CFData, ecAttr as CFDictionary, nil) {
            guard let pem = derToPEM(derData: data) else { throw PrivateKeyImportError.conversionFailed }
            return pem
        }
        if let pemString = String(data: data, encoding: .utf8) {
            let clean = pemString.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasBegin = clean.contains("-----BEGIN PRIVATE KEY-----")    || clean.contains("-----BEGIN RSA PRIVATE KEY-----")
                        || clean.contains("-----BEGIN EC PRIVATE KEY-----") || clean.contains("-----BEGIN DSA PRIVATE KEY-----")
            let hasEnd   = clean.contains("-----END PRIVATE KEY-----")      || clean.contains("-----END RSA PRIVATE KEY-----")
                        || clean.contains("-----END EC PRIVATE KEY-----")   || clean.contains("-----END DSA PRIVATE KEY-----")
            if hasBegin && hasEnd { return data }
        }
        throw PrivateKeyImportError.invalidKey
    }
    
    func importPrivateKey(data: Data, for cert: ALTX509Certificate) {
        do {
            let key = try validateAndFormatPrivateKey(data: data)
            let signable = ALTCertificate(x509: cert, privateKey: key)
            saveLocalCertificate(signable)
            self.loadCertificates(presentingViewController: nil)
            self.alertMessage = "Successfully added private key to certificate \(cert.name)."
            self.showAlert    = true
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
    
    func clearPrivateKey(for cert: ALTX509Certificate) {
        CertificateManager.shared.saveX509Certificate(cert)
        self.loadCertificates(presentingViewController: nil)
        self.alertMessage = "Successfully removed private key from certificate \(cert.name)."
        self.showAlert    = true
    }
    
    private func recordSuccessfulImport(serial: String, hasPrivateKey: Bool, filename: String) {
        if let previous = importedSerialsThisBatch[serial] {
            importSuccessCount -= 1
            importFailedCount += 1
            failedImportsList.append("\(previous.filename): Duplicate certificate (already imported).")
        }
        importedSerialsThisBatch[serial] = (hasPrivateKey, filename)
        importSuccessCount += 1
    }
    
    private func isDuplicate(cert: ALTCertificate, importedSerials: [String: (hasPrivateKey: Bool, filename: String)]) -> Bool {
        if importedSerials[cert.serialNumber] != nil {
            return true
        }
        if self.certificates.contains(where: { $0.serialNumber == cert.serialNumber }) {
            return true
        }
        return false
    }

    private func isDuplicate(cert: ALTX509Certificate, importedSerials: [String: (hasPrivateKey: Bool, filename: String)]) -> Bool {
        if let imported = importedSerials[cert.serialNumber], imported.hasPrivateKey {
            return true
        }
        if self.certificates.contains(where: { $0.serialNumber == cert.serialNumber }) {
            return true
        }
        return false
    }
}
