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
        /// Every time refreshProgress is changed, update all InstalledApps in memory
        /// so that app.isRefreshing == refreshProgress.keys.contains(app.bundleID)
        ///
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
        await Task.detached {
            let dbBackgroundContext = DatabaseManager.shared.persistentContainer.newBackgroundContext()
            var altstoreAppObjectID: NSManagedObjectID?

            #if targetEnvironment(simulator)
            // Apps aren't ever actually installed to simulator, so just do nothing rather than delete them from database.
            #else
        
            do {
                try await dbBackgroundContext.perform {
                    let installedApps = InstalledApp.all(in: dbBackgroundContext)
                
                    if UserDefaults.standard.legacySideloadedApps == nil {
                        // First time updating apps since updating AltStore to use custom UTIs,
                        // so cache all existing apps temporarily to prevent us from accidentally
                        // deleting them due to their custom UTI not existing (yet).
                        let apps = installedApps.map { $0.bundleIdentifier }
                        UserDefaults.standard.legacySideloadedApps = apps
                    }
                
                    let legacySideloadedApps = Set(UserDefaults.standard.legacySideloadedApps ?? [])
                
                    for app in installedApps {
                        guard app.bundleIdentifier != StoreApp.altstoreAppID else {
                            altstoreAppObjectID = app.objectID
                            continue
                        }
                    
                        guard !self.isActivelyManagingApp(withBundleID: app.bundleIdentifier) else { continue }
                    
                        if !UserDefaults.standard.isLegacyDeactivationSupported
                        {
                            // We can't (ab)use provisioning profiles to deactivate apps,
                            // which means we must delete apps to free up active slots.
                            // So, only check if active apps are installed to prevent
                            // false positives when checking inactive apps.
                            guard app.isActive else { continue }
                        }
                    
                        let isDeclared = UTType(app.installedAppUTI)?.isDeclared ?? false
                        if !isDeclared && !legacySideloadedApps.contains(app.bundleIdentifier)
                        {
                            // This UTI is not declared by any apps, which means this app has been deleted by the user.
                            // This app is also not a legacy sideloaded app, so we can assume it's fine to delete it.
                            dbBackgroundContext.delete(app)
                        
                            if var patchedApps = UserDefaults.standard.patchedApps, let index = patchedApps.firstIndex(of: app.bundleIdentifier)
                            {
                                patchedApps.remove(at: index)
                                UserDefaults.standard.patchedApps = patchedApps
                            }
                        }
                    }
                
                    if dbBackgroundContext.hasChanges {
                        try dbBackgroundContext.save()
                    }
                }
            
                if let objectID = altstoreAppObjectID {
                    let context = StandaloneOperationContext(steps: .scheduleExpirationWarningNotification, dbBackgroundContext: dbBackgroundContext)
                    let app = await dbBackgroundContext.perform {
                        dbBackgroundContext.object(with: objectID) as! InstalledApp
                    }
                    let scheduleNotifOp = try ScheduleExpirationWarningNotificationOperation(
                        installedApp: app,
                        context: context
                    )
                    try await scheduleNotifOp.execute()
                }
            } catch {
                debugLog("Error while fetching installed apps. \(error)")
            }
            #endif
        
            let installedAppBundleIDs = await dbBackgroundContext.perform {
                Set(InstalledApp.all(in: dbBackgroundContext).map { $0.bundleIdentifier })
            }
            
            CacheAppOperation.pruneUnusedCaches(activeBundleIDs: installedAppBundleIDs) { bundleID in
                self.isActivelyManagingApp(withBundleID: bundleID)
            }
        }.value
    }
    


    func signIn(presentingViewController: UIViewController?,
                skipDeviceRegistration: Bool = false,
                skipCertificateProvisioning: Bool = false,
                completionHandler: @escaping (Result<(ALTTeam, ALTCertificate?, ALTAppleAPISession), Error>) -> Void)
    {
        Task.detached {
            do {
                let result = try await AuthManager.shared.signIn(
                    presentingViewController: presentingViewController,
                    skipDeviceRegistration: skipDeviceRegistration,
                    skipCertificateProvisioning: skipCertificateProvisioning
                )
                completionHandler(.success((result.team, result.certificate, result.session)))
            } catch {
                completionHandler(.failure(error))
            }
        }
    }
    
    func deactivateApps(for appBundle: ALTApplication, presentingViewController: UIViewController?, completion: @escaping (Result<Void, Error>) -> Void)
    {
        guard !UserDefaults.standard.isAppLimitDisabled, let activeAppsLimit = UserDefaults.standard.activeAppsLimit else { return completion(.success(())) }
        
        DispatchQueue.main.async {
            // Only apps signed with a free developer certificate count toward the 3-app free account limit.
            // Apps signed with a paid certificate coexist independently and must not be counted here.
            let activeApps = InstalledApp.fetchActiveApps(in: DatabaseManager.shared.viewContext)
                .filter { $0.bundleIdentifier != appBundle.bundleIdentifier }   // Don't count app towards total if it matches activating app
                .filter { ($0.team?.type ?? .unknown) == .free }                // Only free-cert-signed apps count against the free limit
                .sorted { ($0.name, $0.refreshedDate) < ($1.name, $1.refreshedDate) }
            
            var title: String = NSLocalizedString("Cannot Activate More than 3 Apps", comment: "")
            let message: String
            
            if UserDefaults.standard.activeAppLimitIncludesExtensions
            {
                if appBundle.appExtensions.isEmpty
                {
                    message = NSLocalizedString("Non-developer Apple IDs are limited to 3 active apps and app extensions. Please choose an app to deactivate.", comment: "")
                }
                else
                {
                    title = NSLocalizedString("Cannot Activate More than 3 Apps and App Extensions", comment: "")
                    
                    let appExtensionText = appBundle.appExtensions.count == 1 ? NSLocalizedString("app extension", comment: "") : NSLocalizedString("app extensions", comment: "")
                    message = String(format: NSLocalizedString("Non-developer Apple IDs are limited to 3 active apps and app extensions, and \"%@\" contains %@ %@. Please choose an app to deactivate.", comment: ""), appBundle.name, NSNumber(value: appBundle.appExtensions.count), appExtensionText)
                }
            }
            else
            {
                message = NSLocalizedString("Non-developer Apple IDs are limited to 3 active apps. Please choose an app to deactivate.", comment: "")
            }
            
            let activeAppsCount = activeApps.map { $0.requiredActiveSlots }.reduce(0, +)
                    
            let availableActiveApps = max(activeAppsLimit - activeAppsCount, 0)
            let requiredActiveSlots = UserDefaults.standard.activeAppLimitIncludesExtensions ? (1 + appBundle.appExtensions.count) : 1
            guard requiredActiveSlots > availableActiveApps else { return completion(.success(())) }

            guard let presentingViewController else {
                let failureReason = String(format: NSLocalizedString("SideStore needs to deactivate another app before installing %@.", comment: ""), appBundle.name)
                return completion(.failure(OperationError.forbidden(failureReason: failureReason)))
            }
            
            let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: UIAlertAction.cancel.title, style: UIAlertAction.cancel.style) { (action) in
                completion(.failure(OperationError.cancelled))
            })
            
            for activeApp in activeApps where activeApp.bundleIdentifier != StoreApp.altstoreAppID
            {
                alertController.addAction(UIAlertAction(title: activeApp.name, style: .default) { (action) in
                    activeApp.isActive = false
                                    
                    self.deactivate(activeApp, presentingViewController: presentingViewController) { (result) in
                        switch result
                        {
                        case .failure(let error):
                            activeApp.managedObjectContext?.perform {
                                activeApp.isActive = true
                                completion(.failure(error))
                            }
                            
                        case .success:
                            self.deactivateApps(for: appBundle, presentingViewController: presentingViewController, completion: completion)
                        }
                    }
                })
            }
            
            presentingViewController.present(alertController, animated: true, completion: nil)
        }
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
            }catch {
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
        async let fetchedSource = try await self.fetchSource(sourceURL: sourceURL, managedObjectContext: context) // Fetch source async while showing alert.

        let title = String(format: NSLocalizedString("Would you like to add the source “%@”?", comment: ""), sourceName)
        let action = await UIAlertAction(title: NSLocalizedString("Add Source", comment: ""), style: .default)
        try await presentingViewController.presentConfirmationAlert(title: title, message: message ?? "", primaryAction: action)

        // Wait for fetch to finish before saving context to make
        // sure there isn't already a source with this identifier.
        let sourceExists = try await fetchedSource.isAdded()
        
        // This is just a sanity check, so pass nil for existingSource to keep code simple.
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
            guard let source = Source.first(satisfying: predicate, in: context) else { return } // Doesn't exist == success.
            
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
                            return (data.objectID, .success(fetchedSource.objectID)) // objectID is thread-safe
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
                var errors = [Source: Error]()
                
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
                let managedObjectContext = DatabaseManager.shared.persistentContainer.newBackgroundContext()
                let context = self.makeAuthenticatedContext(dbBackgroundContext: managedObjectContext)
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
                // Check if the result is failure and rethrow
                if case .failure(let error) = result {
                    throw error  // Rethrow the error
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
                 context: StandaloneOperationContext? = nil,
                 completionHandler: @escaping (Result<InstalledApp, Error>) -> Void) -> RefreshGroup
    {
        debugLog("[AppManager] install() called for target: \(target)")
        let pipelineHandler = self.makePipelineHandler(presentingViewController: presentingViewController)
        let baseContext = self.makeAuthenticatedContext(presentingViewController: presentingViewController, baseContext: context)
        let group = RefreshGroup(context: baseContext)
        group.completionHandler = { results in
            if let result = results.values.first {
                completionHandler(result)
            } else {
                completionHandler(.failure(OperationError.unknown()))
            }
        }

        group.activeTask = Task.detached {
            do {
                let resolvedApp: AppProtocol

                switch target {
                case .app(let app):
                    var targetApp = app
                    if let storeApp = app.storeApp,
                       let source = storeApp.source,
                       try await !source.isAdded()
                    {
                        guard let presentingViewController else { throw OperationError.sourceNotAdded(source) }
                        let message = String(format: NSLocalizedString("You must add this source before installing apps from it.\n\n“%@” will begin downloading once it has been added.", comment: ""), app.name)
                        try await AppManager.shared.add(source, message: message, presentingViewController: presentingViewController)
                        
                        let appBundleID = app.bundleIdentifier
                        let sourceID = source.identifier
                        if let fetchedStoreApp = try await DatabaseManager.shared.viewContext.performAsync({
                            let fetchRequest = StoreApp.fetchRequest()
                            fetchRequest.predicate = NSPredicate(format: "%K == %@ AND %K == %@",
                                                                 #keyPath(StoreApp.bundleIdentifier), appBundleID,
                                                                 #keyPath(StoreApp.sourceIdentifier), sourceID)
                            return try DatabaseManager.shared.viewContext.fetch(fetchRequest).first
                        }) {
                            targetApp = fetchedStoreApp
                        }
                        
                        await MainActor.run {
                            NotificationCenter.default.post(name: AppManager.willInstallAppFromNewSourceNotification, object: app)
                        }
                    }
                    resolvedApp = targetApp

                case .url(let url):
                    guard let packageType = PackageType(url: url) else {
                        throw OperationError.invalidApp(reason: "Unsupported package format '.\(url.pathExtension)'. Expected '.ipa' or '.app'.")
                    }

                    var localURL = url
                    if !url.isFileURL {
                        let temporaryDirectory = FileManager.default.uniqueTemporaryURL()
                        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
                        localURL = try await withCheckedThrowingContinuation { continuation in
                            let downloadTask = URLSession.shared.downloadTask(with: url) { (fileURL, response, error) in
                                do {
                                    let (fileURL, _) = try Result((fileURL, response), error).get()
                                    let dest = temporaryDirectory.appendingPathComponent(url.lastPathComponent)
                                    try FileManager.default.moveItem(at: fileURL, to: dest)
                                    continuation.resume(returning: dest)
                                } catch {
                                    continuation.resume(throwing: error)
                                }
                            }
                            downloadTask.resume()
                        }
                    }

                    let (bundleIdentifier, appName) = try Self.readAppMetadata(from: localURL, packageType: packageType)
                    resolvedApp = AnyApp(name: appName, bundleIdentifier: bundleIdentifier, url: localURL, storeApp: nil)
                }

                let subGroup = self.pipelineRunner.performSingleOperation(
                    .install(resolvedApp),
                    handler: pipelineHandler,
                    context: baseContext,
                    completionHandler: completionHandler
                )
                group.progress.addChild(subGroup.progress, withPendingUnitCount: 100)
            } catch {
                let elapsed = CFAbsoluteTimeGetCurrent() - group.context.operationStartTime
                let status = Task.isCancelled ? "CANCELLED" : "FAILED"
                let targetId: String
                switch target {
                case .url(let url): targetId = url.lastPathComponent
                case .app(let app): targetId = app.bundleIdentifier
                }
                logOperationSummary(
                    operation: "install",
                    target: targetId,
                    status: status,
                    elapsed: elapsed,
                    error: error
                )
                completionHandler(.failure(error))
            }
        }

        return group
    }

    private static func readAppMetadata(from url: URL, packageType: PackageType) throws -> (bundleIdentifier: String, name: String) {
        switch packageType {
        case .ipa:
            let reader = try Archive.Reader.open(at: url)
            try reader.goToFirstFile()
            var plistData: Data?
            repeat {
                let filename = try reader.currentFilename()
                let components = filename.components(separatedBy: "/")
                if components.count == 3 && components[0] == "Payload" && components[1].hasSuffix(".app") && components[2] == "Info.plist" {
                    plistData = try reader.readCurrentFile()
                    break
                }
            } while reader.goToNextFile()

            guard let data = plistData,
                  let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let bundleIdentifier = (plist["CFBundleIdentifier"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !bundleIdentifier.isEmpty else {
                throw OperationError.invalidApp(reason: "Archive missing valid Payload/*.app/Info.plist")
            }
            let appName = (plist["CFBundleDisplayName"] as? String) ?? (plist["CFBundleName"] as? String) ?? url.deletingPathExtension().lastPathComponent
            return (bundleIdentifier, appName)

        case .app:
            let plistURL = url.appendingPathComponent("Info.plist")
            let data = try Data(contentsOf: plistURL)
            guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let bundleIdentifier = (plist["CFBundleIdentifier"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !bundleIdentifier.isEmpty else {
                throw OperationError.invalidApp(reason: "Invalid Info.plist in app directory")
            }
            let appName = (plist["CFBundleDisplayName"] as? String) ?? (plist["CFBundleName"] as? String) ?? url.lastPathComponent
            return (bundleIdentifier, appName)
        }
    }
    
    @discardableResult
    func update(_ installedApp: InstalledApp,
                to version: AppVersion? = nil,
                presentingViewController: UIViewController?,
                completionHandler: @escaping (Result<InstalledApp, Error>) -> Void) -> Progress
    {
        debugLog("[AppManager] update() called for app: \(installedApp.bundleIdentifier)")
        guard let appVersion = version ?? installedApp.storeApp?.latestSupportedVersion else {
            completionHandler(.failure(OperationError.appNotFound(name: installedApp.name)))
            return Progress.discreteProgress(totalUnitCount: 1)
        }
        guard appVersion as AnyObject !== installedApp else {
            completionHandler(.failure(OperationError.invalidParameters("Make sure we never accidentally 'update' to already installed app.")))
            return Progress.discreteProgress(totalUnitCount: 1)
        }
        let pipelineHandler = self.makePipelineHandler(presentingViewController: presentingViewController)
        let context = self.makeAuthenticatedContext(presentingViewController: presentingViewController)
        let group = self.pipelineRunner.performSingleOperation(
            .update(appVersion, customBundleIdentifier: installedApp.customBundleIdentifier), 
            handler: pipelineHandler, 
            context: context, 
            completionHandler: completionHandler
        )
        return group.progress
    }
    
    @discardableResult
    func refresh(_ installedApps: [InstalledApp], presentingViewController: UIViewController?, group: RefreshGroup? = nil) -> RefreshGroup
    {
        debugLog("[AppManager] refresh() called for apps: \(installedApps.map { $0.bundleIdentifier })")
        let pipelineHandler = self.makePipelineHandler(presentingViewController: presentingViewController)
        
        let actualGroup: RefreshGroup
        if let group = group {
            actualGroup = group
        } else {
            let context = self.makeAuthenticatedContext(presentingViewController: presentingViewController)
            actualGroup = RefreshGroup(context: context)
        }
        
        actualGroup.activeTask = Task.detached {
            do {
                try await self.pipelineRunner.perform(installedApps.map { .refresh($0) }, handler: pipelineHandler, group: actualGroup)
            } catch {
                actualGroup.context.error = error
                let results = Dictionary(uniqueKeysWithValues: installedApps.map { ($0.bundleIdentifier, Result<InstalledApp, Error>.failure(error)) })
                actualGroup.completionHandler?(results)
            }
        }
        
        return actualGroup
    }
    
    func activate(_ installedApp: InstalledApp, presentingViewController: UIViewController?, completionHandler: @escaping (Result<InstalledApp, Error>) -> Void)
    {
        debugLog("[AppManager] activate() called for app: \(installedApp.bundleIdentifier)")
        let pipelineHandler = self.makePipelineHandler(presentingViewController: presentingViewController)
        let context = self.makeAuthenticatedContext(presentingViewController: presentingViewController)
        self.pipelineRunner.performSingleOperation(.activate(installedApp), handler: pipelineHandler, context: context, completionHandler: completionHandler)
    }
    
    func deactivate(_ installedApp: InstalledApp, presentingViewController: UIViewController?, completionHandler: @escaping (Result<InstalledApp, Error>) -> Void)
    {
        debugLog("[AppManager] deactivate() called for app: \(installedApp.bundleIdentifier)")
        let pipelineHandler = self.makePipelineHandler(presentingViewController: presentingViewController)
        let context = self.makeAuthenticatedContext(presentingViewController: presentingViewController)
        self.pipelineRunner.performSingleOperation(.deactivate(installedApp), handler: pipelineHandler, context: context, completionHandler: completionHandler)
    }
    
    func deleteApp(_ installedApp: InstalledApp, presentingViewController: UIViewController?, completionHandler: @escaping (Result<InstalledApp, Error>) -> Void)
    {
        debugLog("[AppManager] deleteApp() called for app: \(installedApp.bundleIdentifier)")
        let pipelineHandler = self.makePipelineHandler(presentingViewController: presentingViewController)
        let context = self.makeAuthenticatedContext(presentingViewController: presentingViewController)
        self.pipelineRunner.performSingleOperation(.deleteApp(installedApp), handler: pipelineHandler, context: context, completionHandler: completionHandler)
    }
    
    @discardableResult
    func resign(_ installedApp: InstalledApp,
                alternateIconMode: AlternateIconMode = .preserve,
                presentingViewController: UIViewController?,
                completionHandler: @escaping (Result<InstalledApp, Error>) -> Void) -> RefreshGroup
    {
        debugLog("[AppManager] resign() called for app: \(installedApp.bundleIdentifier)")
        let pipelineHandler = self.makePipelineHandler(presentingViewController: presentingViewController)
        let context = self.makeAuthenticatedContext(presentingViewController: presentingViewController)
        return self.pipelineRunner.performSingleOperation(.resign(installedApp, alternateIconMode: alternateIconMode), handler: pipelineHandler, context: context, completionHandler: completionHandler)
    }
    
    func backup(_ installedApp: InstalledApp, presentingViewController: UIViewController?, completionHandler: @escaping (Result<InstalledApp, Error>) -> Void)
    {
        debugLog("[AppManager] backup() called for app: \(installedApp.bundleIdentifier)")
        let pipelineHandler = self.makePipelineHandler(presentingViewController: presentingViewController)
        let context = self.makeAuthenticatedContext(presentingViewController: presentingViewController)
        self.pipelineRunner.performSingleOperation(.backup(installedApp), handler: pipelineHandler, context: context, completionHandler: completionHandler)
    }
    
    func restore(_ installedApp: InstalledApp, presentingViewController: UIViewController?, completionHandler: @escaping (Result<InstalledApp, Error>) -> Void)
    {
        debugLog("[AppManager] restore() called for app: \(installedApp.bundleIdentifier)")
        let pipelineHandler = self.makePipelineHandler(presentingViewController: presentingViewController)
        let context = self.makeAuthenticatedContext(presentingViewController: presentingViewController)
        self.pipelineRunner.performSingleOperation(.restore(installedApp), handler: pipelineHandler, context: context, completionHandler: completionHandler)
    }
    
    func removeApp(_ installedApp: InstalledApp, presentingViewController: UIViewController? = nil, completionHandler: @escaping (Result<Void, Error>) -> Void)
    {
        debugLog("[AppManager] removeApp() called for app: \(installedApp.bundleIdentifier)")
        let pipelineHandler = self.makePipelineHandler(presentingViewController: presentingViewController)
        let context = self.makeAuthenticatedContext(presentingViewController: presentingViewController)
        self.pipelineRunner.performVoidOperation(.removeApp(installedApp), handler: pipelineHandler, context: context, completionHandler: completionHandler)
    }
    
    func removeDeactivatedApp(_ installedApp: InstalledApp, completionHandler: @escaping (Result<Void, Error>) -> Void)
    {
        self.removeApp(installedApp, completionHandler: completionHandler)
    }
    
    func enableJIT(for installedApp: InstalledApp, completionHandler: @escaping (Result<Void, Error>) -> Void)
    {
        Task.detached {
            debugLog("[AppManager] enableJIT() called for app: \(installedApp.bundleIdentifier)")
            let dbBackgroundContext = DatabaseManager.shared.persistentContainer.newBackgroundContext()
            let context = StandaloneOperationContext(steps: .enableJIT, dbBackgroundContext: dbBackgroundContext)
            do {
                let enableJITOperation = try EnableJITOperation(installedApp: installedApp, context: context)
                do {
                    _ = try await enableJITOperation.execute()
                    completionHandler(.success(()))
                } catch {
                    var appName: String = ""
                    installedApp.managedObjectContext?.performAndWait {
                        appName = installedApp.name
                    }
                    if appName.isEmpty { appName = installedApp.name }
                    let localizedTitle = String(format: NSLocalizedString("Failed to Enable JIT for %@", comment: ""), appName)
                    let mappedError = (error as NSError).withLocalizedTitle(localizedTitle)
                    self.log(error, operation: .enableJIT, app: installedApp)
                    completionHandler(.failure(mappedError))
                }
            } catch {
                completionHandler(.failure(error))
            }
        }
    }

    @discardableResult
    func backgroundRefresh(_ installedApps: [InstalledApp],
                           presentsNotifications: Bool = false,
                           completionHandler: @escaping (Result<[String: Result<InstalledApp, Error>], Error>) -> Void) throws -> BackgroundRefreshAppsOperation
    {
        let dbBackgroundContext = DatabaseManager.shared.persistentContainer.newBackgroundContext()
        let context = StandaloneOperationContext(steps: .backgroundRefreshApps, dbBackgroundContext: dbBackgroundContext)
        let backgroundRefreshAppsOperation = try BackgroundRefreshAppsOperation(installedApps: installedApps, context: context)
        Task.detached {
            do {
                backgroundRefreshAppsOperation.presentsFinishedNotification = presentsNotifications
                
                let result = try await backgroundRefreshAppsOperation.execute()
                completionHandler(.success(result))
            } catch {
                completionHandler(.failure(error))
            }
        }
        return backgroundRefreshAppsOperation
    }
}

enum PackageType: String, CaseIterable, Sendable {
    case ipa
    case app

    init?(url: URL) {
        self.init(rawValue: url.pathExtension.lowercased())
    }
}

extension AppManager {
    enum InstallTarget: @unchecked Sendable, CustomStringConvertible {
        case url(URL)
        case app(AppProtocol)

        var description: String {
            switch self {
            case .url(let url): return "url(\(url.lastPathComponent))"
            case .app(let app): return "app(\(app.bundleIdentifier))"
            }
        }
    }
}
typealias InstallTarget = AppManager.InstallTarget

// MARK: - PipelineRunner Protocol Conformances
extension AppManager: PipelineProgress, PipelineExecutionContext, PipelineErrorLogger {
    
    private func makePipelineHandler(presentingViewController: UIViewController?) -> PipelineExecutionHandler {
        return PipelineHandler(
            isResignActive: presentingViewController is ResignAltStoreViewController,
            presenterProvider: { [weak presentingViewController] in
                presentingViewController?.presentedViewController ?? presentingViewController
            }
        )
    }

    private func makeAuthenticatedContext(presentingViewController: UIViewController? = nil,
                                          baseContext: StandaloneOperationContext? = nil,
                                          dbBackgroundContext: NSManagedObjectContext? = nil) -> StandaloneOperationContext
    {
        if let baseContext = baseContext { return baseContext }
        let backgroundContext = dbBackgroundContext ?? DatabaseManager.shared.persistentContainer.newBackgroundContext()
        return StandaloneOperationContext(steps: .signIn, dbBackgroundContext: backgroundContext)
    }
    

    func installationProgress(for app: AppProtocol) -> Progress?
    {
        return self.progressLock.withLock {
            self.installationProgress[app.bundleIdentifier]
        }
    }
    
    func refreshProgress(for app: AppProtocol) -> Progress?
    {
        return self.progressLock.withLock {
            let bundleID = app.bundleIdentifier
            
            guard let progress = self.refreshProgress[bundleID] ?? self.installationProgress[bundleID] else {
                return nil
            }
            
            guard !progress.isCancelled else {
                self.refreshProgress[bundleID] = nil
                self.installationProgress[bundleID] = nil
                return nil
            }
            
            return progress
        }
    }
    
    func isActivelyManagingApp(withBundleID bundleID: String) -> Bool
    {
        let isActivelyManaging = self.installationProgress.keys.contains(bundleID) || self.refreshProgress.keys.contains(bundleID)
        return isActivelyManaging
    }
    
    var isActivelyManagingAnyApp: Bool
    {
        return self.progressLock.withLock {
            !self.installationProgress.isEmpty || !self.refreshProgress.isEmpty
        }
    }
    
    func progress(for operation: AppOperation) -> Progress?
    {
        // Access outside critical section to avoid deadlock due to `bundleIdentifier` potentially calling performAndWait() on main thread.
        let bundleID = operation.bundleIdentifier
        
        return self.progressLock.withLock {
            switch operation
            {
            case .install, .update: 
                return self.installationProgress[bundleID]
            case .refresh, .activate, .deactivate, .deleteApp, .backup, .restore, .resign, .removeApp, .removeDeactivatedApp: 
                return self.refreshProgress[bundleID]
            }
        }
    }
    
    func set(_ progress: Progress?, for operation: AppOperation)
    {
        // Access outside critical section to avoid deadlock due to `bundleIdentifier` potentially calling performAndWait() on main thread.
        let bundleID = operation.bundleIdentifier
        let operationName = String(describing: operation.loggedErrorOperation)

        self.progressLock.withLock {
            switch operation
            {
            case .install, .update: 
                self.installationProgress[bundleID] = progress
            case .refresh, .activate, .deactivate, .deleteApp, .backup, .restore, .resign, .removeApp, .removeDeactivatedApp: 
                self.refreshProgress[bundleID] = progress
            }
            debugLog("[AppManager] setProgress: \(progress.map { "\($0)" } ?? "nil") for operation: .\(operationName), totalUnitCount: \(progress?.totalUnitCount ?? 0)")
        }
    }
    
    func getMappedError(for operation: AppOperation, error: Error) -> Error {
        var appName: String!
        if let app = operation.app as? (NSManagedObject & AppProtocol) {
            if let context = app.managedObjectContext {
                context.performAndWait {
                    appName = app.name
                }
            } else {
                appName = NSLocalizedString("Unknown App", comment: "")
            }
        } else {
            appName = operation.app.name
        }

        let localizedTitle: String
        switch operation
        {
            case .install:    localizedTitle = String(format: NSLocalizedString("Failed to Install %@",        comment: ""), appName)
            case .refresh:    localizedTitle = String(format: NSLocalizedString("Failed to Refresh %@",        comment: ""), appName)
            case .update:     localizedTitle = String(format: NSLocalizedString("Failed to Update %@",         comment: ""), appName)
            case .activate:   localizedTitle = String(format: NSLocalizedString("Failed to Activate %@",       comment: ""), appName)
            case .deactivate: localizedTitle = String(format: NSLocalizedString("Failed to Deactivate %@",     comment: ""), appName)
            case .deleteApp:  localizedTitle = String(format: NSLocalizedString("Failed to Deactivate %@",     comment: ""), appName)
            case .backup:     localizedTitle = String(format: NSLocalizedString("Failed to Backup %@",         comment: ""), appName)
            case .restore:    localizedTitle = String(format: NSLocalizedString("Failed to Restore %@ Backup", comment: ""), appName)
            case .resign:     localizedTitle = String(format: NSLocalizedString("Failed to Resign %@",         comment: ""), appName)
            case .removeApp, .removeDeactivatedApp: localizedTitle = String(format: NSLocalizedString("Failed to Remove %@", comment: ""), appName)
        }
        
        let nsError = error as NSError
        let mappedError = nsError.withLocalizedTitle(localizedTitle)
        return mappedError
    }
    
    func log(_ error: Error, operation: LoggedError.Operation, app: AppProtocol)
    {
        switch error
        {
            case is CancellationError: return // Don't log CancellationErrors
            case let nsError as NSError where nsError.domain == CancellationError()._domain: return
            default: break
        }

        // Sanitize NSError on same thread before performing background task.
        let sanitizedError = (error as NSError).sanitizedForSerialization()

        DatabaseManager.shared.persistentContainer.performBackgroundTask { context in
            var app = app
            if let managedApp = app as? NSManagedObject, let tempApp = context.object(with: managedApp.objectID) as? AppProtocol
            {
                app = tempApp
            }

            do
            {
                let loggedError = LoggedError(error: sanitizedError, app: app, operation: operation, context: context)
                debugLog("""
                [AppManager] log() error: \(sanitizedError)
                  • app            : \(app.bundleIdentifier)
                  • operation      : \(operation)
                  • loggedErrorID  : \(loggedError.objectID)
                """)
                if context.hasChanges {
                    try context.save()
                }
            }
            catch let saveError
            {
                debugLog("[SideStore] Failed to log error \(sanitizedError.domain) code \(sanitizedError.code) for \(app.bundleIdentifier): \(saveError)")
            }
        }
    }

}


