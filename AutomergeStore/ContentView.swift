import SwiftUI
import CoreData

struct ContentView: View {
    
    @EnvironmentObject var automergeStore: AutomergeStore

    @State private var selection = Set<AutomergeStore.DocumentId>()
    
    var body: some View {
        NavigationView {
            List(selection: self.$selection) {
                ForEach(automergeStore.workspaceIds, id: \.self) { id in
                    NavigationLink {
                        if let index = try? automergeStore.openWorkspace(id: id).index {
                            DocumentView(document: index)
                        } else {
                            Text("Failed to load document")
                        }
                    } label: {
                        Text(id.uuidString)
                    }
                }
                .onDelete { offsets in
                    deleteWorkspaces(offsets.map { automergeStore.workspaceIds[$0] })
                }
            }
            .toolbar {
                ToolbarItem {
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
                _ = try automergeStore.newWorkspace()
            } catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }

    private func deleteWorkspaces(_ deleteIds: [AutomergeStore.WorkspaceId]) {
        withAnimation {
            do {
                for each in deleteIds {
                    try automergeStore.deleteWorkspace(id: each)
                }
                selection = []
            } catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }
     
}
