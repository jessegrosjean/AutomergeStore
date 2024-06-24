import SwiftUI
import Combine
import CloudKit

extension ContentView {

    @MainActor
    @Observable
    final class ViewModel {
        
        var workspaces: [AutomergeStore.WorkspaceId : String] = [:]
        var workspaceIds: [AutomergeStore.WorkspaceId] = []
        var syncStatus: AutomergeStore.SyncStatus = .noNetwork
        var cancellables: Set<AnyCancellable> = []
        var error: Error?
        
        private var automergeStore: AutomergeStore

        init() {
            automergeStore = AppDelegate.store
            //automergeStore = try! AutomergeStore(containerIdentifier: "iCloud.com.hogbaysoftware.AutomergeStore")
            
            automergeStore.$workspaces.sink { [weak self] workspaces in
                self?.workspaces = workspaces
                self?.workspaceIds = workspaces.keys.sorted()
            }.store(in: &cancellables)

            automergeStore.$syncStatus
                .receive(on: DispatchQueue.main)
                .sink { [weak self] cloudStatus in
                    self?.syncStatus = cloudStatus
                }.store(in: &cancellables)
        }
    }
}

extension ContentView.ViewModel {

    public func isShared(workspaceId: AutomergeStore.WorkspaceId) -> Bool {
        automergeStore.isShared(workspaceId: workspaceId)
    }
    
    public func newWorkspace(name: String) -> AutomergeStore.Workspace? {
        do {
            return try automergeStore.newWorkspace(name: name)
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
            for each in workspaceIds {
                try automergeStore.deleteWorkspace(id: each)
            }
        } catch {
            self.error = error
        }
    }

}
