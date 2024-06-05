# AutomergeStore

Workspace Alternative... documents can contain other documents

DocumentMO
    uuid: UUID
    chunks: [ChunkMO]
    parent: DocumentMO?
    children: [DocumentMO]

ChunkMO
    uuid: UUID
    isDelta: Bool
    owner: DocumentMO
    data: Data

Neet idea, but I don't know that I like this. With workspaces we can setup rules such as they retain all history... can't delete a document, but can delete a workspace. Also it's easy to find all documents contained in a workspace, harder if documents contain other documents.






Workspace Thinking

Unit of sharing is Workspace, not document
    - Workspace might be something fancy like a file directory ui with many documents.
    - But Workspace might represent just a single document to user, but since using workspace that single document can be backed by multiple other documents. For example might have a main document that is a text, and then other attachment documents. Or might have main document that is Book, but that's just a list of Chapter documents. 

- Workspace is used to group documents, but should have little API of it's own. It's just a document container and a way to access a well known index document that is in the container.
- Don't need way to observe all documents in workspace, that tracking should be done by index document and observed there.
- Don't allow deleting documents from workspace, workspace should maintain full history.
- Do allow deleting workspaces
- Stop using managed object IDs, instead use UUIDs for documents. Then can be sure that IDs can be used outside of coredata and also don't have to worry about temporary distinction.
- DataModel should be NO conflicts. Don't store document or workspace name... that info should be stored in conflict free workspace index.
 
NSDocument
    - Based of Workspace model (so N Automerge.Document with one special index document)
    - Not based on AutomergeStore, instead uses file wrapper storage
    - Each document is stored as data (no incrementals) with UUID filename.
    - Also includes metadata plist in wrapper, which stores index UUID
    The "magic" part:
        - When loads document it looks at existing AutomergeStore and looks for matching document (that is being synced to icloude). It merges in any changes and then uses AutomergeStore's Automerge.Document instance.
        - So NSDocument is not dependent on AutomergeStore state, but if it finds matching state then it will use that state and automatically sync.
        -   
    
