//
//  EnableJITOperation.swift
//  EnableJITOperation
//
//  Created by Riley Testut on 9/1/21.
//  Copyright © 2021 Riley Testut. All rights reserved.
//

import UIKit
import Combine
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
        
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.enableJIT(for: installedApp)
                self.finish(.success(()))
            } catch {
                self.finish(.failure(error))
            }
        }
    }

    private func enableJIT(for installedApp: InstalledApp) async throws
    {
        let userdefaults = UserDefaults.standard
        
        if #available(iOS 17, *), userdefaults.sidejitenable {
            let sideJITIP = userdefaults.textInputSideJITServerurl ?? "http://sidejitserver._http._tcp.local:8080"
            guard let serverURL = URL(string: sideJITIP) else {
                throw OperationError.unableToConnectSideJIT
            }
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                enableJITSideJITServer(serverURL: serverURL, installedApp: installedApp) { result in
                    switch result {
                    case .success:
                        self.debugLog("JIT Enabled Successfully :3 (code made by Stossy11!)")
                        continuation.resume()
                    case .failure(let error):
                        switch error {
                        case .invalidURL, .errorConnecting:
                            continuation.resume(throwing: OperationError.unableToConnectSideJIT)
                        case .deviceNotFound:
                            continuation.resume(throwing: OperationError.unableToRespondSideJITDevice)
                        case .other(let message):
                            if let startRange = message.range(of: "<p>"),
                               let endRange = message.range(of: "</p>", range: startRange.upperBound..<message.endIndex) {
                                let pContent = message[startRange.upperBound..<endRange.lowerBound]
                                self.debugLog(message + " + " + String(pContent))
                                continuation.resume(throwing: OperationError.SideJITIssue(error: String(pContent)))
                            } else {
                                self.debugLog(message)
                                continuation.resume(throwing: OperationError.SideJITIssue(error: message))
                            }
                        }
                    }
                }
            }
        } else {
            guard let ctx = installedApp.managedObjectContext else {
                throw OperationError.invalidParameters("EnableJITOperation: installedApp.managedObjectContext is nil")
            }
            try await ctx.perform {
                var lastError: Error?
                for _ in 0..<3 {
                    do {
                        try debugApp(installedApp.resignedBundleIdentifier)
                        return
                    } catch {
                        lastError = error
                    }
                }
                if let error = lastError { throw error }
            }
        }
    }

    private func debugLog(_ text: String) {
        print(text)
    }

    private func verboseLog(_ text: String) {
        let isLoggingEnabled = OperationsLoggingControl.getFromDatabase(for: type(of: self))
        if isLoggingEnabled {
            print(text)
        }
    }
}

@available(iOS 17, *)
func enableJITSideJITServer(serverURL: URL, installedApp: InstalledApp, completion: @escaping (Result<Void, SideJITServerErrorType>) -> Void) {
    guard let udid = fetchUDID() else {
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
