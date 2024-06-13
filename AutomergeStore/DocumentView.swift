import SwiftUI
import CoreData
import Automerge

@MainActor
struct DocumentView: View {
    
    @ObservedObject var document: Automerge.Document

    var body: some View {
        Button(action: { increment(by: 1) }) {
            Label("Add", systemImage: "plus")
        }
        Text("Count: \(count)")
        Button(action: { increment(by: -1) }) {
            Label("Subtract", systemImage: "minus")
        }
    }
        
    private var count: Int64 {
        if case .Scalar(.Counter(let count)) = try? document.get(obj: .ROOT, key: "count") {
            return count
        } else {
            return 0
        }
    }
    
    private func increment(by delta: Int64) {
        if case .Scalar(.Counter) = try! document.get(obj: .ROOT, key: "count") {
            // Good, we have counter
        } else {
            try! document.put(obj: .ROOT, key: "count", value: .Counter(0))
        }
        try! document.increment(obj: .ROOT, key: "count", by: delta)
    }

}
