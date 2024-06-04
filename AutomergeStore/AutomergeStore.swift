import Combine
import CoreData
import Automerge
import os.log
import PersistentHistoryTrackingKit

extension URL {
    public static let devNull = URL(fileURLWithPath: "/dev/null")
}

public final class AutomergeStore: ObservableObject {
        
    public typealias DocumentId = NSManagedObjectID
    
    public struct Document: Identifiable {
        public let id: DocumentId
        public let doc: Automerge.Document
    }
    
    public struct PersistentHistoryOptions {
        public let appGroup: String?
        public let author: String
        public let allAuthors: [String]
    }

    @Published public var documentIds: [DocumentId] = []
        
    let container: NSPersistentContainer
    let persistentHistoryTracking: PersistentHistoryTrackingKit?
    var viewContext: NSManagedObjectContext { container.viewContext }

    var handles: [DocumentId : Handle] = [:]
    var scheduleSaveChanges: PassthroughSubject<Void, Never> = .init()
    var pendingContextInsertions: PendingContextInsertions = .init()
    var cancellables: Set<AnyCancellable> = []
    
    public init(url: URL? = nil, persistentHistoryOptions: PersistentHistoryOptions? = nil) throws {
        //container = NSPersistentContainer(name: "AutomergeStore")
        container = NSPersistentCloudKitContainer(name: "AutomergeStore")
        
        let storeDescription = container.persistentStoreDescriptions.first!
        
        if let url {
            storeDescription.url = url
        }
        
        if let _ = persistentHistoryOptions {
            storeDescription.setOption(
                true as NSNumber,
                forKey: NSPersistentHistoryTrackingKey
            )
            storeDescription.setOption(
                true as NSNumber,
                forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey
            )
        }
        
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                /*
                 Typical reasons for an error here include:
                 * The parent directory does not exist, cannot be created, or disallows writing.
                 * The persistent store is not accessible, due to permissions or data protection when the device is locked.
                 * The device is out of space.
                 * The store could not be migrated to the current model version.
                 Check the error message to determine what the actual problem was.
                 */
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
        
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        if let persistentHistoryOptions {
            container.viewContext.transactionAuthor = persistentHistoryOptions.author
            persistentHistoryTracking = .init(
                container: container,
                currentAuthor: persistentHistoryOptions.author,
                allAuthors: persistentHistoryOptions.allAuthors,
                userDefaults: persistentHistoryOptions.appGroup.map { UserDefaults(suiteName: $0)! }  ?? UserDefaults.standard,
                cleanStrategy: .byNotification(times: 1),
                uniqueString: "AutomergeStore.",
                autoStart: true
            )
        } else {
            persistentHistoryTracking = nil
        }

        documentIds = try! viewContext.fetch(DocumentMO.fetchRequest()).map { $0.objectID }
        
        scheduleSaveChanges
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] in
                do {
                    try self?.saveDocumentChanges()
                } catch {
                    print(error)
                }
            }.store(in: &cancellables)

        NotificationCenter.default.publisher(
            for: NSManagedObjectContext.didChangeObjectsNotification,
            object: viewContext
        ).sink { [weak self] notification in
            self?.managedObjectContextObjectsDidChange(notification)
        }.store(in: &cancellables)
    }
        
    public func newDocument(_ document: Automerge.Document = .init()) throws -> Document  {
        let documentMO = DocumentMO(context: viewContext)
        let snapshotMO = SnapshotMO(context: viewContext)
        snapshotMO.data = document.save()
        documentMO.addToSnapshots(snapshotMO)
        documentMO.created = .now
        try viewContext.save()
        let id = documentMO.objectID
        createHandle(id: id, document: document, documentMO: documentMO)
        return .init(id: id, doc: document)
    }
    
    public func openDocument(id: DocumentId) throws -> Document? {
        if let document = handles[id]?.document {
            return .init(id: id, doc: document)
        }
        
        guard let documentMO = try viewContext.existingObject(with: id) as? DocumentMO else {
            return nil
        }
        
        var document: Automerge.Document?
        
        for each in documentMO.snapshots ?? [] {
            if let snapshotData = (each as? SnapshotMO)?.data {
                if let document {
                    try document.applyEncodedChanges(encoded: snapshotData)
                } else {
                    document = try .init(snapshotData)
                }
            }
        }

        guard let document else {
            // Expect to find at least one snapshot, else nil
            return nil
        }

        for each in documentMO.incrementals ?? [] {
            if let incrementalData = (each as? IncrementalMO)?.data {
                try document.applyEncodedChanges(encoded: incrementalData)
            }
        }
        
        createHandle(id: id, document: document, documentMO: documentMO)
        
        return .init(id: id, doc: document)
    }
    
    public func closeDocument(id: DocumentId, storingChanges: Bool = true) throws {
        if storingChanges {
            try storeDocumentChanges(id: id)
        }
        try dropHandle(id: id)
    }
    
    public func deleteDocument(id: DocumentId) throws {
        handles.removeValue(forKey: id)
        if let documentMO = try viewContext.existingObject(with: id) as? DocumentMO {
            viewContext.delete(documentMO)
            try viewContext.save()
        }
    }

    public func storeDocumentChanges(id documentId: DocumentId? = nil) throws {
        for eachId in handles.keys {
            if
                documentId == nil || documentId == eachId,
                let changes = try handles[eachId]?.save()
            {
                if let documentMO = try viewContext.existingObject(with: eachId) as? DocumentMO {
                    Logger.automergeStore.info("􀳃 Storing document changes \(documentMO.objectID.uriRepresentation())")                    
                    let incrementalMO = IncrementalMO(context: viewContext)
                    incrementalMO.data = changes
                    incrementalMO.byteCount = Int32(changes.count)
                    documentMO.addToIncrementals(incrementalMO)
                    snapshotDocumentChangesIfNeeded(documentMO: documentMO)
                }
            }
        }
    }

    public func saveDocumentChanges() throws {
        try storeDocumentChanges()
        
        if viewContext.hasChanges {
            try viewContext.save()
        }
    }

}

extension AutomergeStore {
    
    struct Handle {
        let document: Automerge.Document
        var saved: Set<ChangeHash>
        var subscriptions: Set<AnyCancellable>
        
        init(document: Automerge.Document, subscriptions: Set<AnyCancellable>) {
            self.document = document
            self.saved = document.heads()
            self.subscriptions = subscriptions
        }
        
        mutating func save() throws -> Data? {
            guard document.heads() != saved else {
                return nil
            }
            let changes = try document.encodeChangesSince(heads: saved)
            saved = document.heads()
            return changes
        }
    }
    
    func createHandle(id: DocumentId, document: Automerge.Document, documentMO: DocumentMO) {
        var documentSubscriptions: Set<AnyCancellable> = []

        document.objectWillChange.sink { [weak self] in
            self?.scheduleSaveChanges.send()
        }.store(in: &documentSubscriptions)
        
        handles[id] = .init(
            document: document,
            subscriptions: documentSubscriptions
        )
    }

    func dropHandle(id: DocumentId) throws {
        handles.removeValue(forKey: id)
    }
    
    func snapshotDocumentChangesIfNeeded(documentMO: DocumentMO) {
        guard
            let document = handles[documentMO.objectID]?.document,
            let incrementals = documentMO.incrementals,
            let snapshotBytes = documentMO.snapshots?.reduce(0, { $0 + ($1 as! SnapshotMO).byteCount }),
            let incrementalsBytes = documentMO.incrementals?.reduce(0, { $0 + ($1 as! IncrementalMO).byteCount }),
            incrementalsBytes > (snapshotBytes / 2)
        else {
            return
        }
        
        Logger.automergeStore.info("􀳃 Snapshotting document \(documentMO.objectID.uriRepresentation())")
        
        let cdLatestSnapshot = SnapshotMO(context: viewContext)
        let cdData = document.save()
        
        cdLatestSnapshot.data = cdData
        cdLatestSnapshot.byteCount = Int32(cdData.count)
        documentMO.addToSnapshots(cdLatestSnapshot)
        
        for each in documentMO.snapshots ?? [] {
            if let each = each as? SnapshotMO, each !== cdLatestSnapshot {
                documentMO.removeFromSnapshots(each)
                viewContext.delete(each)
            }
        }
        
        for each in incrementals {
            if let each = each as? IncrementalMO {
                documentMO.removeFromIncrementals(each)
                viewContext.delete(each)
            }
        }
    }

}

extension AutomergeStore {

    public struct Error: Sendable, LocalizedError {
        public var msg: String
        public var errorDescription: String? { "AutomergeStoreError: \(msg)" }

        public init(msg: String) {
            self.msg = msg
        }
    }

}
