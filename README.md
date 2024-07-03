# AutomergeStore

(work in progress)

Conflict free and local first storage. Implemented using Automerge, CoreData, and CloudKit.

### Why would you use this?

Use this package to sync generic JSON like data through CloudKit with incremental sync and automatic conflict resolution. Use to sync data between different devices owned by the same iCloud account. Also use to share synced data between multiple iCloud users.

### Setup instructions

1. Ensure you are logged into your developer account in Xcode with an active membership.
2. In the “Signing & Capabilities” tab of the Automerge target, ensure your team is selected in the Signing section, and there is a valid container selected under the “iCloud” section.
2. Ensure that all devices are logged into the same iCloud account.

#### Using your own iCloud container

- Create a new iCloud container through Xcode’s “Signing & Capabilities” tab of the SyncEngine app target.
- Update the `CKContainer` in ContentView.swift with your new iCloud container identifier.

### How would you use this in code?

```
// @MainActor
// Create a store
let store = try AutomergeStore(containerIdentifier: "iCloud.your.container.identifier")
// Create a workspace in that store
let workspace = try store.newWorkspace(name: "test")
// Each workspace has an index Automerge.Document that we can edit...
try workspace.index?.put(obj: .ROOT, key: "count", value: .Counter(1))
```

Each store contains workspaces. Each workspace contains at least one (`workspace.index`) automerge document, and potentially others. The intention is that a workspace maps to a user level document. Use the `workspace.index` document for main document content. Potentially add other documents to the workspace for state (like attachments) that you don't always need to load into memory.

```
AutomergeStore
    workspaces: [Workspace]
Workspace
    id: UUID
    index: Automerge.Document?
    documents: [Document]
Document
    id: UUID
    automerge: Automerge.Document
```

You can create, open, and delete workspace. You can create and open documents. You can't delete documents. Each automerge document maintains full edit history. Since workspaces don't allow deleting documents, they also maintain full edit history of all included documents.

## Implementation

The implementation uses CoreData/[NSPersistentCloudKitContainer](https://developer.apple.com/documentation/technotes/tn3163-understanding-the-synchronization-of-nspersistentcloudkitcontainer)/CloudKit to store and sync the data. It uses [Automerge](https://github.com/automerge/automerge-swift) to combine/merge that data.

The storage model is different then the API model and looks like this:

```
AutomergeStore (CKDatabase when synced to CloudKit)
    workspaces: [Workspace]
Workspace
    id: UUID
    name: String
    chunks: [Chunk]
Chunk
    id: UUID
    documentId: UUID
    isSnapshot: Bool
    data: Data
```

A workspace contains chunks. Each Chunk has a documentId. There can be more then one chunk with the same documentId. When opening a document:

1. Find all Chunks with that documentId
2. At least one Chunk must have isSnapshot == true, otherwise open fails
3. Create a new Automerge.Document from that snapshot chunk. Then merge in the data from the other matching chunks into the document.

When you make changes to the returned Automerge.Document the store saves a new chunk that contains just those most recent changes. This new chunk has isSnapshot == false. Periodically the store will combine all the Chunks with the same documentId into a single compressed isSnapshot == true Chunk.

Things to notice:

- As you make changes they are stored in small "delta" chunks. These are fast to sync to CloudKit and to apply to other clients.

- Chunks are created or deleted, but never modified. Chunks are only deleted after they are first merged into a new snapshot chunk. Workspaces are grow only data structures and contain a full history of edits.

- The special "index" document associated with each workspace is composed of the set of chunks whose documentId == the workspaces workspaceId.

- A workspace always has an associated index document, but in Swift the document is optional. This is because when syncing a workspace to a new device it might be that the workspace record syncs before the index chunk record. So it should be that "eventually" every workspace will have an index document, but it might be nil if it hasn't synced yet.

## Realtime Sync Notes (Future maybe)

CloudKit does not do realtime/collaboration sync well. In my testing it does the sync "correctly", but the timing varies widely. From a second or two, to just not syncing for a while.

I've come to the conclusion that if you want realtime/collaboration style sync, you will need to use a side channel that delivers sync messages faster. My thought for how to do this is:

- When a computer opens a workspace
- add it's active "participant" information to the workspace
- watch the workspaces for other active participants and create peer to peer sync between them
- In this scenario CoreData/CloudKit is still the source of truth and persistence, the peer to peer is just a way to get sync state distribuated faster.
- This would mean that CoreData/CloudKit would be syncing some duplicate state, but Automerge is designed to handle that.

## NSDocument Notes (Future maybe)

This example implements "shoebox" style storage.

Question: how to integrate this if you want to use NSDocument storage model instead?

Thoughts:

- Each NSDocument should represent a single workspace
- Maybe workspace serialization is uses file wrapper storage, not AutomergeStore
- In anycase must make sure to save WorkspaceId
- The "magic" part:
    - When loads document it looks at default existing AutomergeStore and looks for matching document (that is being synced to iCloud). It merges in any changes and then uses AutomergeStore's Automerge.Document instance.
    - So NSDocument is not dependent on AutomergeStore state, but if it finds matching state then it will use that state and automatically sync.
