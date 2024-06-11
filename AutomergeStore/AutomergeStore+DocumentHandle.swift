import Foundation
import Automerge
import Combine

extension AutomergeStore {
    
    struct DocumentHandle {
        
        let workspaceId: WorkspaceId
        let automerge: Automerge.Document
        var saved: Set<ChangeHash>
        var automergeSubscription: AnyCancellable
        
        init(workspaceId: WorkspaceId, automerge: Automerge.Document, automergeSubscription: AnyCancellable) {
            self.workspaceId = workspaceId
            self.automerge = automerge
            self.saved = automerge.heads()
            self.automergeSubscription = automergeSubscription
        }
        
        mutating func save() -> (heads: Set<ChangeHash>, data: Data)? {
            guard automerge.heads() != saved else {
                return nil
            }
            let newSavedHeads = automerge.heads()
            // Can this really throw if we are sure heads are correct?
            let changes = try! automerge.encodeChangesSince(heads: saved)
            saved = newSavedHeads
            return (newSavedHeads, changes)
        }
    }
    
}
