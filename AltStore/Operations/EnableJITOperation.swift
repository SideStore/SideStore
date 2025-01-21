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
        
        let userdefaults = UserDefaults.standard
        
        if #available(iOS 17, *), userdefaults.sidejitenable {
            let SideJITIP = userdefaults.textInputSideJITServerurl ?? "http://sidejitserver._http._tcp.local:8080"
            installedApp.managedObjectContext?.perform {
                enableJITSideJITServer(serverURL: URL(string: SideJITIP)!, installedApp: installedApp) { result in
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
                        print("JIT Enabled Successfully :3 (code made by Stossy11!)")
                    }
                }
                return
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
func enableJITSideJITServer(serverURL: URL, installedApp: InstalledApp, completion: @escaping (Result<Void, SideJITServerErrorType>) -> Void) {
    guard let udid = fetch_udid()?.toString() else {
        completion(.failure(.other("Unable to get UDID")))
        return
    }
    
    let serverURLWithUDID = serverURL.appendingPathComponent(udid)
    let fullURL = serverURLWithUDID.appendingPathComponent(installedApp.resignedBundleIdentifier)
    
    let task = URLSession.shared.dataTask(with: fullURL) { (data, response, error) in
        if let error = error {
            completion(.failure(.errorConnecting))
            return
        }
        
        guard let data = data, let dataString = String(data: data, encoding: .utf8) else {
            return
        }
        
        if dataString == "Enabled JIT for '\(installedApp.name)'!" {
            let content = UNMutableNotificationContent()
            content.title = "JIT Successfully Enabled"
            content.subtitle = "JIT Enabled For \(installedApp.name)"
            content.sound = .default
            
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
            let request = UNNotificationRequest(identifier: "EnabledJIT", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
            
            completion(.success(()))
        } else {
            let errorType: SideJITServerErrorType = dataString == "Could not find device!"
                ? .deviceNotFound
                : .other(dataString)
            completion(.failure(errorType))
        }
    }
    
    task.resume()
}
