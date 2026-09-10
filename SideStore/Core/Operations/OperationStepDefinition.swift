//
//  OperationStepDefinition.swift
//  SideStore
//
//  Created by Magesh K on 30/07/26.
//  Copyright © 2026 AltStore. All rights reserved.
//

import Foundation

struct PipelineExecutionStep: Hashable {
    let step: PipelineStep
    let weight: Int64

    init(_ step: PipelineStep, _ weight: Int64) {
        self.step = step
        self.weight = weight
    }
}

struct StandaloneExecutionStep: Hashable {
    let step: StandaloneStep
    let weight: Int64
    let maxReuse: Int
    let resetProgress: Bool

    init(_ step: StandaloneStep, _ weight: Int64, maxReuse: Int = 1, resetProgress: Bool = false) {
        self.step = step
        self.weight = weight
        self.maxReuse = maxReuse
        self.resetProgress = resetProgress
    }
}

// `PipelineStepDefinition` defines the exact step sequences for all application operations.
//  NOTE: A pipeline step CANNOT contain another pipeline step nor any standalone steps.
//        Nesting or executing pipeline steps recursively inside a step is strictly disallowed by design to keep pipeline explicit
struct PipelineStepDefinition {
    static let install: [PipelineExecutionStep] = [
        PipelineExecutionStep(.userCustomization,                 2),
        PipelineExecutionStep(.downloadApp,                      20),
        PipelineExecutionStep(.verifyApp,                         1),
        PipelineExecutionStep(.cacheApp,                          1),
        PipelineExecutionStep(.stageApp,                          1),
        PipelineExecutionStep(.updateAppCertificate,              5),
        PipelineExecutionStep(.verifyCertificate,                 5),
        PipelineExecutionStep(.changeAppIcon,                     1),
        PipelineExecutionStep(.removeAppExtensions,               6),
        PipelineExecutionStep(.fetchProvisioningProfiles,        10),
        PipelineExecutionStep(.prepareAppExtensionBundleIDs,      1),
        PipelineExecutionStep(.embedSigningCert,                  1),
        PipelineExecutionStep(.resignApp,                        15),
        PipelineExecutionStep(.createIPA,                         2),
        PipelineExecutionStep(.exportResignedIPA,                 1),
        PipelineExecutionStep(.sendApp,                          18),
        PipelineExecutionStep(.cacheSigningCert,                  1),
        PipelineExecutionStep(.installApp,                       15),
        PipelineExecutionStep(.cleanStagedApp,                    1)
    ]

    static let resign: [PipelineExecutionStep] = [
        PipelineExecutionStep(.stageApp,                          2),
        PipelineExecutionStep(.updateAppCertificate,              5),
        PipelineExecutionStep(.verifyCertificate,                 5),
        PipelineExecutionStep(.changeAppIcon,                     2),
        PipelineExecutionStep(.removeAppExtensions,               6),
        PipelineExecutionStep(.fetchProvisioningProfiles,        15),
        PipelineExecutionStep(.prepareAppExtensionBundleIDs,      2),
        PipelineExecutionStep(.embedSigningCert,                  1),
        PipelineExecutionStep(.resignApp,                        18),
        PipelineExecutionStep(.createIPA,                         2),
        PipelineExecutionStep(.exportResignedIPA,                 2),
        PipelineExecutionStep(.sendApp,                          18),
        PipelineExecutionStep(.cacheSigningCert,                  1),
        PipelineExecutionStep(.installApp,                       21),
        PipelineExecutionStep(.cleanStagedApp,                    2)
    ]

    static let refresh: [PipelineExecutionStep] = [
        PipelineExecutionStep(.updateAppCertificate,              5),
        PipelineExecutionStep(.verifyCertificate,                10),
        PipelineExecutionStep(.fetchProvisioningProfiles,        45),
        PipelineExecutionStep(.refreshApp,                       40)
    ]

    static let activateLegacy: [PipelineExecutionStep] = [
        PipelineExecutionStep(.updateAppCertificate,              5),
        PipelineExecutionStep(.verifyCertificate,                10),
        PipelineExecutionStep(.fetchProvisioningProfiles,        45),
        PipelineExecutionStep(.refreshApp,                       40)
    ]

    static let activate: [PipelineExecutionStep] = [
        // sidebackup app install
        PipelineExecutionStep(.stageBackupApp,                    3),
        PipelineExecutionStep(.updateAppCertificate,              2),
        PipelineExecutionStep(.verifyCertificate,                 2),
        PipelineExecutionStep(.fetchProvisioningProfiles,         3),
        PipelineExecutionStep(.prepareAppExtensionBundleIDs,      1),
        PipelineExecutionStep(.embedSigningCert,                  1),
        PipelineExecutionStep(.resignApp,                         3),
        PipelineExecutionStep(.createIPA,                         1),
        PipelineExecutionStep(.exportResignedIPA,                 1),
        PipelineExecutionStep(.sendApp,                           4),
        PipelineExecutionStep(.cacheSigningCert,                  1),
        PipelineExecutionStep(.installApp,                        5),
        // restore data
        PipelineExecutionStep(.restoreAppData,                   10),
        // install original app
        PipelineExecutionStep(.stageApp,                          2),
        PipelineExecutionStep(.updateAppCertificate,              3),
        PipelineExecutionStep(.verifyCertificate,                 3),
        PipelineExecutionStep(.changeAppIcon,                     2),
        PipelineExecutionStep(.removeAppExtensions,               2),
        PipelineExecutionStep(.fetchProvisioningProfiles,         5),
        PipelineExecutionStep(.prepareAppExtensionBundleIDs,      1),
        PipelineExecutionStep(.embedSigningCert,                  1),
        PipelineExecutionStep(.resignApp,                        15),
        PipelineExecutionStep(.createIPA,                         2),
        PipelineExecutionStep(.exportResignedIPA,                 1),
        PipelineExecutionStep(.sendApp,                          10),
        PipelineExecutionStep(.cacheSigningCert,                  1),
        PipelineExecutionStep(.installApp,                       15),
        // cleanup old backup
        PipelineExecutionStep(.removeBackupData,                  2),
        // cleanup staged app
        PipelineExecutionStep(.cleanStagedApp,                    2)
    ]

    static let deactivateLegacy: [PipelineExecutionStep] = [
        PipelineExecutionStep(.deactivateApp,                   100)
    ]

    static let deactivate: [PipelineExecutionStep] = [
        // sidebackup install
        PipelineExecutionStep(.stageBackupApp,                    5),
        PipelineExecutionStep(.updateAppCertificate,              3),
        PipelineExecutionStep(.verifyCertificate,                 3),
        PipelineExecutionStep(.fetchProvisioningProfiles,         5),
        PipelineExecutionStep(.prepareAppExtensionBundleIDs,      2),
        PipelineExecutionStep(.embedSigningCert,                  1),
        PipelineExecutionStep(.resignApp,                         5),
        PipelineExecutionStep(.createIPA,                         2),
        PipelineExecutionStep(.exportResignedIPA,                 2),
        PipelineExecutionStep(.sendApp,                           8),
        PipelineExecutionStep(.cacheSigningCert,                  1),
        PipelineExecutionStep(.installApp,                       10),
        // backup data
        PipelineExecutionStep(.backupAppData,                    25),
        // uninstall app from device & mark inactive
        PipelineExecutionStep(.uninstallApp,                     28),
        PipelineExecutionStep(.markAppInactive,                   2)
    ]

    static let backup: [PipelineExecutionStep] = [
        // sidebackup app install
        PipelineExecutionStep(.stageBackupApp,                    5),
        PipelineExecutionStep(.updateAppCertificate,              3),
        PipelineExecutionStep(.verifyCertificate,                 3),
        PipelineExecutionStep(.fetchProvisioningProfiles,         5),
        PipelineExecutionStep(.prepareAppExtensionBundleIDs,      2),
        PipelineExecutionStep(.embedSigningCert,                  1),
        PipelineExecutionStep(.resignApp,                         5),
        PipelineExecutionStep(.createIPA,                         2),
        PipelineExecutionStep(.exportResignedIPA,                 2),
        PipelineExecutionStep(.sendApp,                           8),
        PipelineExecutionStep(.cacheSigningCert,                  1),
        PipelineExecutionStep(.installApp,                       10),
        // backup data
        PipelineExecutionStep(.backupAppData,                    25),
        // install original app
        PipelineExecutionStep(.stageApp,                          2),
        PipelineExecutionStep(.updateAppCertificate,              3),
        PipelineExecutionStep(.verifyCertificate,                 3),
        PipelineExecutionStep(.changeAppIcon,                     2),
        PipelineExecutionStep(.removeAppExtensions,               2),
        PipelineExecutionStep(.fetchProvisioningProfiles,         5),
        PipelineExecutionStep(.prepareAppExtensionBundleIDs,      1),
        PipelineExecutionStep(.embedSigningCert,                  1),
        PipelineExecutionStep(.resignApp,                         5),
        PipelineExecutionStep(.createIPA,                         1),
        PipelineExecutionStep(.exportResignedIPA,                 1),
        PipelineExecutionStep(.sendApp,                           1),
        PipelineExecutionStep(.cacheSigningCert,                  1),
        PipelineExecutionStep(.installApp,                        2),
        // cleanup staged app
        PipelineExecutionStep(.cleanStagedApp,                    2)
    ]

    static let restoreLegacy: [PipelineExecutionStep] = [
        PipelineExecutionStep(.updateAppCertificate,              5),
        PipelineExecutionStep(.verifyCertificate,                10),
        PipelineExecutionStep(.fetchProvisioningProfiles,        45),
        PipelineExecutionStep(.refreshApp,                       40)
    ]

    static let restore: [PipelineExecutionStep] = [
        // sidebackup app install
        PipelineExecutionStep(.stageBackupApp,                    3),
        PipelineExecutionStep(.updateAppCertificate,              2),
        PipelineExecutionStep(.verifyCertificate,                 2),
        PipelineExecutionStep(.fetchProvisioningProfiles,         3),
        PipelineExecutionStep(.prepareAppExtensionBundleIDs,      1),
        PipelineExecutionStep(.embedSigningCert,                  1),
        PipelineExecutionStep(.resignApp,                         3),
        PipelineExecutionStep(.createIPA,                         1),
        PipelineExecutionStep(.exportResignedIPA,                 1),
        PipelineExecutionStep(.sendApp,                           4),
        PipelineExecutionStep(.cacheSigningCert,                  1),
        PipelineExecutionStep(.installApp,                        5),
        // restore data
        PipelineExecutionStep(.restoreAppData,                   10),
        // install original app
        PipelineExecutionStep(.stageApp,                          2),
        PipelineExecutionStep(.updateAppCertificate,              3),
        PipelineExecutionStep(.verifyCertificate,                 3),
        PipelineExecutionStep(.changeAppIcon,                     2),
        PipelineExecutionStep(.removeAppExtensions,               2),
        PipelineExecutionStep(.fetchProvisioningProfiles,         5),
        PipelineExecutionStep(.prepareAppExtensionBundleIDs,      1),
        PipelineExecutionStep(.embedSigningCert,                  1),
        PipelineExecutionStep(.resignApp,                        15),
        PipelineExecutionStep(.createIPA,                         2),
        PipelineExecutionStep(.exportResignedIPA,                 1),
        PipelineExecutionStep(.sendApp,                          10),
        PipelineExecutionStep(.cacheSigningCert,                  1),
        PipelineExecutionStep(.installApp,                       15),
        // cleanup old backup
        PipelineExecutionStep(.removeBackupData,                  2),
        // cleanup staged app
        PipelineExecutionStep(.cleanStagedApp,                    2)
    ]

    static let removeApp: [PipelineExecutionStep] = [
        PipelineExecutionStep(.removeBackupData,                 98),
        PipelineExecutionStep(.removeApp,                         2)
    ]

    static let removeDeactivatedApp = removeApp

    static let deleteApp: [PipelineExecutionStep] = [
        PipelineExecutionStep(.uninstallApp,                     96),
        PipelineExecutionStep(.removeBackupData,                  2),
        PipelineExecutionStep(.removeApp,                         2)
    ]

    static func steps(for operation: AppOperation) -> [PipelineExecutionStep] {
        switch operation {
        case .install, .update:
            return install
        case .resign:
            return resign
        case .refresh:
            return refresh
        case .activate:
            return UserDefaults.standard.isLegacyDeactivationSupported ? activateLegacy : activate
        case .deactivate:
            return UserDefaults.standard.isLegacyDeactivationSupported ? deactivateLegacy : deactivate
        case .backup:
            return backup
        case .restore:
            return UserDefaults.standard.isLegacyDeactivationSupported ? restoreLegacy : restore
        case .removeApp, .removeDeactivatedApp:
            return removeApp
        case .deleteApp:
            return deleteApp
        }
    }
}

struct StandaloneStepDefinition {
    static let signIn: [StandaloneExecutionStep] = [
        StandaloneExecutionStep(.signIn, 100)
    ]

    static let backgroundRefreshApps: [StandaloneExecutionStep] = [
        StandaloneExecutionStep(.backgroundRefreshApps, 100)
    ]

    static let clearAppCache: [StandaloneExecutionStep] = [
        StandaloneExecutionStep(.clearAppCache, 100)
    ]

    static let enableJIT: [StandaloneExecutionStep] = [
        StandaloneExecutionStep(.enableJIT, 100)
    ]

    static let scheduleExpirationWarningNotification: [StandaloneExecutionStep] = [
        StandaloneExecutionStep(.scheduleExpirationWarningNotification, 100)
    ]
}

extension Array where Element == PipelineExecutionStep {
    static var install:              [PipelineExecutionStep] { PipelineStepDefinition.install              }
    static var resign:               [PipelineExecutionStep] { PipelineStepDefinition.resign               }
    static var refresh:              [PipelineExecutionStep] { PipelineStepDefinition.refresh              }
    static var activate:             [PipelineExecutionStep] { PipelineStepDefinition.activate             }
    static var deactivate:           [PipelineExecutionStep] { PipelineStepDefinition.deactivate           }
    static var backup:               [PipelineExecutionStep] { PipelineStepDefinition.backup               }
    static var restore:              [PipelineExecutionStep] { PipelineStepDefinition.restore              }
    static var removeApp:            [PipelineExecutionStep] { PipelineStepDefinition.removeApp            }
    static var removeDeactivatedApp: [PipelineExecutionStep] { PipelineStepDefinition.removeDeactivatedApp }
    static var deleteApp:            [PipelineExecutionStep] { PipelineStepDefinition.deleteApp            }
}

extension Array where Element == StandaloneExecutionStep {
    static var signIn:                                [StandaloneExecutionStep] { StandaloneStepDefinition.signIn                                }
    static var backgroundRefreshApps:                 [StandaloneExecutionStep] { StandaloneStepDefinition.backgroundRefreshApps                 }
    static var clearAppCache:                         [StandaloneExecutionStep] { StandaloneStepDefinition.clearAppCache                         }
    static var enableJIT:                             [StandaloneExecutionStep] { StandaloneStepDefinition.enableJIT                             }
    static var scheduleExpirationWarningNotification: [StandaloneExecutionStep] { StandaloneStepDefinition.scheduleExpirationWarningNotification }
}
