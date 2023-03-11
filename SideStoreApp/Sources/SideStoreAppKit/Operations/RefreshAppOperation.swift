//
//  RefreshAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 2/27/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation

import AltSign
import SideStoreCore
import minimuxer
import MiniMuxer
import RoxasUIKit

@objc(RefreshAppOperation)
final class RefreshAppOperation: ResultOperation<InstalledApp> {
    let context: AppOperationContext

    // Strong reference to managedObjectContext to keep it alive until we're finished.
    let managedObjectContext: NSManagedObjectContext

    init(context: AppOperationContext) {
        self.context = context
        managedObjectContext = DatabaseManager.shared.persistentContainer.newBackgroundContext()

        super.init()
    }

    override func main() {
        super.main()

        do {
            if let error = context.error {
                throw error
            }

            guard let profiles = context.provisioningProfiles else { throw OperationError.invalidParameters }

            guard let app = context.app else { throw OperationError.appNotFound }

            DatabaseManager.shared.persistentContainer.performBackgroundTask { _ in
                print("Sending refresh app request...")

                for p in profiles {
                    do {
                        let x = try install_provisioning_profile(plist: p.value.data)
                        if case let .Bad(code) = x {
                            self.finish(.failure(minimuxer_to_operation(code: code)))
                        }
                    } catch let Uhoh.Bad(code) {
                        self.finish(.failure(minimuxer_to_operation(code: code)))
                    } catch {
                        self.finish(.failure(OperationError.unknown))
                    }
                    self.progress.completedUnitCount += 1

                    let predicate = NSPredicate(format: "%K == %@", #keyPath(InstalledApp.bundleIdentifier), app.bundleIdentifier)
                    self.managedObjectContext.perform {
                        guard let installedApp = InstalledApp.first(satisfying: predicate, in: self.managedObjectContext) else {
                            return
                        }
                        installedApp.update(provisioningProfile: p.value)
                        for installedExtension in installedApp.appExtensions {
                            guard let provisioningProfile = profiles[installedExtension.bundleIdentifier] else { continue }
                            installedExtension.update(provisioningProfile: provisioningProfile)
                        }
                        self.finish(.success(installedApp))
                    }
                }
            }
        } catch {
            finish(.failure(error))
        }
    }
}
