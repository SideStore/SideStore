//
//  RSTPersistentContainer.swift
//  AltStoreCore
//
//  Created by Magesh K on 6/17/26.
//

import CoreData

@objc(RSTPersistentContainer)
public class RSTPersistentContainer: NSPersistentContainer {
    @objc open var isMigrationRequired: Bool {
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
    
    @objc open var shouldAddStoresAsynchronously = false
    @objc open var preferredMergePolicy: NSMergePolicy = RSTRelationshipPreservingMergePolicy()
    
    private let parentBackgroundContexts = NSHashTable<NSManagedObjectContext>.weakObjects()
    private let pendingSaveParentBackgroundContexts = NSHashTable<NSManagedObjectContext>.weakObjects()
    
    @objc(initWithName:bundle:)
    public init(name: String, bundle: Bundle) {
        let models = [bundle]
        let managedObjectModel = NSManagedObjectModel.mergedModel(from: models)!
        super.init(name: name, managedObjectModel: managedObjectModel)
        initialize()
    }
    
    @objc(initWithName:managedObjectModel:)
    public override init(name: String, managedObjectModel model: NSManagedObjectModel) {
        super.init(name: name, managedObjectModel: model)
        initialize()
    }
    
    private func initialize() {
        shouldAddStoresAsynchronously = false
        preferredMergePolicy = RSTRelationshipPreservingMergePolicy()
        
        NotificationCenter.default.addObserver(self, selector: #selector(rst_managedObjectContextWillSave(_:)), name: .NSManagedObjectContextWillSave, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(rst_managedObjectContextObjectsDidChange(_:)), name: .NSManagedObjectContextObjectsDidChange, object: nil)
    }
    
    open override func loadPersistentStores(completionHandler: @escaping (NSPersistentStoreDescription, Error?) -> Void) {
        let dispatchGroup = DispatchGroup()
        
        for description in self.persistentStoreDescriptions {
            description.shouldAddStoreAsynchronously = self.shouldAddStoresAsynchronously
            
            guard let url = description.url,
                  let metadata = try? NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: description.type, at: url, options: description.options) else {
                continue
            }
            
            if !self.managedObjectModel.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata) && description.shouldMigrateStoreAutomatically {
                dispatchGroup.enter()
                
                self.progressivelyMigratePersistentStore(to: self.managedObjectModel, configuration: description.configuration, isAsynchronous: description.shouldAddStoreAsynchronously) { error in
                    if let error = error {
                        print("Migration error: \(error)")
                    }
                    dispatchGroup.leave()
                }
            }
        }
        
        let finish: (NSPersistentStoreDescription, Error?) -> Void = { [weak self] description, error in
            guard let self = self else { return }
            self.configure(self.viewContext, parent: nil)
            completionHandler(description, error)
        }
        
        if self.shouldAddStoresAsynchronously {
            dispatchGroup.notify(queue: .global(qos: .default)) {
                super.loadPersistentStores(completionHandler: finish)
            }
        } else {
            dispatchGroup.wait()
            super.loadPersistentStores(completionHandler: finish)
        }
    }
    
    open override func newBackgroundContext() -> NSManagedObjectContext {
        let context = super.newBackgroundContext()
        self.configure(context, parent: nil)
        return context
    }
    
    @objc open func newBackgroundSavingViewContext() -> NSManagedObjectContext {
        let parentBackgroundContext = self.newBackgroundContext()
        self.parentBackgroundContexts.add(parentBackgroundContext)
        
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        self.configure(context, parent: parentBackgroundContext)
        return context
    }
    
    @objc(newViewContextWithParent:)
    open func newViewContext(parent parentContext: NSManagedObjectContext?) -> NSManagedObjectContext {
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        self.configure(context, parent: parentContext)
        
        if parentContext == nil {
            context.persistentStoreCoordinator = self.persistentStoreCoordinator
        }
        
        return context
    }
    
    @objc(newBackgroundContextWithParent:)
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
    
    // MARK: - Migrations
    
    private func progressivelyMigratePersistentStore(to model: NSManagedObjectModel, configuration: String?, isAsynchronous: Bool, completionHandler: @escaping (Error?) -> Void) {
        let migrate = { [weak self] in
            guard let self = self else { return }
            do {
                try self._progressivelyMigratePersistentStore(to: model, configuration: configuration)
                completionHandler(nil)
            } catch {
                completionHandler(error)
            }
        }
        
        if isAsynchronous {
            DispatchQueue.global(qos: .userInitiated).async(execute: migrate)
        } else {
            migrate()
        }
    }
    
    private func _progressivelyMigratePersistentStore(to model: NSManagedObjectModel, configuration: String?) throws {
        guard let description = self.persistentStoreDescriptions.first, let url = description.url else {
            throw NSError(domain: "com.rileytestut.Roxas", code: -25, userInfo: [NSLocalizedDescriptionKey: "Unable to find a persistent store."])
        }
        
        let sourceMetadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: description.type, at: url, options: description.options)
        
        if self.managedObjectModel.isConfiguration(withName: nil, compatibleWithStoreMetadata: sourceMetadata) {
            return
        }
        
        guard let sourceModel = NSManagedObjectModel.mergedModel(from: Bundle.allBundles, forStoreMetadata: sourceMetadata) else {
            throw NSError(domain: "com.rileytestut.Roxas", code: -23, userInfo: [NSLocalizedDescriptionKey: "Unable to find any managed object models."])
        }
        
        var mappingModel: NSMappingModel?
        guard let migrationManager = self.progressiveMigrationManager(forSourceModel: sourceModel, destinationModel: model, configuration: configuration, mappingModel: &mappingModel), let finalMappingModel = mappingModel else {
            throw NSError(domain: "com.rileytestut.Roxas", code: -24, userInfo: [NSLocalizedDescriptionKey: "Unable to find a valid mapping model."])
        }
        
        let temporaryFilename = UUID().uuidString + "." + url.pathExtension
        let temporaryDestinationURL = FileManager.default.temporaryDirectory.appendingPathComponent(temporaryFilename)
        
        try migrationManager.migrateStore(from: url, sourceType: description.type, options: description.options, with: finalMappingModel, toDestinationURL: temporaryDestinationURL, destinationType: description.type, destinationOptions: description.options)
        
        try self.persistentStoreCoordinator.replacePersistentStore(at: url, destinationOptions: description.options, withPersistentStoreFrom: temporaryDestinationURL, sourceOptions: description.options, ofType: description.type)
        
        do {
            try self.persistentStoreCoordinator.destroyPersistentStore(at: temporaryDestinationURL, ofType: description.type, options: description.options)
        } catch {
            print("Error destroying temporary store: \(error)")
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
        guard let mappingModel = NSMappingModel.init(from: Bundle.allBundles, forSourceModel: sourceModel, destinationModel: destinationModel) else {
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
    
    // MARK: - Notifications
    
    @objc private func rst_managedObjectContextWillSave(_ notification: Notification) {
        guard let context = notification.object as? NSManagedObjectContext else { return }
        if let parent = context.parent, self.parentBackgroundContexts.contains(parent) {
            self.pendingSaveParentBackgroundContexts.add(parent)
        }
    }
    
    @objc private func rst_managedObjectContextObjectsDidChange(_ notification: Notification) {
        guard let context = notification.object as? NSManagedObjectContext else { return }
        if self.pendingSaveParentBackgroundContexts.contains(context) {
            do {
                try context.save()
            } catch {
                print("Context save error: \(error)")
            }
            self.pendingSaveParentBackgroundContexts.remove(context)
        }
    }
}
