//
//  ViewAppIntentHandler.swift
//  ViewAppIntentHandler
//
//  Created by Riley Testut on 7/10/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Intents
import AltStoreCore
import minimuxer

public class ViewAppIntentHandler: NSObject, ViewAppIntentHandling
{
    public func provideAppOptionsCollection(for intent: ViewAppIntent, with completion: @escaping (INObjectCollection<AltStoreCore.App>?, Error?) -> Void)
    {        
        DatabaseManager.shared.start { (error) in
            if let error = error
            {
                print("Error starting extension:", error)
            }
            
            DatabaseManager.shared.persistentContainer.performBackgroundTask { (context) in
                let apps = InstalledApp.all(in: context).map { (installedApp: InstalledApp) in
                    return AltStoreCore.App(identifier: installedApp.resignedBundleIdentifier, display: installedApp.name)
                }
                
                let collection = INObjectCollection(items: apps)
                completion(collection, nil)
            }
        }
    }
    public func handle(intent: ViewAppIntent, completion: @escaping (ViewAppIntentResponse) -> Void)
    {
        do
        {
            try debug_app((intent.app?.identifier)!)
            completion(ViewAppIntentResponse(code: .success, userActivity: nil))
        } catch
        {
            completion(ViewAppIntentResponse(code: .failure, userActivity: nil))
        }
    }
}
