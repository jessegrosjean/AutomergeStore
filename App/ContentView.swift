import SwiftUI
import CoreData
import CloudKit

enum ActiveSheet: Identifiable, Equatable {
    case cloudSharingSheet(CKShare)
    case managingSharesView
    case sharePicker(CKRecord)
    case participantView(CKShare)
    var id: String {
        let mirror = Mirror(reflecting: self)
        if let label = mirror.children.first?.label {
            return label
        } else {
            return "\(self)"
        }
    }
}


@MainActor
struct ContentView: View {

    @State var viewModel = ViewModel()
    @State private var selection = Set<AutomergeStore.DocumentId>()
    
    var body: some View {
        NavigationView {
            List(selection: self.$selection) {
                ForEach(viewModel.workspaceIds, id: \.self) { id in
                    NavigationLink(destination: NavigationLazyView(workspaceView(id: id))) {
                        if viewModel.isShared(workspaceId: id) {
                            Image(systemName: "person.3.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 18)
                        }
                        Text("\(viewModel.workspaces[id] ?? "") \(id.uuidString)")
                    }
                }
                .onDelete { offsets in
                    deleteWorkspaces(offsets.map { viewModel.workspaceIds[$0] })
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: newWorkspace) {
                        Label("Add Document", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .status) {
                    SyncStatusView(syncStatus: viewModel.syncStatus)
                }
            }
            #if os(macOS)
            .onDeleteCommand {
                deleteWorkspaces(Array(selection))
            }
            #endif
            Text("Select a document")
            //TodoList(items: $todoItems)
        }
    }

    @ViewBuilder
    func workspaceView(id: AutomergeStore.WorkspaceId) -> some View {
        if let workspace = viewModel.openWorkspace(id: id) {
            WorkspaceView(viewModel: .init(workspace: workspace))
        } else {
            Text("Failed to load workspace")
        }
    }
    
    private func newWorkspace() {
        withAnimation {
            _ = viewModel.newWorkspace(name: "Untitled!")
        }
    }

    private func deleteWorkspaces(_ deleteIds: [AutomergeStore.WorkspaceId]) {
        withAnimation {
            viewModel.deleteWorkspaces(deleteIds)
            selection = []
        }
    }
    
}
