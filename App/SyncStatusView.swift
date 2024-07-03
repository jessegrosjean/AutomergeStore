import SwiftUI

@MainActor
struct SyncStatusView: View {
    
    let syncStatus: AutomergeStore.SyncStatus

    var body: some View {
        if syncStatus.inProgress {
            ProgressView().controlSize(.small)
        } else if syncStatus.isBroken {
            Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
        }
    }
    
    var userDescription: String {
        if syncStatus == .succeeded {
            return ""
        } else {
            return syncStatus.description
        }
    }
    
    var symbolColor: Color {
        if syncStatus.isBroken {
            return .red
        } else {
            return .secondary
        }
    }
    
}
