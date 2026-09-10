//
//  PersistentContainer.swift
//  AltStore
//
//  Created by Magesh K on 8/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import CoreData

open class PersistentContainer: NSPersistentContainer, @unchecked Sendable {
    open var isMigrationRequired: Bool {
        for description in self.persistentStoreDescriptions {
            guard let url = description.url,
                  let metadata = try? NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: description.type, at: url, options: description.options) else {
                continue
            }
            if !self.managedObjectModel.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata) {
                return true
            }
        }
        return false
    }
    
    open var shouldAddStoresAsynchronously = false
    open var preferredMergePolicy: NSMergePolicy = RelationshipPreservingMergePolicy()
    
    private let parentBackgroundContexts = NSHashTable<NSManagedObjectContext>.weakObjects()
    private let pendingSaveParentBackgroundContexts = NSHashTable<NSManagedObjectContext>.weakObjects()
    
    open override class func defaultDirectoryURL() -> URL {
        guard let sharedDirectoryURL = FileManager.default.altstoreSharedDirectory else { return super.defaultDirectoryURL() }
        
        let databaseDirectoryURL = sharedDirectoryURL.appendingPathComponent("Database")
        try? FileManager.default.createDirectory(at: databaseDirectoryURL, withIntermediateDirectories: true, attributes: nil)

        return databaseDirectoryURL
    }
    
    open class func legacyDirectoryURL() -> URL {
        return super.defaultDirectoryURL()
    }
    
    public init(name: String, bundle: Bundle) {
        let models = [bundle]
        let managedObjectModel = NSManagedObjectModel.mergedModel(from: models)!
        super.init(name: name, managedObjectModel: managedObjectModel)
        initialize()
    }
    
    public override init(name: String, managedObjectModel model: NSManagedObjectModel) {
        super.init(name: name, managedObjectModel: model)
        initialize()
    }
    
    private func initialize() {
        shouldAddStoresAsynchronously = false
        preferredMergePolicy = RelationshipPreservingMergePolicy()
        
        NotificationCenter.default.addObserver(self, selector: #selector(managedObjectContextWillSave(_:)), name: .NSManagedObjectContextWillSave, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(managedObjectContextObjectsDidChange(_:)), name: .NSManagedObjectContextObjectsDidChange, object: nil)
    }
    
    open func loadPersistentStores() async throws {
        for description in self.persistentStoreDescriptions {
            guard let url = description.url,
                  let metadata = try? NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: description.type, at: url, options: description.options) else {
                continue
            }
            
            if !self.managedObjectModel.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata) && description.shouldMigrateStoreAutomatically {
                try await self.progressivelyMigratePersistentStore(to: self.managedObjectModel, configuration: description.configuration)
            }
        }
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            super.loadPersistentStores { [weak self] description, error in
                guard let self = self else { return }
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                self.configure(self.viewContext, parent: nil)
                continuation.resume(returning: ())
            }
        }
    }

    
    open override func newBackgroundContext() -> NSManagedObjectContext {
        let context = super.newBackgroundContext()
        self.configure(context, parent: nil)
        return context
    }
    
    open func newBackgroundSavingViewContext() -> NSManagedObjectContext {
        let parentBackgroundContext = self.newBackgroundContext()
        self.parentBackgroundContexts.add(parentBackgroundContext)
        
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        self.configure(context, parent: parentBackgroundContext)
        return context
    }
    
    open func newViewContext(parent parentContext: NSManagedObjectContext?) -> NSManagedObjectContext {
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        self.configure(context, parent: parentContext)
        
        if parentContext == nil {
            context.persistentStoreCoordinator = self.persistentStoreCoordinator
        }
        
        return context
    }
    
    open func newBackgroundContext(parent parentContext: NSManagedObjectContext) -> NSManagedObjectContext {
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        self.configure(context, parent: parentContext)
        return context
    }
    
    private func configure(_ context: NSManagedObjectContext, parent: NSManagedObjectContext?) {
        if let parent = parent {
            context.parent = parent
        }
        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = self.preferredMergePolicy
    }
    
    private func progressivelyMigratePersistentStore(to model: NSManagedObjectModel, configuration: String?) async throws {
        try await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            try self._progressivelyMigratePersistentStore(to: model, configuration: configuration)
        }.value
    }
    
    private func _progressivelyMigratePersistentStore(to model: NSManagedObjectModel, configuration: String?) throws {
        guard let description = self.persistentStoreDescriptions.first, let url = description.url else {
            throw NSError(domain: "io.sidestore.PersistentContainer", code: -25, userInfo: [NSLocalizedDescriptionKey: "Unable to find a persistent store."])
        }
        
        let sourceMetadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: description.type, at: url, options: description.options)
        
        if self.managedObjectModel.isConfiguration(withName: nil, compatibleWithStoreMetadata: sourceMetadata) {
            return
        }
        
        guard let sourceModel = NSManagedObjectModel.mergedModel(from: Bundle.allBundles, forStoreMetadata: sourceMetadata) else {
            throw NSError(domain: "io.sidestore.PersistentContainer", code: -23, userInfo: [NSLocalizedDescriptionKey: "Unable to find any managed object models."])
        }
        
        var mappingModel: NSMappingModel?
        guard let migrationManager = self.progressiveMigrationManager(forSourceModel: sourceModel, destinationModel: model, configuration: configuration, mappingModel: &mappingModel), let finalMappingModel = mappingModel else {
            throw NSError(domain: "io.sidestore.PersistentContainer", code: -24, userInfo: [NSLocalizedDescriptionKey: "Unable to find a valid mapping model."])
        }
        
        let temporaryFilename = UUID().uuidString + "." + url.pathExtension
        let temporaryDestinationURL = FileManager.default.temporaryDirectory.appendingPathComponent(temporaryFilename)
        
        try migrationManager.migrateStore(from: url, sourceType: description.type, options: description.options, with: finalMappingModel, toDestinationURL: temporaryDestinationURL, destinationType: description.type, destinationOptions: description.options)
        
        try self.persistentStoreCoordinator.replacePersistentStore(at: url, destinationOptions: description.options, withPersistentStoreFrom: temporaryDestinationURL, sourceOptions: description.options, ofType: description.type)
        
        do {
            try self.persistentStoreCoordinator.destroyPersistentStore(at: temporaryDestinationURL, ofType: description.type, options: description.options)
        } catch {
            debugLog("Error destroying temporary store: \(error)")
        }
        
        try self._progressivelyMigratePersistentStore(to: model, configuration: configuration)
    }
    
    private func progressiveMigrationManager(forSourceModel sourceModel: NSManagedObjectModel, destinationModel: NSManagedObjectModel, configuration: String?, mappingModel: inout NSMappingModel?) -> NSMigrationManager? {
        if let explicit = self.explicitMappingModel(forSourceModel: sourceModel, destinationModel: destinationModel, configuration: configuration) {
            mappingModel = explicit
            return NSMigrationManager(sourceModel: sourceModel, destinationModel: destinationModel)
        }
        
        let managedObjectModelURLs = self.managedObjectModelURLs()
        for modelURL in managedObjectModelURLs {
            guard let model = NSManagedObjectModel(contentsOf: modelURL) else { continue }
            if let mapping = self.explicitMappingModel(forSourceModel: sourceModel, destinationModel: model, configuration: configuration) {
                mappingModel = mapping
                return NSMigrationManager(sourceModel: sourceModel, destinationModel: model)
            }
        }
        
        if let inferred = try? NSMappingModel.inferredMappingModel(forSourceModel: sourceModel, destinationModel: destinationModel) {
            mappingModel = inferred
            return NSMigrationManager(sourceModel: sourceModel, destinationModel: destinationModel)
        }
        
        return nil
    }
    
    private func managedObjectModelURLs() -> [URL] {
        var modelURLs = [URL]()
        for bundle in Bundle.allBundles {
            if let momdURLs = bundle.urls(forResourcesWithExtension: "momd", subdirectory: nil) {
                for url in momdURLs {
                    let resourceDirectory = url.lastPathComponent
                    if let momURLs = bundle.urls(forResourcesWithExtension: "mom", subdirectory: resourceDirectory) {
                        modelURLs.append(contentsOf: momURLs)
                    }
                }
            }
            if let momURLs = bundle.urls(forResourcesWithExtension: "mom", subdirectory: nil) {
                modelURLs.append(contentsOf: momURLs)
            }
        }
        return modelURLs
    }
    
    private func explicitMappingModel(forSourceModel sourceModel: NSManagedObjectModel, destinationModel: NSManagedObjectModel, configuration: String?) -> NSMappingModel? {
        guard let mappingModel = NSMappingModel(from: Bundle.allBundles, forSourceModel: sourceModel, destinationModel: destinationModel) else {
            return nil
        }
        
        let entities = self.managedObjectModel.entities(forConfigurationName: configuration) ?? []
        for entityDescription in entities {
            guard let entityName = entityDescription.name else { continue }
            if destinationModel.entitiesByName[entityName] == nil {
                continue
            }
            
            for mapping in mappingModel.entityMappings {
                if mapping.destinationEntityName == entityName {
                    return mappingModel
                }
            }
        }
        
        return nil
    }
    
    @objc private func managedObjectContextWillSave(_ notification: Notification) {
        guard let context = notification.object as? NSManagedObjectContext else { return }
        if let parent = context.parent, self.parentBackgroundContexts.contains(parent) {
            self.pendingSaveParentBackgroundContexts.add(parent)
        }
    }
    
    @objc private func managedObjectContextObjectsDidChange(_ notification: Notification) {
        guard let context = notification.object as? NSManagedObjectContext else { return }
        if self.pendingSaveParentBackgroundContexts.contains(context) {
            do {
                try context.save()
            } catch {
                debugLog("Context save error: \(error)")
            }
            self.pendingSaveParentBackgroundContexts.remove(context)
        }
    }
}
