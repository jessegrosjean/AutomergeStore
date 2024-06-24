import Foundation
import Automerge
import CoreData
import CloudKit

extension WorkspaceMO {
    
    convenience init(
        context: NSManagedObjectContext,
        id: AutomergeStore.WorkspaceId = .init(),
        name: String,
        index: Automerge.Document,
        synced: Bool
    ) {
        self.init(context: context)
        self.id = id
        self.name = name

        addToChunks(ChunkMO(
            context: context,
            workspaceId: id,
            documentId: id,
            isSnapshot: true,
            data: index.save()
        ))
    }
    
}
