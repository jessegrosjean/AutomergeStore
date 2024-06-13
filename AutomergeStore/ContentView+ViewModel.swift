import SwiftUI
import Combine
import CloudKit

extension ContentView {

    @MainActor
    @Observable
    class ViewModel {
        
        var workspaceIds: [AutomergeStore.WorkspaceId] = []
        var activity: AutomergeStore.Activity = .waiting
        var cancellables: Set<AnyCancellable> = []
        
        private var automergeStore: AutomergeStore?

        init() {
            Task {
                //let container = CKContainer(identifier: "iCloud.com.hogbaysoftware.AutomergeStore")
                let automergeStore = try await AutomergeStore()

                self.automergeStore = automergeStore
                //self.automergeCloudKit = try await .init(
                //    container: container,
                //    database: container.privateCloudDatabase,
                //    automergeStore: automergeStore
                //)
                
                /*await MainActor.run {
                    automergeStore.$workspaceIds
                        .sink { [weak self] ids in
                            self?.workspaceIds = ids
                        }.store(in: &cancellables)
                }*/
                
                /*self.automergeCloudKit!.activityPublisher
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] activity in
                        self?.activity = activity
                    }.store(in: &cancellables)*/
            }
        }
    }
}

extension ContentView.ViewModel {

    public func newWorkspace() {
        Task {
            do {
                _ = try await automergeStore?.newWorkspace()
            } catch {
            }
        }
    }

    public func openWorkspace(id: AutomergeStore.WorkspaceId) {
        Task {
            do {
                return try await automergeStore?.openWorkspace(id: id)
            } catch {
                return nil
            }
        }
    }

    public func deleteWorkspaces(_ workspaceIds: [AutomergeStore.WorkspaceId]) {
        Task {
            do {
                try await automergeStore?.transaction{ t in
                    for each in workspaceIds {
                        try t.deleteWorkspace(id: each)
                    }
                }
            } catch {
            }
        }
    }

}
