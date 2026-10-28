//
//  AppManager.swift
//  AltStore
//
//  Created by Riley Testut on 5/29/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import Foundation
import CoreData
@preconcurrency import UIKit
import SideSign
import UserNotifications
import MobileCoreServices
import Intents
import Combine
import UniformTypeIdentifiers

extension AppManager
{
    static let didFetchSourceNotification = Notification.Name("io.sidestore.AppManager.didFetchSource")
    static let didAddSourceNotification = Notification.Name("io.sidestore.AppManager.didAddSource")
    static let didRemoveSourceNotification = Notification.Name("io.sidestore.AppManager.didRemoveSource")
    static let willInstallAppFromNewSourceNotification = Notification.Name("io.sidestore.AppManager.willInstallAppFromNewSource")
    
    static let expirationWarningNotificationID = "sidestore-expiration-warning"
    static let enableJITResultNotificationID = "sidestore-enable-jit"
}

final class AppManager: ObservableObject, @unchecked Sendable
{
    static let shared = AppManager()

    lazy var pipelineRunner: PipelineRunner = {
        PipelineRunner(
            progress: self, 
            context: self, 
            logger: self, 
            defaultEntitlements: OperationEntitlements.defaultAdditionalEntitlements
        )
    }()

    @Published
    private(set) var updateSourcesResult: Result<Void, Error>? // nil == loading
    
    @Published private var installationProgress = [String: Progress]()
    @Published private var refreshProgress = [String: Progress]()
    private var cancellables: Set<AnyCancellable> = []
    
    private let progressLock = NSLock()
    
    private init() {
        self.$refreshProgress
            .receive(on: RunLoop.main)
            .map(\.keys)
            .flatMap { (bundleIDs) in
                DatabaseManager.shared.viewContext.registeredObjects.publisher
                    .compactMap { $0 as? InstalledApp }
                    .map { ($0, bundleIDs.contains($0.bundleIdentifier)) }
            }
            .sink { (installedApp, isRefreshing) in
                if installedApp.isRefreshing != isRefreshing {
                    installedApp.isRefreshing = isRefreshing
                }
            }
            .store(in: &self.cancellables)
    }

    func reconcileInstalledApps() async {
        guard !self.isActivelyManagingAnyApp else {
            debugLog("[AppManager] Skipping reconcileInstalledApps: operations in progress")
            return
        }

        let dbBackgroundContext = DatabaseManager.shared.persistentContainer.newBackgroundContext()

        do {
            let (activeBundleIDs, activeSignatures, altStoreApp) = try await dbBackgroundContext.perform {
                let installedApps = InstalledApp.all(in: dbBackgroundContext)
                var altStore: InstalledApp?

                #if !targetEnvironment(simulator)
                let legacyApps = Set(UserDefaults.standard.legacySideloadedApps ?? [])

                for app in installedApps {
                    if app.bundleIdentifier == StoreApp.altstoreAppID {
                        altStore = app
                        continue
                    }

                    guard app.isActive, !self.isActivelyManagingApp(withBundleID: app.bundleIdentifier) else { continue }

                    let isDeclared = UTType(app.installedAppUTI)?.isDeclared ?? false
                    guard !isDeclared, !legacyApps.contains(app.bundleIdentifier) else { continue }

                    CacheResignedMetadataOperation.clearCustomizations(for: app)
                    dbBackgroundContext.delete(app)
                    if var patched = UserDefaults.standard.patchedApps {
                        patched.removeAll { $0 == app.bundleIdentifier }
                        UserDefaults.standard.patchedApps = patched
                    }
                }

                if dbBackgroundContext.hasChanges {
                    try dbBackgroundContext.save()
                }
                #else
                altStore = installedApps.first { $0.bundleIdentifier == StoreApp.altstoreAppID }
                #endif

                let active = installedApps.filter { !$0.isDeleted }
                let ids = Set(active.map(\.resignedBundleIdentifier))
                let sigs = Set(active.compactMap(\.appBundleFingerprint))

                return (ids, sigs, altStore)
            }

            await scheduleExpirationWarning(for: altStoreApp, in: dbBackgroundContext)

            CacheAppOperation.pruneUnusedCaches(activeSignatures: activeSignatures, activeBundleIDs: activeBundleIDs) { [weak self] in
                self?.isActivelyManagingApp(withBundleID: $0) ?? false
            }
        } catch {
            debugLog("[AppManager] Error reconciling installed apps: \(error)")
        }
    }

    private func scheduleExpirationWarning(for altStoreApp: InstalledApp?, in context: NSManagedObjectContext) async {
        #if !targetEnvironment(simulator)
        guard let altStoreApp else { return }
        do {
            let opContext = StandaloneOperationContext(steps: .scheduleExpirationWarningNotification, dbBackgroundContext: context)
            let op = try ScheduleExpirationWarningNotificationOperation(installedApp: altStoreApp, context: opContext)
            try await op.execute()
        } catch {
            debugLog("[AppManager] Failed to schedule expiration notification: \(error)")
        }
        #endif
    }

    func appsToDeactivate(for installedApp: InstalledApp) -> [InstalledApp]? {
        guard !UserDefaults.standard.isAppLimitDisabled,
              let activeAppsLimit = UserDefaults.standard.activeAppsLimit
        else { return nil }

        let activeApps = InstalledApp.fetchActiveApps(in: DatabaseManager.shared.viewContext)
            .filter { $0.resignedBundleIdentifier != installedApp.resignedBundleIdentifier }
            .filter { ($0.team?.type ?? .unknown) == .free }
            .sorted { ($0.name, $0.refreshedDate) < ($1.name, $1.refreshedDate) }

        let activeAppsCount = activeApps.map(\.requiredActiveSlots).reduce(0, +)
        let availableActiveApps = max(activeAppsLimit - activeAppsCount, 0)

        guard installedApp.requiredActiveSlots > availableActiveApps else { return nil }
        return activeApps.filter { $0.bundleIdentifier != StoreApp.altstoreAppID }
    }
    
    func clearAppCache(completion: @escaping (Result<Void, Error>) -> Void)
    {
        Task.detached {
            do {
                let dbBackgroundContext = DatabaseManager.shared.persistentContainer.newBackgroundContext()
                let context = StandaloneOperationContext(steps: .clearAppCache, dbBackgroundContext: dbBackgroundContext)
                try await ClearAppCacheOperation(context: context).execute()
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func fetchSource(sourceURL: URL, managedObjectContext: NSManagedObjectContext) async throws -> Source
    {
        try await withCheckedThrowingContinuation { continuation in
            do {
                try fetchSource(sourceURL: sourceURL, managedObjectContext: managedObjectContext) { result in
                    continuation.resume(with: result)
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    func fetchSources() async throws -> (Set<Source>, NSManagedObjectContext)
    {
        try await withCheckedThrowingContinuation { continuation in
            fetchSources { result in
                continuation.resume(with: result)
            }
        }
    }
    
    func add(@AsyncManaged _ source: Source,
             message: String? = NSLocalizedString("Make sure to only add sources that you trust.", comment: ""),
             presentingViewController: UIViewController) async throws
    {
        let (sourceName, sourceURL) = await $source.perform { ($0.name, $0.sourceURL) }
        
        let context = DatabaseManager.shared.persistentContainer.newBackgroundContext()
        async let fetchedSource = try await self.fetchSource(sourceURL: sourceURL, managedObjectContext: context)

        let title = String(format: NSLocalizedString("Would you like to add the source “%@”?", comment: ""), sourceName)
        let action = await UIAlertAction(title: NSLocalizedString("Add Source", comment: ""), style: .default)
        try await presentingViewController.presentConfirmationAlert(title: title, message: message ?? "", primaryAction: action)

        let sourceExists = try await fetchedSource.isAdded()
        guard !sourceExists else { throw SourceError.duplicate(source, existingSource: nil) }
        
        try await context.performAsync {
            try context.save()
        }
        
        NotificationCenter.default.post(name: AppManager.didAddSourceNotification, object: source)
    }
    
    func remove(@AsyncManaged _ source: Source, presentingViewController: UIViewController) async throws
    {
        let (sourceName, sourceID) = await $source.perform { ($0.name, $0.identifier) }
        guard sourceID != Source.altStoreIdentifier else {
            throw OperationError.forbidden(failureReason: NSLocalizedString("The default SideStore source cannot be removed.", comment: ""))
        }
        
        let title = String(format: NSLocalizedString("Are you sure you want to remove the source “%@”?", comment: ""), sourceName)
        let message = NSLocalizedString("Any apps you've installed from this source will remain, but they'll no longer receive any app updates.", comment: "")
        let action = await UIAlertAction(title: NSLocalizedString("Remove Source", comment: ""), style: .destructive)
        try await presentingViewController.presentConfirmationAlert(title: title, message: message, primaryAction: action)
        
        let context = DatabaseManager.shared.persistentContainer.newBackgroundContext()
        try await context.performAsync {
            let predicate = NSPredicate(format: "%K == %@", #keyPath(Source.identifier), sourceID)
            guard let source = Source.first(satisfying: predicate, in: context) else { return }
            
            context.delete(source)
            try context.save()
        }
        
        NotificationCenter.default.post(name: AppManager.didRemoveSourceNotification, object: source)
    }
    
    @discardableResult
    func fetchSource(sourceURL: URL,
                     managedObjectContext: NSManagedObjectContext,
                     completionHandler: @escaping (Result<Source, Error>) -> Void) throws -> FetchSourceOperation
    {
        let context = StandaloneOperationContext(steps: [], dbBackgroundContext: managedObjectContext)
        let fetchSourceOperation = try FetchSourceOperation(sourceURL: sourceURL, context: context)
        Task.detached {
            do {
                let source = try await fetchSourceOperation.execute()
                completionHandler(.success(source))
            } catch {
                completionHandler(.failure(error))
            }
        }
        return fetchSourceOperation
    }
    
    func fetchSources(completionHandler: @escaping (Result<(Set<Source>, NSManagedObjectContext), FetchSourcesError>) -> Void)
    {
        Task.detached(priority: .utility) {
            let managedObjectContext = DatabaseManager.shared.persistentContainer.newBackgroundContext()
            
            var sourceData = [(objectID: NSManagedObjectID, sourceURL: URL)]()
            
            managedObjectContext.performAndWait {
                let sources = Source.all(in: managedObjectContext)
                sourceData = sources.map { ($0.objectID, $0.sourceURL) }
            }
            
            guard !sourceData.isEmpty else {
                completionHandler(.failure(.init(OperationError.noSources)))
                return
            }
            
            var taskResults = [(NSManagedObjectID, Result<NSManagedObjectID, Error>)]()
            
            await withTaskGroup(of: (NSManagedObjectID, Result<NSManagedObjectID, Error>).self) { taskGroup in
                for data in sourceData {
                    taskGroup.addTask {
                        do {
                            let context = StandaloneOperationContext(steps: [], dbBackgroundContext: managedObjectContext)
                            let fetchSourceOperation = try FetchSourceOperation(sourceURL: data.sourceURL, context: context)
                            let fetchedSource = try await fetchSourceOperation.execute()
                            return (data.objectID, .success(fetchedSource.objectID))
                        } catch {
                            return (data.objectID, .failure(error))
                        }
                    }
                }
                for await result in taskGroup {
                    taskResults.append(result)
                }
            }
            
            await managedObjectContext.perform {
                var fetchedSources = Set<Source>()
                var errors =()
                
                for (objectID, result) in taskResults {
                    let source = managedObjectContext.object(with: objectID) as! Source
                    switch result {
                    case .success(let fetchedObjectID):
                        fetchedSources.insert(managedObjectContext.object(with: fetchedObjectID) as! Source)
                    case .failure(let nsError as NSError):
                        let title = String(format: NSLocalizedString("Unable to Refresh “%@” Source", comment: ""), source.name)
                        let error = nsError.withLocalizedTitle(title)
                        errors[source] = error
                        source.error = error.sanitizedForSerialization()
                    }
                }
                
                do {
                    if managedObjectContext.hasChanges {
                        try managedObjectContext.save()
                    }
                } catch {
                    debugLog("Failed to save managedObjectContext in fetchSources: \(error.localizedDescription)")
                }
                
                if !errors.isEmpty {
                    let sourcesSet = Set(sourceData.compactMap { managedObjectContext.object(with: $0.objectID) as? Source })
                    completionHandler(.failure(.init(sources: sourcesSet, errors: errors, context: managedObjectContext)))
                } else {
                    completionHandler(.success((fetchedSources, managedObjectContext)))
                }
                NotificationCenter.default.post(name: AppManager.didFetchSourceNotification, object: self)
            }
        }
    }
    
    func syncAppIDs(completionHandler: @escaping (Result<Void, Error>) -> Void)
    {
        guard AuthManager.shared.isAuthenticated else {
            debugLog("[AppManager] syncAppIDs: User is unauthenticated. Skipping syncAppIDs.")
            completionHandler(.failure(OperationError.notAuthenticated))
            return
        }
        
        Task.detached(priority: .utility) {
            do {
                let managedObjectContext = self.getValidDbContext()
                let context = StandaloneOperationContext(steps: .syncAppIDs, dbBackgroundContext: managedObjectContext)
                try await AuthManager.shared.getAuthenticatedSession()
                
                let syncAppIDsOperation = try SyncAppIDsOperation(context: context)
                try await syncAppIDsOperation.execute()
                completionHandler(.success(()))
            } catch {
                completionHandler(.failure(error))
            }
        }
    }
    
    @discardableResult
    func updateKnownSources(completionHandler: @escaping (Result<([KnownSource], [KnownSource]), Error>) -> Void) -> UpdateKnownSourcesOperation
    {
        let updateKnownSourcesOperation = UpdateKnownSourcesOperation()
        Task.detached(priority: .utility) {
            do {
                let result = try await updateKnownSourcesOperation.execute()
                completionHandler(.success(result))
            } catch {
                completionHandler(.failure(error))
            }
        }
        return updateKnownSourcesOperation
    }
    
    func updateAllSources(completion: @escaping (Result<Void, Error>) -> Void)
    {
        self.updateSourcesResult = nil
        
        self.fetchSources() { (result) in
            do
            {
                if case .failure(let error) = result {
                    throw error
                }
                
                do
                {
                    let (_, context) = try result.get()
                    try context.save()
                    
                    DispatchQueue.main.async {
                        self.updateSourcesResult = .success(())
                        completion(.success(()))
                    }
                }
                catch let error as AppManager.FetchSourcesError
                {
                    try error.managedObjectContext?.save()
                    throw error
                }
                catch let mergeError as MergeError
                {
                    guard let sourceID = mergeError.sourceID else { throw mergeError }
                    
                    let sanitizedError = (mergeError as NSError).sanitizedForSerialization()
                    DatabaseManager.shared.persistentContainer.performBackgroundTask { context in
                        do
                        {
                            guard let source = Source.first(satisfying: NSPredicate(format: "%K == %@", #keyPath(Source.identifier), sourceID), in: context) else { return }
                            
                            source.error = sanitizedError
                            try context.save()
                        }
                        catch
                        {
                            debugLog("Failed to assign error \(sanitizedError.localizedErrorCode) to source \(sourceID). \(error.localizedDescription)")
                        }
                    }
                    
                    throw mergeError
                }
            }
            catch var error as NSError
            {
                if error.localizedTitle == nil
                {
                    error = error.withLocalizedTitle(NSLocalizedString("Unable to Refresh Store", comment: ""))
                }
                
                DispatchQueue.main.async {
                    self.updateSourcesResult = .failure(error)
                    completion(.failure(error))
                }
            }
        }
    }

    @discardableResult
    func install(_ target: InstallTarget,
                 presentingViewController: UIViewController? = nil,
                 dbBackgroundContext: NSManagedObjectContext? = nil,
                 context: StandaloneOperationContext? = nil,
                 completionHandler: @escaping (Result<InstalledApp, Error>) -> Void) -> RefreshGroup
    {
        debugLog("[AppManager] install() called for target: \(target)")
        let pipelineHandler = self.makePipelineHandler(presentingViewController: presentingViewController)
        let dbContext = self.getValidDbContext(dbBackgroundContext ?? context?.dbBackgroundContext)

        let app = self.resolveApp(for: target)
        return self.pipelineRunner.performSingleOperation(
            .install(app),
            handler: pipelineHandler,
            dbContext: dbContext,
            completionHandler: { result in
                if case .success(let installedApp) = result,
                   UserDefaults.standard.isAutoLaunchAppAfterInstallEnabled,
                   installedApp.bundleIdentifier != StoreApp.altstoreAppID {
                    Task { @MainActor in
                        UIApplication.shared.open(installedApp.openAppURL)
                    }
                }
                completionHandler(result)
            }
        )
    }

    private func resolveApp(for target: InstallTarget) -> AppProtocol {
        switch target {
        case .app(let app):
            return app
        case .url(let url):
            if url.isFileURL,
               let packageType = PackageType(url: url),
               let (bundleID, appName) = try? Self.readAppMetadata(from: url, packageType: packageType) {
                return AnyApp(name: appName, bundleIdentifier: bundleID, url: url, storeApp: nil)
            }
            let name = url.deletingPathExtension().lastPathComponent
            return AnyApp(name: name, bundleIdentifier: name, url: url, storeApp: nil)
        }
    }

    private static func readAppMetadata(from url: URL, packageType
