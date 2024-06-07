import Foundation
import Automerge
import CoreData
import os.log

extension AutomergeStore {
    
    func managedObjectContextObjectsDidChange(_ notification: Notification) {
        Logger.automergeStore.info("􀳃 Managed objects did change")

        let inserted = notification.userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject> ?? []
        let insertedWorkspaces = inserted.compactMap { $0 as? WorkspaceMO }
        updateHandlesForInsertedChunks(inserted.compactMap { $0 as? ChunkMO })

        let deleted = notification.userInfo?[NSDeletedObjectsKey] as? Set<NSManagedObject> ?? []
        let deletedWorkspaces = deleted.compactMap { $0 as? WorkspaceMO }
        updateHandlesForDeletedChunks(deleted.compactMap { $0 as? ChunkMO })
                
        if !insertedWorkspaces.isEmpty || !deletedWorkspaces.isEmpty {
            var workspaceMOs = workspaceManagedObjects.value
            workspaceMOs.append(contentsOf: insertedWorkspaces)
            workspaceMOs = workspaceMOs.filter { !deletedWorkspaces.contains($0) }
            workspaceManagedObjects.value = workspaceMOs
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
                let workspaceMO = fetchWorkspace(id: documentHandles[documentId]!.workspaceId)!
                workspaceMO.addToChunks(ChunkMO(
                    context: context,
                    documentId: documentId,
                    isSnapshot: false,
                    data: changes
                ))
            }

        }
                
        // Second apply inserted chunks to any open documents.
        for chunkMO in insertedChunks {
            let documentId = chunkMO.documentId!
            if let document = documentHandles[documentId]?.document {
                do {
                    try document.applyEncodedChanges(encoded: chunkMO.data!)
                } catch {
                    Logger.automergeStore.error("Failed to apply chunk to document: \(error)")
                }
            }
        }
    }

    private func updateHandlesForDeletedChunks(_ deletedChunks: [ChunkMO]) {
        // If a document has been deleted make sure to remove handle
        for documentId in Set(deletedChunks.filter { $0.isSnapshot }.map { $0.documentId! }) {
            if documentHandles[documentId] != nil {
                if !contains(documentId: documentId) {
                    documentHandles.removeValue(forKey: documentId)
                }
            }
        }
    }

}
