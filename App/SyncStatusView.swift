import SwiftUI

@MainActor
struct SyncStatusView: View {
    
    let syncStatus: AutomergeStore.SyncStatus

    var body: some View {
        HStack {
            Image(systemName: syncStatus.symbolName)
                .foregroundColor(symbolColor)
            Text(userDescription)
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
