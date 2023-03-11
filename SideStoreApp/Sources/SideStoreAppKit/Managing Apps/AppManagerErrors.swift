//
//  AppManagerErrors.swift
//  AltStore
//
//  Created by Riley Testut on 8/27/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import CoreData
import Foundation

import SideStoreCore

public extension AppManager {
    struct FetchSourcesError: LocalizedError, CustomNSError {
		public private(set) var primaryError: Error?

		public private(set) var sources: Set<Source>?
		public private(set) var  errors = [Source: Error]()

		public private(set) var managedObjectContext: NSManagedObjectContext?

		public var errorDescription: String? {
            if let error = primaryError {
                return error.localizedDescription
            } else {
                var localizedDescription: String?

                managedObjectContext?.performAndWait {
                    if self.sources?.count == 1 {
                        localizedDescription = NSLocalizedString("Could not refresh store.", comment: "")
                    } else if self.errors.count == 1 {
                        guard let source = self.errors.keys.first else { return }
                        localizedDescription = String(format: NSLocalizedString("Could not refresh source “%@”.", comment: ""), source.name)
                    } else {
                        localizedDescription = String(format: NSLocalizedString("Could not refresh %@ sources.", comment: ""), NSNumber(value: self.errors.count))
                    }
                }

                return localizedDescription
            }
        }

		public var recoverySuggestion: String? {
            if let error = primaryError as NSError? {
                return error.localizedRecoverySuggestion
            } else if errors.count == 1 {
                return nil
            } else {
                return NSLocalizedString("Tap to view source errors.", comment: "")
            }
        }

		public var errorUserInfo: [String: Any] {
            guard let error = errors.values.first, errors.count == 1 else { return [:] }
            return [NSUnderlyingErrorKey: error]
        }

		public init(_ error: Error) {
            primaryError = error
        }

		public init(sources: Set<Source>, errors: [Source: Error], context: NSManagedObjectContext) {
            self.sources = sources
            self.errors = errors
            managedObjectContext = context
        }
    }
}
