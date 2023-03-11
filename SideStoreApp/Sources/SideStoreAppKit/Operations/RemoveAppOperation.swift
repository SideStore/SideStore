//
//  RemoveAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 5/12/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation

import SideStoreCore
import minimuxer
import MiniMuxer

import SideKit

@objc(RemoveAppOperation)
final class RemoveAppOperation: ResultOperation<InstalledApp> {
    let context: InstallAppOperationContext

    init(context: InstallAppOperationContext) {
        self.context = context

        super.init()
    }

    override func main() {
        super.main()

        if let error = context.error {
            finish(.failure(error))
            return
        }

        guard let installedApp = context.installedApp else { return finish(.failure(OperationError.invalidParameters)) }

        installedApp.managedObjectContext?.perform {
            let resignedBundleIdentifier = installedApp.resignedBundleIdentifier

            do {
                let res = try remove_app(app_id: resignedBundleIdentifier)
                if case let Uhoh.Bad(code) = res {
                    self.finish(.failure(minimuxer_to_operation(code: code)))
                }
            } catch let Uhoh.Bad(code) {
                self.finish(.failure(minimuxer_to_operation(code: code)))
            } catch {
                self.finish(.failure(ALTServerError.appDeletionFailed))
            }
            DatabaseManager.shared.persistentContainer.performBackgroundTask { context in
                self.progress.completedUnitCount += 1

                let installedApp = context.object(with: installedApp.objectID) as! InstalledApp
                installedApp.isActive = false
                self.finish(.success(installedApp))
            }
        }
    }
}
