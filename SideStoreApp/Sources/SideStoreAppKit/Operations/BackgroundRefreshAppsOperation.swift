//
//  BackgroundRefreshAppsOperation.swift
//  AltStore
//
//  Created by Riley Testut on 7/6/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import CoreData
import UIKit
import os.log

import SideStoreCore
import EmotionalDamage

enum RefreshError: LocalizedError {
    case noInstalledApps

    var errorDescription: String? {
        switch self {
        case .noInstalledApps: return NSLocalizedString("No active apps require refreshing.", comment: "")
        }
    }
}

private extension CFNotificationName {
    static let requestAppState = CFNotificationName("com.altstore.RequestAppState" as CFString)
    static let appIsRunning = CFNotificationName("com.altstore.AppState.Running" as CFString)

    static func requestAppState(for appID: String) -> CFNotificationName {
        let name = String(CFNotificationName.requestAppState.rawValue) + "." + appID
        return CFNotificationName(name as CFString)
    }

    static func appIsRunning(for appID: String) -> CFNotificationName {
        let name = String(CFNotificationName.appIsRunning.rawValue) + "." + appID
        return CFNotificationName(name as CFString)
    }
}

private let ReceivedApplicationState: @convention(c) (CFNotificationCenter?, UnsafeMutableRawPointer?, CFNotificationName?, UnsafeRawPointer?, CFDictionary?) -> Void = { _, observer, name, _, _ in
    guard let name = name, let observer = observer else { return }

    let operation = unsafeBitCast(observer, to: BackgroundRefreshAppsOperation.self)
    operation.receivedApplicationState(notification: name)
}

@objc(BackgroundRefreshAppsOperation)
public final class BackgroundRefreshAppsOperation: ResultOperation<[String: Result<InstalledApp, Error>]> {
	public let installedApps: [InstalledApp]
    private let managedObjectContext: NSManagedObjectContext

	public var presentsFinishedNotification: Bool = false

    private let refreshIdentifier: String = UUID().uuidString
    private var runningApplications: Set<String> = []

	public init(installedApps: [InstalledApp]) {
        self.installedApps = installedApps
        managedObjectContext = installedApps.compactMap { $0.managedObjectContext }.first ?? DatabaseManager.shared.persistentContainer.newBackgroundContext()

        super.init()
    }

	public override func finish(_ result: Result<[String: Result<InstalledApp, Error>], Error>) {
        super.finish(result)

        scheduleFinishedRefreshingNotification(for: result, delay: 0)

        managedObjectContext.perform {
            self.stopListeningForRunningApps()
        }

        DispatchQueue.main.async {
            if UIApplication.shared.applicationState == .background {}
        }
    }

	public override func main() {
        super.main()

        guard !installedApps.isEmpty else {
            finish(.failure(RefreshError.noInstalledApps))
            return
        }
        start_em_proxy(bind_addr: Consts.Proxy.serverURL)

        managedObjectContext.perform {
            os_log("Apps to refresh: %@", type: .error , self.installedApps.map(\.bundleIdentifier))

            self.startListeningForRunningApps()

            // Wait for 3 seconds (2 now, 1 later in FindServerOperation) to:
            // a) give us time to discover AltServers
            // b) give other processes a chance to respond to requestAppState notification
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.managedObjectContext.perform {
                    let filteredApps = self.installedApps.filter { !self.runningApplications.contains($0.bundleIdentifier) }
					os_log("Filtered Apps to Refresh: %@", type: .info , filteredApps.map { $0.bundleIdentifier }.joined(separator: "\n"))

                    let group = AppManager.shared.refresh(filteredApps, presentingViewController: nil)
                    group.beginInstallationHandler = { installedApp in
                        guard installedApp.bundleIdentifier == StoreApp.altstoreAppID else { return }

                        // We're starting to install AltStore, which means the app is about to quit.
                        // So, we schedule a "refresh successful" local notification to be displayed after a delay,
                        // but if the app is still running, we cancel the notification.
                        // Then, we schedule another notification and repeat the process.

                        // Also since AltServer has already received the app, it can finish installing even if we're no longer running in background.

                        if let error = group.context.error {
                            self.scheduleFinishedRefreshingNotification(for: .failure(error))
                        } else {
                            var results = group.results
                            results[installedApp.bundleIdentifier] = .success(installedApp)

                            self.scheduleFinishedRefreshingNotification(for: .success(results))
                        }
                    }
                    group.completionHandler = { results in
                        self.finish(.success(results))
                    }
                }
            }
        }
    }
}

private extension BackgroundRefreshAppsOperation {
    func startListeningForRunningApps() {
        let notificationCenter = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()

        for installedApp in installedApps {
            let appIsRunningNotification = CFNotificationName.appIsRunning(for: installedApp.bundleIdentifier)
            CFNotificationCenterAddObserver(notificationCenter, observer, ReceivedApplicationState, appIsRunningNotification.rawValue, nil, .deliverImmediately)

            let requestAppStateNotification = CFNotificationName.requestAppState(for: installedApp.bundleIdentifier)
            CFNotificationCenterPostNotification(notificationCenter, requestAppStateNotification, nil, nil, true)
        }
    }

    func stopListeningForRunningApps() {
        let notificationCenter = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()

        for installedApp in installedApps {
            let appIsRunningNotification = CFNotificationName.appIsRunning(for: installedApp.bundleIdentifier)
            CFNotificationCenterRemoveObserver(notificationCenter, observer, appIsRunningNotification, nil)
        }
    }

    func receivedApplicationState(notification: CFNotificationName) {
        let baseName = String(CFNotificationName.appIsRunning.rawValue)

        let appID = String(notification.rawValue).replacingOccurrences(of: baseName + ".", with: "")
        runningApplications.insert(appID)
    }

    func scheduleFinishedRefreshingNotification(for result: Result<[String: Result<InstalledApp, Error>], Error>, delay: TimeInterval = 5) {
        func scheduleFinishedRefreshingNotification() {
            cancelFinishedRefreshingNotification()

            let content = UNMutableNotificationContent()

            var shouldPresentAlert = false

            do {
                let results = try result.get()
                shouldPresentAlert = false

                for (_, result) in results {
                    guard case let .failure(error) = result else { continue }
                    throw error
                }

                content.title = NSLocalizedString("Refreshed Apps", comment: "")
                content.body = NSLocalizedString("All apps have been refreshed.", comment: "")
            } catch RefreshError.noInstalledApps {
                shouldPresentAlert = false
            } catch {
                os_log("Failed to refresh apps in background. %@", type: .error , error.localizedDescription)

                content.title = NSLocalizedString("Failed to Refresh Apps", comment: "")
                content.body = error.localizedDescription

                shouldPresentAlert = false
            }

            if shouldPresentAlert {
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay + 1, repeats: false)

                let request = UNNotificationRequest(identifier: refreshIdentifier, content: content, trigger: trigger)
                UNUserNotificationCenter.current().add(request)

                if delay > 0 {
                    DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                            // If app is still running at this point, we schedule another notification with same identifier.
                            // This prevents the currently scheduled notification from displaying, and starts another countdown timer.
                            // First though, make sure there _is_ still a pending request, otherwise it's been cancelled
                            // and we should stop polling.
                            guard requests.contains(where: { $0.identifier == self.refreshIdentifier }) else { return }

                            scheduleFinishedRefreshingNotification()
                        }
                    }
                }
            }
        }

        if presentsFinishedNotification {
            scheduleFinishedRefreshingNotification()
        }

        // Perform synchronously to ensure app doesn't quit before we've finishing saving to disk.
        let context = DatabaseManager.shared.persistentContainer.newBackgroundContext()
        context.performAndWait {
            _ = RefreshAttempt(identifier: self.refreshIdentifier, result: result, context: context)

            do { try context.save() } catch { os_log("Failed to save refresh attempt. %@", type: .error , error.localizedDescription) }
        }
    }

    func cancelFinishedRefreshingNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [refreshIdentifier])
    }
}