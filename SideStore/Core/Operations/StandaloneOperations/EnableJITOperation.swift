//
//  EnableJITOperation.swift
//  SideStore
//
//  Created by Magesh K on 23/8/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

@preconcurrency import UIKit
import Combine
import UniformTypeIdentifiers
import CoreData

enum SideJITServerErrorType: Error {
    case invalidURL
    case errorConnecting
    case deviceNotFound
    case other(String)
}

final class EnableJITOperation: BaseStandaloneOperation<StandaloneOperationContext, Bool>, @unchecked Sendable
{
    let installedApp: InstalledApp

    init(installedApp: InstalledApp, context: StandaloneOperationContext) throws {
        self.installedApp = installedApp
        try super.init(context: context)
    }

    override func execute(parentProgress: Progress?) async throws -> Bool {
        let startTime = CFAbsoluteTimeGetCurrent()
        debugLog("[EnableJITOperation] execute() started")
        defer {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            debugLog("[EnableJITOperation] execute() took: \(String(format: "%.3fs", elapsed))")
        }
        try await super.executePreconditionCheck(parentProgress: parentProgress)
        self.setProgress(10)

        try await self.enableJIT(for: self.installedApp)
        self.setProgress(100)
        return true
    }

    private func enableJIT(for installedApp: InstalledApp) async throws
    {
        let userdefaults = UserDefaults.standard
        let dbContext = self.context.dbBackgroundContext

        let (targetBundleId, appName) = await dbContext.perform {
            (installedApp.resignedBundleIdentifier, installedApp.name)
        }

        if #available(iOS 17, *), userdefaults.isSideJITServerEnabled {
            let sideJITURLString = await SideJITManager.shared.resolveServerURL()
            guard let serverURL = URL(string: sideJITURLString) else {
                throw OperationError.unableToConnectSideJIT
            }
            self.setProgress(30)
            do {
                try await enableJITSideJITServer(serverURL: serverURL, bundleIdentifier: targetBundleId, appName: appName)
                self.setProgress(90)
                self.debugLog("JIT Enabled Successfully :3 (code made by Stossy11!)")
            } catch {
                if let serverError = error as? SideJITServerErrorType {
                    switch serverError {
                    case .invalidURL, .errorConnecting:
                        throw OperationError.unableToConnectSideJIT
                    case .deviceNotFound:
                        throw OperationError.unableToRespondSideJITDevice
                    case .other(let message):
                        if let startRange = message.range(of: "<p>"),
                           let endRange = message.range(of: "</p>", range: startRange.upperBound..<message.endIndex) {
                            let pContent = message[startRange.upperBound..<endRange.lowerBound]
                            self.debugLog(message + " + " + String(pContent))
                            throw OperationError.SideJITIssue(error: String(pContent))
                        } else {
                            self.debugLog(message)
                            throw OperationError.SideJITIssue(error: message)
                        }
                    }
                } else {
                    throw error
                }
            }
        } else {
            self.setProgress(30)

            var lastError: Error?
            let maxRetries = 3
            for retry in 0..<maxRetries {
                let percent = 30 + Int64(Double(retry) / Double(maxRetries) * 60.0)
                self.setProgress(percent)
                do {
                    try await debugApp(targetBundleId)
                    return
                } catch {
                    lastError = error
                }
            }
            if let error = lastError { throw error }
        }
    }
}

@available(iOS 17, *)
func enableJITSideJITServer(serverURL: URL, bundleIdentifier: String, appName: String) async throws {
    guard let udid = try await fetchUDID(useStatic: true) else {
        throw SideJITServerErrorType.other("Unable to get UDID")
    }

    let serverURLWithUDID = serverURL.appendingPathComponent(udid)
    let fullURL = serverURLWithUDID.appendingPathComponent(bundleIdentifier)

    debugLog("[EnableJITOperation] Requesting JIT from SideJITServer at: \(fullURL)")
    let (data, _) = try await URLSession.shared.data(from: fullURL)

    guard let dataString = String(data: data, encoding: .utf8) else {
        debugLog("[EnableJITOperation] SideJITServer returned non-UTF8 response data (size: \(data.count) bytes)")
        throw SideJITServerErrorType.other("Invalid response data")
    }

    debugLog("[EnableJITOperation] SideJITServer response: '\(dataString)'")

    let cleanString = dataString.trimmingCharacters(in: CharacterSet(charactersIn: "\"'\n\r\t "))

    if cleanString.contains("Enabled JIT for") {
        #if !os(tvOS)
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("JIT Successfully Enabled", comment: "")
        content.subtitle = String(format: NSLocalizedString("JIT Enabled For %@", comment: ""), appName)
        content.sound = .default

        let request = UNNotificationRequest(identifier: "EnabledJIT", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
        #else
        DispatchQueue.main.async {
            if let window = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.windows.first(where: { $0.isKeyWindow }) }).first {
                let toastView = ToastView(text: String(format: NSLocalizedString("JIT Successfully Enabled for %@", comment: ""), appName), detailText: nil)
                toastView.show(in: window)
            }
        }
        #endif
    } else {
        let errorType: SideJITServerErrorType = cleanString.contains("Could not find device")
            ? .deviceNotFound
            : .other(cleanString)
        throw errorType
    }
}
