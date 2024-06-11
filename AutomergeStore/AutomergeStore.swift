import Combine
import CoreData
import Automerge
import CloudKit
import os.log
import PersistentHistoryTrackingKit

public final class AutomergeStore: ObservableObject {
        
    public typealias WorkspaceId = UUID
    public typealias DocumentId = UUID

    public struct Workspace: Identifiable {
        public let id: WorkspaceId
        public let index: Automerge.Document
    }

    public struct Document: Identifiable {
        public let id: DocumentId
        public let workspaceId: WorkspaceId
        public let automerge: Automerge.Document
    }
    
    public struct PersistentHistoryOptions {
        public let appGroup: String?
        public let author: String
        public let allAuthors: [String]
    }

    public struct Error: Sendable, LocalizedError {
        public var msg: String
        public var errorDescription: String? { "AutomergeStoreError: \(msg)" }

        public init(msg: String) {
            self.msg = msg
        }
    }
    
    @Published public var workspaceIds: [WorkspaceId] = []

    let container: NSPersistentContainer
    var viewContext: NSManagedObjectContext { container.viewContext }
    let workspaceMOs: CurrentValueSubject<[WorkspaceMO], Never> = .init([])
    var documentHandles: [DocumentId : DocumentHandle] = [:]
    let storeHistory: PersistentHistoryTrackingKit?
    let scheduleSave: PassthroughSubject<Void, Never> = .init()
    var cancellables: Set<AnyCancellable> = []
    var syncEngine: CKSyncEngine?

    public init(url: URL? = nil, persistentHistoryOptions: PersistentHistoryOptions? = nil) throws {
        container = NSPersistentContainer(
            name: "AutomergeStore",
            managedObjectModel: try! Self.model(name: "AutomergeStore")
        )
        
        let storeDescription = container.persistentStoreDescriptions.first!
        
        if let url {
            storeDescription.url = url
        }
        
        if let _ = persistentHistoryOptions {
            storeDescription.setOption(
                true as NSNumber,
                forKey: NSPersistentHistoryTrackingKey
            )
            storeDescription.setOption(
                true as NSNumber,
                forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey
            )
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
        
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        if let persistentHistoryOptions {
            container.viewContext.transactionAuthor = persistentHistoryOptions.author
            storeHistory = .init(
                container: container,
                currentAuthor: persistentHistoryOptions.author,
                allAuthors: persistentHistoryOptions.allAuthors,
                userDefaults: persistentHistoryOptions.appGroup.map { UserDefaults(suiteName: $0)! }  ?? UserDefaults.standard,
                cleanStrategy: .byNotification(times: 1),
                uniqueString: "AutomergeStore.",
                autoStart: true
            )
        } else {
            storeHistory = nil
        }

        workspaceMOs.value = try viewContext.fetch(WorkspaceMO.fetchRequest())

        scheduleSave
            .debounce(
                for: .milliseconds(500),
                scheduler: DispatchQueue.main
            ).sink { [weak self] in
                do {
                    Logger.automergeStore.info("􀳃 Autosaving...")
                    try self?.transaction { transaction in
                        transaction.saveChanges()
                    }
                } catch {
                    Logger.automergeStore.error("􀳃 Failed to commit autosave transaction \(error)")
                }
            }.store(in: &cancellables)

        workspaceMOs.sink { [weak self] workspaceMOs in
            self?.workspaceIds = workspaceMOs.compactMap {
                if $0.hasValidIndex {
                    return $0.id
                } else {
                    return nil
                }
            }.sorted()
        }.store(in: &cancellables)
        
        NotificationCenter.default.publisher(
            for: NSManagedObjectContext.didChangeObjectsNotification,
            object: viewContext
        ).sink { [weak self] notification in
            self?.managedObjectContextObjectsDidChange(notification)
        }.store(in: &cancellables)
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
    
    public func newDocument(workspaceId: WorkspaceId, document: Automerge.Document = .init()) throws -> Document {
        try transaction { try $0.newDocument(workspaceId: workspaceId, automerge: document) }
    }
    
    public func openDocument(workspaceId: WorkspaceId, documentId: DocumentId) throws -> Document {
        try transaction { try $0.openDocument(id: documentId) }
    }

    public func closeDocument(id: DocumentId, saveChanges: Bool = true) throws {
        try transaction { $0.closeDocument(id: id, saveChanges: saveChanges) }
    }

}

extension AutomergeStore {

    var syncState: CKSyncEngine.State.Serialization? {
        get {
            try? transaction { $0.syncState }
        }
        set {
            try? transaction { $0.syncState = newValue }
        }
    }
    
    func preparedRecord(id: CKRecord.ID) -> CKRecord? {
        guard let chunkId = UUID(uuidString: id.recordName) else {
            return nil
        }

        return try? transaction {
            $0.fetchChunk(id: chunkId)?.preparedRecord(id: id)
        }
    }
    
}

extension AutomergeStore {
    
    // There can be only one! Otherwise many warnings
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
