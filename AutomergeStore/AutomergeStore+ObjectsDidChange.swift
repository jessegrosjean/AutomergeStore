import Foundation
import Automerge
import CoreData

extension AutomergeStore {

    func managedObjectContextObjectsDidChange(_ notification: Notification) {
        if let objects = notification.userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject> {
            for each in objects {
                if let documentMO = each as? DocumentMO {
                    print(documentMO)
                    //print(documentMO.objectID.isTemporaryID)
                    // ignorable
                } else if let snapshotMO = each as? SnapshotMO {
                    handleSnapshotInserted(snapshotMO)
                } else if let incrementalMO = each as? IncrementalMO {
                    handleIncrementalInserted(incrementalMO)
                }
            }
        }
        
        if let objects = notification.userInfo?[NSUpdatedObjectsKey] as? NSSet {
            for each in objects {
                if let doc = each as? DocumentMO {
                    print(doc)
                    // Expected when snapshots and changes are added
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
                } else if let _ = each as? SnapshotMO {
                    // ignoreable
                } else if let _ = each as? IncrementalMO {
                    // ignoreable
                }
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            // Hack because at this point above logic is breaking because snapshot and incremental do not have document relationship set yet
            self?.reloadAllDocuments()
        }
    }
    
    func reloadAllDocuments() {
        try! saveDocumentChanges()
        for (key, handle) in handles {
            let doc = viewContext.object(with: key) as! DocumentMO
            for snapshot in doc.snapshots ?? [] {
                try! handle.document.applyEncodedChanges(encoded: (snapshot as! SnapshotMO).data!)
            }
            for incremental in doc.incrementals ?? [] {
                try! handle.document.applyEncodedChanges(encoded: (incremental as! IncrementalMO).data!)
            }
        }
    }
    

    func handleSnapshotInserted(_ snapshot: SnapshotMO) {
        guard
            //!snapshot.objectID.isTemporaryID,
            let documentMO = snapshot.document,
            let document = handles[documentMO.objectID]?.document,
            let snapshotData = snapshot.data
        else {
            return
        }

        do {
            try saveExistingChangesBeforeApplyingRemote(documentMO)
            try document.applyEncodedChanges(encoded: snapshotData)
        } catch {
            fatalError("Bad Data!")
        }
    }
    
    func handleIncrementalInserted(_ incremental: IncrementalMO) {
        guard
            //!incremental.objectID.isTemporaryID,
            let documentMO = incremental.document,
            let document = handles[documentMO.objectID]?.document,
            let incrementalData = incremental.data
        else {
            return
        }

        do {
            try saveExistingChangesBeforeApplyingRemote(documentMO)
            try document.applyEncodedChanges(encoded: incrementalData)
        } catch {
            fatalError("Bad Data!")
        }
    }
    
    private func saveExistingChangesBeforeApplyingRemote(_ documentMO: DocumentMO) throws {
        if let changes = try handles[documentMO.objectID]?.save() {
            let incremental = IncrementalMO(context: viewContext)
            incremental.data = changes
            documentMO.addToIncrementals(incremental)
        }
    }

}
