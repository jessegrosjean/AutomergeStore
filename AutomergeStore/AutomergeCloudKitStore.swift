import CloudKit
import Automerge
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
    let cloudKitRecords: CloudKitRecords
    var syncEngineState: CKSyncEngine.State.Serialization?

    public init(
        container: CKContainer,
        database: CKDatabase,
        automaticallySync: Bool = true,
        automergeStore: AutomergeStore
    ) throws {
        self.container = container
        self.database = database
        self.automaticallySync = automaticallySync
        self.cloudKitRecords = try .init()
        self.automergeStore = automergeStore
    }

    public func newWorkspace(index: Automerge.Document = .init()) throws -> Workspace  {
        try automergeStore.newWorkspace(index: index)
    }
    
    public func openWorkspace(id: WorkspaceId) throws -> Workspace? {
        try automergeStore.openWorkspace(id: id)
    }

    public func closeWorkspace(id: WorkspaceId, insertingPendingChanges: Bool = true) throws {
        try automergeStore.closeWorkspace(id: id, insertingPendingChanges: insertingPendingChanges)
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

    public func closeDocument(id: DocumentId, insertingPendingChanges: Bool = true) throws {
        try automergeStore.closeDocument(id: id, insertingPendingChanges: insertingPendingChanges)
    }

    public func deleteLocalData() throws {
        for eachId in automergeStore.workspaceIds {
            try automergeStore.deleteWorkspace(id: eachId)
        }
    }
    
    public func reuploadLocalData() throws {
        for eachId in automergeStore.workspaceIds {
            let workspaceMO = try automergeStore.fetchWorkspace(id: eachId)!
            syncEngine.state.add(pendingDatabaseChanges: [.saveZone(.init(zoneID: workspaceMO.zoneID))])
            for documentMO in workspaceMO.documents as! Set<DocumentMO> {
                for chunkMO in documentMO.chunks as! Set<ChunkMO> {
                    syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(chunkMO.recordID)])
                }
            }
        }
    }
    
    lazy var syncEngine: CKSyncEngine = {
        Logger.automergeCloudKit.info("Initializing CloudKit sync engine.")
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

extension AutomergeStore.Document {
    
    var ckRecordId: CloudKit.CKRecord.ID {
        .init(recordName: id.uuidString, zoneID: .init(zoneName: workspaceId.uuidString))
    }
    
}

extension ChunkMO {
    
    func ckRecordId(in zone: CKRecordZone.ID) -> CKRecord.ID {
        .init(recordName: heads!, zoneID: zone)
    }
    
}

// Add workspace
// Delete workspace
// Add Document
// Add Document chunk
// Delete Document chunk
