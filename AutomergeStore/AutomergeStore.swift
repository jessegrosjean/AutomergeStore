import Foundation
import CoreData
import CloudKit
import Combine
import Automerge
import os.log

@globalActor public actor AutomergeStoreActor {
    public static let shared = AutomergeStoreActor()
    private init() {}
}

// What if instad make this whole class main actor?
// Put


public actor AutomergeStore: ObservableObject {
    
    public typealias WorkspaceId = UUID
    public typealias DocumentId = UUID

    public struct Workspace: Identifiable, Sendable {
        public let id: WorkspaceId
        public let index: Document
    }

    public struct Document: Identifiable, Sendable {
        public let id: DocumentId
        public let workspaceId: WorkspaceId
        public let automerge: Automerge.Document
    }
    
    public struct Error: Sendable, LocalizedError {
        public var msg: String
        public var errorDescription: String? { "AutomergeStoreError: \(msg)" }

        public init(msg: String) {
            self.msg = msg
        }
    }
    
    struct DocumentHandle {
        
        let workspaceId: WorkspaceId
        let automerge: Automerge.Document
        var saved: Set<ChangeHash>
        var automergeSubscription: AnyCancellable
        
        init(workspaceId: WorkspaceId, automerge: Automerge.Document, automergeSubscription: AnyCancellable) {
            self.workspaceId = workspaceId
            self.automerge = automerge
            self.saved = automerge.heads()
            self.automergeSubscription = automergeSubscription
        }
        
        mutating func save() -> (heads: Set<ChangeHash>, data: Data)? {
            guard automerge.heads() != saved else {
                return nil
            }
            let newSavedHeads = automerge.heads()
            // Can this really throw if we are sure heads are correct?
            let changes = try! automerge.encodeChangesSince(heads: saved)
            saved = newSavedHeads
            return (newSavedHeads, changes)
        }
    }
    
    var sync: Sync?
    let container: NSPersistentContainer
    let context: NSManagedObjectContext
    let syncActivity: PassthroughSubject<Activity, Never> = .init()
    let scheduleSave: PassthroughSubject<Void, Never> = .init()
    let workspaceMOs: CurrentValueSubject<[WorkspaceMO], Never> = .init([])
    var documentHandles: [DocumentId : DocumentHandle] = [:]
    var cancellables: Set<AnyCancellable> = []
    var inTransaction: Bool = false

    public init(
        url: URL? = nil,
        syncConfiguration: SyncConfiguration? = nil
    ) async throws {
        container = NSPersistentContainer(
            name: "AutomergeStore" //,
            //managedObjectModel: try await Self.model(name: "AutomergeStore")
        )
        
        let storeDescription = container.persistentStoreDescriptions.first!
        
        if let url {
            storeDescription.url = url
        }
        
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                /*
                 Typical reasons for an error here include:
                 * The parent directory does not exist, cannot be created, or disallows writing.
                 * The persistent store is not accessible, due to permissions or data protection when the device is locked.
                 * The device is out of space.
                 * The store could not be migrated to the current model version.
                 Check the error message to determine what the actual problem was.
                 */
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
        
        context = container.newBackgroundContext()
        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        workspaceMOs.value = try context.fetch(WorkspaceMO.fetchRequest())
        
        if let syncConfiguration {
            initSyncEngineWithConfiguration(syncConfiguration)
        }
        
        scheduleSave
            .debounce(
                for: .milliseconds(500),
                scheduler: DispatchQueue.main
            ).sink { [weak self] in
                guard let self else {
                    return
                }
                
                Task {
                    Logger.automergeStore.info("􀳃 Autosaving...")
                    do {
                        try await self.insertPendingChanges()
                    } catch {
                        Logger.automergeStore.error("􀳃 Failed to commit autosave transaction \(error)")
                    }
                }
            }.store(in: &cancellables)
                
        NotificationCenter.default.publisher(
            for: NSManagedObjectContext.didChangeObjectsNotification,
            object: context
        ).sink { [weak self] notification in
            guard let self else {
                return
            }

            let inserted = notification.userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject> ?? []
            let insertedWorkspaces: [SendableWorkspace] = inserted.compactMap { ($0 as? WorkspaceMO).map { .init($0) } }
            let insertedChunks: [SendableChunk] = inserted.compactMap { ($0 as? ChunkMO).map { .init($0) } }
            let deleted = notification.userInfo?[NSDeletedObjectsKey] as? Set<NSManagedObject> ?? []
            let deletedWorkspaces: [SendableWorkspace] = deleted.compactMap { ($0 as? WorkspaceMO).map { .init($0) } }
            let deletedChunks: [SendableChunk] = deleted.compactMap { ($0 as? ChunkMO).map { .init($0) } }

            Task {
                await self.managedObjectContextObjectsDidChange(
                    insertedWorkspaces,
                    deletedWorkspaces,
                    insertedChunks,
                    deletedChunks
                )
            }
        }.store(in: &cancellables)
    }
    
    public var workspaceIds: AnyPublisher<[WorkspaceId], Never> {
        workspaceMOs
            .map { workspaceMOs in
                workspaceMOs
                    .filter { $0.hasValidIndex }
                    .map { $0.id! }
                    .sorted()
            }
            .eraseToAnyPublisher()
    }

    public var activity: AnyPublisher<Activity, Never> {
        syncActivity.eraseToAnyPublisher()
    }

    public func newWorkspace(index: Automerge.Document = .init()) throws -> Workspace  {
        try transaction { $0.newWorkspace(index: index) }
    }

    public func openWorkspace(id: WorkspaceId) throws -> Workspace {
        try transaction { try $0.openWorkspace(id: id) }
    }

    public func closeWorkspace(id: WorkspaceId, saveChanges: Bool = true) throws {
        try transaction { $0.closeWorkspace(id: id, saveChanges: saveChanges) }
    }

    public func deleteWorkspace(id: WorkspaceId) throws {
        try transaction { try $0.deleteWorkspace(id: id) }
    }
    
    public func newDocument(workspaceId: WorkspaceId, document: Automerge.Document = .init()) throws -> Document  {
        try transaction { try $0.newDocument(workspaceId: workspaceId, automerge: document) }
    }
    
    public func openDocument(workspaceId: WorkspaceId, documentId: DocumentId) throws -> Document {
        try transaction { try $0.openDocument(id: documentId) }
    }

    public func closeDocument(id: DocumentId, saveChanges: Bool = true) throws {
        try transaction { $0.closeDocument(id: id, saveChanges: saveChanges) }
    }
    
    public func insertPendingChanges() throws {
        try transaction { $0.insertPendingChanges() }
    }

}

extension AutomergeStore {
    
    // There can be only one! Otherwise many warnings
    @MainActor
    private static var cachedManagedObjectModel: NSManagedObjectModel?

    @MainActor
    private static func model(name: String) throws -> NSManagedObjectModel {
        if cachedManagedObjectModel == nil {
            cachedManagedObjectModel = try loadModel(name: name, bundle: Bundle.main)
        }
        return cachedManagedObjectModel!
    }
    
    @MainActor
    private static func loadModel(name: String, bundle: Bundle) throws -> NSManagedObjectModel {
        guard let modelURL = bundle.url(forResource: name, withExtension: "momd") else {
            fatalError("failed find momd of name \(name)")
        }
        
        guard let model = NSManagedObjectModel(contentsOf: modelURL) else {
            fatalError("failed to load \(modelURL)")
        }
        
        return model
    }
    
}
