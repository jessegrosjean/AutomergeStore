import Foundation
import Automerge
import CoreData
import os.log

extension AutomergeStore {
    
    func managedObjectContextObjectsDidChange(_ notification: Notification) {
        
        var insertedWorkspaces: [WorkspaceMO] = []
        var deletedWorkspaces: [WorkspaceMO] = []

        if let objects = notification.userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject> {
            for each in objects {
                if let chunkMO = each as? ChunkMO {
                    let documentId = chunkMO.document!.uuid!
                    if let document = documentHandles[documentId]?.document {
                        do {
                            if document.heads().stringHash != chunkMO.heads {
                                try document.applyEncodedChanges(encoded: chunkMO.data!)
                            }
                        } catch {
                            fatalError("Bad chunk data, recover somehow?")
                        }
                    }
                } else if let _ = each as? DocumentMO {
                    // ignorable
                } else if let workspaceMO = each as? WorkspaceMO {
                    insertedWorkspaces.append(workspaceMO)
                }
            }
        }
        
        if let objects = notification.userInfo?[NSUpdatedObjectsKey] as? NSSet {
            for each in objects {
                if let _ = each as? ChunkMO {
                    assertionFailure("Should never happen?")
                } else if let _ = each as? DocumentMO {
                    // assertionFailure("Should never happen?")
                } else if let _ = each as? WorkspaceMO {
                    assertionFailure("Should never happen?")
                }
            }
        }
        
        if let objects = notification.userInfo?[NSDeletedObjectsKey] as? NSSet {
            for each in objects {
                if let _ = each as? ChunkMO {
                    // ignoreable
                } else if let documentMO = each as? DocumentMO {
                    documentHandles.removeValue(forKey: documentMO.uuid!)
                } else if let workspaceMO = each as? WorkspaceMO {
                    deletedWorkspaces.append(workspaceMO)
                }
            }
        }

        if !insertedWorkspaces.isEmpty || !deletedWorkspaces.isEmpty {
            var workspaceMOs = workspaceManagedObjects.value
            workspaceMOs.append(contentsOf: insertedWorkspaces)
            workspaceMOs = workspaceMOs.filter { !deletedWorkspaces.contains($0) }
            workspaceManagedObjects.value = workspaceMOs
        }

    }
    
    private func saveExistingChangesBeforeApplyingRemote(_ documentMO: DocumentMO) throws {
        // This is important because of way we manage heads... otherwise our changes would
        // not get sent to other clients until next time we compacted our changes into a
        // snapshot.
        if let (heads, changes) = try documentHandles[documentMO.uuid!]?.save() {
            documentMO.addToChunks(ChunkMO(context: viewContext, heads: heads, isDelta: true, data: changes))
        }
    }

}
