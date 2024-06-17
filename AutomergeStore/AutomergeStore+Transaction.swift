import os.log
import Automerge
import CoreData
import Combine
import CloudKit

extension AutomergeStore {

    public final class Transaction {

        public typealias Workspace = AutomergeStore.Workspace
        public typealias WorkspaceId = AutomergeStore.WorkspaceId
        public typealias Document = AutomergeStore.Document
        public typealias DocumentId = AutomergeStore.DocumentId
        public typealias Error = AutomergeStore.Error

        let context: NSManagedObjectContext
        let scheduleSave: PassthroughSubject<Void, Never>
        var documentHandles: [DocumentId : DocumentHandle]
        
        init(
            context: NSManagedObjectContext,
            scheduleSave: PassthroughSubject<Void, Never>,
            documentHandles: [DocumentId : DocumentHandle]
        ) {
            self.context = context
            self.scheduleSave = scheduleSave
            self.documentHandles = documentHandles
        }
        
    }
    
    // Transactions save when the closure returns or rollback if there were exceptions
    // when running the closure or when saving. The stores document handles are only
    // updated by the transaction when there are no exceptions.
    public func transaction<R>(
        _ closure: @MainActor (Transaction) throws -> R
    ) throws -> R where R: Sendable {
        assert(!inTransaction)
        inTransaction = true
        defer { inTransaction = false }

        return try accessLocalContext { context in
            do {
                let transaction = Transaction(
                    context: context,
                    scheduleSave: scheduleSave,
                    documentHandles: documentHandles
                )

                let result = try closure(transaction)

                if context.hasChanges {
                    Logger.automergeStore.info("􀳃 Saving transaction")
                    try context.save()
                }

                documentHandles = transaction.documentHandles

                return result
            } catch {
                Logger.automergeStore.info("􀳃 Transaction failed: \(error)")
                throw error
            }
        }
    }
    
    func accessLocalContext<R>(
        _ closure: (NSManagedObjectContext) throws -> R
    ) rethrows -> R where R: Sendable {
        // TODO: performAndWait might cause deadlock when used with async swift... though I
        // haven't been able to reproduce. Instead supposed to use async version of
        // perform... but that will cause many of my methods to become async, and I'm not
        // sure that I need/want that. Need someone smarter then me to evaluate.
        try viewContext.performAndWait {
            try closure(viewContext)
        }
    }

}

extension AutomergeStore.Transaction {
    
    public func newWorkspace(index: Automerge.Document = .init()) -> Workspace  {
        let id = UUID()
        Logger.automergeStore.info("􀳃 Creating workspace \(id)")
        let workspaceMO = WorkspaceMO(context: context, id: id, index: index, synced: false)
        assert(workspaceMO.id == id)
        createDocumentHandle(workspaceId: id, documentId: id, automerge: index)
        return .init(id: id, index: .init(id: id, workspaceId: id, automerge: index))
    }
    
    public func openWorkspace(id: WorkspaceId) throws -> Workspace? {
        guard let workspaceMO = context.fetchWorkspace(id: id) else {
            return nil
        }
        
        assert(workspaceMO.id == id)
        
        if documentHandles[id] == nil {
            Logger.automergeStore.info("􀳃 Opening workspace \(id)")
        }
        
        guard let document = try openDocument(id: id) else {
            return nil
        }
        
        return .init(id: id, index: .init(id: id, workspaceId: id, automerge: document.automerge))
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

extension AutomergeStore.Transaction {

    public func newDocument(workspaceId: WorkspaceId, automerge: Automerge.Document = .init()) throws -> Document {
        let documentId = UUID()
        
        Logger.automergeStore.info("􀳃 Creating document \(documentId)")
        
        guard let workspaceMO = context.fetchWorkspace(id: workspaceId) else {
            throw Error(msg: "Workspace not found: \(workspaceId)")
        }

        workspaceMO.addToChunks(.init(
            context: context,
            workspaceId: workspaceMO.id!,
            documentId: documentId,
            isSnapshot: true,
            data: automerge.save()
        ))
        
        createDocumentHandle(
            workspaceId: workspaceId,
            documentId: documentId,
            automerge: automerge
        )
        
        return .init(id: documentId, workspaceId: workspaceMO.id!, automerge: automerge)
    }
    
    public func openDocument(id: DocumentId) throws -> Document? {
        if let handle = documentHandles[id] {
            return .init(id: id, workspaceId: handle.workspaceId, automerge: handle.automerge)
        }

        Logger.automergeStore.info("􀳃 Opening document \(id)")

        guard
            let chunks = context.fetchDocumentChunks(id: id),
            let workspaceId = chunks.first?.workspace?.id
        else {
            return nil
        }
        
        let snapshots = chunks.filter { $0.isSnapshot }
        
        guard let firstSnapshotData = snapshots.first?.data else {
            throw Error(msg: "Found no snapshots for document: \(id)")
        }
        
        let automerge = try Automerge.Document(firstSnapshotData)
        
        for eachSnapshot in snapshots.dropFirst() {
            if let snapshotData = eachSnapshot.data {
                try automerge.applyEncodedChanges(encoded: snapshotData)
            }
        }
                
        for eachDelta in chunks.filter({ !$0.isSnapshot }) {
            if let deltaData = eachDelta.data {
                try automerge.applyEncodedChanges(encoded: deltaData)
            }
        }
        
        createDocumentHandle(
            workspaceId: workspaceId,
            documentId: id,
            automerge: automerge
        )
        
        return .init(id: id, workspaceId: workspaceId, automerge: automerge)
    }

    public func closeDocument(id: DocumentId, saveChanges: Bool = true) {
        Logger.automergeStore.info("􀳃 Closing document \(id)")
        if saveChanges {
            self.insertPendingChanges(id: id)
        }
        dropDocumentHandle(id: id)
    }

    public func insertPendingChanges(id documentId: DocumentId? = nil) {
        for eachDocumentId in documentHandles.keys {
            guard
                documentId == nil || documentId == eachDocumentId,
                let document = documentHandles[eachDocumentId]?.automerge,
                let (_, changes) = documentHandles[eachDocumentId]?.savePendingChanges(),
                var documentChunkMOs = context.fetchDocumentChunks(id: eachDocumentId),
                let workspaceMO = documentChunkMOs.first?.workspace
            else {
                continue
            }
            
            Logger.automergeStore.info("􀳃 Inserting document changes \(eachDocumentId)")

            let newChunk = ChunkMO(
                context: context,
                workspaceId: workspaceMO.id!,
                documentId: eachDocumentId,
                isSnapshot: false,
                data: changes
            )

            documentChunkMOs.append(newChunk)
            workspaceMO.addToChunks(newChunk)

            let snapshots = documentChunkMOs.filter { $0.isSnapshot }
            let deltas = documentChunkMOs.filter { !$0.isSnapshot }
            let snapshotsSize = snapshots.reduce(0, { $0 + $1.size })
            let deltasSize = deltas.reduce(0, { $0 + $1.size })

            if deltasSize > (snapshotsSize / 2) {
                Logger.automergeStore.info("􀳃 Compressing document chunks \(eachDocumentId)")

                let newSnapshotChunk = ChunkMO(
                    context: context,
                    workspaceId: workspaceMO.id!,
                    documentId: eachDocumentId,
                    isSnapshot: true,
                    data: document.save()
                )
                
                for each in documentChunkMOs {
                    context.delete(each)
                }
                
                workspaceMO.addToChunks(newSnapshotChunk)
            }
        }
    }
    
    func createDocumentHandle(workspaceId: WorkspaceId, documentId: DocumentId, automerge: Automerge.Document) {
        let scheduleSave = scheduleSave
        documentHandles[documentId] = .init(
            workspaceId: workspaceId,
            automerge: automerge,
            automergeSubscription: automerge.objectWillChange.sink {
                scheduleSave.send()
            }
        )
    }
    
    func dropDocumentHandle(id: DocumentId) {
        documentHandles.removeValue(forKey: id)
    }
    
}
