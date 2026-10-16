//
//  AppBootManager.swift
//  SideStore
//
//  Created by Magesh K on 9/7/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import UIKit
import Minimuxer

public final class AppBootManager {
    public static let shared = AppBootManager()
    
    private let lock = NSLock()
    
    private var cachedNeedsPairingPrompt = false
    public var needsPairingPrompt: Bool {
        get { lock.withLock { cachedNeedsPairingPrompt } }
        set { lock.withLock { cachedNeedsPairingPrompt = newValue } }
    }
    
    private var cachedNeedsSideJITPrompt = false
    public var needsSideJITPrompt: Bool {
        get { lock.withLock { cachedNeedsSideJITPrompt } }
        set { lock.withLock { cachedNeedsSideJITPrompt = newValue } }
    }
    
    private init() {}
    

    public nonisolated func startMinimuxer(pairingFile: String) async throws {
        debugLog("[AppBootManager] startMinimuxer() entered")
        defer { debugLog("[AppBootManager] startMinimuxer() exited") }
        
        if UserDefaults.standard.enableEMPforWireguard {
            debugLog("[AppBootManager] Starting EMProxy before minimuxer...")
            try await startEMProxy()
        }

        let preferred = PairingFileManager.shared.preferredProtocol
        try await minimuxerStart(pairingFile, preferred: preferred)
        
        // Validate the pairing by trying to fetch the UDID
        do {
            debugLog("[AppBootManager] startMinimuxer(): Minimuxer fetchUDID() based connection starting...")
            let deviceUDID = try await fetchUDID(forceLive: true)
            debugLog("[AppBootManager] startMinimuxer(): Minimuxer fetchUDID() based connection test SUCCEEDED. UDID: \(deviceUDID)")
            self.needsPairingPrompt = false
        } catch {
            if case MinimuxerError.invalidPairing = error {
                debugLog("[AppBootManager] startMinimuxer(): Minimuxer fetchUDID() based connection test FAILED. \(error)")
                self.needsPairingPrompt = true
                throw error
            } else {
                debugLog("[AppBootManager] startMinimuxer(): Minimuxer fetchUDID() based connection test FAILED but PAIRING FILE IS VALID. \(error)")
            }
        }
    }
    
    @MainActor
    public func promptForPairing(on vc: UIViewController) async {
        var isRetry = false
        while true {
            guard let selectedURL = await withCheckedContinuation({ (continuation: CheckedContinuation<URL?, Never>) in
                PairingViewController.shared.presentPairingFileAlert(on: vc, isRetry: isRetry) { selectedURL in
                    debugLog("[AppBootManager] promptForPairing: alert completed with selectedURL: \(selectedURL?.path ?? "nil")")
                    continuation.resume(returning: selectedURL)
                }
            }) else {
                debugLog("[AppBootManager] promptForPairing: user skipped or cancelled pairing prompt")
                break
            }
            
            debugLog("[AppBootManager] promptForPairing: fetching pairing file at selectedURL: \(selectedURL.path)")
            guard let pairingString = PairingFileManager.shared.fetchPairingFile() else {
                debugLog("[AppBootManager] promptForPairing: failed to read saved pairing file from disk")
                isRetry = true
                continue
            }
            
            do {
                try await self.startMinimuxer(pairingFile: pairingString)
                self.needsPairingPrompt = false
                break
            } catch {
                debugLog("[AppBootManager] startMinimuxer failed with pairing file: \(error)")
                let didSwitch = await PairingViewController.shared.handlePotentialProtocolMismatch(
                    on: vc,
                    pairingContent: pairingString
                )
                if didSwitch {
                    do {
                        try await self.startMinimuxer(pairingFile: pairingString)
                        self.needsPairingPrompt = false
                        break
                    } catch {
                        debugLog("[AppBootManager] startMinimuxer retry after protocol switch failed: \(error)")
                    }
                }
                isRetry = true
            }
        }
    }
    
    public nonisolated func performBootSequence() async {
        debugLog("[AppBootManager] performBootSequence() entered")
        defer { debugLog("[AppBootManager] performBootSequence() exited") }
        
        async let jitCheck: Void = {
            debugLog("[AppBootManager] performBootSequence(): JIT check starting")
            defer { debugLog("[AppBootManager] performBootSequence(): JIT check completed") }
            if #available(iOS 17, *), !UserDefaults.standard.isSideJITServerEnabled {
                do {
                    try await SideJITManager.shared.isSideJITServerDetected()
                    self.needsSideJITPrompt = true
                } catch {
                    debugLog("[AppBootManager] Cannot find sideJITServer")
                }
            }
            
            if #available(iOS 17, *), UserDefaults.standard.isSideJITServerEnabled {
                await SideJITManager.shared.askForNetwork()
                debugLog("[AppBootManager] SideJITServer Enabled")
            }
        }()
        
        async let minimuxerCheck: Void = {
            debugLog("[AppBootManager] performBootSequence(): Minimuxer check starting")
            defer { debugLog("[AppBootManager] performBootSequence(): Minimuxer check completed") }
            guard let pf = PairingFileManager.shared.fetchPairingFile() else {
                #if !targetEnvironment(simulator)
                self.needsPairingPrompt = true
                #endif
                return
            }

            do {
                try await self.startMinimuxer(pairingFile: pf)
            } catch {
                debugLog("[AppBootManager] Failed to start minimuxer: \(error)")
            }
        }()
        
        _ = await (jitCheck, minimuxerCheck)
    }
}
