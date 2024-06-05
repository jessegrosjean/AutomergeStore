import Combine
import CoreData
import Automerge
import os.log
import PersistentHistoryTrackingKit

public final class AutomergeStore: ObservableObject {
        
    public struct PersistentHistoryOptions {
        public let appGroup: String?
        public let author: String
        public let allAuthors: [String]
    }

    @Published public var workspaceIds: [WorkspaceId] = []

    let container: NSPersistentContainer
    var viewContext: NSManagedObjectContext { container.viewContext }
    let persistentHistoryTracking: PersistentHistoryTrackingKit?

    var documentHandles: [DocumentId : Handle] = [:]
    let workspaceManagedObjects: CurrentValueSubject<[WorkspaceMO], Never> = .init([])
    var scheduleSave: PassthroughSubject<Void, Never> = .init()
    //var pendingContextInsertions: PendingContextInsertions = .init()
    var cancellables: Set<AnyCancellable> = []
    
    public init(url: URL? = nil, persistentHistoryOptions: PersistentHistoryOptions? = nil) throws {
        container = NSPersistentContainer(name: "AutomergeStore")
        
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

        workspaceManagedObjects.value = try viewContext.fetch(WorkspaceMO.fetchRequest())

        scheduleSave
            .debounce(
                for: .milliseconds(500),
                scheduler: DispatchQueue.main
            ).sink { [weak self] in
                do {
                    try self?.saveChanges()
                } catch {
                    print(error)
                }
            }.store(in: &cancellables)

        workspaceManagedObjects.sink { [weak self] workspaceMOs in
            self?.workspaceIds = workspaceMOs.map { $0.uuid! }.sorted()
        }.store(in: &cancellables)
        
        NotificationCenter.default.publisher(
            for: NSManagedObjectContext.didChangeObjectsNotification,
            object: viewContext
        ).sink { [weak self] notification in
            self?.managedObjectContextObjectsDidChange(notification)
        }.store(in: &cancellables)
    }
    
    public func saveChanges() throws {
        try insertPendingDocumentChanges()
        
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
        
        mutating func save() throws -> (heads: Set<ChangeHash>, data: Data)? {
            guard document.heads() != saved else {
                return nil
            }
            let newSavedHeads = document.heads()
            let changes = try document.encodeChangesSince(heads: saved)
            saved = newSavedHeads
            return (newSavedHeads, changes)
        }
    }
    
    func createHandle(id: DocumentId, document: Automerge.Document) {
        var documentSubscriptions: Set<AnyCancellable> = []

        document.objectWillChange.sink { [weak self] in
            self?.scheduleSave.send()
        }.store(in: &documentSubscriptions)
        
        documentHandles[id] = .init(
            document: document,
            subscriptions: documentSubscriptions
        )
    }

    func dropHandle(id: DocumentId) throws {
        documentHandles.removeValue(forKey: id)
    }

}
