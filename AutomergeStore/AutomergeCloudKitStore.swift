import CloudKit
import CoreData
import Automerge
import Combine
import os.log

public final actor AutomergeCloudKitStore: ObservableObject {
    
    static let syncEngineFetchTransactionSource = "syncEngineFetchTransactionSource"
        
    public typealias WorkspaceId = AutomergeStore.WorkspaceId
    public typealias Workspace = AutomergeStore.Workspace
    public typealias DocumentId = AutomergeStore.DocumentId
    public typealias Document = AutomergeStore.Document

    public enum Activity {
        case fetching
        case sending
        case waiting
    }
    
    public struct Error: Sendable, LocalizedError {
        public var msg: String
        public var errorDescription: String? { "AutomergeCloudKitError: \(msg)" }

        public init(msg: String) {
            self.msg = msg
        }
    }

    let container: CKContainer
    let database: CKDatabase
    let automaticallySync: Bool
    let automergeStore: AutomergeStore
    var automergeStoreSubscription: AnyCancellable?
    let activityPublisher: PassthroughSubject<Activity, Never> = .init()

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
        self.automergeStore.syncEngine = syncEngine
    }
    
    public func newWorkspace(index: Automerge.Document = .init()) throws -> Workspace  {
        try automergeStore.transaction { $0.newWorkspace(index: index) }
    }

    public func openWorkspace(id: WorkspaceId) throws -> Workspace {
        try automergeStore.transaction { try $0.openWorkspace(id: id) }
    }

    public func closeWorkspace(id: WorkspaceId, saveChanges: Bool = true) throws {
        try automergeStore.transaction { $0.closeWorkspace(id: id, saveChanges: saveChanges) }
    }

    public func deleteWorkspace(id: WorkspaceId) throws {
        try automergeStore.transaction { try $0.deleteWorkspace(id: id) }
    }
    
    public func newDocument(workspaceId: WorkspaceId, document: Automerge.Document = .init()) throws -> Document  {
        try automergeStore.transaction { try $0.newDocument(workspaceId: workspaceId, automerge: document) }
    }
    
    public func openDocument(workspaceId: WorkspaceId, documentId: DocumentId) throws -> Document {
        try automergeStore.transaction { try $0.openDocument(id: documentId) }
    }

    public func closeDocument(id: DocumentId, saveChanges: Bool = true) throws {
        try automergeStore.transaction { $0.closeDocument(id: id, saveChanges: saveChanges) }
    }
    
    public func commitChanges() throws {
        try automergeStore.transaction { $0.saveChanges() }
    }
    
    public func deleteLocalData() throws {
        let workspaceIds = automergeStore.workspaceIds
        try automergeStore.transaction {
            for eachId in workspaceIds {
                try $0.deleteWorkspace(id: eachId)
            }
        }
    }
    
    public func reuploadLocalData() throws {
        let workspaceIds = automergeStore.workspaceIds
        let (databaseChanges, recordChanges) = try automergeStore.transaction {
            var databaseChanges: [CKSyncEngine.PendingDatabaseChange] = []
            var recordChanges: [CKSyncEngine.PendingRecordZoneChange] = []

            for eachId in workspaceIds {
                let workspaceMO = $0.context.fetchWorkspace(id: eachId)!
                databaseChanges.append(.saveZone(.init(zoneID: workspaceMO.zoneID)))
                for chunkMO in workspaceMO.chunks as! Set<ChunkMO> {
                    recordChanges.append(.saveRecord(chunkMO.recordID))
                }
            }
            
            return (databaseChanges, recordChanges)
        }
        syncEngine.state.add(pendingDatabaseChanges: databaseChanges)
        syncEngine.state.add(pendingRecordZoneChanges: recordChanges)
    }
    
    lazy var syncEngine: CKSyncEngine = {
        Logger.automergeCloudKit.info("􀇂 Initializing CloudKit sync engine.")
        var configuration = CKSyncEngine.Configuration(
            database: container.privateCloudDatabase,
            stateSerialization: automergeStore.syncState,
            delegate: self
        )
        configuration.automaticallySync = automaticallySync
        return .init(configuration)
    }()
    
    func preparedRecord(id: CKRecord.ID) -> CKRecord? {
        automergeStore.preparedRecord(id: id)
    }
    
}
