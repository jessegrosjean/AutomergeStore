import SwiftUI
import CoreData
import Automerge

@MainActor
struct WorkspaceView: View {
    
    let viewModel: ViewModel
    
    var body: some View {
        Group {
            if viewModel.index != nil {
                HStack {
                    Button(action: viewModel.descrement) {
                        Image(systemName: "minus")
                    }
                    Text("\(viewModel.count)")
                    Button(action: viewModel.increment) {
                        Image(systemName: "plus")
                    }
                }
            } else {
                Text("Index Loading...")
            }
        }
        .toolbar {
            ShareLink(item: viewModel.workspace, preview: SharePreview(viewModel.workspace.name)) {
                Label("Share Workspace", systemImage: "square.and.arrow.up")
            }
        }
    }

}
