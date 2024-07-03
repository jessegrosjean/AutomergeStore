import SwiftUI

@MainActor
struct WorkspaceRowView: View {
    let text: String
    let isShared: Bool
    let editWorkspaceShare: ()->()
    
    var body: some View {
        HStack {
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
            if isShared {
                Button(action: { editWorkspaceShare() }) {
                    Image(systemName: "person.crop.circle")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.secondary)
                        .frame(width: 14)
                }
                .buttonStyle(BorderlessButtonStyle())
                .frame(alignment: .trailing)
            }
        }
    }

}
