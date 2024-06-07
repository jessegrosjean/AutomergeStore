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
    
    public func newDocument(workspaceId: WorkspaceId, document: Automerge.Document = .init()) throws -> Document {
        guard let workspaceMO = fetchWorkspace(id: workspaceId) else {
            throw Error(msg: "Workspace not found: \(workspaceId)")
        }
        
        let documentId = UUID()
        
        workspaceMO.addToChunks(.init(
            context: context,
            documentId: documentId,
            isSnapshot: true,
            data: document.save()
        ))
        
        createDocumentHandle(
            workspaceId: workspaceId,
            documentId: documentId,
            document: document
        )
        
        return .init(id: documentId, doc: document, workspaceId: workspaceMO.id!)
    }
    
    public func importDocument(
        workspaceId: WorkspaceId,
        documentId: DocumentId,
        document: Automerge.Document = .init()
    ) throws {
        guard let workspaceMO = fetchWorkspace(id: workspaceId) else {
            throw Error(msg: "Workspace not found: \(workspaceId)")
        }
        
        workspaceMO.addToChunks(.init(
            context: context,
            documentId: documentId,
            isSnapshot: true,
            data: document.save()
        ))
    }
    
    public func openDocument(id: DocumentId) throws -> Document? {
        if let handle = documentHandles[id] {
            return .init(id: id, doc: handle.document, workspaceId: handle.workspaceId)
        }
        
        guard
            let chunks = fetchDocumentChunks(id: id),
            let workspaceId = chunks.first?.workspace?.id
        else {
            return nil
        }
        
        let snapshots = chunks.filter { $0.isSnapshot }
        
        guard let firstSnapshotData = snapshots.first?.data else {
            throw Error(msg: "Found no snapshots for document: \(id)")
        }
        
        let document = try Automerge.Document(firstSnapshotData)
        
        for eachSnapshot in snapshots.dropFirst() {
            if let snapshotData = eachSnapshot.data {
                try document.applyEncodedChanges(encoded: snapshotData)
            }
        }
                
        for eachDelta in chunks.filter({ !$0.isSnapshot }) {
            if let deltaData = eachDelta.data {
                try document.applyEncodedChanges(encoded: deltaData)
            }
        }
        
        createDocumentHandle(
            workspaceId: workspaceId,
            documentId: id,
            document: document
        )
        
        return .init(id: id, doc: document, workspaceId: workspaceId)
    }

    public func closeDocument(id: DocumentId, saveChanges: Bool = true) {
        if saveChanges {
            saveDocumentChanges(id: id)
        }
        dropDocumentHandle(id: id)
    }

    func saveDocumentChanges(id documentId: DocumentId? = nil) {
        for eachDocumentId in documentHandles.keys {
            guard
                documentId == nil || documentId == eachDocumentId,
                let document = documentHandles[eachDocumentId]?.document,
                let (_, changes) = documentHandles[eachDocumentId]?.save()
            else {
                continue
            }
            
            var eachDocumentChunkMOs = fetchDocumentChunks(id: eachDocumentId)!
            let workspaceMO = eachDocumentChunkMOs.first!.workspace!

            Logger.automergeStore.info("􀳃 Inserting document changes \(eachDocumentId)")

            let newChunk = ChunkMO(
                context: context,
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

    func containsChunk(id: UUID) -> Bool {
        let request = ChunkMO.fetchRequest()
        request.fetchLimit = 1
        request.includesPendingChanges = true
        request.predicate = .init(format: "%K == %@", "id", id as CVarArg)
        return (try? context.fetch(request).first) != nil
    }
    
    func fetchChunk(id: UUID) -> ChunkMO? {
        let request = ChunkMO.fetchRequest()
        request.fetchLimit = 1
        request.includesPendingChanges = true
        request.predicate = .init(format: "%K == %@", "id", id as CVarArg)
        return try? context.fetch(request).first
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
        return try? context.fetch(request)
    }
    
    func createDocumentHandle(workspaceId: WorkspaceId, documentId: DocumentId, document: Automerge.Document) {
        var documentSubscriptions: Set<AnyCancellable> = []
        let scheduleSave = scheduleSave

        document.objectWillChange.sink {
            scheduleSave.send()
        }.store(in: &documentSubscriptions)
        
        documentHandles[documentId] = .init(
            workspaceId: workspaceId,
            document: document,
            subscriptions: documentSubscriptions
        )
    }
    
    func dropDocumentHandle(id: DocumentId) {
        documentHandles.removeValue(forKey: id)
    }
    
}
