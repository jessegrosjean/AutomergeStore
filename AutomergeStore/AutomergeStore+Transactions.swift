import CoreData
import Combine
import os.log

extension AutomergeStore {

    struct TransactionAuthor {
        static let appViewContext = "appViewContext"
        static let appBackgroundContext = "appBackgroundContext"
    }

    func initTransationProcessing() {
        let fetchRequest = WorkspaceMO.fetchRequest()
        fetchRequest.affectedStores = [privatePersistentStore, sharedPersistentStore]
        fetchRequest.propertiesToFetch = ["id", "name"]
        let workspaceMOs = (try? viewContext.fetch(fetchRequest)) ?? []
        
        
        // Got a dup here after sharing?
        // Maybe same workspace ends up in private and shared stores?
        
        workspaces = .init(uniqueKeysWithValues: workspaceMOs.compactMap {
            guard let id = $0.id, let name = $0.name else {
                return nil
            }
            return (id, name)
        })
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(storeRemoteChange(_:)),
            name: .NSPersistentStoreRemoteChange,
            object: persistentContainer.persistentStoreCoordinator
        )
    }
    
    
    @objc func storeRemoteChange(_ notification: Notification) {
        guard
            let storeUUID = notification.userInfo?[NSStoreUUIDKey] as? String,
            let store: NSPersistentStore = {
                if privatePersistentStore.identifier == storeUUID {
                    return privatePersistentStore
                } else if sharedPersistentStore.identifier == storeUUID {
                    return sharedPersistentStore
                } else {
                    return nil
                }
            }()
        else {
            return
        }
        
        let fetchContext = persistentContainer.newTaskContext()
        let transactions = fetchContext.performAndWait {
            fetchTransactions(store: store, context: fetchContext, historyTokenFolder: historyTokensFolder)
        }
        
        NotificationCenter.default.post(
            name: Self.automergeStoreDidChange,
            object: self,
            userInfo: [
                StoreDidChangeUserInfoKeys.storeUUID: storeUUID,
                StoreDidChangeUserInfoKeys.transactions: transactions
            ]
        )
        
        Task {
            await MainActor.run {
                self.processTransactions(transactions)
            }
        }
    }
    
    private func processTransactions(_ transactions: [NSPersistentHistoryTransaction]) {
        let workspaceEntityName = WorkspaceMO.entity().name
        let chunkEntityName = ChunkMO.entity().name

        for transaction in transactions {
            for change in transaction.changes ?? [] {
                if change.changedObjectID.entity.name == workspaceEntityName {
                    processWorkspaceChange(change)
                } else if change.changedObjectID.entity.name == chunkEntityName {
                    processChunkChange(change)
                }
            }
        }
        
        if viewContext.hasChanges {
            try! viewContext.save()
        }
    }
    
    private func processWorkspaceChange(_ change: NSPersistentHistoryChange) {
        switch change.changeType {
        case .insert:
            if let workspaceMO = viewContext.fetchWorkspace(id: change.changedObjectID), let id = workspaceMO.id {
                workspaces[id] = workspaceMO.name ?? ""
            }
        case .update:
            let workspaceEntity = WorkspaceMO.entity()
            let workspaceIdProperty = workspaceEntity.propertiesByName["id"]!
            let workspaceNameProperty = workspaceEntity.propertiesByName["name"]!
            let updatedProperties = change.updatedProperties ?? []
            if updatedProperties.contains(workspaceIdProperty) || updatedProperties.contains(workspaceNameProperty) {
                if let workspaceMO = viewContext.fetchWorkspace(id: change.changedObjectID), let id = workspaceMO.id {
                    workspaces[id] = workspaceMO.name ?? ""
                }

            }
        case .delete:
            if let id = change.tombstone?["id"] as? UUID {
                // TODO: Check if workspace has any changes. If it does clone to a new workspace
                try? closeWorkspace(id: id, saveChanges: false)
                workspaces.removeValue(forKey: id)
            }
        @unknown default:
            break
        }
    }

    private func processChunkChange(_ change: NSPersistentHistoryChange) {
        // Only want to apply chunks that we did not create outselves. If we skipped this
        // step things would still work since applying chunks is idempotent. This check is
        // just to skip some work.
        guard change.transaction?.author != TransactionAuthor.appViewContext else {
            return
        }
        
        switch change.changeType {
        case .insert:
            applyChunkToOpenDocument(viewContext.object(with: change.changedObjectID) as? ChunkMO)
        case .update:
            // I think its possible for cloudkit to insert a chunk, but don't insert data yet.
            // So watch for case where documentId or data changes (expected change from nil >
            // value, never value > value) and apply in that case.
            let chunkEntity = ChunkMO.entity()
            let chunkDocumentIdProperty = chunkEntity.propertiesByName["documentId"]!
            let chunkDataProperty = chunkEntity.propertiesByName["data"]!

            guard
                let updatedProperties = change.updatedProperties,
                updatedProperties.contains(chunkDocumentIdProperty) ||
                updatedProperties.contains(chunkDataProperty)
            else {
                return
            }
            
            applyChunkToOpenDocument(viewContext.object(with: change.changedObjectID) as? ChunkMO)
        case .delete:
            // Chunks are only deleted when entire worksapce is deleted or when they have
            // already been combined into a larger chunk. So safe to ignore deletion, will
            // never effect open documents.
            break
        default:
            break
        }
    }
    
    private func applyChunkToOpenDocument(_ chunkMO: ChunkMO?) {
        guard
            let documentId = chunkMO?.documentId,
            let handle = documentHandles[documentId],
            let chunkData = chunkMO?.data
        else {
            return
        }
        
        if handle.hasPendingChanges {
            insertPendingChanges(documentId: documentId)
        }
    
        do {
            try documentHandles[documentId]?.applyExternalChanges(chunkData)
        } catch {
            Logger.automergeStore.error("􀳃 Failed to apply chunk to open document: \(error)")
        }
    }
    
    private func insertPendingChanges(documentId: DocumentId) {
        guard
            let workspaceId = documentHandles[documentId]?.workspaceId,
            let (_, changes) = documentHandles[documentId]?.savePendingChanges(),
            let workspaceMO = viewContext.fetchWorkspace(id: workspaceId)
        else {
            return
        }
        workspaceMO.addToChunks(ChunkMO(
            context: viewContext,
            workspaceId: workspaceMO.id!,
            documentId: documentId,
            isSnapshot: false,
            data: changes
        ))
    }
        
}

private func fetchTransactions(
    store: NSPersistentStore,
    context: NSManagedObjectContext,
    historyTokenFolder: URL
) -> [NSPersistentHistoryTransaction] {
    let tokenFile = historyTokenFolder.appendingPathComponent(store.identifier)
    let tokenData = try? Data(contentsOf: tokenFile)
    let token = tokenData.map { try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSPersistentHistoryToken.self, from: $0) } ?? nil
    let request = NSPersistentHistoryChangeRequest.fetchHistory(after: token)
    let historyFetchRequest = NSPersistentHistoryTransaction.fetchRequest!
    request.fetchRequest = historyFetchRequest
    request.affectedStores = [store]
    
    guard
        let result = (try? context.execute(request)) as? NSPersistentHistoryResult,
        let transactions = result.result as? [NSPersistentHistoryTransaction],
        !transactions.isEmpty
    else {
        return []
    }

    if
        let newToken = transactions.last?.token,
        let newTokenData = try? NSKeyedArchiver.archivedData(withRootObject: newToken, requiringSecureCoding: true)
    {
        try? newTokenData.write(to: tokenFile)
    }
    
    return transactions
}
