import SwiftUI
import CoreData

struct ContentView: View {
    
    @EnvironmentObject var automergeStore: AutomergeStore

    @State private var selection = Set<AutomergeStore.DocumentId>()

    var body: some View {
        NavigationView {
            List(selection: self.$selection) {
                ForEach(automergeStore.documentIds, id: \.self) { id in
                    NavigationLink {
                        if let document = try? automergeStore.openDocument(id: id)?.doc {
                            DocumentView(document: document)
                        } else {
                            Text("Failed to load document")
                        }
                    } label: {
                        Text("\(id.uriRepresentation())")
                    }
                }
                .onDelete { offsets in
                    deleteDocuments(offsets.map { automergeStore.documentIds[$0] })
                }
            }
            .toolbar {
                ToolbarItem {
                    Button(action: addDocument) {
                        Label("Add Document", systemImage: "plus")
                    }
                }
            }
            #if os(macOS)
            .onDeleteCommand {
                deleteDocuments(Array(selection))
            }
            #endif
            Text("Select a document")
        }
    }

    private func addDocument() {
        withAnimation {
            do {
                _ = try automergeStore.newDocument()
            } catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }

    private func deleteDocuments(_ deleteIds: [AutomergeStore.DocumentId]) {
        withAnimation {
            do {
                for each in deleteIds {
                    try automergeStore.deleteDocument(id: each)
                }
                selection = []
            } catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }
}
