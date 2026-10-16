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
    
    let signInHandler: SignInHandler
    let anisetteServerHandler: AnisetteServerHandler
    let skipDeviceRegistration: Bool
    let skipCertificateProvisioning: Bool
    let skipResign: Bool
    let skipHowTos: Bool
    let certificateFlow: CertificateProvisioningFlow
    let deviceRegistrationFlow: DeviceRegistrationFlow

    init(
        context: StandaloneOperationContext,
        signInHandler: SignInHandler,
        anisetteServerHandler: AnisetteServerHandler,
        skipDeviceRegistration: Bool = false,
        skipCertificateProvisioning: Bool = false,
        skipResign: Bool = false,
        skipHowTos: Bool = false
    ) throws {
        self.signInHandler = signInHandler
        self.anisetteServerHandler = anisetteServerHandler
        self.skipDeviceRegistration = skipDeviceRegistration
        self.skipCertificateProvisioning = skipCertificateProvisioning
        self.skipResign = skipResign
        self.skipHowTos = skipHowTos
        self.certificateFlow = CertificateProvisioningFlow(
            handler: signInHandler,
            skipCertificateProvisioning: skipCertificateProvisioning
        )
        self.deviceRegistrationFlow = DeviceRegistrationFlow(handler: signInHandler)

        try super.init(context: context)
        self.debugLog("""
        [SignInOperation] Initialized with options:
          • skipDeviceRegistration: \(skipDeviceRegistration)
          • skipCertificateProvisioning: \(skipCertificateProvisioning)
          • skipResign: \(skipResign)
          • skipHowTos: \(skipHowTos)
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
            let authResult = try await self.startAuthentication { [weak self] progress in
                self?.setProgress(progress)
            }
            
            try await self.finalizeAuthentication(result: .success(authResult))
            self.setProgress(100)
            return authResult
        } catch {
            self.debugLog("[SignInOperation] execute caught error during authentication: \(error). Cleaning up...")
            if !AuthManager.shared.hasStoredPassword &&
               !AuthManager.shared.hasStoredXcodeToken
            {
                await AuthManager.shared.signOut()
            }
            try? await self.finalizeAuthentication(result: .failure(error))
            throw error
        }
    }
    
    private func startAuthentication(reportProgress: @escaping @Sendable (Int64) -> Void) async throws -> SignInResult {
        let (account, session) = try await self.authenticationLoop()

        let stepWeight: Int64 = self.skipDeviceRegistration ? 33 : 25
        reportProgress(stepWeight)

        if self.isCancelled { throw OperationError.cancelled }

        // Resolve Team & Save State
        let team = try await self.fetchTeam(for: account, session: session)
        try await self.saveTeamAndAccount(team, makeActive: true)
        reportProgress(stepWeight * 2)

        let authResult = try await self.provision(
            team: team,
            session: session,
            stepWeight: stepWeight,
            reportProgress: reportProgress
        )
        
        return authResult
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
                let errorString = "\(error)"
                if errorString.contains("-80045") || errorString.contains("-45061") {
                    self.debugLog("[SignInOperation] Detected auth error -80045/-45061. Purging stored anisette ADI blob...")
                    AnisetteConfigManager.shared.anisetteAdiBlob = nil
                }
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


    private func provision(team: ALTTeam,
                           session: ALTAppleAPISession,
                           stepWeight: Int64,
                           reportProgress: @escaping @Sendable (Int64) -> Void) async throws -> SignInResult
    {
        if self.isCancelled { throw OperationError.cancelled }

        // 1. Resolve Certificate (Custom vs Developer Portal)
        self.verboseLog("[SignInOperation] Resolving signing certificate...")
        let resolvedCertificate: ALTCertificate?
        if let certificate = try await self.certificateFlow.resolveCertificate(for: team) {
            self.debugLog("[SignInOperation] Resolved signing certificate (serial: \(certificate.serialNumber)).")
            resolvedCertificate = certificate
        } else {
            self.debugLog("[SignInOperation] Certificate resolution skipped by user.")
            await self.signInHandler.showCertificateSkipAcknowledgment()
            resolvedCertificate = nil
        }

        // 2. Register Current Device
        if !self.skipDeviceRegistration {
            self.verboseLog("[SignInOperation] Registering current device...")
            if let device = try await self.deviceRegistrationFlow.registerCurrentDevice(for: team) {
                self.debugLog("[SignInOperation] Registered current device UDID: \(device.identifier).")
                reportProgress(stepWeight * 3)
            } else {
                self.debugLog("[SignInOperation] Device registration skipped by user.")
                await self.signInHandler.showDeviceRegistrationSkipAcknowledgment()
            }
        }

        return SignInResult(
            team: team,
            certificate: resolvedCertificate,
            session: session
        )
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
                
                var didResign = false
                if !self.skipResign,
                   let signingCertificate = certificate,
                   !self.skipCertificateProvisioning,
                   UserDefaults.standard.isDeviceRegistered
                {
                    let resignFlow = CodeSignValidationFlow(handler: self.signInHandler)
                    didResign = try await resignFlow.validateAndResignIfNeeded(
                        team: team,
                        certificate: signingCertificate,
                        portalCertificates: self.certificateFlow.portalCertificates,
                        context: self.context
                    )
                    self.verboseLog("[SignInOperation] finalizeAuthentication: didResign = \(didResign)")
                }
                
                if !self.skipHowTos && !didResign && self.requiresPostAuthFlow {
                    await self.signInHandler.resolvePostAuth()
                    self.verboseLog("[SignInOperation] finalizeAuthentication: post auth flow completed...")
                }
                
                await self.signInHandler.complete()
                self.verboseLog("[SignInOperation] finalizeAuthentication: invoked auth complete for .success case...")
        }
    }
}

// Persistence Helpers
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
}
