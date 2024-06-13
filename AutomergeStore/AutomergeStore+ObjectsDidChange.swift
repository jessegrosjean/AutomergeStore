import Foundation
import Automerge
import CoreData
import CloudKit
import os.log

extension AutomergeStore {
    
    struct SendableChunk: Sendable {
        let id: UUID
        let workspaceId: UUID
        let documentId: UUID
        let isSnapshot: Bool
        let data: Data
        var recordId: CKRecord.ID {
            .init(recordName: id.uuidString, zoneID: .init(zoneName: workspaceId.uuidString))
        }
        init(_ chunkMO: ChunkMO) {
            self.id = chunkMO.id!
            self.workspaceId = chunkMO.workspaceId!
            self.documentId = chunkMO.documentId!
            self.isSnapshot = chunkMO.isSnapshot
            self.data = chunkMO.data!
        }
    }

    struct SendableWorkspace: Sendable {
        let id: UUID
        let zoneID: CKRecordZone.ID
        init(_ workspaceMO: WorkspaceMO) {
            self.id = workspaceMO.id!
            self.zoneID = workspaceMO.zoneID
        }
    }

    func managedObjectContextObjectsDidChange(
        _ insertedWorkspaces: [SendableWorkspace],
        _ deletedWorkspaces: [SendableWorkspace],
        _ insertedChunks: [SendableChunk],
        _ deletedChunks: [SendableChunk]
    ) {
        if !insertedWorkspaces.isEmpty || !deletedWorkspaces.isEmpty || !insertedChunks.isEmpty || !deletedChunks.isEmpty {
            Logger.automergeStore.info("􀳃 Managed objects did change")
        }
        
        if !insertedWorkspaces.isEmpty {
            Logger.automergeStore.info("  Inserted workspaces \(insertedWorkspaces.map { $0.id })")
        }
        
        if !insertedChunks.isEmpty {
            Logger.automergeStore.info("  Inserted chunks \(insertedChunks.map { $0.id })")
        }
        
        if !deletedWorkspaces.isEmpty {
            Logger.automergeStore.info("  Deleted workspaces \(deletedWorkspaces.map { $0.id })")
        }
        
        if !deletedChunks.isEmpty {
            Logger.automergeStore.info("  Deleted chunks \(deletedChunks.map { $0.id })")
        }
        
        updateHandles(
            insertedChunks,
            deletedChunks
        )
        
        scheduleSyncEngine(
            insertedWorkspaces,
            deletedWorkspaces,
            insertedChunks,
            deletedChunks
        )
        
        workspaceMOs.value = try! context.fetch(WorkspaceMO.fetchRequest())
    }

    private func updateHandles(
        _ insertedChunks: [SendableChunk],
        _ deletedChunks: [SendableChunk])
    {
        // Special handling is only required for open documents with chunks inserted
        let effectedDocumentIds: [DocumentId] = insertedChunks.compactMap { chunkMO in
            if documentHandles.keys.contains(chunkMO.documentId) {
                return chunkMO.documentId
            } else {
                return nil
            }
        }
        
        // First insert local changes of open documents
        for documentId in effectedDocumentIds {
            if let (_, changes) = documentHandles[documentId]?.save() {
                let workspaceMO = context.fetchWorkspace(id: documentHandles[documentId]!.workspaceId)!
                workspaceMO.addToChunks(ChunkMO(
                    context: context,
                    workspaceId: workspaceMO.id!,
                    documentId: documentId,
                    isSnapshot: false,
                    data: changes
                ))
            }
        }
                
        // Second apply inserted chunks to any open documents.
        for chunkMO in insertedChunks {
            let documentId = chunkMO.documentId
            if let document = documentHandles[documentId]?.automerge {
                do {
                    try document.applyEncodedChanges(encoded: chunkMO.data)
                } catch {
                    Logger.automergeStore.error("􀳃 Failed to apply chunk to document: \(error)")
                }
            }
        }
        
        // Documents are derived from chunks. When snapshot chunks are deleted need to make
        // sure that the document still exists, and if not then remove that document handle.
        for documentId in Set(deletedChunks.filter { $0.isSnapshot }.map { $0.documentId }) {
            if documentHandles[documentId] != nil {
                if !context.contains(documentId: documentId) {
                    documentHandles.removeValue(forKey: documentId)
                }
            }
        }
    }
    
    private func scheduleSyncEngine(
        _ insertedWorkspaces: [SendableWorkspace],
        _ deletedWorkspaces: [SendableWorkspace],
        _ insertedChunks: [SendableChunk],
        _ deletedChunks: [SendableChunk]
    ) {
        // TODO: Only want to schedule new changes with sync engine if sync engine event is
        // not the source of these changes. How to track that?
        guard let sync else {
            return
        }
        
        let databaseChanges: [CKSyncEngine.PendingDatabaseChange] =
            insertedWorkspaces.map { .saveZone(.init(zoneID: $0.zoneID)) } +
            deletedWorkspaces.map { .deleteZone($0.zoneID) }
        
        let recordZoneChanges: [CKSyncEngine.PendingRecordZoneChange] =
            insertedChunks.map { .saveRecord($0.recordId) } +
            deletedChunks.map { .deleteRecord($0.recordId) }
        
        if databaseChanges.isEmpty {
            sync.engine.state.add(pendingDatabaseChanges: databaseChanges)
        }
        
        if recordZoneChanges.isEmpty {
            sync.engine.state.add(pendingRecordZoneChanges: recordZoneChanges)
        }
    }
        
}
