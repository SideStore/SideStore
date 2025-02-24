//
//  ActiveAppsTimelineProvider+Simulator.swift
//  AltStore
//
//  Created by Magesh K on 10/01/25.
//  Copyright © 2025 SideStore. All rights reserved.
//


/// Simulator data generator
#if targetEnvironment(simulator)
@available(iOS 17, *)
extension ActiveAppsTimelineProvider {

    func getSimulatedData(apps: [AppSnapshot]) -> [AppSnapshot]{
        var apps = apps
        var newSets: [AppSnapshot] = []
        // this dummy data is for simulator (uncomment when testing ActiveAppsWidget pagination)
        if (apps.count > 0){
            let app = apps[0]
            for i in 1...10 {
                let name = "\(app.name) - \(i)"
                let x = AppSnapshot(name: name,
                                    bundleIdentifier: app.bundleIdentifier,
                                    expirationDate: app.expirationDate,
                                    refreshedDate: app.refreshedDate
                        )
                newSets.append(x)
            }
            apps = newSets
        }
        return apps
    }
}
#endif

