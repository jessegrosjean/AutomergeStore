import CoreTransferable
import Foundation
import Automerge
import CoreData
import CloudKit
import Combine
import os.log

extension AutomergeStore {
    
    public typealias WorkspaceId = UUID

    public struct Workspace: Identifiable, Hashable {

        public static func == (lhs: Workspace, rhs: Workspace) -> Bool {
            lhs.id == rhs.id && lhs.index === rhs.index
        }
        
        public let id: WorkspaceId
        public let namePublisher: AnyPublisher<String, Never>
        public let indexPublisher: AnyPublisher<Automerge.Document?, Never>
        
        public var name: String {
            var name = ""
            _ = namePublisher.sink { n in
                name = n
            }
            return name
        }
        
        public var index: Automerge.Document? {
            var index: Automerge.Document?
            _ = indexPublisher.sink { i in
                index = i
            }
            return index
        }
        
        weak var store: AutomergeStore?
        
        init(
            id: WorkspaceId,
            store: AutomergeStore,
            namePublisher: AnyPublisher<String, Never>,
            indexPublisher: AnyPublisher<Automerge.Document?, Never>)
        {
            self.id = id
            self.store = store
            self.namePublisher = namePublisher
            self.indexPublisher = indexPublisher
        }
        
        public func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
        
    }
    
    public func contains(workspaceId: WorkspaceId) -> Bool {
        let request = WorkspaceMO.fetchRequest()
        request.fetchLimit = 1
        request.includesPendingChanges = true
        request.predicate = .init(format: "%K == %@", "id", workspaceId as CVarArg)
        return (try? viewContext.count(for: request)) == 1
    }

    public func newWorkspace(name: String, index: Automerge.Document = .init()) throws -> Workspace  {
        let id = UUID()
        Logger.automergeStore.info("􀳃 Creating workspace \(id)")
        let workspaceMO = WorkspaceMO(context: viewContext, id: id, name: name, index: index, synced: false)
        viewContext.assign(workspaceMO, to: privatePersistentStore)
        try viewContext.save()
        assert(workspaceMO.id == id)
        workspaces[id] = name
        _ = installDocumentHandle(workspaceId: id, documentId: id, automerge: index)
        return instalWorkspaceHandle(workspaceId: id, name: name).workspace(store: self)
    }
    
    public func openWorkspace(id: WorkspaceId) throws -> Workspace? {
        if let handle = workspaceHandles[id] {
            return handle.workspace(store: self)
        }

        Logger.automergeStore.info("􀳃 Opening workspace \(id)")

        guard let workspaceMO = viewContext.fetchWorkspace(id: id) else {
            return nil
        }
        
        assert(workspaceMO.id == id)
                       
        _ = try? openDocument(id: id)
        
        return instalWorkspaceHandle(
            workspaceId: id,
            name: workspaceMO.name ?? ""
        ).workspace(store: self)
    }
    
    public func closeWorkspace(id: WorkspaceId, saveChanges: Bool = true) throws {
        guard let handle = workspaceHandles[id] else {
            return
        }
        
        Logger.automergeStore.info("􀳃 Closing workspace \(id)")
        
        handle.indexPublisher.value = nil

        let workspaceOpenDocumentIds = documentHandles.compactMap { key, value in
            value.workspaceId == id ? key : nil
        }
        
        for documentId in workspaceOpenDocumentIds {
            try closeDocument(id: documentId, saveChanges: saveChanges)
        }
        
        dropWorkspaceHandle(id: id)
    }
    
    public func deleteWorkspace(id: WorkspaceId) throws {
        Logger.automergeStore.info("􀳃 Deleting workspace \(id)")

        guard let workspaceMO = viewContext.fetchWorkspace(id: id) else {
            throw Error(msg: "Workspace not found: \(id)")
        }

        try closeWorkspace(id: id, saveChanges: false)
        workspaces.removeValue(forKey: id)
        viewContext.delete(workspaceMO)
        try viewContext.save()
    }
    
    func instalWorkspaceHandle(
        workspaceId: WorkspaceId,
        name: String
    ) -> WorkspaceHandle {
        // WorkspaceHandle and DocumentHandle should share same automergePublisher instance
        workspaceHandles[workspaceId] = .init(
            id: workspaceId,
            namePublisher: .init(name),
            indexPublisher: documentHandles[workspaceId]?.automergePublisher ?? .init(nil)
        )
        return workspaceHandles[workspaceId]!
    }
    
    func dropWorkspaceHandle(id: WorkspaceId) {
        workspaceHandles.removeValue(forKey: id)
    }

}

extension AutomergeStore.Workspace: Transferable {
    
    public static var transferRepresentation: some TransferRepresentation {
        CKShareTransferRepresentation { workspaceToExport in
            guard let store = workspaceToExport.store else {
                throw AutomergeStore.Error(msg: "Store deallocated")
            }
            
            guard let ckContainer = store.cloudKitContainer else {
                throw AutomergeStore.Error(msg: "Container missing")
            }

            let workspaceId = workspaceToExport.id
            let pContainer = store.persistentContainer
            let context = pContainer.newBackgroundContext()
            let objectId = context.performAndWait {
                context.fetchWorkspace(id: workspaceId)?.objectID
            }
            
            if let objectId, let (_, share) = (try? pContainer.fetchShares(matching: [objectId]))?.first {
                return .existing(share, container: ckContainer)
            }
            
            return .prepareShare(container: ckContainer) {
                return try await store.shareWorkspace(workspaceId, to: nil).share
            }
        }
    }
    
}
