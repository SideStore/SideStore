//
//  DaemonRequestHandler.swift
//  AltDaemon
//
//  Created by Riley Testut on 6/1/20.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation

import SideKit
import os.log

typealias DaemonConnectionManager = ConnectionManager<DaemonRequestHandler>

private let connectionManager = ConnectionManager(requestHandler: DaemonRequestHandler(),
                                                  connectionHandlers: [XPCConnectionHandler()])

extension DaemonConnectionManager {
    static var shared: ConnectionManager {
        connectionManager
    }
}

struct DaemonRequestHandler: RequestHandler {
    func handleAnisetteDataRequest(_: AnisetteDataRequest, for _: Connection, completionHandler: @escaping (Result<AnisetteDataResponse, Error>) -> Void) {
        do {
            let anisetteData = try AnisetteDataManager.shared.requestAnisetteData()

            let response = AnisetteDataResponse(anisetteData: anisetteData)
            completionHandler(.success(response))
        } catch {
            completionHandler(.failure(error))
        }
    }

    func handlePrepareAppRequest(_ request: PrepareAppRequest, for connection: Connection, completionHandler: @escaping (Result<InstallationProgressResponse, Error>) -> Void) {
        guard let fileURL = request.fileURL else { return completionHandler(.failure(ALTServerError(.invalidRequest))) }

        print("Awaiting begin installation request...")

        connection.receiveRequest { result in
            os_log("Received begin installation request with result: %@", type: .info , String(describing: result))

            do {
                guard case let .beginInstallation(request) = try result.get() else { throw ALTServerError(.unknownRequest) }
                guard let bundleIdentifier = request.bundleIdentifier else { throw ALTServerError(.invalidRequest) }

                AppManager.shared.installApp(at: fileURL, bundleIdentifier: bundleIdentifier, activeProfiles: request.activeProfiles) { result in
                    let result = result.map { InstallationProgressResponse(progress: 1.0) }
					os_log("Installed app with result: %@", type: .info, String(describing: result))

                    completionHandler(result)
                }
            } catch {
                completionHandler(.failure(error))
            }
        }
    }

    func handleInstallProvisioningProfilesRequest(_ request: InstallProvisioningProfilesRequest, for _: Connection,
                                                  completionHandler: @escaping (Result<InstallProvisioningProfilesResponse, Error>) -> Void) {
        AppManager.shared.install(request.provisioningProfiles, activeProfiles: request.activeProfiles) { result in
            switch result {
            case let .failure(error):
				os_log("Failed to install profiles %@ : %@", type: .error , request.provisioningProfiles.map { $0.bundleIdentifier }.joined(separator: "\n"), error.localizedDescription)
                completionHandler(.failure(error))

            case .success:
				os_log("Installed profiles: %@", type: .info , request.provisioningProfiles.map { $0.bundleIdentifier }.joined(separator: "\n"))

                let response = InstallProvisioningProfilesResponse()
                completionHandler(.success(response))
            }
        }
    }

    func handleRemoveProvisioningProfilesRequest(_ request: RemoveProvisioningProfilesRequest, for _: Connection,
                                                 completionHandler: @escaping (Result<RemoveProvisioningProfilesResponse, Error>) -> Void) {
        AppManager.shared.removeProvisioningProfiles(forBundleIdentifiers: request.bundleIdentifiers) { result in
            switch result {
            case let .failure(error):
				os_log("Failed to remove profiles %@ : %@", type: .error, request.bundleIdentifiers, error.localizedDescription)
                completionHandler(.failure(error))

            case .success:
                os_log("Removed profiles: %@", type: .info , request.bundleIdentifiers)

                let response = RemoveProvisioningProfilesResponse()
                completionHandler(.success(response))
            }
        }
    }

    func handleRemoveAppRequest(_ request: RemoveAppRequest, for _: Connection, completionHandler: @escaping (Result<RemoveAppResponse, Error>) -> Void) {
        AppManager.shared.removeApp(forBundleIdentifier: request.bundleIdentifier) { result in
            switch result {
            case let .failure(error):
                os_log("Failed to remove app %@ : %@", type: .error , request.bundleIdentifier, error.localizedDescription)
                completionHandler(.failure(error))

            case .success:
                os_log("Removed app: %@", type: .info , request.bundleIdentifier)

                let response = RemoveAppResponse()
                completionHandler(.success(response))
            }
        }
    }
}
