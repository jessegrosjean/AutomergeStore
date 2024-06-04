import Foundation
import Automerge
import CoreData
import os.log

extension AutomergeStore {

    struct PendingContextInsertions {
        var documents: [DocumentMO] = []
        var snapshots: [SnapshotMO] = []
        var incrementals: [IncrementalMO] = []
        var isEmpty: Bool {
            documents.isEmpty && snapshots.isEmpty && incrementals.isEmpty
        }
    }
    
    func managedObjectContextObjectsDidChange(_ notification: Notification) {
        if let objects = notification.userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject> {
            for each in objects {
                if let documentMO = each as? DocumentMO {
                    pendingContextInsertions.documents.append(documentMO)
                } else if let snapshotMO = each as? SnapshotMO {
                    pendingContextInsertions.snapshots.append(snapshotMO)
                } else if let incrementalMO = each as? IncrementalMO {
                    pendingContextInsertions.incrementals.append(incrementalMO)
                }
            }
        }
        
        if let objects = notification.userInfo?[NSUpdatedObjectsKey] as? NSSet {
            for each in objects {
                if let _ = each as? DocumentMO {
                    // ignore
                } else if let _ = each as? SnapshotMO {
                    assertionFailure("Should never happen?")
                } else if let _ = each as? IncrementalMO {
                    assertionFailure("Should never happen?")
                }
            }
        }
        
        if let objects = notification.userInfo?[NSDeletedObjectsKey] as? NSSet {
            for each in objects {
                if let documentId = (each as? DocumentMO)?.objectID {
                    handles.removeValue(forKey: documentId)
                    documentIds = documentIds.filter {
                        $0.uriRepresentation() != documentId.uriRepresentation()
                    }
                } else if let _ = each as? SnapshotMO {
                    // ignoreable
                } else if let _ = each as? IncrementalMO {
                    // ignoreable
                }
            }
        }
        
        if !pendingContextInsertions.isEmpty {
            // When snapshots and increments come from CloudKit the relationships may not be
            // setup. So snapshot.document might return nil. This means we can't process them
            // right away in above loops, and instead store in ProcessContextInsertions
            // structure, waiting until relationships are filled, or objects are no longer part
            // of store.
            processPendingContextInsertions()
        }
    }
        
    private func processPendingContextInsertions() {
        guard !pendingContextInsertions.isEmpty else {
            return
        }

        Logger.automergeStore.info("􀳃 ProcessPendingContextInsertions")

        let readyDocuments = pendingContextInsertions.documents.filter { !$0.objectID.isTemporaryID }
        let readySnapshots = pendingContextInsertions.snapshots.filter { $0.document != nil }
        let readyIncrementals = pendingContextInsertions.incrementals.filter { $0.document != nil }

        pendingContextInsertions.documents = pendingContextInsertions.documents.filter {
            $0.objectID.isTemporaryID && (try? viewContext.existingObject(with: $0.objectID)) != nil
        }

        pendingContextInsertions.snapshots = pendingContextInsertions.snapshots.filter {
            $0.document == nil && (try? viewContext.existingObject(with: $0.objectID)) != nil
        }

        pendingContextInsertions.incrementals = pendingContextInsertions.incrementals.filter {
            $0.document == nil && (try? viewContext.existingObject(with: $0.objectID)) != nil
        }
        
        documentIds.append(contentsOf: readyDocuments.map { $0.objectID })

        for each in readySnapshots {
            let documentMO = each.document!

            guard
                let document = handles[documentMO.objectID]?.document,
                let snapshotData = each.data
            else {
                continue
            }

            do {
                try saveExistingChangesBeforeApplyingRemote(documentMO)
                Logger.automergeStore.info("􀳃 Applying snapshot \(each.objectID.uriRepresentation()) to document: \(documentMO.objectID.uriRepresentation())")
                try document.applyEncodedChanges(encoded: snapshotData)
            } catch {
                Logger.automergeStore.error("􀳃 Failed while apply snapshot \(error.localizedDescription)")
            }
        }

        for each in readyIncrementals {
            let documentMO = each.document!

            guard
                let document = handles[documentMO.objectID]?.document,
                let incrementalData = each.data
            else {
                continue
            }

            do {
                try saveExistingChangesBeforeApplyingRemote(documentMO)
                Logger.automergeStore.info("􀳃 Applying incremental \(each.objectID.uriRepresentation()) to document: \(documentMO.objectID.uriRepresentation())")
                try document.applyEncodedChanges(encoded: incrementalData)
            } catch {
                Logger.automergeStore.error("􀳃 Failed while applying incremental \(error.localizedDescription)")
            }
        }

        if !pendingContextInsertions.isEmpty {
            DispatchQueue.main.async { [weak self] in
                self?.processPendingContextInsertions()
            }
        }
    }
    
    private func saveExistingChangesBeforeApplyingRemote(_ documentMO: DocumentMO) throws {
        // This is important because of way we manage heads... otherwise our changes would
        // not get sent to other clients until next time we compacted our changes into a
        // snapshot.
        if let changes = try handles[documentMO.objectID]?.save() {
            let incremental = IncrementalMO(context: viewContext)
            incremental.data = changes
            documentMO.addToIncrementals(incremental)
        }
    }

}
