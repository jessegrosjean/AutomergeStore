import SwiftUI
import CoreData
import Automerge

@MainActor
struct WorkspaceView: View {
    
    let viewModel: ViewModel
    
    var body: some View {
        Group {
            if viewModel.index != nil {
                Button(action: { viewModel.increment() }) {
                    Label("Add", systemImage: "plus")
                }
                Text("Count: \(viewModel.count)")
                Button(action: { viewModel.descrement() }) {
                    Label("Subtract", systemImage: "minus")
                }

                Button(action: { viewModel.createShare() }) {
                    Text("Create Share")
                }

                if let share = viewModel.share {
                    Button(action: { viewModel.editShare(share) }) {
                        Text("Edit Share")
                    }

                    Button(action: { viewModel.deleteShare(share) }) {
                        Text("Delete Share")
                    }

                    Section {
                        if let participants = viewModel.shareParticipants {
                            ForEach(participants, id: \.self) { participant in
                                VStack(alignment: .leading) {
                                    Text(participant.userIdentity.nameComponents?.formatted(.name(style: .long)) ?? "")
                                        .font(.headline)
                                    Text("Acceptance Status: \(AutomergeStore.string(for: participant.acceptanceStatus))")
                                        .font(.subheadline)
                                    Text("Role: \(AutomergeStore.string(for: participant.role))")
                                        .font(.subheadline)
                                    Text("Permissions: \(AutomergeStore.string(for: participant.permission))")
                                        .font(.subheadline)
                                }
                                .padding(.bottom, 8)
                            }
                        }
                    } header: {
                        Text("Participants")
                    }
                } else {
                    ShareLink(item: viewModel.workspace, preview: SharePreview("A workspace to share")) {
                        Text("Share")
                    }
                }
                //presentCloudSharingController
            } else {
                Text("Index Loading...")
            }
        }
    }

}
