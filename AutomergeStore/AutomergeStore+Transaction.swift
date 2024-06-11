import os.log
import Automerge
import CoreData
import Combine
import CloudKit

extension AutomergeStore {

    public class Transaction {

        public typealias Workspace = AutomergeStore.Workspace
        public typealias WorkspaceId = AutomergeStore.WorkspaceId
        public typealias Document = AutomergeStore.Document
        public typealias DocumentId = AutomergeStore.DocumentId
        public typealias Error = AutomergeStore.Error

        let context: NSManagedObjectContext
        let scheduleSave: PassthroughSubject<Void, Never>
        
        var documentHandles: [DocumentId : DocumentHandle]
        
        init(
            context: NSManagedObjectContext,
            scheduleSave: PassthroughSubject<Void, Never>,
            documentHandles: [DocumentId : DocumentHandle],
            workspaceIds: Set<WorkspaceId>
        ) {
            self.context = context
            self.scheduleSave = scheduleSave
            self.documentHandles = documentHandles
        }
        
        var syncState: CKSyncEngine.State.Serialization? {
            get {
                context.syncState
            }
            set {
                Logger.automergeStore.info("􀳃 Storing sync state")
                context.syncState = newValue
            }
        }
        
        func fetchChunk(id: UUID) -> ChunkMO? {
            context.fetchChunk(id: id)
        }

    }

    public func transaction<R>(
        source: String? = nil,
        _ closure: (Transaction) throws -> R
    ) throws -> R {
        return try viewContext.performAndWait {
            do {
                let transaction = Transaction(
                    context: viewContext,
                    scheduleSave: scheduleSave,
                    documentHandles: documentHandles,
                    workspaceIds: Set(workspaceIds)
                )

                let result = try closure(transaction)

                if viewContext.hasChanges {
                    Logger.automergeStore.info("􀳃 Saving transaction")
                    
                    let savedSyncEngine = syncEngine
                    
                    if source == AutomergeCloudKitStore.syncEngineFetchTransactionSource {
                        // Temporarily nil while saving context so that new sync events are not scheduled
                        // on syncEngine when context is being updated in response to fetched sync engine
                        // changes.
                        syncEngine = nil
                    }
                    
                    try viewContext.save()
                    
                    syncEngine = savedSyncEngine
                }
                
                documentHandles = transaction.documentHandles
                
                return result
            } catch {
                Logger.automergeStore.info("􀳃 Transaction rollback")
                viewContext.rollback()
                throw error
            }
        }
    }

}
