//
//  DeveloperServicesViewModel.swift
//  SideStore
//
//  Created by Magesh K on 2/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import SwiftUI
import SideSign

@MainActor
class DeveloperServicesViewModel: ObservableObject {
    @Published var appIDs: [ALTAppID] = []
    @Published var profiles: [ALTListedProvisioningProfile] = []
    @Published var appGroups: [ALTAppGroup] = []
    @Published var devices: [ALTDevice] = []
    @Published var certificates: [ALTX509Certificate] = []

    @Published var isLoading = false
    @Published var isActionLoading = false
    @Published var errorMessage: String? = nil {
        didSet { showErrorAlert = errorMessage != nil }
    }
    @Published var showErrorAlert = false

    @Published var toastMessage: String = ""
    @Published var showToast = false

    var team: ALTTeam? {
        AuthManager.shared.team
    }

    var isPaidAccount: Bool {
        guard let team = AuthManager.shared.team else { return false }
        return team.isPaid
    }

    func showToastMessage(_ message: String) {
        self.toastMessage = message
        self.showToast = true
    }

    func loadAll(presentingViewController: UIViewController? = nil, isPullToRefresh: Bool = false) async {
        self.isLoading = true
        self.errorMessage = nil
        defer { self.isLoading = false }

        do {
            if isPullToRefresh {
                AuthManager.shared.session = nil
            }
            async let fetchedAppIDs = DeveloperPortalProxy.shared.fetchAppIDs()
            async let fetchedProfiles = DeveloperPortalProxy.shared.listProvisioningProfiles()
            async let fetchedGroups = DeveloperPortalProxy.shared.fetchAppGroups()
            async let fetchedDevices = DeveloperPortalProxy.shared.fetchDevices(types: .all)
            async let fetchedCerts = DeveloperPortalProxy.shared.fetchCertificates()

            let (appIDs, profiles, groups, devices, certs) = try await (fetchedAppIDs, fetchedProfiles, fetchedGroups, fetchedDevices, fetchedCerts)
            self.appIDs = appIDs.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            self.profiles = profiles.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            self.appGroups = groups.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            self.devices = devices.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            self.certificates = certs.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            debugLog("[DeveloperServices] loadAll failed: \(error)")
            if !(error is CancellationError) {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func fetchCertificates(presentingViewController: UIViewController? = nil, isPullToRefresh: Bool = false) async {
        self.isLoading = true
        defer { self.isLoading = false }
        do {
            if isPullToRefresh {
                AuthManager.shared.session = nil
            }
            let certs = try await DeveloperPortalProxy.shared.fetchCertificates()
            self.certificates = certs.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            debugLog("[DeveloperServices] fetchCertificates failed: \(error)")
            if !(error is CancellationError) {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func revokeCertificate(_ certificate: ALTX509Certificate, presentingViewController: UIViewController? = nil) async -> Bool {
        self.isActionLoading = true
        defer { self.isActionLoading = false }
        do {
            _ = try await DeveloperPortalProxy.shared.revokeCertificate(certificate)
            self.certificates.removeAll { $0.serialNumber == certificate.serialNumber }
            self.showToastMessage(String(format: NSLocalizedString("Revoked certificate '%@'", comment: ""), certificate.name))
            return true
        } catch {
            debugLog("[DeveloperServices] revokeCertificate failed: \(error)")
            self.errorMessage = error.localizedDescription
            return false
        }
    }

    func fetchAppIDs(presentingViewController: UIViewController? = nil, isPullToRefresh: Bool = false) async {
        self.isLoading = true
        defer { self.isLoading = false }
        do {
            if isPullToRefresh {
                AuthManager.shared.session = nil
            }
            let ids = try await DeveloperPortalProxy.shared.fetchAppIDs()
            self.appIDs = ids.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            if !(error is CancellationError) {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func createAppID(name: String, bundleIdentifier: String, presentingViewController: UIViewController? = nil) async -> Bool {
        self.isActionLoading = true
        defer { self.isActionLoading = false }
        do {
            let newAppID = try await DeveloperPortalProxy.shared.addAppID(name: name, bundleIdentifier: bundleIdentifier)
            self.appIDs.append(newAppID)
            self.appIDs.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            self.showToastMessage(String(format: NSLocalizedString("Registered App ID '%@'", comment: ""), newAppID.name))
            return true
        } catch {
            self.errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteAppID(_ appID: ALTAppID, presentingViewController: UIViewController? = nil) async -> Bool {
        self.isActionLoading = true
        defer { self.isActionLoading = false }
        do {
            _ = try await DeveloperPortalProxy.shared.deleteAppID(appID)
            self.appIDs.removeAll { $0.identifier == appID.identifier }
            self.showToastMessage(String(format: NSLocalizedString("Deleted App ID '%@'", comment: ""), appID.name))
            return true
        } catch {
            self.errorMessage = error.localizedDescription
            return false
        }
    }

    func updateAppGroups(for appID: ALTAppID, to selectedGroups: [ALTAppGroup], presentingViewController: UIViewController? = nil) async -> Bool {
        self.isActionLoading = true
        defer { self.isActionLoading = false }
        do {
            let updated = try await DeveloperPortalProxy.shared.assignAppID(appID, to: selectedGroups)
            if let idx = self.appIDs.firstIndex(where: { $0.identifier == appID.identifier }) {
                self.appIDs[idx] = updated
            }
            self.showToastMessage(String(format: NSLocalizedString("Updated App Groups for '%@'", comment: ""), appID.name))
            return true
        } catch {
            self.errorMessage = error.localizedDescription
            return false
        }
    }

    func fetchProfiles(presentingViewController: UIViewController? = nil, isPullToRefresh: Bool = false) async {
        self.isLoading = true
        defer { self.isLoading = false }
        do {
            if isPullToRefresh {
                AuthManager.shared.session = nil
            }
            let profs = try await DeveloperPortalProxy.shared.listProvisioningProfiles()
            self.profiles = profs.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            debugLog("[DeveloperServices] fetchProfiles failed: \(error)")
            if !(error is CancellationError) {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func downloadProfile(for appID: ALTAppID, type: ALTProfileType? = nil, presentingViewController: UIViewController? = nil) async -> Bool {
        self.isActionLoading = true
        defer { self.isActionLoading = false }
        do {
            if let type = type {
                _ = try await DeveloperPortalProxy.shared.downloadProvisioningProfile(for: appID, type: type)
            } else {
                _ = try await DeveloperPortalProxy.shared.downloadProvisioningProfile(for: appID, deviceType: DeveloperPortalProxy.currentDeviceType)
            }
            await self.fetchProfiles(presentingViewController: presentingViewController)
            self.showToastMessage(String(format: NSLocalizedString("Profile generated for '%@'", comment: ""), appID.name))
            return true
        } catch {
            debugLog("[DeveloperServices] downloadProfile failed: \(error)")
            self.errorMessage = error.localizedDescription
            return false
        }
    }

    func createManualProfile(name: String, appID: ALTAppID, certificateIDs: [String], deviceIDs: [String], type: ALTProfileType = .iOS, presentingViewController: UIViewController? = nil) async -> Bool {
        self.isActionLoading = true
        defer { self.isActionLoading = false }
        do {
            _ = try await DeveloperPortalProxy.shared.createProvisioningProfile(name: name, appID: appID, certificateIDs: certificateIDs, deviceIDs: deviceIDs, type: type)
            await self.fetchProfiles(presentingViewController: presentingViewController)
            self.showToastMessage(String(format: NSLocalizedString("Created profile '%@'", comment: ""), name))
            return true
        } catch {
            debugLog("[DeveloperServices] createManualProfile failed: \(error)")
            self.errorMessage = error.localizedDescription
            return false
        }
    }

    func updateProfile(_ profile: ALTListedProvisioningProfile, name: String, appIDId: String, certificateIDs: [String], deviceIDs: [String], type: ALTProfileType? = nil, presentingViewController: UIViewController? = nil) async -> Bool {
        guard let profileID = profile.identifier else {
            self.errorMessage = "Profile identifier missing"
            return false
        }
        self.isActionLoading = true
        defer { self.isActionLoading = false }
        do {
            if let type = type {
                _ = try await DeveloperPortalProxy.shared.updateProvisioningProfile(
                    profileID: profileID,
                    name: name,
                    appIDId: appIDId,
                    certificateIDs: certificateIDs,
                    deviceIDs: deviceIDs,
                    type: type
                )
            } else {
                _ = try await DeveloperPortalProxy.shared.updateProvisioningProfile(
                    profileID: profileID,
                    name: name,
                    appIDId: appIDId,
                    certificateIDs: certificateIDs,
                    deviceIDs: deviceIDs
                )
            }
            await self.fetchProfiles(presentingViewController: presentingViewController)
            self.showToastMessage(String(format: NSLocalizedString("Updated profile '%@'", comment: ""), name))
            return true
        } catch {
            debugLog("[DeveloperServices] updateProfile failed: \(error)")
            self.errorMessage = error.localizedDescription
            return false
        }
    }

    func downloadProfile(profile: ALTListedProvisioningProfile) async -> ALTProvisioningProfile? {
        guard let profileID = profile.identifier else {
            self.errorMessage = "Profile identifier missing"
            return nil
        }
        self.isActionLoading = true
        defer { self.isActionLoading = false }
        do {
            let downloaded = try await DeveloperPortalProxy.shared.downloadProvisioningProfile(profileID: profileID)
            return downloaded
        } catch {
            debugLog("[DeveloperServices] downloadProfile(profile:) failed: \(error)")
            self.errorMessage = error.localizedDescription
            return nil
        }
    }

    func deleteProfile(_ profile: ALTListedProvisioningProfile, presentingViewController: UIViewController? = nil) async -> Bool {
        guard let profileID = profile.identifier else {
            self.errorMessage = "Profile identifier is missing"
            return false
        }
        self.isActionLoading = true
        defer { self.isActionLoading = false }
        do {
            _ = try await DeveloperPortalProxy.shared.deleteProvisioningProfile(profileID: profileID)
            self.profiles.removeAll { $0.uuid == profile.uuid }
            self.showToastMessage(String(format: NSLocalizedString("Deleted profile '%@'", comment: ""), profile.name))
            return true
        } catch {
            debugLog("[DeveloperServices] deleteProfile failed: \(error)")
            self.errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteAllProfiles(presentingViewController: UIViewController? = nil) async -> (deletedCount: Int, failedCount: Int) {
        self.isActionLoading = true
        defer { self.isActionLoading = false }
        do {
            var deleted = 0
            var failed = 0
            for profile in self.profiles {
                guard let profileID = profile.identifier else {
                    failed += 1
                    continue
                }
                do {
                    _ = try await DeveloperPortalProxy.shared.deleteProvisioningProfile(profileID: profileID)
                    deleted += 1
                } catch {
                    debugLog("[DeveloperServices] deleteProfile '\(profile.name)' failed: \(error)")
                    failed += 1
                }
            }
            await self.fetchProfiles(presentingViewController: presentingViewController)
            self.showToastMessage(failed > 0 ? String(format: NSLocalizedString("Purged %d profile(s) (%d failed)", comment: ""), deleted, failed) : String(format: NSLocalizedString("Purged %d profile(s)", comment: ""), deleted))
            return (deleted, failed)
        } catch {
            debugLog("[DeveloperServices] deleteAllProfiles failed: \(error)")
            self.errorMessage = error.localizedDescription
            return (0, 0)
        }
    }

    func fetchAppGroups(presentingViewController: UIViewController? = nil, isPullToRefresh: Bool = false) async {
        self.isLoading = true
        defer { self.isLoading = false }
        do {
            if isPullToRefresh {
                AuthManager.shared.session = nil
            }
            let groups = try await DeveloperPortalProxy.shared.fetchAppGroups()
            self.appGroups = groups.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            if !(error is CancellationError) {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func createAppGroup(name: String, groupIdentifier: String, presentingViewController: UIViewController? = nil) async -> Bool {
        self.isActionLoading = true
        defer { self.isActionLoading = false }
        do {
            let newGroup = try await DeveloperPortalProxy.shared.addAppGroup(name: name, groupIdentifier: groupIdentifier)
            self.appGroups.append(newGroup)
            self.appGroups.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            self.showToastMessage(String(format: NSLocalizedString("Created App Group '%@'", comment: ""), newGroup.name))
            return true
        } catch {
            self.errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteAppGroup(_ group: ALTAppGroup, presentingViewController: UIViewController? = nil) async -> Bool {
        self.isActionLoading = true
        defer { self.isActionLoading = false }
        do {
            _ = try await DeveloperPortalProxy.shared.deleteAppGroup(group)
            self.appGroups.removeAll { $0.identifier == group.identifier || $0.groupID == group.groupID }
            self.showToastMessage(String(format: NSLocalizedString("Deleted App Group '%@'", comment: ""), group.name))
            return true
        } catch {
            self.errorMessage = error.localizedDescription
            return false
        }
    }

    func updateAppGroup(_ group: ALTAppGroup, newName: String, presentingViewController: UIViewController? = nil) async -> Bool {
        self.isActionLoading = true
        defer { self.isActionLoading = false }
        do {
            var target = group
            target.name = newName
            let updated = try await DeveloperPortalProxy.shared.updateAppGroup(target)
            if let idx = self.appGroups.firstIndex(where: { $0.identifier == group.identifier || $0.groupID == group.groupID }) {
                self.appGroups[idx] = updated
            }
            self.appGroups.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            self.showToastMessage(String(format: NSLocalizedString("Updated App Group '%@'", comment: ""), updated.name))
            return true
        } catch {
            self.errorMessage = error.localizedDescription
            return false
        }
    }

    func fetchDevices(presentingViewController: UIViewController? = nil, isPullToRefresh: Bool = false) async {
        self.isLoading = true
        defer { self.isLoading = false }
        do {
            if isPullToRefresh {
                AuthManager.shared.session = nil
            }
            let devs = try await DeveloperPortalProxy.shared.fetchDevices(types: .all)
            self.devices = devs.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            if !(error is CancellationError) {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func registerDevice(name: String, identifier: String, type: ALTDeviceType, presentingViewController: UIViewController? = nil) async -> Bool {
        self.isActionLoading = true
        defer { self.isActionLoading = false }
        do {
            let newDev = try await DeveloperPortalProxy.shared.registerDevice(name: name, identifier: identifier, type: type)
            self.devices.append(newDev)
            self.devices.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            self.showToastMessage(String(format: NSLocalizedString("Registered Device '%@'", comment: ""), newDev.name))
            return true
        } catch {
            self.errorMessage = error.localizedDescription
            return false
        }
    }

    func updateDevice(_ device: ALTDevice, newName: String, presentingViewController: UIViewController? = nil) async -> Bool {
        self.isActionLoading = true
        defer { self.isActionLoading = false }
        do {
            var target = device
            target.name = newName
            let updated = try await DeveloperPortalProxy.shared.updateDevice(target)
            if let idx = self.devices.firstIndex(where: { $0.identifier == device.identifier }) {
                self.devices[idx] = updated
            }
            self.devices.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            self.showToastMessage(String(format: NSLocalizedString("Renamed Device to '%@'", comment: ""), updated.name))
            return true
        } catch {
            self.errorMessage = error.localizedDescription
            return false
        }
    }

    func disableDevice(_ device: ALTDevice, presentingViewController: UIViewController? = nil) async -> Bool {
        self.isActionLoading = true
        defer { self.isActionLoading = false }
        do {
            let disabled = try await DeveloperPortalProxy.shared.disableDevice(device)
            if let idx = self.devices.firstIndex(where: { $0.identifier == device.identifier }) {
                self.devices[idx] = disabled
            }
            self.showToastMessage(String(format: NSLocalizedString("Disabled Device '%@'", comment: ""), device.name))
            return true
        } catch {
            self.errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func deleteDevice(_ device: ALTDevice, presentingViewController: UIViewController? = nil) async -> Bool {
        self.isActionLoading = true
        defer { self.isActionLoading = false }
        do {
            _ = try await DeveloperPortalProxy.shared.deleteDevice(device)
            self.devices.removeAll { $0.identifier == device.identifier }
            self.showToastMessage(String(format: NSLocalizedString("Deleted Device '%@'", comment: ""), device.name))
            return true
        } catch {
            self.errorMessage = error.localizedDescription
            return false
        }
    }
}
