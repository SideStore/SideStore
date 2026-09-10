//
//  OperationStep.swift
//  SideStore
//
//  Created by Magesh K on 30/07/26.
//  Copyright © 2026 AltStore. All rights reserved.
//

import Foundation

protocol OperationStep: Equatable, Hashable {}

enum PipelineStep: OperationStep {
    case backupAppData
    case cacheApp
    case cleanStagedApp
    case deactivateApp
    case downloadApp
    case exportResignedIPA
    case fetchProvisioningProfiles
    case installApp
    case markAppInactive
    case stageBackupApp
    case changeAppIcon
    case prepareAppExtensionBundleIDs
    case preflightChecks
    case refreshApp
    case removeApp
    case removeBackupData
    case removeAppExtensions
    case resignApp
    case restoreAppData
    case sendApp
    case stageApp
    case uninstallApp
    case userCustomization
    case verifyApp
    case verifyCertificate
    case updateAppCertificate
    case embedSigningCert
    case cacheSigningCert
    case createIPA

    fileprivate static let stepMap: [ObjectIdentifier: PipelineStep] = [
        ObjectIdentifier(PerformBackupRestoreOperation.self):             .backupAppData,
        ObjectIdentifier(CacheAppOperation.self):                         .cacheApp,
        ObjectIdentifier(CacheSigningCertOperation.self):                 .cacheSigningCert,
        ObjectIdentifier(CleanStagedAppOperation.self):                   .cleanStagedApp,
        ObjectIdentifier(DeactivateAppOperation.self):                    .deactivateApp,
        ObjectIdentifier(DownloadAppOperation.self):                      .downloadApp,
        ObjectIdentifier(ExportResignedIpaOperation.self):                .exportResignedIPA,
        ObjectIdentifier(FetchProvisioningProfilesOperation.self):        .fetchProvisioningProfiles,
        ObjectIdentifier(InstallAppOperation.self):                       .installApp,
        ObjectIdentifier(MarkAppInactiveOperation.self):                  .markAppInactive,
        ObjectIdentifier(StageBackupAppOperation.self):                   .stageBackupApp,
        ObjectIdentifier(ChangeAppIconOperation.self):                    .changeAppIcon,
        ObjectIdentifier(PrepareAppExtensionBundleIDsOperation.self):     .prepareAppExtensionBundleIDs,
        ObjectIdentifier(PreflightChecksOperation.self):                  .preflightChecks,
        ObjectIdentifier(RefreshAppOperation.self):                       .refreshApp,
        ObjectIdentifier(RemoveBackupDataOperation.self):                 .removeBackupData,
        ObjectIdentifier(RemoveAppExtensionsOperation.self):              .removeAppExtensions,
        ObjectIdentifier(RemoveAppOperation.self):                        .removeApp,
        ObjectIdentifier(ResignAppOperation.self):                        .resignApp,
        ObjectIdentifier(CreateIpaOperation.self):                        .createIPA,
        ObjectIdentifier(SendAppOperation.self):                          .sendApp,
        ObjectIdentifier(StageAppOperation.self):                         .stageApp,
        ObjectIdentifier(UninstallAppOperation.self):                     .uninstallApp,
        ObjectIdentifier(UserCustomizationOperation.self):                .userCustomization,
        ObjectIdentifier(VerifyAppOperation.self):                        .verifyApp,
        ObjectIdentifier(VerifyCertificateOperation.self):                .verifyCertificate,
        ObjectIdentifier(UpdateAppCertificateOperation.self):             .updateAppCertificate,
        ObjectIdentifier(EmbedSigningCertOperation.self):                 .embedSigningCert,
    ]

    static func step(for type: Any.Type) -> PipelineStep? {
        stepMap[ObjectIdentifier(type)]
    }

    static func step(for operation: Any) -> PipelineStep? {
        if let backupOp = operation as? PerformBackupRestoreOperation {
            return backupOp.action == .backup ? .backupAppData : .restoreAppData
        }
        return step(for: type(of: operation))
    }
}

enum StandaloneStep: OperationStep {
    case signIn
    case backgroundRefreshApps
    case clearAppCache
    case enableJIT
    case fetchAppIDs
    case fetchSource
    case scheduleExpirationWarningNotification
    case unknown

    fileprivate static let stepMap: [ObjectIdentifier: StandaloneStep] = [
        ObjectIdentifier(SignInOperation.self):                          .signIn,
        ObjectIdentifier(BackgroundRefreshAppsOperation.self):                   .backgroundRefreshApps,
        ObjectIdentifier(ClearAppCacheOperation.self):                           .clearAppCache,
        ObjectIdentifier(EnableJITOperation.self):                               .enableJIT,
        ObjectIdentifier(SyncAppIDsOperation.self):                              .fetchAppIDs,
        ObjectIdentifier(FetchSourceOperation.self):                             .fetchSource,
        ObjectIdentifier(ScheduleExpirationWarningNotificationOperation.self):   .scheduleExpirationWarningNotification,
    ]

    static func step(for type: Any.Type) -> StandaloneStep? {
        stepMap[ObjectIdentifier(type)] ?? .unknown
    }
}
