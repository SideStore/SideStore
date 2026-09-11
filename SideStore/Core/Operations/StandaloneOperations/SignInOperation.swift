//
//  SignInOperation.swift
//  SideStore
//
//  Created by Magesh K on 7/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

@preconcurrency import UIKit
import Foundation
import CoreData
import SideSign

struct SignInResult {
    let team: ALTTeam
    let certificate: ALTCertificate?
    let session: ALTAppleAPISession
}

final class SignInOperation: BaseStandaloneOperation<StandaloneOperationContext, SignInResult>, @unchecked Sendable {
    
    private var appleIDEmailAddress: String?
    private var requiresPostAuthFlow = false
    private var portalCertificates: [ALTX509Certificate]?
    
    let signInHandler: SignInHandler
    let anisetteServerHandler: AnisetteServerHandler
    let skipDeviceRegistration: Bool
    let skipCertificateProvisioning: Bool

    init(
        context: StandaloneOperationContext,
        signInHandler: SignInHandler,
        anisetteServerHandler: AnisetteServerHandler,
        skipDeviceRegistration: Bool = false,
        skipCertificateProvisioning: Bool = false
    ) throws {
        self.signInHandler = signInHandler
        self.anisetteServerHandler = anisetteServerHandler
        self.skipDeviceRegistration = skipDeviceRegistration
        self.skipCertificateProvisioning = skipCertificateProvisioning

        try super.init(context: context)
        self.debugLog("""
        [SignInOperation] Initialized with options:
          • skipDeviceRegistration: \(skipDeviceRegistration)
          • skipCertificateProvisioning: \(skipCertificateProvisioning)
        """)
    }

    private func getAnisetteData() async throws -> ALTAnisetteData {
        try await AnisetteProvider.fetch(handler: self.anisetteServerHandler)
    }
    
    // Main Pipeline Execution
    override func execute(parentProgress: Progress?) async throws -> SignInResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        debugLog("[SignInOperation] execute() started")
        defer {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            debugLog("[SignInOperation] execute() took: \(String(format: "%.3fs", elapsed))")
        }
        try await super.executePreconditionCheck(parentProgress: parentProgress)

        do {
            let authResult: SignInResult

            if var session = AuthManager.shared.session,
               let team = AuthManager.shared.team,
               (self.skipCertificateProvisioning || CertificateManager.shared.activeCertificate != nil)
            {
                session.anisetteData = try await self.getAnisetteData()
                let certToUse = CertificateManager.shared.activeCertificate?.certificate
                
                self.debugLog("[SignInOperation] Using cached session, team, certificate")
                authResult = SignInResult(
                    team: team, 
                    certificate: certToUse, 
                    session: session
                )
            } else {
                authResult = try await self.startAuthentication { [weak self] progress in
                    self?.setProgress(progress)
                }
            }
            
            try await self.finalizeAuthentication(result: .success(authResult))
            self.setProgress(100)
            return authResult
        } catch {
            self.debugLog("[SignInOperation] execute caught error during authentication: \(error). Cleaning up...")
            if !AuthManager.shared.hasStoredPassword &&
               !AuthManager.shared.hasStoredXcodeToken
            {
                AuthManager.shared.signOut()
            }
            try? await self.finalizeAuthentication(result: .failure(error))
            throw error
        }
    }
    
    private func startAuthentication(reportProgress: @escaping @Sendable (Int64) -> Void) async throws -> SignInResult {
        let (account, session) = if let silentResult = try await self.silentSignIn() {
            silentResult
        } else {
            try await self.authenticationLoop()
        }
        AuthManager.shared.session = session

        let authResult = try await self.provisioningLoop(
            account: account,
            session: session,
            reportProgress: reportProgress
        )
        
        return authResult
    }

    private func provisioningLoop(account: ALTAccount,
                                  session: ALTAppleAPISession,
                                  reportProgress: @escaping @Sendable (Int64) -> Void) async throws -> SignInResult
    {
        let stepWeight: Int64 = self.skipDeviceRegistration ? 33 : 25
        reportProgress(stepWeight)

        var resolvedTeam: ALTTeam?
        var resolvedCertificate: ALTCertificate?

        var isCertificateResolved = false
        var isDeviceRegistered = false

        while true {
            if self.isCancelled { throw OperationError.cancelled }

            do {
                // 1. Resolve Team & Save State
                if resolvedTeam == nil {
                    let team = try await self.fetchTeam(for: account, session: session)
                    AuthManager.shared.team = team

                    try await self.saveTeamAndAccount(team)
                    reportProgress(stepWeight * 2)
                    resolvedTeam = team
                }

                guard let team = resolvedTeam else { continue }

                // 2. Resolve Certificate (Custom vs Developer Portal)
                if !isCertificateResolved {
                    let activeCert = CertificateManager.shared.activeCertificate?.certificate
                    let isCustomCert = activeCert?.data.map { data in
                        let details = parseCertificate(derData: data)
                        return !details.subject.contains(team.identifier) && !details.issuer.contains(team.identifier)
                    } ?? false
                    if isCustomCert {
                        self.debugLog("[SignInOperation] Custom active certificate detected (Subject OU mismatch with Team ID '\(team.identifier)'). Bypassing portal fetch.")
                        resolvedCertificate = activeCert
                    } else if self.skipCertificateProvisioning {
                        resolvedCertificate = activeCert
                    } else {
                        let certificate = try await self.fetchCertificate(for: team, session: session)
                        try CertificateManager.shared.setActiveCertificate(certificate)
                        resolvedCertificate = certificate
                    }
                    isCertificateResolved = true
                }

                guard isCertificateResolved else { continue }

                // 3. Register Current Device
                if !isDeviceRegistered {
                    if !self.skipDeviceRegistration {
                        self.verboseLog("[SignInOperation] Registering current device...")
                        let device = try await self.registerCurrentDevice(for: team, session: session)
                        self.debugLog("[SignInOperation] Registered current device UDID: \(device.identifier).")
                        reportProgress(stepWeight * 3)
                    }
                    isDeviceRegistered = true
                }

                return SignInResult(
                    team: team,
                    certificate: resolvedCertificate,
                    session: session
                )
                
            } catch {
                if self.isCancelled { throw OperationError.cancelled }

                self.debugLog("[SignInOperation] provisioningLoop caught error: \(error)")
                let decision = await self.signInHandler.resolveProvisioningError(error)
                switch decision {
                    case .retry:
                        self.debugLog("[SignInOperation] User chose retry in provisioningLoop")
                        continue
                    case .cancel:
                        self.debugLog("[SignInOperation] User cancelled in provisioningLoop")
                        throw OperationError.cancelled
                }
            }
        }
    }
    
    private func silentSignIn() async throws -> (ALTAccount, ALTAppleAPISession)? {
        // Try silent auth using Keychain Token
        if let adsid = AuthManager.shared.adsid, 
           let xcodeToken = AuthManager.shared.xcodeToken 
        {
            self.verboseLog("[SignInOperation] Authenticating Apple ID with tokens...")

            do {
                let anisetteData = try await self.getAnisetteData()
                let xcodeVersion = await AnisetteConfigManager.shared.resolvedXcodeVersion()

                return try await AuthManager.shared.authenticateWithToken(
                    adsid: adsid,
                    xcodeToken: xcodeToken, 
                    anisetteData: anisetteData, 
                    xcodeVersion: xcodeVersion
                )
            } catch {
                self.debugLog("[SignInOperation] Token authentication failed: \(error)")
            }
        }
        
        // Try silent auth using Keychain Password
        if let appleID = AuthManager.shared.currentAppleID, 
           let password = AuthManager.shared.password 
        {
            self.debugLog("[SignInOperation] Authenticating Apple ID with saved password...")
            do {
                return try await self.signIn(appleID: appleID, password: password)
            } catch {
                self.debugLog("[SignInOperation] Saved password authentication failed: \(error)")
            }
        }

        return nil
    }

    private func authenticationLoop() async throws -> (account: ALTAccount, session: ALTAppleAPISession) {
        self.verboseLog("[SignInOperation] authenticationLoop: Requesting credentials...")
        let handler = self.signInHandler
        
        while true {
            let (appleID, password) = try await handler.credentials()
            if self.isCancelled { throw OperationError.cancelled }
            
            do {
                let (account, session) = try await self.signIn(appleID: appleID, password: password)
                self.debugLog("[SignInOperation] authenticationLoop: signIn succeeded.")
                
                await handler.handleSignInResult(.success((account, session)))
                
                self.requiresPostAuthFlow = true
                return (account, session)
            } catch {
                self.debugLog("[SignInOperation] authenticationLoop: Attempt failed with error: \(error)")
                await handler.handleSignInResult(.failure(error))
            }
        }
    }
    
    private func signIn(appleID: String, password: String) async throws -> (ALTAccount, ALTAppleAPISession) {
        self.appleIDEmailAddress = appleID
        
        let anisetteData = try await self.getAnisetteData()
        let handler = self.signInHandler
        
        let xcodeVersion = await AnisetteConfigManager.shared.resolvedXcodeVersion()

        let (account, session) = try await AuthManager.shared.signIn(
            appleID: appleID,
            password: password,
            anisetteData: anisetteData,
            xcodeVersion: xcodeVersion,
            accountRepairHandler: { url, message in
                await handler.accountRepair(url: url, message: message)
            },
            verificationHandler: { request in
                try await handler.verificationCode(for: request)
            }
        )
        
        AuthManager.shared.adsid = session.dsid
        AuthManager.shared.xcodeToken = session.authToken
        AuthManager.shared.currentAppleID = appleID
        AuthManager.shared.password = password
        
        return (account, session)
    }

    private func finalizeAuthentication(result: Result<SignInResult, Error>) async throws {
        self.verboseLog("[SignInOperation] finalizeAuthentication: Starting cleanup...")
        
        switch result {
            case .failure(let error):
                self.debugLog("[SignInOperation] finalizeAuthentication: Failure result - \(error.localizedDescription)")
                await self.signInHandler.complete()
                self.verboseLog("[SignInOperation] finalizeAuthentication: invoked auth complete for .failure case...")
                
            case .success(let result):
                let team = result.team
                let certificate = result.certificate
                let session = result.session

                self.verboseLog("[SignInOperation] finalizeAuthentication: Authentication Success for team \(team.identifier) account.")
                do {
                    try await self.saveTeamAndAccount(team, makeActive: true)
                } catch {
                    self.debugLog("[SignInOperation] finalizeAuthentication: error occured when performing cleanup: \(error)")
                }
                self.verboseLog("[SignInOperation] finalizeAuthentication: Database updates completed.")
                
                if let signingCertificate = certificate, !self.skipCertificateProvisioning
                {
                    let signer = ALTSigner(team: team, certificate: signingCertificate)
                    let didResign = try await self.validateCodeSign(signer: signer, session: session)
                    self.verboseLog("[SignInOperation] finalizeAuthentication: didResign = \(didResign)")
                    
                    if !didResign && self.requiresPostAuthFlow {
                        await self.signInHandler.resolvePostAuth()
                        self.verboseLog("[SignInOperation] finalizeAuthentication: post auth flow completed...")
                    }
                }
                
                await self.signInHandler.complete()
                self.verboseLog("[SignInOperation] finalizeAuthentication: invoked auth complete for .success case...")
        }
    }
}

// Persistence and Codesign Validity Check Helpers
private extension SignInOperation {

    private func saveTeamAndAccount(_ altTeam: ALTTeam, makeActive: Bool = false) async throws {
        let context = self.context.dbBackgroundContext
        try await context.perform {
            let account: Account
            let team: Team
            
            let accountIdentifier = altTeam.account?.identifier ?? altTeam.identifier
            if let tempAccount = Account.first(satisfying: NSPredicate(format: "%K == %@", #keyPath(Account.identifier), accountIdentifier), in: context) {
                account = tempAccount
            } else if let altAccount = altTeam.account {
                account = Account(altAccount, context: context)
            } else {
                let altAccount = ALTAccount(appleID: self.appleIDEmailAddress ?? "", identifier: accountIdentifier)
                account = Account(altAccount, context: context)
            }
            
            if let tempTeam = Team.first(satisfying: NSPredicate(format: "%K == %@", #keyPath(Team.identifier), altTeam.identifier), in: context) {
                team = tempTeam
            } else {
                team = Team(altTeam, account: account, context: context)
            }
            
            if let altAccount = altTeam.account {
                account.update(account: altAccount)
            }

            if let providedEmailAddress = self.appleIDEmailAddress {
                account.appleID = providedEmailAddress
            }
            
            team.update(team: altTeam)
            
            if makeActive {
                // Account
                account.isActiveAccount = true
                let otherAccountsFetchRequest = Account.fetchRequest() as NSFetchRequest<Account>
                otherAccountsFetchRequest.predicate = NSPredicate(format: "%K != %@", #keyPath(Account.identifier), account.identifier)
                let otherAccounts = try context.fetch(otherAccountsFetchRequest)
                for otherAccount in otherAccounts {
                    otherAccount.isActiveAccount = false
                }

                // Team
                team.isActiveTeam = true
                let otherTeamsFetchRequest = Team.fetchRequest() as NSFetchRequest<Team>
                otherTeamsFetchRequest.predicate = NSPredicate(format: "%K != %@", #keyPath(Team.identifier), team.identifier)
                let otherTeams = try context.fetch(otherTeamsFetchRequest)
                for otherTeam in otherTeams {
                    otherTeam.isActiveTeam = false
                }

                let isSparseRestorePatched   = ProcessInfo().sparseRestorePatched
                let isAppLimitDisabled       = UserDefaults.standard.isAppLimitDisabled

                UserDefaults.standard.activeAppsLimit = nil
                if team.type == .free {
                    if !isAppLimitDisabled && isSparseRestorePatched ||
                        isAppLimitDisabled && !isSparseRestorePatched 
                    {
                        UserDefaults.standard.activeAppsLimit = InstalledApp.freeAccountActiveAppsLimit
                    }
                }
            }
            
            try context.save()
        }
    }
    
    private func validateCodeSign(signer: ALTSigner, session: ALTAppleAPISession) async throws -> Bool {
        self.verboseLog("[SignInOperation] validateCodeSign: entering method")
        guard let appBundle = ALTApplication(fileURL: Bundle.Info.activeBundleURL), 
              let provisioningProfile = appBundle.provisioningProfile else 
        {
            self.verboseLog("[SignInOperation] validateCodeSign: Application bundle or provisioning profile nil, returning false")
            return false
        }
        
        let portalCertificates: [ALTX509Certificate]
        if let cached = self.portalCertificates {
            portalCertificates = cached
        } else {
            let fetched = try await DeveloperPortalProxy.shared.fetchCertificates(team: signer.team)
            self.portalCertificates = fetched
            portalCertificates = fetched
        }
        
        let result = CodeSignValidator.validate(
            runningProfile: provisioningProfile,
            portalCertificates: portalCertificates,
            signerCertificate: signer.certificate.x509,
            signerTeam: signer.team
        )
        
        switch result {
            case .success:
                self.verboseLog("[SignInOperation] validateCodeSign: Validation succeeded, no resign required.")
                return false
                
            case .failure(let reason):
                self.debugLog("[SignInOperation] Signing certificate mismatch detected: \(reason)")
                
                if signer.team.type != .free && (reason == .privateKeyLost || reason == .externalSigner) {
                    self.debugLog("[SignInOperation] Running certificate is still active on the Paid account portal. Skipping resign screen.")
                    return false
                }
                
                let handler = self.signInHandler
                do {
                    return try await handler.resolveResign(mismatchReason: reason, context: self.context)
                } catch {
                    self.verboseLog("[SignInOperation] validateCodeSign: error occured when handling resolveResign error: \(error)")
                    return false
                }
        }
    }
}

// Team, Certificate Resolution & Device Registration Helpers
private extension SignInOperation {

    private func fetchTeam(for account: ALTAccount, session: ALTAppleAPISession) async throws -> ALTTeam {
        self.verboseLog("[SignInOperation] fetchTeam: Requesting teams from Apple...")
        let teams = try await DeveloperPortalProxy.shared.fetchTeams(for: account)
        
        guard !teams.isEmpty else {
            throw DeveloperPortalError.noTeams
        }
        
        let selectedTeam: ALTTeam
        if teams.count == 1 {
            selectedTeam = teams[0]
        } else {
            self.debugLog("[SignInOperation] Multiple teams found (\(teams.count)). Prompting user for team selection...")
            selectedTeam = try await self.signInHandler.resolveTeam(teams)
        }
        
        self.debugLog("[SignInOperation] fetchTeam completed successfully ('\(selectedTeam.name)').")
        return selectedTeam
    }

    private func fetchCertificate(for team: ALTTeam, session: ALTAppleAPISession) async throws -> ALTCertificate {
        let portalCertificates = try await DeveloperPortalProxy.shared.fetchCertificates(team: team)
        self.portalCertificates = portalCertificates
        
        let mainBundleCertSerial = Bundle.main.object(forInfoDictionaryKey: Bundle.Info.certificateID) as? String
        
        if let activeCert = CertificateManager.shared.activeCertificate,
           let certificate = portalCertificates.first(where: { $0.serialNumber == activeCert.serialNumber }) 
        {
            var keyStoreCert = activeCert.certificate
            keyStoreCert.machineIdentifier = certificate.machineIdentifier

            if let mainBundleCertSerial = mainBundleCertSerial, 
                mainBundleCertSerial.lowercased() != activeCert.serialNumber.lowercased() 
            {
                self.debugLog("[SignInOperation] Active certificate (\(activeCert.serialNumber)) and running bundle certificate (\(mainBundleCertSerial)) mismatch detected. Running Bundle Certificate is still active on the Paid account portal. Using active Keychain certificate.")
            }
            return keyStoreCert
        }
        
        if let mainBundleCertSerial = mainBundleCertSerial,
           let certificate = portalCertificates.first(where: { $0.serialNumber.lowercased() == mainBundleCertSerial.lowercased() }),
           var cert = CertificateManager.shared.getSignableCertificate(for: mainBundleCertSerial, fallbackPassword: certificate.machineIdentifier) 
        {
            cert.machineIdentifier = certificate.machineIdentifier
            self.debugLog("[SignInOperation] Using running bundle certificate (\(cert.serialNumber)) with valid private key from signable cache.")
            return cert
        }
        
        if portalCertificates.isEmpty {
            return try await self.requestCertificate(for: team, session: session)
        } else {
            return try await self.replaceCertificate(portalCertificates: portalCertificates, for: team, session: session)
        }
    }

    private func requestCertificate(for team: ALTTeam, session: ALTAppleAPISession) async throws -> ALTCertificate {
        let deviceName = await UIDevice.current.name
        let accountName = team.account?.firstName ?? team.name
        let machineName: String = "SideStore - \(accountName)'s \(deviceName)"
        self.verboseLog("[SignInOperation] Requesting certificate for machineName '\(machineName)'...")

        do {
            let newPortalCertificate = try await DeveloperPortalProxy.shared.createCertificate(machineName: machineName, team: team)
            self.debugLog("[SignInOperation] Successfully requested new portal certificate (Serial: \(newPortalCertificate.serialNumber)).")
            
            let portalCertificates = try await DeveloperPortalProxy.shared.fetchCertificates(team: team)
            self.portalCertificates = portalCertificates

            let finalCert: ALTCertificate
            if let fullX509 = portalCertificates.first(where: { $0.serialNumber.lowercased() == newPortalCertificate.serialNumber.lowercased() }) {
                finalCert = ALTCertificate(x509: fullX509, privateKey: newPortalCertificate.privateKey)
            } else {
                finalCert = newPortalCertificate
            }

            return finalCert
        } catch {
            self.debugLog("[SignInOperation] requestCertificate: Failed with error: \(error)")
            throw error
        }
    }

    private func replaceCertificate(portalCertificates: [ALTX509Certificate], for team: ALTTeam, session: ALTAppleAPISession) async throws -> ALTCertificate {
        let iosCertificates = portalCertificates.filter { cert in
            let nameLower = cert.name.lowercased()
            return nameLower.contains("ios development") || nameLower.contains("iphone developer")
        }

        self.debugLog("[SignInOperation] replaceCertificate: Starting. Total certs on portal: \(portalCertificates.count), iOS Development certs: \(iosCertificates.count)")
        
        if iosCertificates.isEmpty {
            self.verboseLog("[SignInOperation] replaceCertificate: No iOS Development certificates found on portal. Requesting new...")
            return try await self.requestCertificate(for: team, session: session)
        }
        
        self.debugLog("[SignInOperation] replaceCertificate: Presenting revoke alert for \(iosCertificates.count) iOS Development cert(s)...")
        let action = try await self.signInHandler.resolveRevocation(certificates: iosCertificates, teamType: team.type)
        self.debugLog("[SignInOperation] replaceCertificate: User action was \(action)")
        switch action {
            case .keepExisting:
                self.verboseLog("[SignInOperation] replaceCertificate: Keeping existing, calling requestCertificate...")
                return try await self.requestCertificate(for: team, session: session)
                
            case .revokeSelected(let certsToRevoke):
                self.debugLog("[SignInOperation] replaceCertificate: Revoking \(certsToRevoke.count) selected certificate(s)...")
                var firstError: Error? = nil

                for certificate in certsToRevoke {
                    do {
                        self.verboseLog("[SignInOperation] replaceCertificate: Revoking certificate '\(certificate.machineName ?? certificate.name)' (Serial: \(certificate.serialNumber))...")
                        _ = try await DeveloperPortalProxy.shared.revokeCertificate(certificate, team: team)
                        self.verboseLog("[SignInOperation] replaceCertificate: Revoke succeeded.")
                    } catch {
                        self.debugLog("[SignInOperation] replaceCertificate: Revoke failed with error: \(error)")
                        if firstError == nil {
                            firstError = error
                        }
                    }
                }

                if let error = firstError {
                    self.debugLog("[SignInOperation] replaceCertificate: Error occurred during revocation, throwing...")
                    throw error
                } else {
                    self.debugLog("[SignInOperation] replaceCertificate: Selected certificates successfully revoked. Requesting new certificate...")
                    return try await self.requestCertificate(for: team, session: session)
                }
        }
    }
    
    @discardableResult
    private func registerCurrentDevice(for team: ALTTeam, session: ALTAppleAPISession) async throws -> ALTDevice {
        self.debugLog("[SignInOperation] registerCurrentDevice starting...")
        var deviceUDID: String?
        do {
            await CellularRefreshManager.shared.turnOffDataIfNeeded()
            deviceUDID = try await fetchUDID()
            await CellularRefreshManager.shared.turnOnDataIfNeeded(addOnDelay: 2.0)
        } catch {
            await CellularRefreshManager.shared.turnOnDataIfNeeded(addOnDelay: 2.0)
            self.debugLog("[SignInOperation] fetchUDID failed: \(error)")
        }
        
        if deviceUDID == nil || deviceUDID?.isEmpty == true || deviceUDID == "XXXXX-XXXX-XXXXX-XXXX" {
            deviceUDID = try? await fetchUDID(useStatic: true)
        }
        
        guard let udid = deviceUDID, !udid.isEmpty, udid != "XXXXX-XXXX-XXXXX-XXXX" else {
            self.debugLog("[SignInOperation] Failed to fetch device UDID.")
            throw OperationError.unknownUDID
        }
        self.debugLog("[SignInOperation] Fetched device UDID: \(udid). Fetching team devices...")
        
        let devices = try await DeveloperPortalProxy.shared.fetchDevices(for: team, types: .all)
        if let device = devices.first(where: { $0.identifier == udid }) {
            self.debugLog("[SignInOperation] Device '\(device.name)' (UDID: \(udid)) is registered on team.")
            return device
        } else {
            let deviceName = await MainActor.run { UIDevice.current.name }
            self.debugLog("[SignInOperation] Registering new device '\(deviceName)' (UDID: \(udid))...")
            let device = try await DeveloperPortalProxy.shared.registerDevice(name: deviceName, identifier: udid, type: DeveloperPortalProxy.currentDeviceType, team: team)
            self.debugLog("[SignInOperation] Device '\(device.name)' (UDID: \(udid)) successfully registered.")
            return device
        }
    }
}
