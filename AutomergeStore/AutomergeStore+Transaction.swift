import os.log
import Automerge
import CoreData
import Combine

extension AutomergeStore {

    public class Transaction {

        public typealias Workspace = AutomergeStore.Workspace
        public typealias WorkspaceId = AutomergeStore.WorkspaceId
        public typealias Document = AutomergeStore.Document
        public typealias DocumentId = AutomergeStore.DocumentId
        public typealias Error = AutomergeStore.Error

        let context: NSManagedObjectContext
        let scheduleSave: PassthroughSubject<Void, Never>
        var documentHandles: [DocumentId : Handle]
        var workspaceIds: Set<WorkspaceId>
        
        init(
            context: NSManagedObjectContext,
            scheduleSave: PassthroughSubject<Void, Never>,
            documentHandles: [DocumentId : Handle],
            workspaceIds: Set<WorkspaceId>
        ) {
            self.context = context
            self.scheduleSave = scheduleSave
            self.documentHandles = documentHandles
            self.workspaceIds = workspaceIds
        }
        
    }
    
    public var inTransaction: Bool {
        transaction > 0
    }
    
    public func beginTransaction() {
        transaction += 1
    }
    
    public func endTransaction() throws {
        transaction -= 1
        if transaction == 0 {
            if context.hasChanges {
                Logger.automergeStore.info("􀳃 Committing transaction")
                try context.save()
                let temp = transactionSuccesCallbacks
                transactionSuccesCallbacks.removeAll()
                transactionRollbackCallbacks.removeAll()
                temp.forEach { $0() }
            }
        }
    }

    public enum TransactionType {
        case view
        case background
    }
    
    public func transaction<R>(
        type: TransactionType = .view,
        _ closure: (Transaction) throws -> R
    ) throws -> R {
        
        let context =  type == .view ? container.viewContext : container.newBackgroundContext()
        
        let transaction = Transaction(
            context: context,
            scheduleSave: scheduleSave,
            documentHandles: documentHandles,
            workspaceIds: Set(workspaceIds)
        )
        
        return try context.performAndWait {
            do {
                let result = try closure(transaction)
                let hasChanges = context.hasChanges
                if hasChanges {
                    try context.save()
                }
                documentHandles = transaction.documentHandles
                if hasChanges {
                    // recompute workspace ids?
                }
                return result
            } catch {
                context.rollback()
                throw error
            }
        }        
    }
    
    public func transaction<R>(
        _ closure: () throws -> R,
        onSuccess: (() -> ())? = nil,
        onRollback: (() -> ())? = nil
    ) throws -> R {
        if let onSuccess {
            transactionSuccesCallbacks.append(onSuccess)
        }
        
        if let onRollback {
            transactionRollbackCallbacks.append(onRollback)
        }
        
        do {
            beginTransaction()
            let r = try closure()
            try endTransaction()
            return r
        } catch {
            context.rollback()
            let temp = transactionRollbackCallbacks
            transactionRollbackCallbacks.removeAll()
            transactionSuccesCallbacks.removeAll()
            temp.forEach { $0() }
            throw error
        }
    }

    public func commitChanges(force: Bool = false) throws {
        try saveDocumentChanges()
                
        if context.hasChanges || force {
            Logger.automergeStore.info("􀳃 Saving changes")
            try context.save()
        }
    }

}
