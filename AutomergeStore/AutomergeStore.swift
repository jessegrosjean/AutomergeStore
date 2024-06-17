import Foundation
import CoreData
import CloudKit
import Combine
import Automerge
import os.log

@MainActor
public final class AutomergeStore: ObservableObject {
    
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
        
        var hasPendingChanges: Bool {
            automerge.heads() != saved
        }
        
        mutating func savePendingChanges() -> (heads: Set<ChangeHash>, data: Data)? {
            guard automerge.heads() != saved else {
                return nil
            }
            let newSavedHeads = automerge.heads()
            // Can this really throw if we are sure heads are correct?
            let changes = try! automerge.encodeChangesSince(heads: saved)
            saved = newSavedHeads
            return (newSavedHeads, changes)
        }
        
        mutating func applyExternalChanges(_ data: Data) throws {
            assert(!hasPendingChanges)
            try automerge.applyEncodedChanges(encoded: data)
            saved = automerge.heads()
        }
        
    }
    
    let container: NSPersistentCloudKitContainer
    let viewContext: NSManagedObjectContext
    let scheduleSave: PassthroughSubject<Void, Never> = .init()
    let readyWorkspaceIds: CurrentValueSubject<[WorkspaceId], Never> = .init([])
    var documentHandles: [DocumentId : DocumentHandle] = [:]
    var workspaceMOs: Set<WorkspaceMO> = []
    var cancellables: Set<AnyCancellable> = []
    var inTransaction: Bool = false

    public init(
        url: URL? = nil,
        containerOptions: NSPersistentCloudKitContainerOptions? = nil
    ) throws {
        container = NSPersistentCloudKitContainer(
            name: "AutomergeStore",
            managedObjectModel: try Self.model(name: "AutomergeStore")
        )
        
        let storeDescription = container.persistentStoreDescriptions.first!
        
        if let url {
            storeDescription.url = url
        }

        storeDescription.cloudKitContainerOptions = containerOptions

        storeDescription.setOption(
            true as NSNumber,
            forKey: NSPersistentHistoryTrackingKey
        )
        storeDescription.setOption(
            true as NSNumber,
            forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey
        )
        
        #if DEBUG
        //do {
            //try container.initializeCloudKitSchema(options: [])
        //} catch {
        //    fatalError("Failed initializeCloudKitSchema \(error)")
        //}
        #endif
        
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
        
        viewContext = container.viewContext
        viewContext.automaticallyMergesChangesFromParent = true
        viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        workspaceMOs = Set(try viewContext.fetch(WorkspaceMO.fetchRequest()))
        readyWorkspaceIds.value = workspaceMOs.compactMap { workspaceMO in
            guard let id = workspaceMO.id, viewContext.contains(documentId: id) else {
                return nil
            }
            return id
        }
        
        try initCoreDataObservation()
                
        scheduleSave
            .debounce(
                for: .milliseconds(500),
                scheduler: DispatchQueue.main
            ).sink { [weak self] in
                guard let self else {
                    return
                }
                do {
                    if self.documentHandles.values.first(where: { $0.hasPendingChanges }) != nil {
                        Logger.automergeStore.info("􀳃 Autosaving...")
                        try self.insertPendingChanges()
                    }
                } catch {
                    Logger.automergeStore.error("􀳃 Failed to commit autosave transaction \(error)")
                }
            }.store(in: &cancellables)
    }

    public func contains(workspaceId: WorkspaceId) -> Bool {
        accessLocalContext { context in
            let request = WorkspaceMO.fetchRequest()
            request.fetchLimit = 1
            request.includesPendingChanges = true
            request.predicate = .init(format: "%K == %@", "id", workspaceId as CVarArg)
            return (try? context.count(for: request)) == 1
        }
    }

    public func contains(documentId: DocumentId) -> Bool {
        accessLocalContext { context in
            let request = ChunkMO.fetchRequest()
            request.fetchLimit = 1
            request.includesPendingChanges = true
            request.predicate = .init(format: "%K == %@ and isSnapshot == true", "documentId", documentId as CVarArg)
            return (try? context.count(for: request)) == 1
        }
    }

    public var workspaceIds: [WorkspaceId] {
        readyWorkspaceIds.value
    }

    public var workspaceIdsPublisher: AnyPublisher<[WorkspaceId], Never> {
        readyWorkspaceIds.eraseToAnyPublisher()
    }

    public func newWorkspace(index: Automerge.Document = .init()) throws -> Workspace  {
        try transaction { $0.newWorkspace(index: index) }
    }

    public func openWorkspace(id: WorkspaceId) throws -> Workspace? {
        try transaction { try $0.openWorkspace(id: id) }
    }

    public func closeWorkspace(id: WorkspaceId, saveChanges: Bool = true) throws {
        try transaction { $0.closeWorkspace(id: id, saveChanges: saveChanges) }
    }

    public func deleteWorkspace(id: WorkspaceId) throws {
        try transaction { try $0.deleteWorkspace(id: id) }
    }

    public func isOpen(id: DocumentId) -> Bool  {
        documentHandles.keys.contains(id)
    }

    public func newDocument(workspaceId: WorkspaceId, document: Automerge.Document = .init()) throws -> Document  {
        try transaction { try $0.newDocument(workspaceId: workspaceId, automerge: document) }
    }
    
    public func openDocument(workspaceId: WorkspaceId, documentId: DocumentId) throws -> Document? {
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
    
    private static var cachedManagedObjectModel: NSManagedObjectModel?

    private static func model(name: String) throws -> NSManagedObjectModel {
        if cachedManagedObjectModel == nil {
            cachedManagedObjectModel = try loadModel(name: name, bundle: Bundle.main)
        }
        return cachedManagedObjectModel!
    }
    
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

extension NSPersistentCloudKitContainerOptions {
    
    public convenience init(containerIdentifier: String, databaseScope: CKDatabase.Scope = .private) {
        self.init(containerIdentifier: containerIdentifier)
        self.databaseScope = databaseScope
    }
    
}
