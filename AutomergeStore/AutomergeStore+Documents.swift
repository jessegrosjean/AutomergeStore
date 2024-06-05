import Foundation
import CoreData
import Automerge
import os.log

extension AutomergeStore {
    
    public typealias DocumentId = UUID
    
    public struct Document: Identifiable {
        public let id: DocumentId
        public let doc: Automerge.Document
        public let workspaceId: WorkspaceId
    }
    
    public func newDocument(workspaceId: WorkspaceId, document: Automerge.Document = .init()) throws -> Document {
        guard let workspaceMO = try fetchWorkspace(id: workspaceId) else {
            throw Error(msg: "Workspace not found: \(workspaceId)")
        }
        
        let documentMO = DocumentMO(context: viewContext, document: document)
        let documentId = documentMO.uuid!
        workspaceMO.addToDocuments(documentMO)
        try viewContext.save()
        createHandle(id: documentId, document: document)
        return .init(id: documentId, doc: document, workspaceId: workspaceMO.uuid!)
    }
    
    public func openDocument(id: DocumentId) throws -> Document? {
        try openDocumentInner(id: id)?.document
    }
    
    func openDocumentInner(id: DocumentId) throws -> (document: Document, documentMO: DocumentMO)? {
        guard let documentMO = try fetchDocument(id: id) else {
            return nil
        }
        
        let chunks = (documentMO.chunks as? Set<ChunkMO>) ?? []
        let snapshots = chunks.filter { !$0.isDelta }
        let deltas = chunks.filter { $0.isDelta }
        var document: Automerge.Document?
        
        for each in snapshots {
            if let snapshotData = each.data {
                if let document = document {
                    try document.applyEncodedChanges(encoded: snapshotData)
                } else {
                    document = try .init(snapshotData)
                }
            }
        }
        
        guard let document else {
            fatalError("Found no snapshot data")
        }
        
        for each in deltas {
            if let deltaData = each.data {
                try document.applyEncodedChanges(encoded: deltaData)
            }
        }
                
        createHandle(id: id, document: document)
        
        return (.init(id: id, doc: document, workspaceId: documentMO.workspace!.uuid!), documentMO)
    }

    public func closeDocument(id: DocumentId, insertingPendingChanges: Bool = true) throws {
        if insertingPendingChanges {
            try insertPendingDocumentChanges(id: id)
        }
        try dropHandle(id: id)
    }

    func insertPendingDocumentChanges(id documentId: DocumentId? = nil) throws {
        for eachId in documentHandles.keys {
            if
                documentId == nil || documentId == eachId,
                let (heads, changes) = try documentHandles[eachId]?.save()
            {
                if let documentMO = try fetchDocument(id: eachId) {
                    Logger.automergeStore.info("􀳃 Inserting document changes \(documentMO.objectID.uriRepresentation())")
                    documentMO.addToChunks(ChunkMO(context: viewContext, heads: heads, isDelta: true, data: changes))
                    compressChunksIfNeeded(documentMO: documentMO)
                }
            }
        }
    }

    func compressChunksIfNeeded(documentMO: DocumentMO) {
        guard
            let document = documentHandles[documentMO.uuid!]?.document,
            let chunks = documentMO.chunks as? Set<ChunkMO>
        else {
            return
        }

        let deltas = chunks.filter { $0.isDelta }
        let snapshots = chunks.filter { !$0.isDelta }
        let deltasSize = deltas.reduce(0, { $0 + $1.size })
        let snapshotsSize = snapshots.reduce(0, { $0 + $1.size })

        if deltasSize > (snapshotsSize / 2) {
            Logger.automergeStore.info("􀳃 Compressing document \(documentMO.objectID.uriRepresentation())")

            let chunkHeads = document.heads()
            let chunkData = document.save()

            let newChunk = ChunkMO(
                context: viewContext,
                heads: chunkHeads,
                isDelta: false,
                data: chunkData
            )
            
            for each in chunks {
                viewContext.delete(each)
            }
            
            documentMO.addToChunks(newChunk)
        }
    }
    
    func fetchDocument(id: DocumentId) throws -> DocumentMO? {
        let request = DocumentMO.fetchRequest()
        request.predicate = .init(format: "%K == %@", "uuid", id as CVarArg)
        return try viewContext.fetch(request).first
    }

    func fetchChunk(heads: String) throws -> ChunkMO? {
        let request = ChunkMO.fetchRequest()
        request.predicate = .init(format: "%K == %@", "heads", heads as CVarArg)
        return try viewContext.fetch(request).first
    }

}

