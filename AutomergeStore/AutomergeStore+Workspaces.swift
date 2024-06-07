import Foundation
import Automerge
import CoreData

extension AutomergeStore {
    
    public typealias WorkspaceId = UUID

    public struct Workspace: Identifiable {
        public let id: WorkspaceId
        public let index: Automerge.Document
    }
        
    public func newWorkspace(index: Automerge.Document = .init()) throws -> Workspace  {
        let workspaceId = UUID()
        return try transaction {
            let workspaceMO = WorkspaceMO(context: context, id: workspaceId, index: index)
            createHandle(workspaceId: workspaceMO.id!, documentId: workspaceMO.id!, document: index)
            return .init(id: workspaceId, index: index)
        } onRollback: {
            self.documentHandles.removeValue(forKey: workspaceId)
        }
    }

    public func importWorkspace(
        id: WorkspaceId,
        index: Automerge.Document?
    ) throws {
        guard !contains(workspaceId: id) else {
            return
        }
        _ = try transaction {
            WorkspaceMO(
                context: context,
                id: id,
                index: index
            )
        }
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

    public func closeWorkspace(id: WorkspaceId, saveChanges: Bool = true) throws {
        guard let chunks = fetchWorkspaceChunks(id: id) else {
            return
        }
        
        try transaction {
            for documentId in Set(chunks.filter { $0.isSnapshot }.map { $0.documentId! }) {
                try closeDocument(id: documentId, saveChanges: saveChanges)
            }
        }
    }

    public func deleteWorkspace(id: WorkspaceId) throws {
        try transaction {
            try closeWorkspace(id: id, saveChanges: false)
            let workspaceMO = fetchWorkspace(id: id)!
            context.delete(workspaceMO)
        }
    }

    func contains(workspaceId: DocumentId) -> Bool {
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
