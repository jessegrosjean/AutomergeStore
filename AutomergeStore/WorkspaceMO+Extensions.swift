import Foundation
import Automerge
import CoreData
import CloudKit

extension WorkspaceMO {
    
    public convenience init(
        context: NSManagedObjectContext,
        id: UUID = .init(),
        index: Automerge.Document?
    ) {
        self.init(context: context)
        self.id = id

        if let index {
            addToChunks(ChunkMO(
                context: context,
                documentId: id,
                isSnapshot: true,
                data: index.save())
            )
        }
    }
    
    var zoneID: CKRecordZone.ID {
        .init(zoneName: id!.uuidString)
    }

    var hasValidIndex: Bool {
        // Because CKSyncEngine will create workspace zone before sending chunks.
        // Because it will send chunks over time, so need to make sure index snapshot is present
        // before indicating that workspace is valid.
        for each in (chunks as? Set<ChunkMO>) ?? [] {
            if each.documentId == id, each.isSnapshot {
                return true
            }
        }
        return false
    }
    
}
