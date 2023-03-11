//
//  AltXPCProtocol.swift
//  SideStore
//
//  Created by Joseph Mattiello on 02/28/23.
//  Copyright © 2023 Joseph Mattiello. All rights reserved.
//

import Foundation
import AltSign

public typealias AltXPCProtocol = SideXPCProtocol

@objc
public protocol SideXPCProtocol {
	func ping(completionHandler: @escaping () -> Void)
	func requestAnisetteData(completionHandler: @escaping (ALTAnisetteData?, Error?) -> Void)
}
