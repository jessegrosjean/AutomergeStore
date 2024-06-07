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
        return try transaction {
            workspaceMO.addToChunks(.init(
                context: context,
                documentId: documentId,
                isSnapshot: true,
                data: document.save()
            ))
            
            createHandle(
                workspaceId: workspaceId,
                documentId: documentId,
                document: document
            )
            
            return .init(id: documentId, doc: document, workspaceId: workspaceMO.id!)
        } onRollback: {
            self.documentHandles.removeValue(forKey: documentId)
        }
    }
    
    public func importDocument(
        workspaceId: WorkspaceId,
        documentId: DocumentId,
        document: Automerge.Document = .init()
    ) throws {
        guard let workspaceMO = fetchWorkspace(id: workspaceId) else {
            throw Error(msg: "Workspace not found: \(workspaceId)")
        }
        
        return try transaction {
            workspaceMO.addToChunks(.init(
                context: context,
                documentId: documentId,
                isSnapshot: true,
                data: document.save()
            ))
        }
    }
    
    public func openDocument(id: DocumentId) throws -> Document? {
        if let handle = documentHandles[id] {
            return .init(id: id, doc: handle.document, workspaceId: handle.workspaceId)
        }
        
        guard 
            let chunks = try fetchDocumentChunks(id: id),
            let workspaceId = chunks.first?.workspace?.id
        else {
            return nil
        }
        
        let snapshots = chunks.filter { $0.isSnapshot }
        let deltas = chunks.filter { !$0.isSnapshot }
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
        
        createHandle(
            workspaceId: workspaceId,
            documentId: id,
            document: document
        )
        
        return .init(id: id, doc: document, workspaceId: workspaceId)
    }

    public func closeDocument(id: DocumentId, saveChanges: Bool = true) throws {
        if saveChanges {
            try saveDocumentChanges(id: id)
        }
        dropHandle(id: id)
    }

    func saveDocumentChanges(id documentId: DocumentId? = nil) throws {
        try transaction {
            for eachDocumentId in documentHandles.keys {
                guard
                    documentId == nil || documentId == eachDocumentId,
                    let document = documentHandles[eachDocumentId]?.document,
                    let (_, changes) = documentHandles[eachDocumentId]?.save()
                else {
                    continue
                }
                
                var eachDocumentChunkMOs = try! fetchDocumentChunks(id: eachDocumentId)!
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

                    try transaction {
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
    
    func fetchDocumentChunks(id: DocumentId, snapshotsOnly: Bool = false, fetchLimit: Int? = nil) throws -> [ChunkMO]? {
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
        return try context.fetch(request)
    }

}

