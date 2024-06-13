import CloudKit
import os.log

extension AutomergeStore {
    
    public enum Activity {
        case fetching
        case sending
        case waiting
    }

    public struct SyncConfiguration: Sendable {
        let container: CKContainer
        let database: CKDatabase
        let automaticallySync: Bool
    }

    struct Sync {
        let engine: CKSyncEngine
        let configuration: SyncConfiguration
    }
    
    func initSyncEngineWithConfiguration(_ syncConfiguration: SyncConfiguration) {
        let syncEngine = try! transaction { t in
            Logger.automergeCloudKit.info("􀇂 Initializing CloudKit sync engine.")
            var configuration = CKSyncEngine.Configuration(
                database: syncConfiguration.container.privateCloudDatabase,
                stateSerialization: t.context.syncState,
                delegate: self
            )
            configuration.automaticallySync = syncConfiguration.automaticallySync
            return CKSyncEngine(configuration)
        }
        sync = .init(engine: syncEngine, configuration: syncConfiguration)
    }

    func fetchChunk(id: UUID) -> ChunkMO? {
        context.fetchChunk(id: id)
    }
    
    func preparedRecord(id: CKRecord.ID) -> CKRecord? {
        guard let chunkId = UUID(uuidString: id.recordName) else {
            return nil
        }
        return context.fetchChunk(id: chunkId)?.preparedRecord(id: id)
    }
    
    func deleteLocalData() async throws {
        try transaction { t in
            t.context.syncState = nil
            for workspaceMO in try t.context.fetch(WorkspaceMO.fetchRequest()) {
                t.context.delete(workspaceMO)
            }
        }
        if let sync {
            initSyncEngineWithConfiguration(sync.configuration)
        }
    }
    
    func deleteServerData() async throws {
        guard let sync else {
            return
        }
        
        let workspaceZones = workspaceMOs.value.map { $0.zoneID }
        sync.engine.state.add(pendingDatabaseChanges: workspaceZones.map { .deleteZone($0) })
        try await sync.engine.sendChanges()
    }
    
    func reuploadLocalData() async throws {
        guard let sync else {
            return
        }

        var databaseChanges: [CKSyncEngine.PendingDatabaseChange] = []
        var recordChanges: [CKSyncEngine.PendingRecordZoneChange] = []
        
        for workspaceMO in try context.fetch(WorkspaceMO.fetchRequest()) {
            databaseChanges.append(.saveZone(.init(zoneID: workspaceMO.zoneID)))
            for chunkMO in workspaceMO.chunks as! Set<ChunkMO> {
                recordChanges.append(.saveRecord(chunkMO.recordID))
            }
        }
        
        sync.engine.state.add(pendingDatabaseChanges: databaseChanges)
        sync.engine.state.add(pendingRecordZoneChanges: recordChanges)
    }
    
}

extension AutomergeStore: CKSyncEngineDelegate {
    
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
            syncActivity.send(.fetching)
        case .fetchedDatabaseChanges(let fetchedDatabaseChanges):
            Logger.automergeCloudKit.info("􀇂 fetchedDatabaseChanges")
            handleFetchedDatabaseChanges(fetchedDatabaseChanges)
        case .didFetchChanges:
            Logger.automergeCloudKit.info("􀇂 didFetchChanges")
            syncActivity.send(.waiting)

        // Fetch record changes
        case .willFetchRecordZoneChanges:
            Logger.automergeCloudKit.info("􀇂 willFetchRecordZoneChanges")
            syncActivity.send(.fetching)
        case .fetchedRecordZoneChanges(let fetchedRecordZoneChanges):
            Logger.automergeCloudKit.info("􀇂 fetchedRecordZoneChanges")
            handleFetchedRecordZoneChanges(fetchedRecordZoneChanges)
        case .didFetchRecordZoneChanges:
            Logger.automergeCloudKit.info("􀇂 didFetchRecordZoneChanges")
            syncActivity.send(.waiting)

        // Send database and record changes
        case .willSendChanges:
            Logger.automergeCloudKit.info("􀇂 willSendChanges")
            syncActivity.send(.sending)
        case .sentDatabaseChanges(let sentDatabaseChanges):
            Logger.automergeCloudKit.info("􀇂 sentDatabaseChanges")
            handleSentDatabaseChanges(sentDatabaseChanges)
        case .sentRecordZoneChanges(let sentRecordZoneChanges):
            Logger.automergeCloudKit.info("􀇂 sentRecordZoneChanges")
            handleSentRecordZoneChanges(sentRecordZoneChanges)
        case .didSendChanges:
            Logger.automergeCloudKit.info("􀇂 didSendChanges")
            syncActivity.send(.waiting)

        @unknown default:
            Logger.automergeCloudKit.info("􀇂 Received unknown event: \(event)")
        }
    }
    
    func handleStateUpdate(_ stateUpdate: CKSyncEngine.Event.StateUpdate) {
        do {
            try transaction { $0.context.syncState = stateUpdate.stateSerialization }
        } catch {
            Logger.automergeCloudKit.error("􀇂 Failed to save sync engine state")
        }
    }

    // Handle workspace zone create/delete
    func handleFetchedDatabaseChanges(_ fetchedDatabaseChanges: CKSyncEngine.Event.FetchedDatabaseChanges) {
        context.performAndWait {
            for modification in fetchedDatabaseChanges.modifications {
                if let workspaceId = UUID(uuidString: modification.zoneID.zoneName) {
                    Logger.automergeCloudKit.info("􀇂 Saving workspace \(workspaceId)")
                    let _ = context.fetchWorkspace(id: workspaceId) ?? WorkspaceMO(
                        context: context,
                        id: workspaceId,
                        index: nil
                    )
                }
            }

            for deletion in fetchedDatabaseChanges.deletions {
                if let workspaceId = UUID(uuidString: deletion.zoneID.zoneName) {
                    Logger.automergeCloudKit.info("􀇂 Deleting workspace \(workspaceId)")
                    if let workspaceMO = context.fetchWorkspace(id: workspaceId) {
                        context.delete(workspaceMO)
                    }
                }
            }
        }
    }
    
    // Handle chunk record create/delete
    func handleFetchedRecordZoneChanges(_ fetchedRecordZoneChanges: CKSyncEngine.Event.FetchedRecordZoneChanges) {
        context.performAndWait {
            for modification in fetchedRecordZoneChanges.modifications {
                let record = modification.record
                let recordType = record.recordType
                
                if recordType == .chunkRecordType {
                    let recordId = modification.record.recordID
                    
                    Logger.automergeCloudKit.info("􀇂 Modifying chunk \(recordId)")
                    
                    guard
                        let chunkId = UUID(uuidString: recordId.recordName),
                        !self.context.containsChunk(id: chunkId), // if we already have chunk nothing to do
                        let workspaceId = UUID(uuidString: recordId.zoneID.zoneName),
                        let workspaceMO = self.context.fetchWorkspace(id: workspaceId)
                    else {
                        continue
                    }
                    
                    do {
                        workspaceMO.addToChunks(try .init(
                            context: self.context,
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
                        let chunkMO = self.context.fetchChunk(id: chunkId)
                    else {
                        continue
                    }
                    
                    self.context.delete(chunkMO)
                }
            }
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
            
        Task {
            do {
                if shouldDeleteLocalData {
                    try await deleteLocalData()
                }
                
                if shouldReUploadLocalData {
                    try await reuploadLocalData()
                }
            } catch {
                assertionFailure("Now what?")
            }
        }
    }
    
}
