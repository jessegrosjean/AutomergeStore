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
        let batch = await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { [weak self] recordID -> CKRecord? in
            guard let record = await self?.preparedRecord(id: recordID) else {
                // record no longer exists locally, probably deleted
                syncEngine.state.remove(pendingRecordZoneChanges: [ .saveRecord(recordID) ])
                return nil
            }
            return record
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

        // Fetch database changes
        case .willFetchChanges:
            Logger.automergeCloudKit.info("􀇂 willFetchChanges")
            activityPublisher.send(.fetching)
        case .fetchedDatabaseChanges(let fetchedDatabaseChanges):
            Logger.automergeCloudKit.info("􀇂 fetchedDatabaseChanges")
            handleFetchedDatabaseChanges(fetchedDatabaseChanges)
        case .didFetchChanges:
            Logger.automergeCloudKit.info("􀇂 didFetchChanges")
            activityPublisher.send(.waiting)

        // Fetch record changes
        case .willFetchRecordZoneChanges:
            Logger.automergeCloudKit.info("􀇂 willFetchRecordZoneChanges")
            activityPublisher.send(.fetching)
        case .fetchedRecordZoneChanges(let fetchedRecordZoneChanges):
            Logger.automergeCloudKit.info("􀇂 fetchedRecordZoneChanges")
            handleFetchedRecordZoneChanges(fetchedRecordZoneChanges)
        case .didFetchRecordZoneChanges:
            Logger.automergeCloudKit.info("􀇂 didFetchRecordZoneChanges")
            activityPublisher.send(.waiting)

        // Send database and record changes
        case .willSendChanges:
            Logger.automergeCloudKit.info("􀇂 willSendChanges")
            activityPublisher.send(.sending)
        case .sentDatabaseChanges(let sentDatabaseChanges):
            Logger.automergeCloudKit.info("􀇂 sentDatabaseChanges")
            handleSentDatabaseChanges(sentDatabaseChanges)
        case .sentRecordZoneChanges(let sentRecordZoneChanges):
            Logger.automergeCloudKit.info("􀇂 sentRecordZoneChanges")
            handleSentRecordZoneChanges(sentRecordZoneChanges)
        case .didSendChanges:
            Logger.automergeCloudKit.info("􀇂 didSendChanges")
            activityPublisher.send(.waiting)

        @unknown default:
            Logger.automergeCloudKit.info("􀇂 Received unknown event: \(event)")
        }
    }

    func handleStateUpdate(_ stateUpdate: CKSyncEngine.Event.StateUpdate) {
        do {
            try automergeStore.transaction { t in
                t.context.syncState = stateUpdate.stateSerialization
            }
        } catch {
            Logger.automergeCloudKit.error("􀇂 Failed to save sync engine state")
        }
    }

    // Handle workspace zone create/delete
    func handleFetchedDatabaseChanges(_ fetchedDatabaseChanges: CKSyncEngine.Event.FetchedDatabaseChanges) {
        do {
            try automergeStore.transaction(source: Self.syncEngineFetchTransactionSource) { t in
                for modification in fetchedDatabaseChanges.modifications {
                    if let workspaceId = UUID(uuidString: modification.zoneID.zoneName) {
                        Logger.automergeCloudKit.info("􀇂 Saving workspace \(workspaceId)")
                        t.importWorkspace(id: workspaceId, index: nil)
                    }
                }
                
                for deletion in fetchedDatabaseChanges.deletions {
                    if let workspaceId = UUID(uuidString: deletion.zoneID.zoneName) {
                        Logger.automergeCloudKit.info("􀇂 Deleting workspace \(workspaceId)")
                        try? t.deleteWorkspace(id: workspaceId) // ignore error, it's already been deleted?
                    }
                }
            }
        } catch {
            Logger.automergeCloudKit.error("􀇂 Error handleFetchedDatabaseChanges error: \(error)")
        }
    }
    
    // Handle document zone create/delete
    func handleFetchedRecordZoneChanges(_ fetchedRecordZoneChanges: CKSyncEngine.Event.FetchedRecordZoneChanges) {
        do {
            try automergeStore.transaction(source: Self.syncEngineFetchTransactionSource) { t in
                for modification in fetchedRecordZoneChanges.modifications {
                    let record = modification.record
                    let recordType = record.recordType
                    
                    if recordType == .chunkRecordType {
                        let recordId = modification.record.recordID

                        Logger.automergeCloudKit.info("􀇂 Modifying chunk \(recordId)")

                        guard
                            let chunkId = UUID(uuidString: recordId.recordName),
                            !t.context.containsChunk(id: chunkId), // if we already have chunk nothing to do
                            let workspaceId = UUID(uuidString: recordId.zoneID.zoneName),
                            let workspaceMO = t.context.fetchWorkspace(id: workspaceId)
                        else {
                            continue
                        }

                        do {
                            workspaceMO.addToChunks(try .init(
                                context: t.context,
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
                            let chunkMO = t.context.fetchChunk(id: chunkId)
                        else {
                            continue
                        }
                        
                        t.context.delete(chunkMO)
                    }
                }
            }
        } catch {
            Logger.automergeCloudKit.error("􀇂 handleFetchedRecordZoneChanges error \(error)")
        }
    }
    
    func handleSentDatabaseChanges(_ sentDatabaseChanges: CKSyncEngine.Event.SentDatabaseChanges) {
        for failedZoneSave in sentDatabaseChanges.failedZoneSaves {
            Logger.automergeCloudKit.error("􀇂 failedZoneSave \(failedZoneSave)")
        }
        
        for (id, error) in sentDatabaseChanges.failedZoneDeletes {
            Logger.automergeCloudKit.error("􀇂 failedZoneDelete \(id)-\(error)")
        }
    }
    
    func handleSentRecordZoneChanges(_ sentRecordZoneChanges: CKSyncEngine.Event.SentRecordZoneChanges) {
        for failedRecordSave in sentRecordZoneChanges.failedRecordSaves {
            Logger.automergeCloudKit.error("􀇂 failedRecordSave \(failedRecordSave)")
        }
        
        for (id, error) in sentRecordZoneChanges.failedRecordDeletes {
            Logger.automergeCloudKit.error("􀇂 failedRecordDelete \(id)-\(error)")
        }
        
        /*
        automergeStore.transaction {
            for savedRecord in sentRecordZoneChanges.savedRecords {
                if
                    let id = UUID(uuidString: savedRecord.recordID.recordName),
                    let chunk = $0.context.fetchChunk(id: id)
                {
                    chunk.setLastKnownRecordIfNewer(savedRecord)
                }
            }
        }
        
        var newPendingRecordZoneChanges = [CKSyncEngine.PendingRecordZoneChange]()
        var newPendingDatabaseChanges = [CKSyncEngine.PendingDatabaseChange]()
        
        for failedRecordSave in sentRecordZoneChanges.failedRecordSaves {
            let failedRecord = failedRecordSave.record
            let recordId = failedRecord.recordID
            
            switch failedRecordSave.error.code {
            case .serverRecordChanged:
                // Chunk are immutable. If same chunk is already on the server we can ignore error
                // and we don't need to reschedule send.
                
                guard let serverRecord = failedRecordSave.error.serverRecord else {
                    Logger.automergeCloudKit.error("􀇂 No server record for conflict \(failedRecordSave.error)")
                    continue
                }
                
                handleCreateOrModifyRecord(serverRecord)
                
            case .zoneNotFound:
                let zone = CKRecordZone(zoneID: failedRecord.recordID.zoneID)
                newPendingDatabaseChanges.append(.saveZone(zone))
                newPendingRecordZoneChanges.append(.saveRecord(failedRecord.recordID))
                removeSyncRecord(id: recordId)
                
            case .unknownItem:
                break
                // Record no longer exists on the server, must have been deleted by another client. Delete locally
                // removeRecord(id: recordId)
                // should also delete assocaited snapshot/incrmental... but that will eventually happen thorugh other means?
                
            case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable, .notAuthenticated, .operationCancelled:
                Logger.automergeCloudKit.info("􀇂 Retryable error saving \(failedRecord.recordID): \(failedRecordSave.error)")
                
            default:
                Logger.automergeCloudKit.error("􀇂 Unknown error saving record \(failedRecord.recordID): \(failedRecordSave.error)")
            }
        }
        
        for failedRecordDelete in sentRecordZoneChanges.failedRecordDeletes {
            
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
