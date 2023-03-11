//
//  LoggedError.swift
//  SideStoreCore
//
//  Created by Riley Testut on 9/6/22.
//  Copyright © 2022 Riley Testut. All rights reserved.
//

import CoreData

public extension LoggedError {
    enum Operation: String {
        case install
        case update
        case refresh
        case activate
        case deactivate
        case backup
        case restore
    }
}

@objc(LoggedError)
public class LoggedError: NSManagedObject, Fetchable {
    /* Properties */
    @NSManaged public private(set) var date: Date

    @nonobjc public var operation: Operation? {
        guard let rawOperation = _operation else { return nil }

        let operation = Operation(rawValue: rawOperation)
        return operation
    }

    @NSManaged @objc(operation) private var _operation: String?

    @NSManaged public private(set) var domain: String
    @NSManaged public private(set) var code: Int32
    @NSManaged public private(set) var userInfo: [String: Any]

    @NSManaged public private(set) var appName: String
    @NSManaged public private(set) var appBundleID: String

    /* Relationships */
    @NSManaged public private(set) var storeApp: StoreApp?
    @NSManaged public private(set) var installedApp: InstalledApp?

    private static let dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .none
        return dateFormatter
    }()

    override private init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?) {
        super.init(entity: entity, insertInto: context)
    }

    public init(error: Error, app: AppProtocol, date: Date = Date(), operation: Operation? = nil, context: NSManagedObjectContext) {
        super.init(entity: LoggedError.entity(), insertInto: context)

        self.date = date
        _operation = operation?.rawValue

        let nsError = error as NSError
        domain = nsError.domain
        code = Int32(nsError.code)
        userInfo = nsError.userInfo

        appName = app.name
        appBundleID = app.bundleIdentifier

        switch app {
        case let storeApp as StoreApp: self.storeApp = storeApp
        case let installedApp as InstalledApp: self.installedApp = installedApp
        default: break
        }
    }
}

public extension LoggedError {
    var app: AppProtocol {
        // `as AppProtocol` needed to fix "cannot convert AnyApp to StoreApp" compiler error with Xcode 14.
        let app = installedApp ?? storeApp ?? AnyApp(name: appName, bundleIdentifier: appBundleID, url: nil) as AppProtocol
        return app
    }

    var error: Error {
        let nsError = NSError(domain: domain, code: Int(code), userInfo: userInfo)
        return nsError
    }

    @objc
    var localizedDateString: String {
        let localizedDateString = LoggedError.dateFormatter.string(from: date)
        return localizedDateString
    }

    var localizedFailure: String? {
        guard let operation = operation else { return nil }
        switch operation {
        case .install: return String(format: NSLocalizedString("Install %@ Failed", comment: ""), appName)
        case .update: return String(format: NSLocalizedString("Update %@ Failed", comment: ""), appName)
        case .refresh: return String(format: NSLocalizedString("Refresh %@ Failed", comment: ""), appName)
        case .activate: return String(format: NSLocalizedString("Activate %@ Failed", comment: ""), appName)
        case .deactivate: return String(format: NSLocalizedString("Deactivate %@ Failed", comment: ""), appName)
        case .backup: return String(format: NSLocalizedString("Backup %@ Failed", comment: ""), appName)
        case .restore: return String(format: NSLocalizedString("Restore %@ Failed", comment: ""), appName)
        }
    }
}

public extension LoggedError {
    @nonobjc class func fetchRequest() -> NSFetchRequest<LoggedError> {
        NSFetchRequest<LoggedError>(entityName: "LoggedError")
    }
}
