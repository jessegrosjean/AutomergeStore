import CloudKit
import Automerge
import os.log

public final actor AutomergeCloudKitStore {
    
    public typealias DocumentId = AutomergeStore.DocumentId
    public typealias Document = AutomergeStore.Document

    let container: CKContainer
    let database: CKDatabase
    let automaticallySync: Bool
    let automergeStore: AutomergeStore
    
    public init(
        container: CKContainer,
        database: CKDatabase,
        automaticallySync: Bool = true,
        automergeStore: AutomergeStore
    ) {
        self.container = container
        self.database = database
        self.automaticallySync = automaticallySync
        self.automergeStore = automergeStore
    }
    
    public func newDocument(_ document: Automerge.Document = .init()) throws -> Document  {
        try automergeStore.newDocument(document)
    }
    
    public func openDocument(id: DocumentId) throws -> Document? {
        try automergeStore.openDocument(id: id)
    }

    public func closeDocument(id: DocumentId, storingChanges: Bool = true) throws {
        try automergeStore.closeDocument(id: id, storingChanges: storingChanges)
    }

    public func deleteDocument(id: DocumentId) throws {
        try automergeStore.deleteDocument(id: id)
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
    
    var syncEngineState: CKSyncEngine.State.Serialization?

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
