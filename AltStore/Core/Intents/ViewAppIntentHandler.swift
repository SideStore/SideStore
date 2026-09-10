//
//  ViewAppIntentHandler.swift
//  ViewAppIntentHandler
//
//  Created by Riley Testut on 7/10/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

#if !os(tvOS)
import Intents

public class ViewAppIntentHandler: NSObject, ViewAppIntentHandling
{
    public func provideAppOptionsCollection(for intent: ViewAppIntent, with completion: @escaping (INObjectCollection<App>?, Error?) -> Void)
    {        
        Task<Void, Never>.detached(priority: .userInitiated) {
            do
            {
                try await DatabaseManager.shared.start()
                let collection = await DatabaseManager.shared.persistentContainer.performBackgroundTask { (context) in
                    let apps = InstalledApp.all(in: context).map { (installedApp) in
                        return App(identifier: installedApp.bundleIdentifier, display: installedApp.name)
                    }
                    return INObjectCollection(items: apps)
                }
                completion(collection, nil)
            }
            catch
            {
                debugLog("Error starting extension: \(error)")
                completion(nil, error)
            }
        }
    }
}
#endif
