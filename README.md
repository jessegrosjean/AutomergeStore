# AutomergeStore

---

Need two types of observation on store:

First, must see all inserts/deletes of Workspaces and Chunks. This is used to update internal state of open document handles. This is used to schedule new CKSyncEngine operations.

Second, must publish valid workspaces in store. A valid workspace must contain an index document. When sync is happening it's possible for a workspace to be invalid... we get notification of the workspace zone being inserted, but don't yet have index document. Use NSFetchedResultsController for this?

---

Conflict free local first storage backed by Automerge. Stored locally in CoreData. Optionally synced with CloudKit using CKSyncEngine.

### Why would you use this?

Use this package to sync generic JSON like data through CloudKit with efficient sync and automatic conflic resolution. I think this is a good base to also support sharing synced data with other users through CKShares, though I have not implemented that.

### Setup instructions

1. Ensure you are logged into your developer account in Xcode with an active membership.
2. In the “Signing & Capabilities” tab of the Automerge target, ensure your team is selected in the Signing section, and there is a valid container selected under the “iCloud” section.
2. Ensure that all devices are logged into the same iCloud account.

#### Using your own iCloud container

- Create a new iCloud container through Xcode’s “Signing & Capabilities” tab of the SyncEngine app target.
- Update the `CKContainer` in ContentView.swift with your new iCloud container identifier.

### How would you use this in code?

```
// Create a store
let store = try AutomergeStore()
// Create a workspace in that store
let workspace = try store.newWorkspace()
// Each workspace has an index Automerge.Document that we can edit...
try workspace.index.automerge.put(obj: .ROOT, key: "count", value: .Counter(1))
```

Each store contains workspaces. Each workspace contains at least one (`workspace.index`) automerge document, and potentially more. The intention is that a workspace maps to a user level document. Use the `workspace.index` document for main document content. Potentially add other documents to the workspace for state (like attachments) that you don't always need to load into memory.

```
AutomergeStore
    workspaces: [Workspace]
Workspace
    id: UUID
    documents: [Document]
Document
    id: UUID
    automerge: Automerge.Document
```

You can create, open, and delete workspace. You can create and open documents. You can't delete documents. Each automerge document maintains full edit history. Since workspaces don't allow deleting documents, they also maintain full edit history of all included documents.

## Implementation

The storage model is different then the API model and looks like this:

```
AutomergeStore (CKDatabase when synced to CloudKit)
    workspaces: [Workspace]
Workspace (CKRecordZone when synced to CloudKit)
    id: UUID
    chunks: [Chunk]
Chunk (CKRecord when synced to CloudKit)
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


---

Only operations that matter:

WorkspaceZone
    insert
    delete

ChunkCKRecord
    insert
    delete - Only used for compaction, or when containing workspace is deleted. Anytime a chunk is deleted it must first have been combined to create a new snapshot chunk.
