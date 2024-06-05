import CloudKit
import os.log

extension CKRecord.RecordType {
    static let chunkRecordType = "Chunk"
}

extension CKRecord.FieldKey {
    static let heads = "heads"
    static let isDelta = "isDelta"
    static let document = "document"
    static let data = "data"
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
            if let record = cloudKitRecords.prepareChunkRecordForSend(id: recordID, automergeStore: automergeStore) {
                return record
            } else {
                // record no longer exists locally, probably deleted
                syncEngine.state.remove(pendingRecordZoneChanges: [ .saveRecord(recordID) ])
                return nil
            }
        }
        
        Logger.automergeCloudKit.info("nextRecordZoneChangeBatch with \(batch?.recordsToSave.count ?? 0) saves/edits and \(batch?.recordIDsToDelete.count ?? 0) removals")
        
        return batch
    }
    
    // Apply changes to storage
    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let stateUpdate):
            handleStateUpdate(stateUpdate)
        case .accountChange(let accountChange):
            handleAccountChange(accountChange)
        case .fetchedDatabaseChanges(let fetchedDatabaseChanges):
            handleFetchedDatabaseChanges(fetchedDatabaseChanges)
        case .fetchedRecordZoneChanges(let fetchedRecordZoneChanges):
            handleFetchedRecordZoneChanges(fetchedRecordZoneChanges)
        case .sentDatabaseChanges(let sentDatabaseChanges):
            handleSentDatabaseChanges(sentDatabaseChanges)
        case .sentRecordZoneChanges(let sentRecordZoneChanges):
            handleSentRecordZoneChanges(sentRecordZoneChanges)
        case .willFetchChanges:
            break
        case .willFetchRecordZoneChanges:
            break
        case .didFetchRecordZoneChanges:
            break
        case .didFetchChanges:
            break
        case .willSendChanges:
            break
        case .didSendChanges:
            break
        @unknown default:
            Logger.automergeCloudKit.error("Received unknown event: \(event)")
        }
    }

    func handleStateUpdate(_ stateUpdate: CKSyncEngine.Event.StateUpdate) {
        // Don't save until
        do {
            try cloudKitRecords.viewContext.save()
            syncEngineState = stateUpdate.stateSerialization
        } catch {
            Logger.automergeCloudKit.error("Failed to save cloudkit records, skipping save of sync engine state")
        }
    }

    // Handle workspace zone create/delete
    func handleFetchedDatabaseChanges(_ fetchedDatabaseChanges: CKSyncEngine.Event.FetchedDatabaseChanges) {
        for modification in fetchedDatabaseChanges.modifications {
            
            let workspaceId = modification.zoneID.zoneName
            if let workspaceId = UUID(uuidString: workspaceId) {
                if (try? automergeStore.fetchWorkspace(id: workspaceId)) == nil {
                    //automergeStore.newWorkspace()
                }
            }
            // create workspace if needed
        }
        
        for deletion in fetchedDatabaseChanges.deletions {
            let workspaceId = deletion.zoneID.zoneName
            do {
                Logger.automergeCloudKit.info("Deleting workspace \(workspaceId)")
                if let workspaceId = UUID(uuidString: workspaceId), let workspaceMO = try? automergeStore.fetchWorkspace(id: workspaceId) {
                    try automergeStore.deleteWorkspace(id: workspaceId)
                }
            } catch {
                Logger.automergeCloudKit.error("Error deleting workspace \(workspaceId), error: \(error)")
            }
            
        }
    }
    
    // Handle document zone create/delete
    func handleFetchedRecordZoneChanges(_ fetchedRecordZoneChanges: CKSyncEngine.Event.FetchedRecordZoneChanges) {
        for modification in fetchedRecordZoneChanges.modifications {
            let record = modification.record
            let recordType = record.recordType
            
            if recordType == .chunkRecordType {
                let recordId = record.recordID
                let workspaceId = recordId.zoneID.zoneName
                // create and apply if doesn't already exist
            } else {
                // unexpected
            }
        }
        
        for deletion in fetchedRecordZoneChanges.deletions {
            let recordType = deletion.recordType

            if recordType == .chunkRecordType {
                let recordId = deletion.recordID
                // delete if needed
            } else {
                // unexpected
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
        // This is a simplistic approach and can loose data in some cases, such as logging
        // out before all data has synced to server. This is not a big problem in our
        // (UI/NS)Document based design since we still always have a copy of the data
        // stored in the document file.
        
        let shouldDeleteLocalData: Bool
        let shouldReUploadLocalData: Bool
        
        switch accountChange.changeType {
        case .signIn:
            shouldDeleteLocalData = false
            shouldReUploadLocalData = true
            
        case .switchAccounts:
            shouldDeleteLocalData = true
            shouldReUploadLocalData = false
            
        case .signOut:
            shouldDeleteLocalData = true
            shouldReUploadLocalData = false
            
        @unknown default:
            Logger.automergeCloudKit.error("Unknown account change type: \(accountChange)")
            shouldDeleteLocalData = false
            shouldReUploadLocalData = false
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
