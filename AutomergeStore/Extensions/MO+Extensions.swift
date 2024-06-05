import CoreData
import Automerge

extension WorkspaceMO {
    
    public convenience init(context moc: NSManagedObjectContext, index: Automerge.Document = .init()) {
        self.init(context: moc)
        
        self.uuid = UUID()

        let documentMO = DocumentMO(context: moc, document: index)
        documentMO.uuid = uuid
        addToDocuments(documentMO)
    }
    
}

extension DocumentMO {
    
    public convenience init(context moc: NSManagedObjectContext, document: Automerge.Document = .init()) {
        self.init(context: moc)
        
        self.uuid = UUID()

        addToChunks(ChunkMO(
            context: moc,
            heads: document.heads(),
            isDelta: false,
            data: document.save()
        ))
    }
    
}

extension ChunkMO {
    
    public convenience init(context moc: NSManagedObjectContext, heads: Set<ChangeHash>, isDelta: Bool, data: Data) {
        self.init(context: moc)
        
        self.uuid = .init()
        self.heads = heads.stringHash
        self.isDelta = isDelta
        self.data = data
        self.size = Int64(data.count)
    }
    
}

