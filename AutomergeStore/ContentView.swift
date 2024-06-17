import SwiftUI
import CoreData

@MainActor
struct ContentView: View {

    @State var viewModel = ViewModel()
    @State private var selection = Set<AutomergeStore.DocumentId>()
    
    var body: some View {
        NavigationView {
            List(selection: self.$selection) {
                ForEach(viewModel.workspaceIds, id: \.self) { id in
                    NavigationLink {
                        if let workspace = viewModel.openWorkspace(id: id) {
                            DocumentView(document: workspace.index.automerge)
                        } else {
                            Text("Failed to load workspace")
                        }
                    } label: {
                        Text(id.uuidString)
                    }
                }
                .onDelete { offsets in
                    deleteWorkspaces(offsets.map { viewModel.workspaceIds[$0] })
                }
            }
            .toolbar {
                ToolbarItem() {
                    Button(action: newWorkspace) {
                        Label("Add Document", systemImage: "plus")
                    }
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

    private func newWorkspace() {
        withAnimation {
            _ = viewModel.newWorkspace()
        }
    }

    private func deleteWorkspaces(_ deleteIds: [AutomergeStore.WorkspaceId]) {
        withAnimation {
            viewModel.deleteWorkspaces(deleteIds)
            selection = []
        }
    }
    
}
