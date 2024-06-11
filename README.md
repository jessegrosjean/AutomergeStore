# AutomergeStore

(In progress)

Conflic free storage backed by Automerge, stored locally in CoreData, and optionally synced with CloudKit using CKSyncEngine.

Each store contains workspaces. Each workspace contains at least one (`workspace.index`), and potentially more automerge documents. The intention is that a workspace maps to a user level document. Use the `workspace.index` document for main document content. Potentially add other documents to the workspace for state (like attachments) that you don't always need to load into memory.

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

You can create, open, and delete workspace. You can create and open documents. You can't delete documents. Automerge documents maintain full edit history. Since workspaces don't allow deleting documents, they also maintain full edit history.


The storage model is different then the API model and looks like this:

```
AutomergeStore (CKDatabase when synced to CloudKit)
    workspaces: [Workspace]
Workspace (CKRecordZone when synced to CloudKit)
    id: UUID
    chunks: [Document]
Chunk (CKRecord when synced to CloudKit)
    id: UUID
    documentId: UUID
    isSnapshot: Bool
    data: Data
```

A workspace contains chunks. Each Chunk has a documentId. There can be more then one chunk with the same documentId. When opening a document:

1. Find all Chunks with that documentId
2. At least one Chunk must have isSnapshot == true, else open fails
3. Create a new Automerge.Document from that snapshot chunk. Then merge in the data from the other matching chunks into the document.

When you make changes to the returned Automerge.Document the store saves a new chunk that just contains those changes (isSnapshot == false). Eventually the store will combine all the Chunks with the same documentId into a single compressed isSnapshot == true Chunk.

Things to notice:

- As you make changes the changes are stored into small "delta" chunks. These are fast to sync to CloudKit and to apply to other clients.

- Chunks are created or deleted, but never modified. And chunks are only deleted after they are first merged into a new snapshot chunk. Workspaces are grow only datastructures and contain a full history of edits.
