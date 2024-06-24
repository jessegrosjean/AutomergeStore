import Foundation
import os.log

extension AutomergeStore {
    
    func initAutosave() {
        scheduleSave
            .debounce(
                for: .milliseconds(500),
                scheduler: DispatchQueue.main
            ).sink { [weak self] in
                guard let self else {
                    return
                }
                do {
                    if self.documentHandles.values.first(where: { $0.hasPendingChanges }) != nil {
                        Logger.automergeStore.info("􀳃 Autosaving...")
                        try self.insertPendingChanges()
                    }
                } catch {
                    Logger.automergeStore.error("􀳃 Failed to commit autosave transaction \(error)")
                }
            }.store(in: &cancellables)
    }
    
}
