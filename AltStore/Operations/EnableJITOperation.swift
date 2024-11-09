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
import UniformTypeIdentifiers

import AltStoreCore

enum SideJITServerErrorType: Error {
     case invalidURL
     case errorConnecting
     case deviceNotFound
     case other(String)
 }

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
        
        guard let installedApp = self.context.installedApp else {
            return self.finish(.failure(OperationError.invalidParameters("EnableJITOperation.main: self.context.installedApp is nil")))
        }
        if #available(iOS 17, *) {
            let sideJITenabled = UserDefaults.standard.sidejitenable
            let SideJITIP = UserDefaults.standard.textInputSideJITServerurl ?? ""
            
            if sideJITenabled {
                installedApp.managedObjectContext?.perform {
                    EnableJITSideJITServer(serverurl: SideJITIP, installedapp: installedApp) { result in
                        switch result {
                        case .failure(let error):
                            switch error {
                            case .invalidURL, .errorConnecting:
                                self.finish(.failure(OperationError.unableToConnectSideJIT))
                            case .deviceNotFound:
                                self.finish(.failure(OperationError.unableToRespondSideJITDevice))
                            case .other(let message):
                                if let startRange = message.range(of: "<p>"),
                                   let endRange = message.range(of: "</p>", range: startRange.upperBound..<message.endIndex) {
                                    let pContent = message[startRange.upperBound..<endRange.lowerBound]
                                    self.finish(.failure(OperationError.SideJITIssue(error: String(pContent))))
                                    print(message + " + " + String(pContent))
                                } else {
                                    print(message)
                                    self.finish(.failure(OperationError.SideJITIssue(error: message)))
                                }
                            }
                        case .success():
                            self.finish(.success(()))
                            print("Thank you for using this, it was made by Stossy11 and tested by trolley or sniper1239408")
                        }
                    }
                    return
                }
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

@available(iOS 17, *)
func EnableJITSideJITServer(serverurl: String, installedapp: InstalledApp, completion: @escaping (Result<Void, SideJITServerErrorType>) -> Void) {
    guard let udid = fetch_udid()?.toString() else {
        completion(.failure(.other("Unable to get UDID")))
        return
    }
    
    var SJSURL = serverurl
    
     if (UserDefaults.standard.textInputSideJITServerurl ?? "").isEmpty {
      SJSURL = "http://sidejitserver._http._tcp.local:8080"
     }
    
    if !SJSURL.hasPrefix("http") {
        completion(.failure(.invalidURL))
        return
    }
    
    let fullurl = SJSURL + "/\(udid)/" + installedapp.resignedBundleIdentifier
    
    let url = URL(string: fullurl)!
    
    let task = URLSession.shared.dataTask(with: url) {(data, response, error) in
        if let error = error {
            completion(.failure(.errorConnecting))
            return
        }
        
        guard let data = data, let datastring = String(data: data, encoding: .utf8) else { return }
        
        if datastring == "Enabled JIT for '\(installedapp.name)'!" {
            let content = UNMutableNotificationContent()
            content.title = "JIT Successfully Enabled"
            content.subtitle = "JIT Enabled For \(installedapp.name)"
            content.sound = UNNotificationSound.default

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
            let request = UNNotificationRequest(identifier: "EnabledJIT", content: content, trigger: nil)

            UNUserNotificationCenter.current().add(request)
            completion(.success(()))
        } else {
            let errorType: SideJITServerErrorType = datastring == "Could not find device!" ? .deviceNotFound : .other(datastring)
            completion(.failure(errorType))
        }
    }
    
    task.resume()
}
