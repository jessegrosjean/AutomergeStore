import Foundation
import Automerge
import os.log
extension AutomergeStore.Transaction {
        
    public func newWorkspace(index: Automerge.Document = .init()) -> Workspace  {
        let id = UUID()
        Logger.automergeStore.info("􀳃 Creating workspace \(id)")
        let workspaceMO = WorkspaceMO(context: context, id: id, index: index)
        createDocumentHandle(workspaceId: workspaceMO.id!, documentId: workspaceMO.id!, automerge: index)
        return .init(id: id, index: index)
    }
    
    public func importWorkspace(
        id: WorkspaceId,
        index: Automerge.Document?
    ) {
        Logger.automergeStore.info("􀳃 Importing workspace \(id)")

        let _ = context.fetchWorkspace(id: id) ?? WorkspaceMO(
            context: context,
            id: id,
            index: nil
        )
        
        if let index {
            try! importDocument(workspaceId: id, documentId: id, automerge: index)
        }
    }
    
    public func openWorkspace(id: WorkspaceId) throws -> Workspace {
        Logger.automergeStore.info("􀳃 Opening workspace \(id)")

        guard let workspaceMO = context.fetchWorkspace(id: id) else {
            throw Error(msg: "Workspace not found: \(id)")
        }
        let document = try openDocument(id: workspaceMO.id!)
        return .init(id: id, index: document.automerge)
    }
    
    public func closeWorkspace(id: WorkspaceId, saveChanges: Bool = true) {
        Logger.automergeStore.info("􀳃 Closing workspace \(id)")

        guard let chunks = context.fetchWorkspaceChunks(id: id) else {
            return
        }
        
        for documentId in Set(chunks.filter { $0.isSnapshot }.map { $0.documentId! }) {
            closeDocument(id: documentId, saveChanges: saveChanges)
        }
    }
    
    public func deleteWorkspace(id: WorkspaceId) throws {
        Logger.automergeStore.info("􀳃 Deleting workspace \(id)")

        guard let workspaceMO = context.fetchWorkspace(id: id) else {
            throw Error(msg: "Workspace not found: \(id)")
        }

        closeWorkspace(id: id, saveChanges: false)
        context.delete(workspaceMO)
    }
        
}
