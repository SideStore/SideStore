//
//  DeactivateAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 3/4/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation

import AltSign
import SideStoreCore
import minimuxer
import MiniMuxer
import RoxasUIKit
import SideKit

@objc(DeactivateAppOperation)
final class DeactivateAppOperation: ResultOperation<InstalledApp> {
    let app: InstalledApp
    let context: OperationContext

    init(app: InstalledApp, context: OperationContext) {
        self.app = app
        self.context = context

        super.init()
    }

    override func main() {
        super.main()

        if let error = context.error {
            finish(.failure(error))
            return
        }

        DatabaseManager.shared.persistentContainer.performBackgroundTask { context in
            let installedApp = context.object(with: self.app.objectID) as! InstalledApp
            let appExtensionProfiles = installedApp.appExtensions.map { $0.resignedBundleIdentifier }
            let allIdentifiers = [installedApp.resignedBundleIdentifier] + appExtensionProfiles

            for profile in allIdentifiers {
                do {
                    let res = try remove_provisioning_profile(id: profile)
                    if case let Uhoh.Bad(code) = res {
                        self.finish(.failure(minimuxer_to_operation(code: code)))
                    }
                } catch let Uhoh.Bad(code) {
                    self.finish(.failure(minimuxer_to_operation(code: code)))
                } catch {
                    self.finish(.failure(ALTServerError.unknownResponse))
                }
            }

            self.progress.completedUnitCount += 1
            installedApp.isActive = false
            self.finish(.success(installedApp))
        }
    }
}
