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
        
        guard let installedApp = self.context.installedApp else { return self.finish(.failure(OperationError.invalidParameters)) }
        if #available(iOS 17, *) {
            let sideJITenabled = UserDefaults.standard.sidejitenable
            let sideJITip = UserDefaults.standard.textInputSideJITServerurl ?? ""
            
            if sideJITenabled {
                installedApp.managedObjectContext?.perform {
                    getRequest(from: installedApp.resignedBundleIdentifier, IP: sideJITip, installedAppName: installedApp.name) { result in
                        switch result {
                        case .failure(let error):
                            switch error {
                            case .invalidURL:
                                self.finish(.failure(OperationError.unabletoconnectSideJIT))
                            case .errorConnecting:
                                self.finish(.failure(OperationError.unabletoconnectSideJIT))
                            case .deviceNotFound:
                                self.finish(.failure(OperationError.unabletoconSideJITDevice))
                            case .other(let message):
                                print(message)
                                self.finish(.failure(OperationError.SideJITIssue(error: message)))
                                // handle other errors
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

func getRequest(from installedApp: String, IP ipAddress: String, installedAppName: String, completion: @escaping (Result<Void, SideJITServerErrorType>) -> Void) {
    guard let serverUdid = fetch_udid()?.toString() else {
        completion(.failure(.other("Failed to get UDID. Please reset your pairing file.")))
        return
    }

    let serverAddress = "\(serverUdid)/\(installedApp)"
    var combinedString = ipAddress.hasSuffix("/") ? "\(ipAddress)\(serverAddress)/" : "\(ipAddress)/\(serverAddress)/"

    if ipAddress.isEmpty {
      combinedString = "http://sidejitserver._http._tcp.local:8080/\(serverAddress)/"
    }
    
    guard let url = URL(string: combinedString) else {
        completion(.failure(.invalidURL))
        return
    }

    let taskQueue = DispatchQueue(label: "com.SideStore.SideJITServer", attributes: .concurrent)
    taskQueue.async {
        URLSession.shared.dataTask(with: url) { data, _, error in
            if let error = error {
                completion(.failure(.errorConnecting))
                return
            }

            guard let data = data, let dataString = String(data: data, encoding: .utf8) else { return }

            if dataString == "Enabled JIT for '\(installedAppName)'!" {
                let content = UNMutableNotificationContent()
                content.title = "JIT Successfully Enabled"
                content.subtitle = "JIT Enabled For \(installedAppName)"
                content.sound = UNNotificationSound.default

                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
                let request = UNNotificationRequest(identifier: "EnabledJIT", content: content, trigger: nil)

                UNUserNotificationCenter.current().add(request)
            } else {
                let errorType: SideJITServerErrorType = dataString == "Could not find device!" ? .deviceNotFound : .other(dataString)
                completion(.failure(errorType))
            }
        }.resume()
    }
}
