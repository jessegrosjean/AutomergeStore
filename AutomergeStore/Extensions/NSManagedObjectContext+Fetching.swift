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

    func fetchWorkspace(id: NSManagedObjectID) -> WorkspaceMO? {
        try? existingObject(with: id) as? WorkspaceMO
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

    func fetchWorkspaceSnapshotChunks(id: WorkspaceId) -> [ChunkMO]? {
        let request = ChunkMO.fetchRequest()
        request.includesPendingChanges = true
        request.predicate = .init(format: "%K == %@ and isSnapshot == true", "workspaceId", id as CVarArg)
        return try? fetch(request)
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

}
