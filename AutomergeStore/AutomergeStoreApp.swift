import SwiftUI

@main
struct AutomergeStoreApp: App {
    
    @StateObject var automergeStore = try! AutomergeStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(automergeStore)
        }
    }
}
