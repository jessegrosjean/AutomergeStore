import CoreData
import os.log
import CloudKit

extension NSManagedObjectContext {
    
    typealias DocumentId = AutomergeStore.DocumentId
    typealias WorkspaceId = AutomergeStore.WorkspaceId

    func fetchWorkspace(id: WorkspaceId) -> WorkspaceMO? {
        let request = WorkspaceMO.fetchRequest()
        request.includesPendingChanges = true
        request.fetchLimit = 1
        request.predicate = .init(format: "%K == %@", "id", id as CVarArg)
        return try? fetch(request).first
    }
    
    func fetchWorkspaceChunks(id: WorkspaceId) -> Set<ChunkMO>? {
        fetchWorkspace(id: id)?.chunks as? Set<ChunkMO>
    }
    
    func containsChunk(id: UUID) -> Bool {
        let request = ChunkMO.fetchRequest()
        request.fetchLimit = 1
        request.includesPendingChanges = true
        request.predicate = .init(format: "%K == %@", "id", id as CVarArg)
        return (try? fetch(request).first) != nil
    }
    
    func fetchChunk(id: UUID) -> ChunkMO? {
        let request = ChunkMO.fetchRequest()
        request.fetchLimit = 1
        request.includesPendingChanges = true
        request.predicate = .init(format: "%K == %@", "id", id as CVarArg)
        return try? fetch(request).first
    }
    
    func contains(documentId: DocumentId) -> Bool {
        let request = ChunkMO.fetchRequest()
        request.fetchLimit = 1
        request.includesPendingChanges = true
        request.predicate = .init(format: "%K == %@ and isSnapshot == true", "documentId", documentId as CVarArg)
        return (try? count(for: request)) == 1
    }

    func fetchDocumentChunks(id: DocumentId, snapshotsOnly: Bool = false, fetchLimit: Int? = nil) -> [ChunkMO]? {
        let request = ChunkMO.fetchRequest()
        request.includesPendingChanges = true
        if snapshotsOnly {
            request.predicate = .init(format: "%K == %@ and isSnapshot == true", "documentId", id as CVarArg)
        } else {
            request.predicate = .init(format: "%K == %@", "documentId", id as CVarArg)
        }
        if let fetchLimit {
            request.fetchLimit = fetchLimit
        }
        return try? fetch(request)
    }

    var syncState: CKSyncEngine.State.Serialization? {
        get {
            findOrCreateSyncState().data.map {
                try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0)
            } ?? nil
        }
        set {
            findOrCreateSyncState().data = newValue.map { try? JSONEncoder().encode($0) } ?? nil
        }
    }
    
    func findOrCreateSyncState() -> SyncStateMO {
        let request = SyncStateMO.fetchRequest()
        request.includesPendingChanges = true
        let syncStates = try! fetch(request)
        if syncStates.isEmpty {
            return SyncStateMO(context: self)
        } else if syncStates.count == 1 {
            return syncStates.first!
        } else {
            Logger.automergeStore.error("􀳃 Found multiple SyncStateMO: \(syncStates)")
            return syncStates.first!
        }
    }

}
