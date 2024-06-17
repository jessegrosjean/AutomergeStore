import Foundation
import Automerge
import CoreData

extension WorkspaceMO {
    
    convenience init(
        context: NSManagedObjectContext,
        id: AutomergeStore.WorkspaceId = .init(),
        index: Automerge.Document,
        synced: Bool
    ) {
        self.init(context: context)
        self.id = id

        addToChunks(ChunkMO(
            context: context,
            workspaceId: id,
            documentId: id,
            isSnapshot: true,
            data: index.save()
        ))
    }
    
}
