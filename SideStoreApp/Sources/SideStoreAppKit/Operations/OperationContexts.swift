//
//  Contexts.swift
//  AltStore
//
//  Created by Riley Testut on 6/20/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import CoreData
import Foundation
import Network

import AltSign
import SideStoreCore

public class OperationContext {
    var error: Error?

    var presentingViewController: UIViewController?

    let operations: NSHashTable<Foundation.Operation>

	public init(error: Error? = nil, operations: [Foundation.Operation] = []) {
        self.error = error

        self.operations = NSHashTable<Foundation.Operation>.weakObjects()
        for operation in operations {
            self.operations.add(operation)
        }
    }

	public convenience init(context: OperationContext) {
        self.init(error: context.error, operations: context.operations.allObjects)
    }
}

public final class AuthenticatedOperationContext: OperationContext {
    var session: ALTAppleAPISession?

    var team: ALTTeam?
    var certificate: ALTCertificate?

    weak var authenticationOperation: AuthenticationOperation?

	public convenience init(context: AuthenticatedOperationContext) {
        self.init(error: context.error, operations: context.operations.allObjects)

        session = context.session
        team = context.team
        certificate = context.certificate
        authenticationOperation = context.authenticationOperation
    }
}

@dynamicMemberLookup
class AppOperationContext {
    let bundleIdentifier: String
    let authenticatedContext: AuthenticatedOperationContext

    var app: ALTApplication?
    var provisioningProfiles: [String: ALTProvisioningProfile]?

    var isFinished = false

    var error: Error? {
        get {
            _error ?? self.authenticatedContext.error
        }
        set {
            _error = newValue
        }
    }

    private var _error: Error?

    init(bundleIdentifier: String, authenticatedContext: AuthenticatedOperationContext) {
        self.bundleIdentifier = bundleIdentifier
        self.authenticatedContext = authenticatedContext
    }

    subscript<T>(dynamicMember keyPath: WritableKeyPath<AuthenticatedOperationContext, T>) -> T {
        self.authenticatedContext[keyPath: keyPath]
    }
}

class InstallAppOperationContext: AppOperationContext {
    lazy var temporaryDirectory: URL = {
        let temporaryDirectory = FileManager.default.uniqueTemporaryURL()

        do { try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true, attributes: nil) } catch { self.error = error }

        return temporaryDirectory
    }()

    var resignedApp: ALTApplication?
    var installedApp: InstalledApp? {
        didSet {
            installedAppContext = installedApp?.managedObjectContext
        }
    }

    private var installedAppContext: NSManagedObjectContext?

    var beginInstallationHandler: ((InstalledApp) -> Void)?

    var alternateIconURL: URL?
}
