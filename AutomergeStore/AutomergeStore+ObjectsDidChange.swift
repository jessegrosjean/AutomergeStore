import Foundation
import Automerge
import CoreData
import CloudKit
import os.log

extension AutomergeStore {
    
    func managedObjectContextObjectsDidChange(_ notification: Notification) {
        // Sync database state changes to any open Automerge.Documents. Also keep track of
        // WorkspaceMO's so that AutomergeStore can have observable workspaceIds.

        let inserted = notification.userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject> ?? []
        let insertedWorkspaces = inserted.compactMap { $0 as? WorkspaceMO }
        let insertedChunks = inserted.compactMap { $0 as? ChunkMO }

        let deleted = notification.userInfo?[NSDeletedObjectsKey] as? Set<NSManagedObject> ?? []
        let deletedWorkspaces = deleted.compactMap { $0 as? WorkspaceMO }
        let deletedChunks = deleted.compactMap { $0 as? ChunkMO }

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

        updateHandlesForInsertedChunks(insertedChunks)
        updateHandlesForDeletedChunks(deletedChunks)
        
        workspaceMOs.value = try! viewContext.fetch(WorkspaceMO.fetchRequest())
        
        if let syncEngine {
            let databaseChanges: [CKSyncEngine.PendingDatabaseChange] =
                insertedWorkspaces.map { .saveZone(.init(zoneID: $0.zoneID)) } +
                deletedWorkspaces.map { .deleteZone($0.zoneID) }
            
            let recordZoneChanges: [CKSyncEngine.PendingRecordZoneChange] =
                insertedChunks.map { .saveRecord($0.recordID) } +
                deletedChunks.map { .deleteRecord($0.recordID) }

            if !databaseChanges.isEmpty {
                syncEngine.state.add(pendingDatabaseChanges: databaseChanges)
                Logger.automergeCloudKit.info("􀇂 scheduleDatabaseChanges \(databaseChanges)")
            }
            
            if !recordZoneChanges.isEmpty {
                syncEngine.state.add(pendingRecordZoneChanges: recordZoneChanges)
                Logger.automergeCloudKit.info("􀇂 scheduleRecordZoneChanges \(recordZoneChanges)")
            }
        }
    }

    func updateHandlesForInsertedChunks(_ insertedChunks: [ChunkMO]) {
        // Special handling is only required for open documents with chunks inserted
        let effectedDocumentIds: [DocumentId] = insertedChunks.compactMap { chunkMO in
            if documentHandles.keys.contains(chunkMO.documentId!) {
                return chunkMO.documentId
            } else {
                return nil
            }
        }
        
        // First insert local changes of open documents
        for documentId in effectedDocumentIds {
            if let (_, changes) = documentHandles[documentId]?.save() {
                let workspaceMO = viewContext.fetchWorkspace(id: documentHandles[documentId]!.workspaceId)!
                workspaceMO.addToChunks(ChunkMO(
                    context: viewContext,
                    workspaceId: workspaceMO.id!,
                    documentId: documentId,
                    isSnapshot: false,
                    data: changes
                ))
            }

        }
                
        // Second apply inserted chunks to any open documents.
        for chunkMO in insertedChunks {
            let documentId = chunkMO.documentId!
            if let document = documentHandles[documentId]?.automerge {
                do {
                    try document.applyEncodedChanges(encoded: chunkMO.data!)
                } catch {
                    Logger.automergeStore.error("􀳃 Failed to apply chunk to document: \(error)")
                }
            }
        }
    }

    private func updateHandlesForDeletedChunks(_ deletedChunks: [ChunkMO]) {
        // Documents are derived from chunks. When snapshot chunks are deleted need to make
        // sure that the document still exists, and if not then remove that document handle.
        for documentId in Set(deletedChunks.filter { $0.isSnapshot }.map { $0.documentId! }) {
            if documentHandles[documentId] != nil {
                if !viewContext.contains(documentId: documentId) {
                    documentHandles.removeValue(forKey: documentId)
                }
            }
        }
    }

}
