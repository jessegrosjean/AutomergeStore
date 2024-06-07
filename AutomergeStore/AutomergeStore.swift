import Combine
import CoreData
import Automerge
import CloudKit
import os.log
import PersistentHistoryTrackingKit

// When a transaction fails we can even rollback context and reload document state?
public protocol Transaction {
    
    typealias WorkspaceId = AutomergeStore.WorkspaceId
    typealias Workspace = AutomergeStore.Workspace
    typealias DocumentId = AutomergeStore.DocumentId
    typealias Document = AutomergeStore.Document

    func newWorkspace(index: Automerge.Document) throws -> Workspace
    func openWorkspace(id: WorkspaceId) throws -> Workspace?
    func closeWorkspace(id: WorkspaceId, insertingPendingChanges: Bool) throws
    func deleteWorkspace(id: WorkspaceId) throws
    func importWorkspace(id: WorkspaceId, index: Automerge.Document) throws -> Workspace

    func newDocument(workspaceId: WorkspaceId, document: Automerge.Document) throws -> Document
    func openDocument(workspaceId: WorkspaceId, documentId: DocumentId) throws -> Document?
    func closeDocument(id: DocumentId, insertingPendingChanges: Bool) throws
    func importDocument(workspaceId: WorkspaceId, documentId: DocumentId, document: Automerge.Document) throws -> Document
}

public final class AutomergeStore: ObservableObject {
        
    private static var cachedManagedObjectModel: NSManagedObjectModel?

    public struct PersistentHistoryOptions {
        public let appGroup: String?
        public let author: String
        public let allAuthors: [String]
    }

    @Published public var workspaceIds: [WorkspaceId] = []

    let container: NSPersistentContainer
    var context: NSManagedObjectContext { container.viewContext }
    let persistentHistoryTracking: PersistentHistoryTrackingKit?
    var documentHandles: [DocumentId : Handle] = [:]
    let workspaceManagedObjects: CurrentValueSubject<[WorkspaceMO], Never> = .init([])
    let scheduleSave: PassthroughSubject<Void, Never> = .init()
    var cancellables: Set<AnyCancellable> = []
    var transaction: UInt8 = 0
    var transactionSuccesCallbacks: [()->()] = []
    var transactionRollbackCallbacks: [()->()] = []

    public init(url: URL? = nil, persistentHistoryOptions: PersistentHistoryOptions? = nil) throws {
        container = NSPersistentContainer(
            name: "AutomergeStore",
            managedObjectModel: try! Self.model(name: "AutomergeStore")
        )
        
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

        workspaceManagedObjects.value = try context.fetch(WorkspaceMO.fetchRequest())

        scheduleSave
            .debounce(
                for: .milliseconds(500),
                scheduler: DispatchQueue.main
            ).sink { [weak self] in
                do {
                    try self?.saveDocumentChanges()
                } catch {
                    print(error)
                }
            }.store(in: &cancellables)

        workspaceManagedObjects.sink { [weak self] workspaceMOs in
            self?.workspaceIds = workspaceMOs.compactMap {
                if $0.hasValidIndex {
                    return $0.id
                } else {
                    return nil
                }
            }.sorted()
        }.store(in: &cancellables)
        
        NotificationCenter.default.publisher(
            for: NSManagedObjectContext.didChangeObjectsNotification,
            object: context
        ).sink { [weak self] notification in
            self?.managedObjectContextObjectsDidChange(notification)
        }.store(in: &cancellables)
    }
    
    var synEngineState: CKSyncEngine.State? {
        get {
            nil
        }
        set {
            
        }
    }

}

extension AutomergeStore {
    
    struct Handle {
        
        let workspaceId: WorkspaceId
        let document: Automerge.Document
        var saved: Set<ChangeHash>
        var subscriptions: Set<AnyCancellable>
        
        init(workspaceId: WorkspaceId, document: Automerge.Document, subscriptions: Set<AnyCancellable>) {
            self.workspaceId = workspaceId
            self.document = document
            self.saved = document.heads()
            self.subscriptions = subscriptions
        }
        
        mutating func save() -> (heads: Set<ChangeHash>, data: Data)? {
            guard document.heads() != saved else {
                return nil
            }
            let newSavedHeads = document.heads()
            // Can this really throw if we are sure heads are correct?
            let changes = try! document.encodeChangesSince(heads: saved)
            saved = newSavedHeads
            return (newSavedHeads, changes)
        }
    }
    
    func createHandle(workspaceId: WorkspaceId, documentId: DocumentId, document: Automerge.Document) {
        var documentSubscriptions: Set<AnyCancellable> = []

        document.objectWillChange.sink { [weak self] in
            self?.scheduleSave.send()
        }.store(in: &documentSubscriptions)
        
        documentHandles[documentId] = .init(
            workspaceId: workspaceId,
            document: document,
            subscriptions: documentSubscriptions
        )
    }

    func dropHandle(id: DocumentId) {
        documentHandles.removeValue(forKey: id)
    }

}

extension AutomergeStore {
    
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
