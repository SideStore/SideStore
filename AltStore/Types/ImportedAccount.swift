//
//  ImportedAccount.swift
//  AltStore
//
//  Created by ny on 9/7/25.
//  Copyright © 2025 SideStore. All rights reserved.
//

import Foundation

struct ImportedAccount: Codable {
    let email: String
    let password: String
    let cert: Data
    let certpass: String
    let local_user: String
    let adiPB: String
}
