import Foundation
import CoreData
import CloudKit
import Combine
import Automerge
import os.log

@MainActor
public final class AutomergeStore: ObservableObject {
    
    public static let automergeStoreDidChange = Notification.Name("automergeStoreDidChange")

    public struct StoreDidChangeUserInfoKeys {
        public static let storeUUID = "storeUUID"
        public static let transactions = "transactions"
    }

    public struct Error: Sendable, LocalizedError {
        public var msg: String
        public var errorDescription: String? { "AutomergeStoreError: \(msg)" }

        public init(msg: String) {
            self.msg = msg
        }
    }
    
    @Published public var workspaces: [WorkspaceId : String] = [:]
    @Published public var syncStatus: SyncStatus = .noNetwork

    struct WorkspaceHandle {
        let id: WorkspaceId
        let namePublisher: CurrentValueSubject<String, Never>
        let indexPublisher: CurrentValueSubject<Automerge.Document?, Never>
        func workspace(store: AutomergeStore) -> Workspace {
            .init(
                id: id,
                store: store,
                namePublisher: namePublisher.eraseToAnyPublisher(),
                indexPublisher: indexPublisher.eraseToAnyPublisher()
            )
        }
    }

    struct DocumentHandle {
        let id: DocumentId
        let workspaceId: WorkspaceId
        let automergePublisher: CurrentValueSubject<Automerge.Document?, Never>
        var saved: Set<ChangeHash>
        var automergeSubscription: AnyCancellable
        
        init(
            id: DocumentId,
            workspaceId: WorkspaceId,
            automergePublisher: CurrentValueSubject<Automerge.Document?, Never>,
            automergeSubscription: AnyCancellable
        ) {
            self.id = id
            self.workspaceId = workspaceId
            self.automergePublisher = automergePublisher
            self.saved = automergePublisher.value?.heads() ?? []
            self.automergeSubscription = automergeSubscription
        }
        
        var document: Document {
            .init(
                id: id,
                workspaceId: workspaceId,
                automergePublisher: automergePublisher.eraseToAnyPublisher()
            )
        }

        var hasPendingChanges: Bool {
            guard let automerge = automergePublisher.value else {
                return false
            }
            return automerge.heads() != saved
        }
        
        mutating func savePendingChanges() -> (heads: Set<ChangeHash>, data: Data)? {
            guard
                let automerge = automergePublisher.value,
                automerge.heads() != saved
            else {
                return nil
            }
            
            let newSavedHeads = automerge.heads()
            // Can this really throw if we are sure heads are correct?
            let changes = try! automerge.encodeChangesSince(heads: saved)
            saved = newSavedHeads
            return (newSavedHeads, changes)
        }
        
        mutating func applyExternalChanges(_ data: Data) throws {
            guard let automerge = automergePublisher.value else {
                return
            }
            assert(!hasPendingChanges)
            try automerge.applyEncodedChanges(encoded: data)
            saved = automerge.heads()
        }
        
    }
        
    let cloudKitContainer: CKContainer?
    let cloudKitSyncMonitor: SyncMonitor
    nonisolated public let persistentContainer: NSPersistentCloudKitContainer
    var privatePersistentStore: NSPersistentStore!
    var sharedPersistentStore: NSPersistentStore!
    let historyTokensFolder: URL
    let scheduleSave: PassthroughSubject<Void, Never> = .init()
    var workspaceHandles: [WorkspaceId : WorkspaceHandle] = [:]
    var documentHandles: [DocumentId : DocumentHandle] = [:]
    var cancellables: Set<AnyCancellable> = []
    
    public init(
        url: URL? = nil,
        containerIdentifier: String?
    ) throws {
        let fileManager = FileManager.default
        let baseURL = url ?? NSPersistentContainer.defaultDirectoryURL()
        let (historyTokens, privateStoreFolderURL, sharedStoreFolderURL) = try { () throws -> (URL, URL, URL) in
            let storeFolderURL = baseURL.appendingPathComponent("CoreDataStores")
            let privateStoreFolderURL = storeFolderURL.appendingPathComponent("Private")
            let sharedStoreFolderURL = storeFolderURL.appendingPathComponent("Shared")
            let historyTokensFolder = baseURL.appendingPathComponent("CoreDataHistoryTokens")
            try fileManager.createDirectory(at: historyTokensFolder, withIntermediateDirectories: true, attributes: nil)
            for folderURL in [privateStoreFolderURL, sharedStoreFolderURL] where !fileManager.fileExists(atPath: folderURL.path) {
                try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)
            }
            return (historyTokensFolder, privateStoreFolderURL, sharedStoreFolderURL)
        }()
        
        historyTokensFolder = historyTokens
        cloudKitContainer = containerIdentifier.map { .init(identifier: $0) }
        persistentContainer = NSPersistentCloudKitContainer(
            name: "AutomergeStore",
            managedObjectModel: try Self.model(name: "AutomergeStore")
        )
               
        cloudKitSyncMonitor = .init(persistentContainer: persistentContainer)
        
        guard
            let privateStoreDescription = persistentContainer.persistentStoreDescriptions.first,
            let sharedStoreDescription = privateStoreDescription.copy() as? NSPersistentStoreDescription
        else {
            fatalError("#\(#function): Failed to retrieve a persistent store descriptions")
        }
        
        privateStoreDescription.url = privateStoreFolderURL.appendingPathComponent("private.sqlite")
        privateStoreDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        privateStoreDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        
        sharedStoreDescription.url = sharedStoreFolderURL.appendingPathComponent("shared.sqlite")
        sharedStoreDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        sharedStoreDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        if let containerIdentifier {
            privateStoreDescription.cloudKitContainerOptions = .init(containerIdentifier: containerIdentifier, databaseScope: .private)
            sharedStoreDescription.cloudKitContainerOptions = .init(containerIdentifier: containerIdentifier, databaseScope: .shared)
        } else {
            privateStoreDescription.cloudKitContainerOptions = nil
            sharedStoreDescription.cloudKitContainerOptions = nil
        }
        
        persistentContainer.persistentStoreDescriptions.append(sharedStoreDescription)
        
        persistentContainer.loadPersistentStores { [weak self] (loadedStoreDescription, error) in
            guard let self else {
                return
            }
            
            guard error == nil else {
                fatalError("#\(#function): Failed to load persistent stores:\(error!)")
            }
            
            let storeURL = loadedStoreDescription.url!
            let storeLastPathComponent = storeURL.lastPathComponent

            if storeLastPathComponent.hasSuffix("private.sqlite") {
                privatePersistentStore = persistentContainer.persistentStoreCoordinator.persistentStore(for: storeURL)
            } else if storeLastPathComponent.hasSuffix("shared.sqlite") {
                sharedPersistentStore = persistentContainer.persistentStoreCoordinator.persistentStore(for: storeURL)
            }
        }

        persistentContainer.viewContext.mergePolicy = NSMergePolicyType.mergeByPropertyObjectTrumpMergePolicyType
        persistentContainer.viewContext.automaticallyMergesChangesFromParent = true
        persistentContainer.viewContext.transactionAuthor = TransactionAuthor.appViewContext
                
        do {
          try persistentContainer.viewContext.setQueryGenerationFrom(.current)
        } catch {
          fatalError("Failed to pin viewContext to the current generation: \(error)")
        }
        
        initAutosave()
        initSyncStatus()
        initTransationProcessing()
        
        /*
        #if DEBUG
        do {
            try persistentContainer.initializeCloudKitSchema(options: [])
        } catch {
            Logger.automergeStore.error("􀳃 Failed initializeCloudKitSchema: \(error)")
        }
        #endif
        */
    }
    
    var viewContext: NSManagedObjectContext { persistentContainer.viewContext }

    public var automergeStoreDidChangePublisher: Publishers.ReceiveOn<NotificationCenter.Publisher, DispatchQueue> {
        NotificationCenter.default.publisher(for: Self.automergeStoreDidChange, object: self).receive(on: DispatchQueue.main)
    }

}

extension AutomergeStore {
    
    private static var cachedManagedObjectModel: NSManagedObjectModel?

    private static func model(name: String) throws -> NSManagedObjectModel {
        if cachedManagedObjectModel == nil {
            cachedManagedObjectModel = try loadModel(name: name, bundle: Bundle.main)
        }
        return cachedManagedObjectModel!
    }
    
    private static func loadModel(name: String, bundle: Bundle) throws -> NSManagedObjectModel {
        guard let modelURL = bundle.url(forResource: name, withExtension: "momd") else {
            fatalError("failed find momd of name \(name)")
        }
        
        guard let model = NSManagedObjectModel(contentsOf: modelURL) else {
            fatalError("failed to load \(modelURL)")
        }
        
        return model
    }
    
}

extension NSPersistentCloudKitContainerOptions {
    
    public convenience init(containerIdentifier: String, databaseScope: CKDatabase.Scope = .private) {
        self.init(containerIdentifier: containerIdentifier)
        self.databaseScope = databaseScope
    }
    
}
