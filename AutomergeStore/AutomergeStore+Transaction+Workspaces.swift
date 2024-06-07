import Foundation
import Automerge

extension AutomergeStore.Transaction {
        
    public func newWorkspace(index: Automerge.Document = .init()) -> Workspace  {
        let workspaceId = UUID()
        let workspaceMO = WorkspaceMO(context: context, id: workspaceId, index: index)
        createDocumentHandle(workspaceId: workspaceMO.id!, documentId: workspaceMO.id!, document: index)
        workspaceIds.insert(workspaceId)
        return .init(id: workspaceId, index: index)
    }
    
    public func importWorkspace(
        id: WorkspaceId,
        index: Automerge.Document?
    ) {
        guard !contains(workspaceId: id) else {
            return
        }
        _ = WorkspaceMO(
            context: context,
            id: id,
            index: index
        )
    }
    
    public func openWorkspace(id: WorkspaceId) throws -> Workspace {
        guard let workspaceMO = fetchWorkspace(id: id) else {
            throw Error(msg: "Workspace not found: \(id)")
        }
        
        guard let document = try openDocument(id: workspaceMO.id!) else {
            throw Error(msg: "Workspace index document not found: \(id)")
        }
        
        return .init(id: id, index: document.doc)
    }
    
    public func closeWorkspace(id: WorkspaceId, saveChanges: Bool = true) {
        guard let chunks = fetchWorkspaceChunks(id: id) else {
            return
        }
        
        for documentId in Set(chunks.filter { $0.isSnapshot }.map { $0.documentId! }) {
            closeDocument(id: documentId, saveChanges: saveChanges)
        }
    }
    
    public func deleteWorkspace(id: WorkspaceId) {
        closeWorkspace(id: id, saveChanges: false)
        let workspaceMO = fetchWorkspace(id: id)!
        context.delete(workspaceMO)
        workspaceIds.remove(id)
    }
    
    func contains(workspaceId: WorkspaceId) -> Bool {
        workspaceIds.contains(workspaceId)
    }
    
    func fetchWorkspace(id: WorkspaceId) -> WorkspaceMO? {
        let request = WorkspaceMO.fetchRequest()
        request.includesPendingChanges = true
        request.fetchLimit = 1
        request.predicate = .init(format: "%K == %@", "id", id as CVarArg)
        return try? context.fetch(request).first
    }
    
    func fetchWorkspaceChunks(id: WorkspaceId) -> Set<ChunkMO>? {
        fetchWorkspace(id: id)?.chunks as? Set<ChunkMO>
    }
    
}
