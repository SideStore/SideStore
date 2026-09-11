//
//  SideJITManager.swift
//  SideStore
//
//  Created by Magesh K on 14/8/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import UIKit

public final class SideJITManager {
    public static let shared = SideJITManager()
    
    private init() {}
    
    public func resolveServerURL() async -> String {
        if let userInput = UserDefaults.standard.textInputSideJITServerurl, !userInput.isEmpty {
            debugLog("[SideJITManager] resolveServerURL: user override specified '\(userInput)'")
            if let resolved = await resolveAddressIfNeeded(userInput) {
                debugLog("[SideJITManager] resolveServerURL: user override resolved to '\(resolved)'")
                return resolved
            }
            debugLog("[SideJITManager] resolveServerURL: using raw user override '\(userInput)'")
            return userInput
        }
        
        debugLog("[SideJITManager] resolveServerURL: attempting Bonjour auto-discovery for type='\(AppConstants.SideJIT.bonjourServiceType)', prefix='\(AppConstants.SideJIT.bonjourServiceName)' (timeout: \(AppConstants.SideJIT.timeout)s)")
        if let resolved = await BonjourDiscoveryManager.resolveFirstService(
            ofType: AppConstants.SideJIT.bonjourServiceType,
            namePrefix: AppConstants.SideJIT.bonjourServiceName,
            timeout: AppConstants.SideJIT.timeout
        ) {
            let cleanHost = resolved.host.strippingInterfaceScope
            let url = "http://\(cleanHost):\(resolved.port)"
            debugLog("[SideJITManager] resolveServerURL: Discovered SideJITServer via Bonjour at: \(url)")
            return url
        }
        debugLog("[SideJITManager] resolveServerURL: Bonjour discovery did not return any service within timeout")
        
        debugLog("[SideJITManager] resolveServerURL: trying fallback address '\(AppConstants.SideJIT.defaultServerURL)'")
        if let fallback = await resolveAddressIfNeeded(AppConstants.SideJIT.defaultServerURL) {
            debugLog("[SideJITManager] resolveServerURL: fallback resolved to '\(fallback)'")
            return fallback
        }
        
        debugLog("[SideJITManager] resolveServerURL: returning default server URL '\(AppConstants.SideJIT.defaultServerURL)'")
        return AppConstants.SideJIT.defaultServerURL
    }
    
    private func resolveAddressIfNeeded(_ input: String) async -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        let urlString = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
        guard let url = URL(string: urlString), let host = url.host else {
            debugLog("[SideJITManager] resolveAddressIfNeeded: unable to parse URL from '\(trimmed)'")
            return nil
        }
        let port = url.port ?? 8080
        debugLog("[SideJITManager] resolveAddressIfNeeded: parsing host='\(host)', port=\(port)")
        
        // 1. Direct IP address (strict IPv4 / IPv6 validation via POSIX inet_pton)
        var sin = sockaddr_in()
        var sin6 = sockaddr_in6()
        let cleanHost = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        let isIPv4 = inet_pton(AF_INET, host, &sin.sin_addr) == 1
        let isIPv6 = inet_pton(AF_INET6, cleanHost, &sin6.sin6_addr) == 1
        if isIPv4 || isIPv6 {
            debugLog("[SideJITManager] resolveAddressIfNeeded: direct IP matched (\(isIPv4 ? "IPv4" : "IPv6")) -> http://\(host):\(port)")
            return "http://\(host):\(port)"
        }
        
        // 2. DNS-SD Bonjour Service Descriptor (e.g. sidejitserver._http._tcp.local or _http._tcp)
        if host.contains("._tcp") || host.contains("._udp") {
            let parts = host.components(separatedBy: "._")
            let namePrefix = parts.first ?? ""
            let serviceType = parts.count > 1 ? "_\(parts.dropFirst().joined(separator: "._"))" : AppConstants.SideJIT.bonjourServiceType
            let cleanType = serviceType.replacingOccurrences(of: ".local", with: "")
            debugLog("[SideJITManager] resolveAddressIfNeeded: DNS-SD descriptor -> searching type='\(cleanType)', prefix='\(namePrefix)'")
            
            if let resolved = await BonjourDiscoveryManager.resolveFirstService(
                ofType: cleanType.isEmpty ? AppConstants.SideJIT.bonjourServiceType : cleanType,
                namePrefix: namePrefix == cleanType ? "" : namePrefix,
                timeout: AppConstants.SideJIT.timeout
            ) {
                let cleanHost = resolved.host.strippingInterfaceScope
                let resolvedPort = resolved.port > 0 ? resolved.port : UInt16(port)
                let resolvedURL = "http://\(cleanHost):\(resolvedPort)"
                debugLog("[SideJITManager] resolveAddressIfNeeded: Resolved mDNS service '\(host)' via Bonjour to: \(resolvedURL)")
                return resolvedURL
            }
            debugLog("[SideJITManager] resolveAddressIfNeeded: DNS-SD resolution timed out for descriptor '\(host)'")
        }
        
        // 3. Local hostname (.local)
        if host.hasSuffix(".local") {
            debugLog("[SideJITManager] resolveAddressIfNeeded: resolving .local hostname '\(host)' via getaddrinfo")
            let ips = BonjourDiscoveryManager.resolveHostToIPs(host)
            debugLog("[SideJITManager] resolveAddressIfNeeded: resolved IPs for '\(host)': \(ips)")
            if let firstIP = ips.first {
                let resolvedURL = "http://\(firstIP):\(port)"
                debugLog("[SideJITManager] resolveAddressIfNeeded: Resolved host '\(host)' to IP: \(resolvedURL)")
                return resolvedURL
            }
        }
        
        debugLog("[SideJITManager] resolveAddressIfNeeded: default raw host -> http://\(host):\(port)")
        return "http://\(host):\(port)"
    }
    
    public func askForNetwork() async {
        let SJSURL = await resolveServerURL()
        guard let url = URL(string: "\(SJSURL)/re/") else {
            debugLog("[SideJITManager] askForNetwork: invalid URL '\(SJSURL)/re/'")
            return
        }
        debugLog("[SideJITManager] askForNetwork: sending network trigger to \(url)")
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = AppConstants.SideJIT.timeout
            
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    let (_, response) = try await URLSession.shared.data(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 200
                    debugLog("[SideJITManager] askForNetwork: received response from \(url) (status: \(status))")
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(AppConstants.SideJIT.timeout * 1_000_000_000))
                    throw URLError(.timedOut)
                }
                try await group.next()
                group.cancelAll()
            }
        } catch {
            debugLog("[SideJITManager] askForNetwork error for \(url): \(error)")
        }
    }

    public func isSideJITServerDetected() async throws {
        let SJSURL = await resolveServerURL()
        guard let url = URL(string: SJSURL) else {
            debugLog("[SideJITManager] isSideJITServerDetected: invalid URL '\(SJSURL)'")
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = AppConstants.SideJIT.timeout
        debugLog("[SideJITManager] isSideJITServerDetected: testing detection at \(url)")
        
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                let (_, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 200
                debugLog("[SideJITManager] isSideJITServerDetected: SideJITServer detected at \(url) (status: \(status))")
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(AppConstants.SideJIT.timeout * 1_000_000_000))
                throw URLError(.timedOut)
            }
            try await group.next()
            group.cancelAll()
        }
    }
}

// MARK: - UI Extension
extension SideJITManager {
    @MainActor
    public func presentJITPrompt(presentingVC: UIViewController) {
        let alert = UIAlertController(
            title: NSLocalizedString("SideJITServer Detected", comment: ""),
            message: NSLocalizedString("Would you like to enable SideJITServer?", comment: ""),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: systemLocalizedString("OK"), style: .default) { _ in UserDefaults.standard.isSideJITServerEnabled = true })
        alert.addAction(.cancel)
        presentingVC.present(alert, animated: true)
    }
}
