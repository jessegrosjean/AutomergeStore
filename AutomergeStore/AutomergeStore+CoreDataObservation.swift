import Foundation
import Automerge
import CoreData
import CloudKit
import Combine
import os.log

extension AutomergeStore {
    
    func initCoreDataObservation() throws {
        NotificationCenter.default.publisher(
            for: NSManagedObjectContext.didChangeObjectsNotification,
            object: viewContext
        ).sink { [weak self] notification in
            guard let self else {
                return
            }
            
            let inserted = notification.userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject> ?? []
            let insertedChunks = inserted.compactMap { ($0 as? ChunkMO) }
            let insertedWorkspaces = inserted.compactMap { ($0 as? WorkspaceMO) }

            let updated = notification.userInfo?[NSUpdatedObjectsKey] as? Set<NSManagedObject> ?? []
            let updatedChunks = updated.compactMap { ($0 as? ChunkMO) }

            let deleted = notification.userInfo?[NSDeletedObjectsKey] as? Set<NSManagedObject> ?? []
            let deletedWorkspaces = deleted.compactMap { ($0 as? WorkspaceMO) }
            
            if !insertedChunks.isEmpty || !insertedWorkspaces.isEmpty || !deletedWorkspaces.isEmpty {
                self.updateWorkspaces(
                    insertedWorkspaces: insertedWorkspaces,
                    insertedChunks: insertedChunks,
                    updatedChunks: updatedChunks,
                    deletedWorkspaces: deletedWorkspaces
                )
                
                self.updateDocumentHandles(
                    insertedChunks: insertedChunks,
                    deletedWorkspaces: deletedWorkspaces
                )
            }
        }.store(in: &cancellables)
    }
    
    func updateWorkspaces(
        insertedWorkspaces: [WorkspaceMO],
        insertedChunks: [ChunkMO],
        updatedChunks: [ChunkMO],
        deletedWorkspaces: [WorkspaceMO]
    ) {
        // This is important, so that WorkspaceMO isn't a fault, that means we will see
        // WorkspaceMO deletes that are performed in background.
        _ = insertedWorkspaces.map { $0.id }

        workspaceMOs.subtract(deletedWorkspaces)
        workspaceMOs.formUnion(insertedWorkspaces)
               
        // Workspaces are ready (exposed to public API) only when they have a valid index
        // document chunk. That's a snapshot chunk whos id matches containing workspace.id.
        // Local API already enforces that all created workspaces will be valid, but
        // cloudkit can have partial sync, where workspace is synced, but not contained
        // chunks. So this ready distiontion is need for that case.
        var nextReadyWorkspaceIds = Set(readyWorkspaceIds.value)
        let originalReadyWorkspaceIds = nextReadyWorkspaceIds
        
        for chunk in insertedChunks + updatedChunks {
            guard
                chunk.isSnapshot,
                let documentId = chunk.documentId,
                !nextReadyWorkspaceIds.contains(documentId),
                let workspaceId = chunk.workspaceId,
                documentId == workspaceId
            else {
                continue
            }
            nextReadyWorkspaceIds.insert(workspaceId)
        }

        // Can't use deleted workspace.ids for this because at time of deletion they are
        // likley nil. So instead just make sure can only have ready id if also have
        // workspaceMO for it.
        nextReadyWorkspaceIds.formIntersection(Set(workspaceMOs.compactMap { $0.id }))
        
        if originalReadyWorkspaceIds != nextReadyWorkspaceIds {
            readyWorkspaceIds.value = nextReadyWorkspaceIds.sorted()
        }
    }

    func updateDocumentHandles(
        insertedChunks: [ChunkMO],
        deletedWorkspaces: [WorkspaceMO]
    ) {
        // Only open document handles are effected by changes
        let openDocumentIdsWithInsertedChunks: [DocumentId] = insertedChunks.compactMap { chunkMO in
            if let documentId = chunkMO.documentId, documentHandles.keys.contains(documentId) {
                return chunkMO.documentId
            } else {
                return nil
            }
        }
        
        // First insert local changes of open documents
        for documentId in openDocumentIdsWithInsertedChunks {
            if let (_, changes) = documentHandles[documentId]?.savePendingChanges() {
                guard let workspaceMO = viewContext.fetchWorkspace(id: documentHandles[documentId]!.workspaceId) else {
                    continue
                }
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
            guard let documentId = chunkMO.documentId, let chunkData = chunkMO.data else {
                continue
            }
            do {
                try documentHandles[documentId]?.applyExternalChanges(chunkData)
            } catch {
                Logger.automergeStore.error("􀳃 Failed to apply chunk to open document: \(error)")
            }
        }
        
        if !deletedWorkspaces.isEmpty {
            let workspaceIds = Set(workspaceMOs.compactMap { $0.id })
            let deletedWorkspaceHandles = documentHandles.filter { (documentId, handle) in
                !workspaceIds.contains(handle.workspaceId)
            }

            for (documentId, deletedHandle) in deletedWorkspaceHandles {
                if deletedHandle.hasPendingChanges {
                    // ???
                    // Save these somewhere? Or build UI so that
                }
                documentHandles.removeValue(forKey: documentId)
            }
        }

    }
    
}
