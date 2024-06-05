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
        let workspaceMO = WorkspaceMO(context: viewContext, index: index)
        try viewContext.save()
        return .init(id: workspaceMO.uuid!, index: index)
    }
    
    public func openWorkspace(id: WorkspaceId) throws -> Workspace? {
        guard let (document, workspaceMO) = try openDocumentInner(id: id) else {
            return nil
        }
        
        guard workspaceMO.uuid == id else {
            throw Error(msg: "Workspace document id mismatch: \(id)")
        }

        return .init(id: id, index: document.doc)
    }

    public func closeWorkspace(id: WorkspaceId, insertingPendingChanges: Bool = true) throws {
        guard let workspaceMO = try fetchWorkspace(id: id) else {
            throw Error(msg: "Workspace Not Found: \(id)")
        }

        if let documents = workspaceMO.documents as? Set<DocumentMO> {
            for document in documents {
                try closeDocument(id: document.uuid!, insertingPendingChanges: insertingPendingChanges)
            }
        }
    }

    public func deleteWorkspace(id: WorkspaceId) throws {
        try closeWorkspace(id: id, insertingPendingChanges: false)
        let workspaceMO = try! fetchWorkspace(id: id)!
        viewContext.delete(workspaceMO)
        try viewContext.save()
    }

    func fetchWorkspace(id: WorkspaceId) throws -> WorkspaceMO? {
        let request = WorkspaceMO.fetchRequest()
        request.predicate = .init(format: "%K == %@", "uuid", id as CVarArg)
        return try viewContext.fetch(request).first
    }
    
}
