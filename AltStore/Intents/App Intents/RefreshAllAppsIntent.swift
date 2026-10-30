//
//  RefreshAllAppsIntent.swift
//  AltStore
//
//  Created by Riley Testut on 8/18/23.
//  Copyright © 2023 Riley Testut. All rights reserved.
//

import AppIntents

// Shouldn't conform types we don't own to protocols we don't own, so make custom
// NSError subclass that conforms to CustomLocalizedStringResourceConvertible instead.
//
// Would prefer to just conform ALTLocalizedError to CustomLocalizedStringResourceConvertible,
// but that can't be done without raising minimum version for ALTLocalizedError to iOS 16 :/
@available(iOS 16, tvOS 16, *)
class IntentError: NSError, CustomLocalizedStringResourceConvertible, @unchecked Sendable
{
    var localizedStringResource: LocalizedStringResource {
        return "\(self.localizedDescription)"
    }
    
    init(_ error: some Error)
    {
        let serializedError = (error as NSError).sanitizedForSerialization()
        super.init(domain: serializedError.domain, code: serializedError.code, userInfo: serializedError.userInfo)
    }
    
    required init?(coder: NSCoder)
    {
        super.init(coder: coder)
    }
}

@available(iOS 17.0, tvOS 17.0, *)
struct InstallIPAIntent: AppIntent, ProgressReportingIntent
{
    static var title: LocalizedStringResource = "Install IPA"
    static var description = IntentDescription("Installs an IPA file with SideStore.")
    static var openAppWhenRun = false

    @Parameter(title: "IPA File")
    var ipaFile: IntentFile

    static var parameterSummary: some ParameterSummary {
        Summary("Install \(\.$ipaFile)")
    }

    init()
    {
        self.progress.completedUnitCount = 0
        self.progress.totalUnitCount = 1
    }

    func perform() async throws -> some IntentResult
    {
        do
        {
            try await DatabaseManager.shared.start()

            let temporaryDirectory = FileManager.default.uniqueTemporaryURL()
            defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

            try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

            let ipaURL = temporaryDirectory.appendingPathComponent("App.ipa")
            try self.ipaFile.data.write(to: ipaURL)

            let intentProgress = self.progress
            _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<InstalledApp, Error>) in
                let group = AppManager.shared.install(.url(ipaURL)) { result in
                    continuation.resume(with: result)
                }
                intentProgress.addChild(group.progress, withPendingUnitCount: 1)
            }

            return .result()
        }
        catch
        {
            let intentError = IntentError(error)
            throw intentError
        }
    }
}


@available(iOS 17.0, tvOS 17.0, *)
extension RefreshAllAppsIntent
{
    private actor OperationActor
    {
        private(set) var operation: BackgroundRefreshAppsOperation?
        
        func set(_ operation: BackgroundRefreshAppsOperation?)
        {
            self.operation = operation
        }
    }
}

@available(iOS 17.0, tvOS 17.0, *)
struct RefreshAllAppsIntent: AppIntent, CustomIntentMigratedAppIntent, PredictableIntent, ProgressReportingIntent, ForegroundContinuableIntent
{
    static let intentClassName = "RefreshAllIntent"
    
    static var title: LocalizedStringResource = "Refresh All Apps"
    static var description = IntentDescription("Refreshes your sideloaded apps to prevent them from expiring.")
    
    static var parameterSummary: some ParameterSummary {
        Summary("Refresh All Apps")
    }
    
    static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction {
            DisplayRepresentation(
                title: "Refresh All Apps",
                subtitle: ""
            )
        }
    }
    
    let presentsNotifications: Bool
    
    private let operationActor = OperationActor()
    
    init(presentsNotifications: Bool)
    {
        self.presentsNotifications = presentsNotifications
        
        self.progress.completedUnitCount = 0
        self.progress.totalUnitCount = 1
    }
    
    init()
    {
        self.init(presentsNotifications: false)
    }
    
    func perform() async throws -> some IntentResult & ProvidesDialog
    {
        do
        {
            // Request foreground execution at ~27 seconds to gracefully handle timeout.
            let deadline: ContinuousClock.Instant = .now + .seconds(27)
            
            try await withThrowingTaskGroup(of: Void.self) { taskGroup in
                taskGroup.addTask {
                    try await self.refreshAllApps()
                }
                
                taskGroup.addTask {
                    try await Task.sleep(until: deadline)
                    throw OperationError.timedOut
                }
                
                do
                {
                    for try await _ in taskGroup.prefix(1)
                    {
                        // We only care about the first child task to complete.
                        taskGroup.cancelAll()
                        break
                    }
                }
                catch OperationError.timedOut
                {
                    // We took too long to finish and return the final result,
                    // so we'll now present a normal notification when finished.
                    let operation = await self.operationActor.operation
                    operation?.presentsFinishedNotification = true
                    
                    try await self.requestToContinueInForeground()
                }
            }
            
            return .result(dialog: "All apps have been refreshed.")
        }
        catch
        {
            // Print-only: log the failure instead of throwing, so a refresh
            // error doesn't fail the intent and stop the rest of the Shortcuts
            // script. Needs proper testing.
            debugLog("[RefreshAllAppsIntent] Refresh All Apps failed: \(error)")
            return .result(dialog: "All apps have been refreshed.")
        }
    }
}

@available(iOS 17.0, tvOS 17.0, *)
private extension RefreshAllAppsIntent
{
    func refreshAllApps() async throws
    {
        try await DatabaseManager.shared.start()
        
        let context = DatabaseManager.shared.persistentContainer.newBackgroundContext()
        let installedApps = await context.perform { InstalledApp.fetchAppsForRefreshingAll(in: context) }
        
        try await withCheckedThrowingContinuation { continuation in
            let operation = try? AppManager.shared.backgroundRefresh(installedApps, presentsNotifications: self.presentsNotifications) { (result) in
                do
                {
                    let results = try result.get()
                    
                    for (_, result) in results
                    {
                        guard case let .failure(error) = result else { continue }
                        throw error
                    }
                    
                    continuation.resume()
                }
                catch OperationError.noInstalledApps
                {
                    continuation.resume()
                }
                catch
                {
                    continuation.resume(throwing: error)
                }
            }
            
            guard let operation else {
                debugLog("[RefreshAllAppsIntent] backgroundRefresh instance is nil")
                return 
            }
            
            operation.ignoresServerNotFoundError = false
            
            self.progress.addChild(operation.progress, withPendingUnitCount: 1)
            
            Task {
                await self.operationActor.set(operation)
            }
        }
    }
}

// MARK: - Refresh App (single app)

// App picker for RefreshAppIntent. Mirrors AltWidget's InstalledAppEntity, but
// resolves against the app's own database instead of the widget snapshot.
@available(iOS 17.0, tvOS 17.0, *)
struct InstalledAppEntity: AppEntity
{
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Installed App"
    static var defaultQuery = InstalledAppQuery()
    
    var id: String // bundle identifier
    var name: String
    
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

@available(iOS 17.0, tvOS 17.0, *)
struct InstalledAppQuery: EntityQuery
{
    func entities(for identifiers: [String]) async throws -> [InstalledAppEntity]
    {
        debugLog("[InstalledAppQuery] Fetching entities for identifiers: \(identifiers)")
        let installedApps = try await Self.fetchRefreshableApps()
        return installedApps
            .filter { identifiers.contains($0.bundleIdentifier) }
            .map { InstalledAppEntity(id: $0.bundleIdentifier, name: $0.name) }
    }
    
    func suggestedEntities() async throws -> [InstalledAppEntity]
    {
        let installedApps = try await Self.fetchRefreshableApps()
        debugLog("[InstalledAppQuery] Suggested entities requested (\(installedApps.count) app(s) returned)")
        return installedApps
            .map { InstalledAppEntity(id: $0.bundleIdentifier, name: $0.name) }
            .sorted { $0.name < $1.name }
    }
    
    private static func fetchRefreshableApps() async throws -> [InstalledApp]
    {
        try await DatabaseManager.shared.start()
        let context = DatabaseManager.shared.persistentContainer.newBackgroundContext()
        return await context.perform { InstalledApp.fetchAppsForRefreshingAll(in: context) }
    }
}

@available(iOS 17.0, tvOS 17.0, *)
extension RefreshAppIntent
{
    private actor OperationActor
    {
        private(set) var operation: BackgroundRefreshAppsOperation?
        
        func set(_ operation: BackgroundRefreshAppsOperation?)
        {
            self.operation = operation
        }
    }
}

@available(iOS 17.0, tvOS 17.0, *)
struct RefreshAppIntent: AppIntent, PredictableIntent, ProgressReportingIntent, ForegroundContinuableIntent
{
    static var title: LocalizedStringResource = "Refresh App"
    static var description = IntentDescription("Refreshes the selected sideloaded app to prevent it from expiring.")
    
    @Parameter(title: "App")
    var app: InstalledAppEntity?
    
    static var parameterSummary: some ParameterSummary {
        Summary("Refresh \(\.$app)")
    }
    
    static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction {
            DisplayRepresentation(
                title: "Refresh App",
                subtitle: ""
            )
        }
    }
    
    private let operationActor = OperationActor()
    
    init() {}
    
    func perform() async throws -> some IntentResult & ProvidesDialog
    {
        do
        {
            // Request foreground execution at ~27 seconds to gracefully handle timeout.
            let deadline: ContinuousClock.Instant = .now + .seconds(27)
            
            try await withThrowingTaskGroup(of: Void.self) { taskGroup in
                taskGroup.addTask {
                    try await self.refreshApp()
                }
                
                taskGroup.addTask {
                    try await Task.sleep(until: deadline)
                    throw OperationError.timedOut
                }
                
                do
                {
                    for try await _ in taskGroup.prefix(1)
                    {
                        // We only care about the first child task to complete.
                        taskGroup.cancelAll()
                        break
                    }
                }
                catch OperationError.timedOut
                {
                    // We took too long to finish and return the final result,
                    // so we'll now present a normal notification when finished.
                    let operation = await self.operationActor.operation
                    operation?.presentsFinishedNotification = true
                    
                    try await self.requestToContinueInForeground()
                }
            }
            
            return .result(dialog: "Refreshed \(self.app?.name ?? "app").")
        }
        catch
        {
            // Print-only: log the failure instead of failing the Shortcuts run.
            debugLog("[RefreshAppIntent] Refresh App failed: \(error)")
            return .result(dialog: "Refreshed \(self.app?.name ?? "app").")
        }
    }
}

@available(iOS 17.0, tvOS 17.0, *)
private extension RefreshAppIntent
{
    func refreshApp() async throws
    {
        guard let app = self.app else {
            debugLog("[RefreshAppIntent] no app selected")
            return
        }
        
        try await DatabaseManager.shared.start()
        
        let context = DatabaseManager.shared.persistentContainer.newBackgroundContext()
        let installedApps = await context.perform { InstalledApp.fetchAppsForRefreshingAll(in: context) }
        
        guard let installedApp = installedApps.first(where: { $0.bundleIdentifier == app.id }) else {
            debugLog("[RefreshAppIntent] app '\(app.name)' (\(app.id)) not found or not refreshable")
            return
        }
        
        try await withCheckedThrowingContinuation { continuation in
            let operation = try? AppManager.shared.backgroundRefresh([installedApp], presentsNotifications: true) { (result) in
                do
                {
                    let results = try result.get()
                    
                    for (_, result) in results
                    {
                        guard case let .failure(error) = result else { continue }
                        debugLog("[RefreshAppIntent] failed to refresh app: \(error)")
                    }
                    
                    continuation.resume()
                }
                catch OperationError.noInstalledApps
                {
                    continuation.resume()
                }
                catch
                {
                    debugLog("[RefreshAppIntent] backgroundRefresh failed: \(error)")
                    continuation.resume()
                }
            }
            
            guard let operation else {
                debugLog("[RefreshAppIntent] backgroundRefresh instance is nil")
                continuation.resume()
                return
            }
            
            operation.ignoresServerNotFoundError = false
            
            self.progress.addChild(operation.progress, withPendingUnitCount: 1)
            
            Task {
                await self.operationActor.set(operation)
            }
        }
    }
}
