import Combine
import Automerge
import Foundation
import os.log

extension AutomergeStore.Transaction {
    
    public func contains(documentId: DocumentId) -> Bool {
        let request = ChunkMO.fetchRequest()
        request.fetchLimit = 1
        request.includesPendingChanges = true
        request.predicate = .init(format: "%K == %@ and isSnapshot == true", "documentId", documentId as CVarArg)
        return (try? context.count(for: request)) == 1
    }
    
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
    
    public func importDocument(
        workspaceId: WorkspaceId,
        documentId: DocumentId,
        automerge: Automerge.Document
    ) throws {
        Logger.automergeStore.info("􀳃 Importing document \(documentId)")

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
    }
    
    public func openDocument(id: DocumentId) throws -> Document {
        Logger.automergeStore.info("􀳃 Opening document \(id)")

        if let handle = documentHandles[id] {
            return .init(id: id, workspaceId: handle.workspaceId, automerge: handle.automerge)
        }
        
        guard
            let chunks = context.fetchDocumentChunks(id: id),
            let workspaceId = chunks.first?.workspace?.id
        else {
            throw Error(msg: "Found no chunks for document: \(id)")
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
            self.saveChanges(id: id)
        }
        dropDocumentHandle(id: id)
    }

    public func saveChanges(id documentId: DocumentId? = nil) {
        for eachDocumentId in documentHandles.keys {
            guard
                documentId == nil || documentId == eachDocumentId,
                let document = documentHandles[eachDocumentId]?.automerge,
                let (_, changes) = documentHandles[eachDocumentId]?.save()
            else {
                continue
            }
            
            var eachDocumentChunkMOs = context.fetchDocumentChunks(id: eachDocumentId)!
            let workspaceMO = eachDocumentChunkMOs.first!.workspace!

            Logger.automergeStore.info("􀳃 Inserting document changes \(eachDocumentId)")

            let newChunk = ChunkMO(
                context: context,
                workspaceId: workspaceMO.id!,
                documentId: eachDocumentId,
                isSnapshot: false,
                data: changes
            )

            eachDocumentChunkMOs.append(newChunk)
            workspaceMO.addToChunks(newChunk)

            let snapshots = eachDocumentChunkMOs.filter { $0.isSnapshot }
            let deltas = eachDocumentChunkMOs.filter { !$0.isSnapshot }
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
                
                for each in eachDocumentChunkMOs {
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
