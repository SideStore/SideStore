//
//  NetworkConnection.swift
//  AltKit
//
//  Created by Riley Testut on 6/1/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation
import Network
import SideKit

public class NetworkConnection: NSObject, SideConnection {
    public let nwConnection: NWConnection

    public init(_ nwConnection: NWConnection) {
        self.nwConnection = nwConnection
    }

    public func __send(_ data: Data, completionHandler: @escaping (Bool, Error?) -> Void) {
        nwConnection.send(content: data, completion: .contentProcessed { error in
            completionHandler(error == nil, error)
        })
    }

    public func __receiveData(expectedSize: Int, completionHandler: @escaping (Data?, Error?) -> Void) {
        nwConnection.receive(minimumIncompleteLength: expectedSize, maximumLength: expectedSize) { data, _, _, error in
            guard data != nil || error != nil else {
                return completionHandler(nil, ALTServerError.lostConnection(underlyingError: error))
            }

            completionHandler(data, error)
        }
    }

    public func disconnect() {
        switch nwConnection.state {
        case .cancelled, .failed: break
        default: nwConnection.cancel()
        }
    }
}

public extension NetworkConnection {
    override var description: String {
        "\(nwConnection.endpoint) (Network)"
    }
}
