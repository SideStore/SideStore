//
//  RefreshGroup.swift
//  AltStore
//
//  Created by Riley Testut on 6/20/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import CoreData
import Foundation

import AltSign
import SideStoreCore

public final class RefreshGroup: NSObject {
    let context: AuthenticatedOperationContext
    let progress = Progress.discreteProgress(totalUnitCount: 0)

    var completionHandler: (([String: Result<InstalledApp, Error>]) -> Void)?
    var beginInstallationHandler: ((InstalledApp) -> Void)?

    private(set) var results = [String: Result<InstalledApp, Error>]()

    // Keep strong references to managed object contexts
    // so they don't die out from under us.
    private(set) var _contexts = Set<NSManagedObjectContext>()

    private var isFinished = false

    private let dispatchGroup = DispatchGroup()
    private var operations: [Foundation.Operation] = []

	public init(context: AuthenticatedOperationContext = AuthenticatedOperationContext()) {
        self.context = context

        super.init()
    }

    /// Used to keep track of which operations belong to this group.
    /// This does _not_ add them to any operation queue.
	public func add(_ operations: [Foundation.Operation]) {
        for operation in operations {
            dispatchGroup.enter()

            operation.completionBlock = { [weak self] in
                self?.dispatchGroup.leave()
            }
        }

        if self.operations.isEmpty && !operations.isEmpty {
            dispatchGroup.notify(queue: .global()) { [weak self] in
                self?.finish()
            }
        }

        self.operations.append(contentsOf: operations)
    }

	public func set(_ result: Result<InstalledApp, Error>, forAppWithBundleIdentifier bundleIdentifier: String) {
        results[bundleIdentifier] = result

        switch result {
        case .failure: break
        case let .success(installedApp):
            guard let context = installedApp.managedObjectContext else { break }
            _contexts.insert(context)
        }
    }

	public func cancel() {
        operations.forEach { $0.cancel() }
    }
}

private extension RefreshGroup {
    func finish() {
        guard !isFinished else { return }
        isFinished = true

        completionHandler?(results)
    }
}
