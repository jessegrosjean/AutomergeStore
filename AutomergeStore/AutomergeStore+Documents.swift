import Foundation
import Automerge
import Combine
import os.log

extension AutomergeStore {

    public typealias DocumentId = UUID

    public struct Document: Identifiable {
        public let id: DocumentId
        public let workspaceId: WorkspaceId
        public let automergePublisher: AnyPublisher<Automerge.Document?, Never>
        public var automerge: Automerge.Document? {
            var result: Automerge.Document?
            _ = automergePublisher.sink { r in
                result = r
            }
            return result
        }
    }
    
    public func newDocument(workspaceId: WorkspaceId, automerge: Automerge.Document = .init()) throws -> Document {
        let documentId = UUID()
        
        Logger.automergeStore.info("􀳃 Creating document \(documentId)")
        
        guard let workspaceMO = viewContext.fetchWorkspace(id: workspaceId) else {
            throw Error(msg: "Workspace not found: \(workspaceId)")
        }

        workspaceMO.addToChunks(.init(
            context: viewContext,
            workspaceId: workspaceMO.id!,
            documentId: documentId,
            isSnapshot: true,
            data: automerge.save()
        ))
        
        try viewContext.save()
        
        return installDocumentHandle(
            workspaceId: workspaceId,
            documentId: documentId,
            automerge: automerge
        ).document
    }
    
    public func openDocument(id: DocumentId) throws -> Document? {
        if let handle = documentHandles[id] {
            return handle.document
        }

        Logger.automergeStore.info("􀳃 Opening document \(id)")

        guard
            let chunks = viewContext.fetchDocumentChunks(id: id),
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
        
        return installDocumentHandle(
            workspaceId: workspaceId,
            documentId: id,
            automerge: automerge
        ).document
    }

    public func closeDocument(id: DocumentId, saveChanges: Bool = true) throws {
        guard documentHandles.keys.contains(id) else {
            return
        }

        Logger.automergeStore.info("􀳃 Closing document \(id)")
        
        if saveChanges {
            try insertPendingChanges(id: id, saveChanges: saveChanges)
        }
        
        dropDocumentHandle(id: id)
    }

    public func insertPendingChanges(id documentId: DocumentId? = nil, saveChanges: Bool = true) throws {
        for eachDocumentId in documentHandles.keys {
            guard
                documentId == nil || documentId == eachDocumentId,
                let document = documentHandles[eachDocumentId]?.automergePublisher.value,
                let (_, changes) = documentHandles[eachDocumentId]?.savePendingChanges(),
                var documentChunkMOs = viewContext.fetchDocumentChunks(id: eachDocumentId),
                let workspaceMO = documentChunkMOs.first?.workspace
            else {
                continue
            }
            
            Logger.automergeStore.info("􀳃 Inserting document changes \(eachDocumentId)")

            let newChunk = ChunkMO(
                context: viewContext,
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
                
                workspaceMO.addToChunks(ChunkMO(
                    context: viewContext,
                    workspaceId: workspaceMO.id!,
                    documentId: eachDocumentId,
                    isSnapshot: true,
                    data: document.save()
                ))

                for each in documentChunkMOs {
                    viewContext.delete(each)
                }
            }
        }
        
        if saveChanges && viewContext.hasChanges {
            try viewContext.save()
        }
    }
    
    func installDocumentHandle(workspaceId: WorkspaceId, documentId: DocumentId, automerge: Automerge.Document) -> DocumentHandle {
        // WorkspaceHandle and DocumentHandle should share same automergePublisher instance
        let scheduleSave = scheduleSave
        let automergePublisher = {
            if let indexPublisher = workspaceHandles[documentId]?.indexPublisher {
                assert(indexPublisher.value == nil)
                indexPublisher.value = automerge
                return indexPublisher
            } else {
                return .init(automerge)
            }
        }()
        documentHandles[documentId] = .init(
            id: documentId,
            workspaceId: workspaceId,
            automergePublisher: automergePublisher,
            automergeSubscription: automerge.objectWillChange.sink {
                scheduleSave.send()
            }
        )
        return documentHandles[documentId]!
    }
    
    func dropDocumentHandle(id: DocumentId) {
        if let handle = workspaceHandles[id] {
            handle.indexPublisher.value = nil
        }
        documentHandles.removeValue(forKey: id)
    }
    
}
