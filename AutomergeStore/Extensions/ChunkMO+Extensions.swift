import Foundation
import CoreData

extension ChunkMO {
    
    convenience init(
        context: NSManagedObjectContext,
        workspaceId: UUID,
        documentId: UUID,
        isSnapshot: Bool,
        data: Data
    ) {
        self.init(context: context)
        self.id = .init()
        self.workspaceId = workspaceId
        self.documentId = documentId
        self.isSnapshot = isSnapshot
        self.data = data
        self.size = Int64(data.count)
    }

}
