//
//  CFNotificationName+AltStore.swift
//  AltStoreCore
//
//  Created by Magesh K on 2026-06-28.
//

import Foundation

public let ALTWiredServerConnectionAvailableRequest = CFNotificationName("io.sidestore.Request.WiredServerConnectionAvailable" as CFString)
public let ALTWiredServerConnectionAvailableResponse = CFNotificationName("io.sidestore.Response.WiredServerConnectionAvailable" as CFString)
public let ALTWiredServerConnectionStartRequest = CFNotificationName("io.sidestore.Request.WiredServerConnectionStart" as CFString)

extension CFNotificationName {
    public static let wiredServerConnectionAvailableRequest = ALTWiredServerConnectionAvailableRequest
    public static let wiredServerConnectionAvailableResponse = ALTWiredServerConnectionAvailableResponse
    public static let wiredServerConnectionStartRequest = ALTWiredServerConnectionStartRequest
}
