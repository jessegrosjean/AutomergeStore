import CloudKit
import CoreData
import Automerge
import Combine
import os.log

public final actor AutomergeCloudKitStore {
    
    public typealias WorkspaceId = AutomergeStore.WorkspaceId
    public typealias Workspace = AutomergeStore.Workspace
    public typealias DocumentId = AutomergeStore.DocumentId
    public typealias Document = AutomergeStore.Document

    let container: CKContainer
    let database: CKDatabase
    let automaticallySync: Bool
    let automergeStore: AutomergeStore
    var syncEngineState: CKSyncEngine.State.Serialization?
    var processingSyncEngineChanges: Bool
    var subscription: AnyCancellable?

    public init (
        container: CKContainer,
        database: CKDatabase,
        automaticallySync: Bool = true,
        automergeStore: AutomergeStore
    ) async throws {
        self.container = container
        self.database = database
        self.automaticallySync = automaticallySync
        self.automergeStore = automergeStore
        self.processingSyncEngineChanges = false
        self.subscribeToAutomergeStore()
    }

    func subscribeToAutomergeStore() {
        // Expectation is we must see all changes from this store. Maybe should be using
        // history tracking to really make sure?
        self.subscription = NotificationCenter.default.publisher(
            for: NSManagedObjectContext.didChangeObjectsNotification,
            object: automergeStore.context
        ).sink { [weak self] notification in
            guard let self else {
                return
            }
            Task {
                await self.automergeStoreManagedObjectContextObjectsDidChange(notification)
            }
        }
    }
    
    public func newWorkspace(index: Automerge.Document = .init()) throws -> Workspace  {
        try automergeStore.newWorkspace(index: index)
    }

    public func openWorkspace(id: WorkspaceId) throws -> Workspace? {
        try automergeStore.openWorkspace(id: id)
    }

    public func closeWorkspace(id: WorkspaceId, saveChanges: Bool = true) throws {
        try automergeStore.closeWorkspace(id: id, saveChanges: saveChanges)
    }

    public func deleteWorkspace(id: WorkspaceId) throws {
        try automergeStore.deleteWorkspace(id: id)
    }
    
    public func newDocument(workspaceId: WorkspaceId, document: Automerge.Document = .init()) throws -> Document  {
        try automergeStore.newDocument(workspaceId: workspaceId, document: document)
    }
    
    public func openDocument(workspaceId: WorkspaceId, documentId: DocumentId) throws -> Document? {
        try automergeStore.openDocument(id: documentId)
    }

    public func closeDocument(id: DocumentId, saveChanges: Bool = true) throws {
        try automergeStore.closeDocument(id: id, saveChanges: saveChanges)
    }

    public func commitChanges() throws {
        try automergeStore.commitChanges()
    }
    
    public func deleteLocalData() throws {
        for eachId in automergeStore.workspaceIds {
            try automergeStore.deleteWorkspace(id: eachId)
        }
    }
    
    public func reuploadLocalData() throws {
        for eachId in automergeStore.workspaceIds {
            let workspaceMO = automergeStore.fetchWorkspace(id: eachId)!
            syncEngine.state.add(pendingDatabaseChanges: [.saveZone(.init(zoneID: workspaceMO.zoneID))])
            for chunkMO in workspaceMO.chunks as! Set<ChunkMO> {
                syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(chunkMO.recordID)])
            }
        }
    }
    
    lazy var syncEngine: CKSyncEngine = {
        Logger.automergeCloudKit.info("􀇂 Initializing CloudKit sync engine.")
        var configuration = CKSyncEngine.Configuration(
            database: container.privateCloudDatabase,
            stateSerialization: syncEngineState,
            delegate: self
        )
        configuration.automaticallySync = automaticallySync
        return .init(configuration)
    }()
    
}

extension AutomergeCloudKitStore {

    public struct Error: Sendable, LocalizedError {
        public var msg: String
        public var errorDescription: String? { "AutomergeCloudKitError: \(msg)" }

        public init(msg: String) {
            self.msg = msg
        }
    }

}
