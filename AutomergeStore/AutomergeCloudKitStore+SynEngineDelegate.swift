import CloudKit
import os.log

extension CKRecord.RecordType {
    static let chunkRecordType = "Chunk"
}

extension CKRecord.FieldKey {
    // ChunkID and WorkspaceID encoded in CKRecord.ID
    static let documentId = "documentId"
    static let isSnapshot = "isSnapshot"
    static let data = "data"
    static let asset = "asset"
}

extension AutomergeCloudKitStore: CKSyncEngineDelegate {
    
    // Read changes from storage
    public func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        let batch = await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { recordID -> CKRecord? in
            guard
                let chunkId = UUID(uuidString: recordID.recordName),
                let chunkMO = automergeStore.fetchChunk(id: chunkId)
            else {
                // record no longer exists locally, probably deleted
                syncEngine.state.remove(pendingRecordZoneChanges: [ .saveRecord(recordID) ])
                return nil
            }
            return chunkMO.preparedRecord(id: recordID)
        }
        
        Logger.automergeCloudKit.info("􀇂 nextRecordZoneChangeBatch with \(batch?.recordsToSave.count ?? 0) saves/edits and \(batch?.recordIDsToDelete.count ?? 0) removals")
        
        return batch
    }
    
    // Apply changes to storage
    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let stateUpdate):
            Logger.automergeCloudKit.info("􀇂 stateUpdate")
            handleStateUpdate(stateUpdate)
        case .accountChange(let accountChange):
            Logger.automergeCloudKit.info("􀇂 accountChange")
            handleAccountChange(accountChange)
        case .fetchedDatabaseChanges(let fetchedDatabaseChanges):
            Logger.automergeCloudKit.info("􀇂 fetchedDatabaseChanges")
            handleFetchedDatabaseChanges(fetchedDatabaseChanges)
        case .fetchedRecordZoneChanges(let fetchedRecordZoneChanges):
            Logger.automergeCloudKit.info("􀇂 fetchedRecordZoneChanges")
            handleFetchedRecordZoneChanges(fetchedRecordZoneChanges)
        case .sentDatabaseChanges(let sentDatabaseChanges):
            Logger.automergeCloudKit.info("􀇂 sentDatabaseChanges")
            handleSentDatabaseChanges(sentDatabaseChanges)
        case .sentRecordZoneChanges(let sentRecordZoneChanges):
            Logger.automergeCloudKit.info("􀇂 sentRecordZoneChanges")
            handleSentRecordZoneChanges(sentRecordZoneChanges)
        case .willFetchChanges:
            Logger.automergeCloudKit.info("􀇂 willFetchChanges")
            processingSyncEngineChanges = true
        case .willFetchRecordZoneChanges:
            Logger.automergeCloudKit.info("􀇂 willFetchRecordZoneChanges")
        case .didFetchRecordZoneChanges:
            Logger.automergeCloudKit.info("􀇂 didFetchRecordZoneChanges")
        case .didFetchChanges:
            Logger.automergeCloudKit.info("􀇂 didFetchChanges")
            processingSyncEngineChanges = false
        case .willSendChanges:
            Logger.automergeCloudKit.info("􀇂 willSendChanges")
        case .didSendChanges:
            Logger.automergeCloudKit.info("􀇂 didSendChanges")
        @unknown default:
            Logger.automergeCloudKit.info("􀇂 Received unknown event: \(event)")
        }
    }

    func handleStateUpdate(_ stateUpdate: CKSyncEngine.Event.StateUpdate) {
        do {
            try automergeStore.commitChanges()
            syncEngineState = stateUpdate.stateSerialization
        } catch {
            Logger.automergeCloudKit.error("􀇂 Failed to save cloudkit records, skipping save of sync engine state")
        }
    }

    // Handle workspace zone create/delete
    func handleFetchedDatabaseChanges(_ fetchedDatabaseChanges: CKSyncEngine.Event.FetchedDatabaseChanges) {
        for modification in fetchedDatabaseChanges.modifications {
            if let workspaceId = UUID(uuidString: modification.zoneID.zoneName) {
                do {
                    Logger.automergeCloudKit.info("􀇂 Saving workspace \(workspaceId)")
                    if !automergeStore.contains(workspaceId: workspaceId) {
                        try automergeStore.importWorkspace(id: workspaceId, index: nil)
                    }
                } catch {
                    Logger.automergeCloudKit.error("􀇂 Error saving workspace \(workspaceId), error: \(error)")
                }
            }
        }
        
        for deletion in fetchedDatabaseChanges.deletions {
            if let workspaceId = UUID(uuidString: deletion.zoneID.zoneName) {
                do {
                    Logger.automergeCloudKit.info("􀇂 Deleting workspace \(workspaceId)")
                    if automergeStore.contains(workspaceId: workspaceId) {
                        try automergeStore.deleteWorkspace(id: workspaceId)
                    }
                } catch {
                    Logger.automergeCloudKit.error("􀇂 Error deleting workspace \(workspaceId), error: \(error)")
                }
            }
        }
    }
    
    // Handle document zone create/delete
    func handleFetchedRecordZoneChanges(_ fetchedRecordZoneChanges: CKSyncEngine.Event.FetchedRecordZoneChanges) {
        for modification in fetchedRecordZoneChanges.modifications {
            let record = modification.record
            let recordType = record.recordType
            
            if recordType == .chunkRecordType {
                let recordId = modification.record.recordID

                Logger.automergeCloudKit.info("􀇂 Modifying chunk \(recordId)")

                guard 
                    let chunkId = UUID(uuidString: recordId.recordName),
                    !automergeStore.containsChunk(id: chunkId),
                    let workspaceId = UUID(uuidString: recordId.zoneID.zoneName),
                    let workspaceMO = automergeStore.fetchWorkspace(id: workspaceId)
                else {
                    continue
                }

                do {
                    workspaceMO.addToChunks(try .init(
                        context: automergeStore.context,
                        record: record
                    ))
                } catch {
                    Logger.automergeCloudKit.error("􀇂 Failed to decode chunk record \(error)")
                }
            }
        }
        
        for deletion in fetchedRecordZoneChanges.deletions {
            let recordType = deletion.recordType

            if recordType == .chunkRecordType {
                let recordId = deletion.recordID
                
                Logger.automergeCloudKit.info("􀇂 Deleting chunk \(recordId)")

                guard
                    let chunkId = UUID(uuidString: recordId.recordName),
                    let chunkMO = automergeStore.fetchChunk(id: chunkId) 
                else {
                    continue
                }
                
                automergeStore.context.delete(chunkMO)
            }
        }
    }
    
    func handleSentDatabaseChanges(_ sentDatabaseChanges: CKSyncEngine.Event.SentDatabaseChanges) {
        for failedZoneSave in sentDatabaseChanges.failedZoneSaves {
            fatalError("\(failedZoneSave)")
        }
        
        for failedZoneDelete in sentDatabaseChanges.failedZoneDeletes {
            fatalError("\(failedZoneDelete)")
        }
    }
    
    func handleSentRecordZoneChanges(_ sentRecordZoneChanges: CKSyncEngine.Event.SentRecordZoneChanges) {
        
        /*
        var newPendingRecordZoneChanges = [CKSyncEngine.PendingRecordZoneChange]()
        var newPendingDatabaseChanges = [CKSyncEngine.PendingDatabaseChange]()
        
        for failedRecordSave in sentRecordZoneChanges.failedRecordSaves {
            let failedRecord = failedRecordSave.record
            let recordId = failedRecord.recordID
            
            switch failedRecordSave.error.code {
            case .serverRecordChanged:
                // Generally user conflicts should never happen. Maybe possible if when creating
                // copies of unsynced changes and then syncing both copies. Safe to just delete
                // local then.
                
                guard let serverRecord = failedRecordSave.error.serverRecord else {
                    Logger.automergeCloudKit.error("No server record for conflict \(failedRecordSave.error)")
                    continue
                }
                handleCreateOrModifyRecord(serverRecord)
                newPendingRecordZoneChanges.append(.saveRecord(failedRecord.recordID))
                
            case .zoneNotFound:
                let zone = CKRecordZone(zoneID: failedRecord.recordID.zoneID)
                newPendingDatabaseChanges.append(.saveZone(zone))
                newPendingRecordZoneChanges.append(.saveRecord(failedRecord.recordID))
                removeRecord(id: recordId)
                
            case .unknownItem:
                // Record no longer exists on the server, must have been deleted by another client. Delete locally
                // removeRecord(id: recordId)
                // should also delete assocaited snapshot/incrmental... but that will eventually happen thorugh other means?
                
            case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable, .notAuthenticated, .operationCancelled:
                Logger.automergeCloudKit.debug("Retryable error saving \(failedRecord.recordID): \(failedRecordSave.error)")
                
            default:
                Logger.automergeCloudKit.fault("Unknown error saving record \(failedRecord.recordID): \(failedRecordSave.error)")
            }
        }
        */
    }
    
    func handleAccountChange(_ accountChange: CKSyncEngine.Event.AccountChange) {
        var shouldDeleteLocalData = false
        var shouldReUploadLocalData = false
        
        switch accountChange.changeType {
        case .signIn(_):
            // Options:
            // - Merge the local data with the newly-signed-in account's data.
            // - Keep the local data separate from cloud-synced data (e.g. a separate "local account").
            // - Delete the local data.
            // - Prompt the user to make the decision.
            shouldReUploadLocalData = true
        case .signOut(_):
            shouldDeleteLocalData = true // danger!
        case .switchAccounts(_, _):
            shouldDeleteLocalData = true // danger!
        @unknown default:
            Logger.automergeCloudKit.error("􀇂 Unknown account change type: \(accountChange)")
        }
            
        do {
            if shouldDeleteLocalData {
                try deleteLocalData()
            }
            
            if shouldReUploadLocalData {
                try reuploadLocalData()
            }
        } catch {
            assertionFailure("Now what?")
        }
    }
    
}
