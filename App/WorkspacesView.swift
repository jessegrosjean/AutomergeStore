import SwiftUI

@MainActor
struct WorkspacesView: View {

    @State var viewModel = ViewModel()
    @State var newWorkspaceName: String = ""
    @State var showingNewWorkspaceNameAlert: Bool = false
    @State var selectedWorkspaceId: AutomergeStore.WorkspaceId?
    @Binding var selectedWorkspace: AutomergeStore.Workspace?

    var body: some View {
        VStack(alignment: .leading) {
            List(selection: $selectedWorkspaceId) {
                ForEach(viewModel.workspaceIds, id: \.self) { id in
                    NavigationLink(value: id) {
                        WorkspaceRowView(
                            text: "\(viewModel.workspaces[id] ?? "")",
                            isShared: viewModel.isShared(workspaceId: id),
                            editWorkspaceShare: { editWorkspaceShare(id: id) }
                        )
                    }
                }
                .onDelete { offsets in
                    deleteWorkspaces(offsets.map { viewModel.workspaceIds[$0] })
                }
            }
            .navigationTitle("Workspaces")
            #if os(macOS)
            .onDeleteCommand {
                deleteWorkspaces(selectedWorkspaceId.map { [$0] } ?? [])
            }
            #endif
            #if os(macOS)
            .safeAreaInset(edge: .bottom, content: {
                HStack {
                    Button(action: { newWorkspace() }) {
                        Label("Add Workspace", systemImage: "plus.circle")
                    }.buttonStyle(BorderlessButtonStyle())
                    Spacer()
                    SyncStatusView(syncStatus: viewModel.syncStatus)
                }.padding(.init(top: 8, leading: 8, bottom: 8, trailing: 8))
            })
            #else
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        Button(action: { newWorkspace() }) {
                            Label("Add Workspace", systemImage: "plus.circle")
                        }.buttonStyle(BorderlessButtonStyle())
                        Spacer()
                        SyncStatusView(syncStatus: viewModel.syncStatus)
                    }
                }
            }
            #endif
            .alert("Add Workspace", 
                isPresented: $showingNewWorkspaceNameAlert,
                actions: {
                    Group {
                        TextField("Workspace Name", text: $newWorkspaceName).frame(width: 200)
                        Button("Add Workspace", action: { newWorkspace(name: newWorkspaceName) })
                        Button("Cancel", role: .cancel, action: {})
                    }
                },
                message: {
                    Text("Please enter a new for your new workspace.")
                }
            )
            .onChange(of: selectedWorkspaceId) {
                if let selectedWorkspaceId {
                    selectedWorkspace = viewModel.openWorkspace(id: selectedWorkspaceId)
                } else {
                    selectedWorkspace = nil
                }
            }
        }
    }

    private func newWorkspace(name: String? = nil) {
        withAnimation {
            if let name {
                if let workspace = viewModel.newWorkspace(name: name) {
                    selectedWorkspaceId = workspace.id
                    selectedWorkspace = workspace
                }
            } else {
                showingNewWorkspaceNameAlert = true
            }
        }
    }

    private func editWorkspaceShare(id: AutomergeStore.WorkspaceId) {
        withAnimation {
            _ = viewModel.editWorkspaceShare(id: id)
        }
    }

    private func deleteWorkspaces(_ deleteIds: [AutomergeStore.WorkspaceId]) {
        withAnimation {
            viewModel.deleteWorkspaces(deleteIds)
        }
    }
    
}
