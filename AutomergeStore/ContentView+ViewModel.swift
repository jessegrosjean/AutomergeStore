import SwiftUI
import Combine
import CloudKit

extension ContentView {

    @MainActor
    @Observable
    class ViewModel {
        
        var workspaceIds: [AutomergeStore.WorkspaceId] = []
        var cancellables: Set<AnyCancellable> = []
        var error: Error?
        
        private var automergeStore: AutomergeStore

        init() {
            automergeStore = try! AutomergeStore(containerOptions: .init(
                containerIdentifier: "iCloud.com.hogbaysoftware.AutomergeStore",
                databaseScope: .private
            ))
            
            automergeStore.workspaceIdsPublisher.sink { [weak self] workspaceIds in
                self?.workspaceIds = workspaceIds.sorted()
            }.store(in: &cancellables)
        }
    }
}

extension ContentView.ViewModel {

    public func newWorkspace() -> AutomergeStore.Workspace? {
        do {
            return try automergeStore.newWorkspace()
        } catch {
            self.error = error
            return nil
        }
    }

    public func openWorkspace(id: AutomergeStore.WorkspaceId) -> AutomergeStore.Workspace? {
        guard automergeStore.contains(workspaceId: id) else {
            return nil
        }
        do {
            return try automergeStore.openWorkspace(id: id)
        } catch {
            self.error = error
            return nil
        }
    }

    public func deleteWorkspaces(_ workspaceIds: [AutomergeStore.WorkspaceId]) {
        do {
            try automergeStore.transaction{ t in
                for each in workspaceIds {
                    try t.deleteWorkspace(id: each)
                }
            }
        } catch {
            self.error = error
        }
    }

}
