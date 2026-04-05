//
//  ViewAppIntent.swift
//  AltWidgetExtension
//
//  Replaces the legacy SiriKit-based ViewAppIntent (from ViewApp.intentdefinition)
//  with a modern AppIntents-based intent, required for iOS 17+ widget compatibility.
//  IntentConfiguration (old API) does not support containerBackground on iOS 17+,
//  causing the "Please adopt containerBackground" error.
//

import AppIntents
import WidgetKit
import AltStoreCore

// Mirrors the App type from the old intentdefinition — just the bundle identifier.
@available(iOS 16, *)
struct AppEntity: AppEntity
{
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "App"
    static var defaultQuery = AppEntityQuery()

    var id: String // bundle identifier
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(displayName)")
    }
    var displayName: String

    init(id: String, displayName: String)
    {
        self.id = id
        self.displayName = displayName
    }
}

@available(iOS 16, *)
struct AppEntityQuery: EntityQuery
{
    func entities(for identifiers: [String]) async throws -> [AppEntity]
    {
        try await DatabaseManager.shared.start()
        let context = DatabaseManager.shared.persistentContainer.newBackgroundContext()
        return try await context.performAsync {
            let fetchRequest = InstalledApp.fetchRequest()
            fetchRequest.predicate = NSPredicate(
                format: "%K IN %@",
                #keyPath(InstalledApp.bundleIdentifier),
                identifiers
            )
            fetchRequest.returnsObjectsAsFaults = false
            let apps = try context.fetch(fetchRequest)
            return apps.map { AppEntity(id: $0.bundleIdentifier, displayName: $0.name) }
        }
    }

    func suggestedEntities() async throws -> [AppEntity]
    {
        try await DatabaseManager.shared.start()
        let context = DatabaseManager.shared.persistentContainer.newBackgroundContext()
        return try await context.performAsync {
            let apps = InstalledApp.all(in: context)
            return apps.map { AppEntity(id: $0.bundleIdentifier, displayName: $0.name) }
                .sorted { $0.displayName < $1.displayName }
        }
    }
}

@available(iOS 16, *)
struct SelectAppIntent: WidgetConfigurationIntent
{
    static var title: LocalizedStringResource = "Select App"
    static var description = IntentDescription("Choose which app to display.")

    @Parameter(title: "App")
    var app: AppEntity?
}
