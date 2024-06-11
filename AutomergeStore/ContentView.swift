import SwiftUI
import CoreData

struct ContentView: View {

    @State var viewModel = ViewModel()
    @State private var selection = Set<AutomergeStore.DocumentId>()
    
    var body: some View {
        NavigationView {
            List(selection: self.$selection) {
                Group {
                    switch viewModel.activity {
                    case .fetching:
                        Image(systemName: "icloud.and.arrow.down")
                    case .sending:
                        Image(systemName: "icloud.and.arrow.up")
                    case .waiting:
                        Image(systemName: "icloud")
                    }
                }

                ForEach(viewModel.workspaceIds, id: \.self) { id in
                    NavigationLink {
                        if let index = try? viewModel.openWorkspace(id: id).index {
                            DocumentView(document: index)
                        } else {
                            Text("Failed to load document")
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
        }
    }

    private func newWorkspace() {
        withAnimation {
            do {
                _ = try viewModel.newWorkspace()
            } catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }

    private func deleteWorkspaces(_ deleteIds: [AutomergeStore.WorkspaceId]) {
        withAnimation {
            do {
                try viewModel.deleteWorkspaces(deleteIds)
                selection = []
            } catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }
    
}
