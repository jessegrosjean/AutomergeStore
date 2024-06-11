import SwiftUI
import Combine
import CloudKit

extension ContentView {
    @Observable
    class ViewModel {
        
        var workspaceIds: [AutomergeStore.WorkspaceId] = []
        var activity: AutomergeCloudKitStore.Activity = .waiting

        var cancellables: Set<AnyCancellable> = []
        
        private var automergeStore: AutomergeStore?
        private var automergeCloudKit: AutomergeCloudKitStore?

        init() {
            Task {
                let container: CKContainer = CKContainer(identifier: "iCloud.com.hogbaysoftware.AutomergeStore.testing")
                let automergeStore = try AutomergeStore()

                self.automergeStore = automergeStore
                self.automergeCloudKit = try await .init(
                    container: container,
                    database: container.privateCloudDatabase,
                    automergeStore: automergeStore
                )
                
                self.automergeStore!.$workspaceIds
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] ids in
                        self?.workspaceIds = ids
                    }.store(in: &cancellables)
                
                self.automergeCloudKit!.activityPublisher
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] activity in
                        self?.activity = activity
                    }.store(in: &cancellables)
            }
        }
    }
}

extension ContentView.ViewModel {

    public func newWorkspace() throws -> AutomergeStore.Workspace {
        try automergeStore!.newWorkspace()
    }

    public func openWorkspace(id: AutomergeStore.WorkspaceId) throws -> AutomergeStore.Workspace {
        try automergeStore!.openWorkspace(id: id)
    }

    public func deleteWorkspaces(_ workspaceIds: [AutomergeStore.WorkspaceId]) throws {
        try automergeStore!.transaction {
            for each in workspaceIds {
                try $0.deleteWorkspace(id: each)
            }
        }
    }
    
}
