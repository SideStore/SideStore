//
//  XPCConnection.swift
//  AltKit
//
//  Created by Riley Testut on 6/15/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation
import SideKit
import os.log

@objc private protocol XPCConnectionProxy {
    func ping(completionHandler: @escaping () -> Void)
    func receive(_ data: Data, completionHandler: @escaping (Bool, Error?) -> Void)
}

public extension XPCConnection {
    static let unc0verMachServiceName = "cy:io.altstore.altdaemon"
    static let odysseyMachServiceName = "lh:io.altstore.altdaemon"

    static let machServiceNames = [unc0verMachServiceName, odysseyMachServiceName]
}

public class XPCConnection: NSObject, SideConnection {
    public let xpcConnection: NSXPCConnection

    private let queue = DispatchQueue(label: "io.altstore.XPCConnection")
    private let dispatchGroup = DispatchGroup()
    private var semaphore: DispatchSemaphore?
    private var buffer = Data(capacity: 1024)

    private var error: Error?

    public init(_ xpcConnection: NSXPCConnection) {
        let proxyInterface = NSXPCInterface(with: XPCConnectionProxy.self)
        xpcConnection.remoteObjectInterface = proxyInterface
        xpcConnection.exportedInterface = proxyInterface

        self.xpcConnection = xpcConnection

        super.init()

        xpcConnection.interruptionHandler = {
            self.error = ALTServerError.lostConnection(underlyingError: nil)
        }

        xpcConnection.exportedObject = self
        xpcConnection.resume()
    }

    deinit {
        self.disconnect()
    }
}

private extension XPCConnection {
    func makeProxy(errorHandler: @escaping (Error) -> Void) -> XPCConnectionProxy {
        let proxy = xpcConnection.remoteObjectProxyWithErrorHandler { error in
			os_log("Error messaging remote object proxy: %@", type: .error , error.localizedDescription)
            self.error = error
            errorHandler(error)
        } as! XPCConnectionProxy

        return proxy
    }
}

public extension XPCConnection {
    func connect(completionHandler: @escaping (Result<Void, Error>) -> Void) {
        let proxy = makeProxy { error in
            completionHandler(.failure(error))
        }

        proxy.ping {
            completionHandler(.success(()))
        }
    }

    func disconnect() {
        xpcConnection.invalidate()
    }

    func __send(_ data: Data, completionHandler: @escaping (Bool, Error?) -> Void) {
        guard error == nil else { return completionHandler(false, error) }

        let proxy = makeProxy { error in
            completionHandler(false, error)
        }

        proxy.receive(data) { success, error in
            completionHandler(success, error)
        }
    }

    func __receiveData(expectedSize: Int, completionHandler: @escaping (Data?, Error?) -> Void) {
        guard error == nil else { return completionHandler(nil, error) }

        queue.async {
            let copiedBuffer = self.buffer // Copy buffer to prevent runtime crashes.
            guard copiedBuffer.count >= expectedSize else {
                self.semaphore = DispatchSemaphore(value: 0)
                DispatchQueue.global().async {
                    _ = self.semaphore?.wait(timeout: .now() + 1.0)
                    self.__receiveData(expectedSize: expectedSize, completionHandler: completionHandler)
                }
                return
            }

            let data = copiedBuffer.prefix(expectedSize)
            self.buffer = copiedBuffer.dropFirst(expectedSize)

            completionHandler(data, nil)
        }
    }
}

public extension XPCConnection {
    override var description: String {
        "\(xpcConnection.endpoint) (XPC)"
    }
}

extension XPCConnection: XPCConnectionProxy {
    fileprivate func ping(completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    fileprivate func receive(_ data: Data, completionHandler: @escaping (Bool, Error?) -> Void) {
        queue.async {
            self.buffer.append(data)

            self.semaphore?.signal()
            self.semaphore = nil

            completionHandler(true, nil)
        }
    }
}
