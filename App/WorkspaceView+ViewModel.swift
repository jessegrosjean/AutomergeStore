import SwiftUI
import Combine
import Automerge
import CloudKit

extension WorkspaceView {
    
    @MainActor
    @Observable
    final class ViewModel {
        
        var count: Int = 0
        var isShared = false
        var share: CKShare?
        var shareParticipants: [CKShare.Participant]?

        let workspace: AutomergeStore.Workspace
        var cancellables: Set<AnyCancellable> = []
        var documentCancelable: AnyCancellable?

        init(workspace: AutomergeStore.Workspace) {
            self.workspace = workspace
            self.workspace.indexPublisher.sink { [weak self] document in
                self?.index = document
            }.store(in: &cancellables)
            
            refreshSharing()
            self.workspace.store?.automergeStoreDidChangePublisher.sink { [weak self] _ in
                self?.refreshSharing()
            }.store(in: &cancellables)
        }
        
        var index: Automerge.Document? {
            didSet {
                refreshCount()
                documentCancelable = index?
                    .objectWillChange
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] in
                        self?.refreshCount()
                    }
            }
        }
        
        func increment() {
            adjust(delta: 1)
        }
        
        func descrement() {
            adjust(delta: -1)
        }
        
        func adjust(delta: Int) {
            guard let index = index else {
                return
            }
            if case .Scalar(.Counter) = try? index.get(obj: .ROOT, key: "count") {
                // Good, we have counter
            } else {
                try? index.put(obj: .ROOT, key: "count", value: .Counter(0))
            }
            try? index.increment(obj: .ROOT, key: "count", by: Int64(delta))
        }

        func createShare() {
            Task {
                try await workspace.store?.createShare()
            }
        }

        func editShare(_ share: CKShare) {
            workspace.store?.presentCloudSharingController(share: share)
        }

        func deleteShare(_ share: CKShare) {
            workspace.store?.deleteShare(share, keepingContent: true)
        }

        func refreshCount() {
            guard let index = self.index else {
                self.count = 0
                return
            }
            
            if case .Scalar(.Counter(let count)) = try? index.get(obj: .ROOT, key: "count") {
                self.count = Int(count)
            } else {
                self.count = 0
            }
        }
        
        func refreshSharing() {
            self.isShared = workspace.store?.isShared(workspaceId: workspace.id) ?? false
            self.share = try? workspace.store?.shares(matching: [workspace.id]).values.first
            self.shareParticipants = workspace.store?.participants(for: workspace.id)
        }

    }
    
}
