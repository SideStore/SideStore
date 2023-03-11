//
//  AnalyticsManager.swift
//  AltStore
//
//  Created by Riley Testut on 3/31/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation

import SideStoreCore

import AppCenter
import AppCenterAnalytics
import AppCenterCrashes

private let appCenterAppSecret = "73532d3e-e573-4693-99a4-9f85840bbb44"

public extension AnalyticsManager {
    enum EventProperty: String {
        case name
        case bundleIdentifier
        case developerName
        case version
        case size
        case tintColor
        case sourceIdentifier
        case sourceURL
    }

    enum Event {
        case installedApp(InstalledApp)
        case updatedApp(InstalledApp)
        case refreshedApp(InstalledApp)

		public var name: String {
            switch self {
            case .installedApp: return "installed_app"
            case .updatedApp: return "updated_app"
            case .refreshedApp: return "refreshed_app"
            }
        }

		public var properties: [EventProperty: String] {
            let properties: [EventProperty: String?]

            switch self {
            case let .installedApp(app), let .updatedApp(app), let .refreshedApp(app):
                let appBundleURL = InstalledApp.fileURL(for: app)
                let appBundleSize = FileManager.default.directorySize(at: appBundleURL)

                properties = [
                    .name: app.name,
                    .bundleIdentifier: app.bundleIdentifier,
                    .developerName: app.storeApp?.developerName,
                    .version: app.version,
                    .size: appBundleSize?.description,
                    .tintColor: app.storeApp?.tintColor?.hexString,
                    .sourceIdentifier: app.storeApp?.sourceIdentifier,
                    .sourceURL: app.storeApp?.source?.sourceURL.absoluteString
                ]
            }

            return properties.compactMapValues { $0 }
        }
    }
}

public final class AnalyticsManager {
	public static let shared = AnalyticsManager()

    private init() {}
}

public extension AnalyticsManager {
    func start() {
        AppCenter.start(withAppSecret: appCenterAppSecret, services: [
            Analytics.self,
            Crashes.self
        ])
    }

    func trackEvent(_ event: Event) {
        let properties = event.properties.reduce(into: [:]) { properties, item in
            properties[item.key.rawValue] = item.value
        }

        Analytics.trackEvent(event.name, withProperties: properties)
    }
}
