//
//  AnisetteProvider.swift
//  SideStore
//
//  Created by Magesh K on 8/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import SideSign

enum AnisetteProvider {
    static func fetch(handler: AnisetteServerHandler? = nil) async throws -> ALTAnisetteData {
        if UserDefaults.standard.useOnDeviceAnisette {
            debugLog("[AnisetteProvider] Fetching anisette via On-Device Anisette (ODA)...")
            return try await OnDeviceAnisetteManager.shared.fetchAnisetteData()
        } else {
            debugLog("[AnisetteProvider] Fetching anisette via remote server...")
            return try await fetchRemote(handler: handler)
        }
    }

    private static func fetchRemote(handler: AnisetteServerHandler? = nil) async throws -> ALTAnisetteData {
        let serverUrlStrings = await AnisetteServersManager.shared.getActiveServerURLs()
        let servers = serverUrlStrings.compactMap { URL(string: $0) }
        guard !servers.isEmpty else {
            throw AnisetteError.noServersConfigured
        }

        let lastServer = UserDefaults.standard.menuAnisetteURL
        let startIndex = servers.firstIndex(where: { $0.absoluteString == lastServer }) ?? 0
        let rotationDisabled = UserDefaults.standard.disableAnisetteRotation

        let provider = SideSign.AnisetteDataManager.shared
        let existingBlob = AnisetteConfigManager.shared.anisetteAdiBlob.flatMap { Data(base64Encoded: $0) }
        let identifier = await AnisetteConfigManager.shared.resolveDeviceIdentifier()
        let headers = await AnisetteConfigManager.shared.makeRequestHeaders()

        // Try the server that worked last first, then walk the rest. A server
        // that answers with a 503 or an HTML error page is just a failed
        // attempt: we move on instead of surfacing its markup to the user.
        let order: [Int] = rotationDisabled
            ? [startIndex]
            : Array(0..<servers.count).map { (startIndex + $0) % servers.count }

        var attempted = 0
        var lastStatusCode: Int?

        for index in order {
            let server = servers[index]
            attempted += 1
            debugLog("[AnisetteProvider] Attempting server [\(attempted)/\(order.count)]: \(server.absoluteString)")

            do {
                let (anisetteData, newBlob) = try await provider.fetchAnisetteData(
                    mode: .remote(server: server),
                    identifier: identifier,
                    existingAdiBlob: existingBlob,
                    headers: headers,
                    onError: { error in
                        if let anisetteError = error as? SideSign.AnisetteError,
                           case .outdatedV1Server(let serverURL, _) = anisetteError {
                            if UserDefaults.standard.defaultServerURL == serverURL.absoluteString {
                                return true
                            }
                            if let handler = handler {
                                let shouldContinue = try await handler.warnOutdatedAnisetteServer()
                                if shouldContinue {
                                    UserDefaults.standard.defaultServerURL = serverURL.absoluteString
                                }
                                return shouldContinue
                            }
                        }
                        return false
                    }
                )

                if let freshBlob = newBlob {
                    AnisetteConfigManager.shared.anisetteAdiBlob = freshBlob.base64EncodedString()
                }

                UserDefaults.standard.menuAnisetteURL = server.absoluteString
                debugLog("[AnisetteProvider] Successfully fetched Anisette data from \(server.absoluteString)")
                return anisetteData
            } catch {
                lastStatusCode = SignInFailure.classify(error)?.statusCode ?? lastStatusCode
                debugLog("[AnisetteProvider] Server '\(server.absoluteString)' failed: \(SignInFailure.logSummary(for: error))")

                guard SignInFailure.shouldRetryOnAnotherServer(error) else {
                    throw error
                }
            }
        }

        debugLog("[AnisetteProvider] All \(attempted) server(s) failed. Last status: \(lastStatusCode.map { String($0) } ?? "n/a")")
        throw OperationError.anisetteServerUnavailable(attempted: attempted, lastStatusCode: lastStatusCode)
    }
}
