//
//  NSManagedObjectContext+SafeCoreData.swift
//  AltStoreCore
//
//  Some Core Data internal consistency checks (e.g. the persistent store
//  coordinator's "you never successfully opened the database corrupted"
//  assertion) raise an NSException rather than throwing a normal error.
//  Swift's do/catch cannot intercept those, so a plain `try context.save()`
//  or `try context.fetch(...)` can crash the process even from inside a
//  do/catch block. These wrappers route the call through RSTExceptionCatcher
//  so any such exception comes back as a normal, catchable Swift Error
//  instead of aborting the process (app OR widget extension).
//

import CoreData

public extension NSManagedObjectContext
{
    /// Equivalent to `save()`, but converts an NSException raised by Core
    /// Data's internals into a thrown Swift Error instead of crashing.
    func saveSafely() throws
    {
        var thrownError: Error?
        var caughtExceptionError: NSError?

        let completedWithoutException = RSTExceptionCatcher.catchException({
            do { try self.save() }
            catch { thrownError = error }
        }, error: &caughtExceptionError)

        if !completedWithoutException
        {
            let error = caughtExceptionError ?? NSError(domain: "RSTExceptionCatcherErrorDomain", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown Core Data exception."])
            debugLog("[NSManagedObjectContext+SafeCoreData] Caught NSException while saving context (likely persistent store corruption): \(error)")
            throw error
        }

        if let thrownError { throw thrownError }
    }

    /// Equivalent to `fetch(_:)`, but converts an NSException raised by Core
    /// Data's internals into a thrown Swift Error instead of crashing.
    func fetchSafely<T>(_ request: NSFetchRequest<T>) throws -> [T]
    {
        var results: [T] = []
        var thrownError: Error?
        var caughtExceptionError: NSError?

        let completedWithoutException = RSTExceptionCatcher.catchException({
            do { results = try self.fetch(request) }
            catch { thrownError = error }
        }, error: &caughtExceptionError)

        if !completedWithoutException
        {
            let error = caughtExceptionError ?? NSError(domain: "RSTExceptionCatcherErrorDomain", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown Core Data exception."])
            debugLog("[NSManagedObjectContext+SafeCoreData] Caught NSException while fetching (likely persistent store corruption): \(error)")
            throw error
        }

        if let thrownError { throw thrownError }
        return results
    }
}
