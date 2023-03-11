//
//  ConnectionManager.swift
//  AltServer
//
//  Created by Riley Testut on 5/23/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import Network
import SideKit
import os.log

public protocol RequestHandler {
    func handleAnisetteDataRequest(_ request: AnisetteDataRequest, for connection: Connection, completionHandler: @escaping (Result<AnisetteDataResponse, Error>) -> Void)
    func handlePrepareAppRequest(_ request: PrepareAppRequest, for connection: Connection, completionHandler: @escaping (Result<InstallationProgressResponse, Error>) -> Void)

    func handleInstallProvisioningProfilesRequest(_ request: InstallProvisioningProfilesRequest, for connection: Connection,
                                                  completionHandler: @escaping (Result<InstallProvisioningProfilesResponse, Error>) -> Void)
    func handleRemoveProvisioningProfilesRequest(_ request: RemoveProvisioningProfilesRequest, for connection: Connection,
                                                 completionHandler: @escaping (Result<RemoveProvisioningProfilesResponse, Error>) -> Void)

    func handleRemoveAppRequest(_ request: RemoveAppRequest, for connection: Connection, completionHandler: @escaping (Result<RemoveAppResponse, Error>) -> Void)

    func handleEnableUnsignedCodeExecutionRequest(_ request: EnableUnsignedCodeExecutionRequest, for connection: Connection, completionHandler: @escaping (Result<EnableUnsignedCodeExecutionResponse, Error>) -> Void)
}

public protocol ConnectionHandler: AnyObject {
    associatedtype ConnectionType = Connection
    var connectionHandler: ((ConnectionType) -> Void)? { get set }
    var disconnectionHandler: ((ConnectionType) -> Void)? { get set }

    func startListening()
    func stopListening()
}

public class ConnectionManager<RequestHandlerType: RequestHandler, ConnectionType: NetworkConnection & AnyObject, ConnectionHandlerType: ConnectionHandler> where ConnectionHandlerType.ConnectionType == ConnectionType {
    public let requestHandler: RequestHandlerType
    public let connectionHandlers: [ConnectionHandlerType]

    public var isStarted = false

    private var connections = [ConnectionType]()
    private let connectionsLock = NSLock()

    public init(requestHandler: RequestHandlerType, connectionHandlers: [ConnectionHandlerType]) {
        self.requestHandler = requestHandler
        self.connectionHandlers = connectionHandlers

        for handler in connectionHandlers {
            handler.connectionHandler = { [weak self] connection in
                self?.prepare(connection)
            }

            handler.disconnectionHandler = { [weak self] connection in
                self?.disconnect(connection)
            }
        }
    }

    public func start() {
        guard !isStarted else { return }

        for connectionHandler in connectionHandlers {
            connectionHandler.startListening()
        }

        isStarted = true
    }

    public func stop() {
        guard isStarted else { return }

        for connectionHandler in connectionHandlers {
            connectionHandler.stopListening()
        }

        isStarted = false
    }
}

private extension ConnectionManager {
    func prepare(_ connection: ConnectionType) {
        connectionsLock.lock()
        defer { self.connectionsLock.unlock() }

        guard !connections.contains(where: { $0 === connection }) else { return }
        connections.append(connection)

        handleRequest(for: connection)
    }

    func disconnect(_ connection: ConnectionType) {
        connectionsLock.lock()
        defer { self.connectionsLock.unlock() }

        guard let index = connections.firstIndex(where: { $0 === connection }) else { return }
        connections.remove(at: index)
    }

    func handleRequest(for connection: ConnectionType) {
        func finish<T: ServerMessageProtocol>(_ result: Result<T, Error>) {
            do {
                let response = try result.get()
                connection.send(response, shouldDisconnect: true) { result in
					os_log("Sent response %@ with result: %@", type: .error , response.identifier, String(describing: result))
                }
            } catch {
                let response = ErrorResponse(error: ALTServerError(error))
                connection.send(response, shouldDisconnect: true) { result in
					os_log("Sent error response %@ with result: %@", type: .error , response.error.localizedDescription, String(describing: result))
                }
            }
        }

        connection.receiveRequest { result in
			os_log("Received request with result: %@", type: .info, String(describing: result))

            switch result {
            case let .failure(error): finish(Result<ErrorResponse, Error>.failure(error))

            case let .success(.anisetteData(request)):
                self.requestHandler.handleAnisetteDataRequest(request, for: connection) { result in
                    finish(result)
                }

            case let .success(.prepareApp(request)):
                self.requestHandler.handlePrepareAppRequest(request, for: connection) { result in
                    finish(result)
                }

            case .success(.beginInstallation): break

            case let .success(.installProvisioningProfiles(request)):
                self.requestHandler.handleInstallProvisioningProfilesRequest(request, for: connection) { result in
                    finish(result)
                }

            case let .success(.removeProvisioningProfiles(request)):
                self.requestHandler.handleRemoveProvisioningProfilesRequest(request, for: connection) { result in
                    finish(result)
                }

            case let .success(.removeApp(request)):
                self.requestHandler.handleRemoveAppRequest(request, for: connection) { result in
                    finish(result)
                }

            case let .success(.enableUnsignedCodeExecution(request)):
                self.requestHandler.handleEnableUnsignedCodeExecutionRequest(request, for: connection) { result in
                    finish(result)
                }

            case .success(.unknown):
                finish(Result<ErrorResponse, Error>.failure(ALTServerError.unknownRequest))
            }
        }
    }
}
