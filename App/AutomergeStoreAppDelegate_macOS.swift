import CoreData
import CloudKit
import AppKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    
    static let store = try! AutomergeStore(containerIdentifier: "iCloud.com.hogbaysoftware.AutomergeStore")

    func application(_ application: NSApplication, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        guard let sharedStore = Self.store.sharedPersistentStore else {
            return
        }
        Self.store.persistentContainer.acceptShareInvitations(from: [metadata], into: sharedStore) { (_, error) in
            if let error = error {
                DispatchQueue.main.async {
                    NSApp.presentError(error)
                }
            }
        }
    }
    
}
