import SwiftUI
import CoreData
import CloudKit

@MainActor
struct ContentView: View {

    @State var sideBarVisibility: NavigationSplitViewVisibility = .doubleColumn
    @State var selectedWorkspace: AutomergeStore.Workspace?

    var body: some View {
        NavigationSplitView(columnVisibility: $sideBarVisibility) {
            WorkspacesView(selectedWorkspace: $selectedWorkspace)
                .navigationSplitViewColumnWidth(min: 200, ideal: 200, max: nil)
        } detail: {
            if let selectedWorkspace {
                WorkspaceView(viewModel: .init(workspace: selectedWorkspace))
            }
        }
    }
    
}
