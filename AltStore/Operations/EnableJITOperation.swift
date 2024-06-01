//
//  EnableJITOperation.swift
//  EnableJITOperation
//
//  Created by Riley Testut on 9/1/21.
//  Copyright © 2021 Riley Testut. All rights reserved.
//

import UIKit
import Combine
import minimuxer

import AltStoreCore

@available(iOS 14, *)
protocol EnableJITContext
{
    var installedApp: InstalledApp? { get }
    
    var error: Error? { get }
}

@available(iOS 14, *)
final class EnableJITOperation<Context: EnableJITContext>: ResultOperation<Void>
{
    let context: Context
    
    private var cancellable: AnyCancellable?
    
    init(context: Context)
    {
        self.context = context
    }
    
    override func main()
    {
        super.main()
        
        if let error = self.context.error
        {
            self.finish(.failure(error))
            return
        }
        
        guard let installedApp = self.context.installedApp else { return self.finish(.failure(OperationError.invalidParameters)) }
        if #available(iOS 17, *) {
            let sideJITenabled = UserDefaults.standard.sidejitenable
            if sideJITenabled {
                if let bundleIdentifier = (getBundleIdentifier(from: "\(installedApp)")) {
                    print("\(bundleIdentifier)")
                   if UserDefaults.standard.textInputSideJITServerurl?.isEmpty {
                       getrequest(from: installedApp.resignedBundleIdentifier, IP: "http://sidejitserver._http._tcp.local:8080")
                   } else {
                       getrequest(from: installedApp.resignedBundleIdentifier, IP: UserDefaults.standard.textInputSideJITServerurl ?? "")
                  }
                }
                return
            } else {
                let toastView = ToastView(error: OperationError.tooNewError)
                print("beans")
            }
            
            func getBundleIdentifier(from installedApp: String) -> String? {
                // Get the bundle ID
                let pattern = "BundleIdentifier = \"(.*?)\""
                let regex = try? NSRegularExpression(pattern: pattern)
                let range = NSRange(location: 0, length: installedApp.utf16.count)
                if let match = regex?.firstMatch(in: installedApp, options: [], range: range) {
                    let range = match.range(at: 1)
                    if let swiftRange = Range(range, in: installedApp) {
                        return String(installedApp[swiftRange])
                    }
                }
                return nil
            }
        
            func getrequest(from installedApp: String, IP ipadress: String) -> String? {
                    let serverUrl = ipadress ?? ""
                    let serverUdid: String = fetch_udid()?.toString() ?? ""
                    let appname = installedApp
                    let serveradress2 = serverUdid + "/" + appname
                
                
                    var combinedString = "\(serverUrl)" + "/" + serveradress2 + "/"
                guard let url = URL(string: combinedString) else {
                    print("Invalid URL: " + combinedString)
                    return("beans")
                }
                
                URLSession.shared.dataTask(with: url) { data, _, error in
                    if let error = error {
                        print("Error fetching data: \(error.localizedDescription)")
                        return
                    }
                    
                    if let data = data {
                            if let dataString = String(data: data, encoding: .utf8), dataString == "Enabled JIT for '\(installedApp)'!" {
                                let content = UNMutableNotificationContent()
                                content.title = "JIT Succsessfully Enabled"
                                content.subtitle = "JIT Enabled For \(installedApp)"
                                content.sound = UNNotificationSound.default

                                // show this notification five seconds from now
                                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)

                                // choose a random identifier
                                let request = UNNotificationRequest(identifier: "EnabledJIT", content: content, trigger: nil)

                                // add our notification request
                                UNUserNotificationCenter.current().add(request)
                            } else {
                                let content = UNMutableNotificationContent()
                                content.title = "An Error Occured"
                                content.subtitle = "Please check your SideJITServer Console"
                                content.sound = UNNotificationSound.default

                                // show this notification five seconds from now
                                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)

                                // choose a random identifier
                                let request = UNNotificationRequest(identifier: "EnabledJITError", content: content, trigger: nil)

                                // add our notification request
                                UNUserNotificationCenter.current().add(request)
                        }
                    }
                }.resume()
                return("")
            }
        } else {
            installedApp.managedObjectContext?.perform {
                var retries = 3
                while (retries > 0){
                    do {
                        try debug_app(installedApp.resignedBundleIdentifier)
                        self.finish(.success(()))
                        retries = 0
                    } catch {
                        retries -= 1
                        if (retries <= 0){
                            self.finish(.failure(error))
                        }
                    }
                }
            }
        }
    }
}
