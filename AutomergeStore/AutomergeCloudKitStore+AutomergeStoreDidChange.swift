import Foundation
import Automerge
import CoreData
import CloudKit
import os.log

extension AutomergeCloudKitStore {
    
    func automergeStoreManagedObjectContextObjectsDidChange(_ notification: Notification) {
        if let objects = notification.userInfo?[NSInsertedObjectsKey] as? NSSet {
            for each in objects {
                if let chunkMO = each as? ChunkMO {
                    syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(chunkMO.recordID)])
                } else if let workspaceMO = each as? WorkspaceMO {
                    syncEngine.state.add(pendingDatabaseChanges: [.saveZone(.init(zoneID: workspaceMO.zoneID))])
                }
            }
        }
        
        if let objects = notification.userInfo?[NSUpdatedObjectsKey] as? NSSet {
            for each in objects {
                if let _ = each as? ChunkMO {
                    // ignorable
                } else if let _ = each as? WorkspaceMO {
                    // ignorable
                }
            }
        }
        
        if let objects = notification.userInfo?[NSDeletedObjectsKey] as? NSSet {
            for each in objects {
                if let chunkMO = each as? ChunkMO {
                    syncEngine.state.add(pendingRecordZoneChanges: [.deleteRecord(chunkMO.recordID)])
                } else if let workspaceMO = each as? WorkspaceMO {
                    syncEngine.state.add(pendingDatabaseChanges: [.deleteZone(workspaceMO.zoneID)])
                }
            }
        }
    }

}
