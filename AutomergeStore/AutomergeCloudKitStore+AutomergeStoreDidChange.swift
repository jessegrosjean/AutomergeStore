import Foundation
import Automerge
import CoreData
import CloudKit
import os.log

extension AutomergeCloudKitStore {
    
    func automergeStoreManagedObjectContextObjectsDidChange(_ notification: Notification) {
        guard !processingSyncEngineChanges else {
            return
        }
        
        if let objects = notification.userInfo?[NSInsertedObjectsKey] as? NSSet {
            for each in objects {
                if let chunkMO = each as? ChunkMO {
                    Logger.automergeCloudKit.info("􀇂 scheduleSaveChunkRecord \(chunkMO.recordID)")
                    syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(chunkMO.recordID)])
                } else if let workspaceMO = each as? WorkspaceMO {
                    Logger.automergeCloudKit.info("􀇂 scheduleSaveWorkspaceZone \(workspaceMO.zoneID)")
                    syncEngine.state.add(pendingDatabaseChanges: [.saveZone(.init(zoneID: workspaceMO.zoneID))])
                }
            }
        }
                
        if let objects = notification.userInfo?[NSDeletedObjectsKey] as? NSSet {
            for each in objects {
                if let chunkMO = each as? ChunkMO {
                    Logger.automergeCloudKit.info("􀇂 scheduleDeleteChunkRecord \(chunkMO.recordID)")
                    syncEngine.state.add(pendingRecordZoneChanges: [.deleteRecord(chunkMO.recordID)])
                } else if let workspaceMO = each as? WorkspaceMO {
                    Logger.automergeCloudKit.info("􀇂 scheduleDeleteWorkspaceZone \(workspaceMO.zoneID)")
                    syncEngine.state.add(pendingDatabaseChanges: [.deleteZone(workspaceMO.zoneID)])
                }
            }
        }
    }

}
