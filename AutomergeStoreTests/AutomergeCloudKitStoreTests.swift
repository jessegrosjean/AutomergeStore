import CloudKit
import XCTest
import Automerge
@testable import AutomergeStore

final class AutomergeCloudkitTests: XCTestCase {
    
    let container: CKContainer = CKContainer(identifier: "iCloud.com.hogbaysoftware.AutomergeStore.testing")

    override func setUp() async throws {
        for zone in try await container.privateCloudDatabase.allRecordZones() {
            try await container.privateCloudDatabase.deleteRecordZone(withID: zone.zoneID)
        }
    }

    func testNewCloudKitStore() async throws {
        _ = try await newTestCloudKitStore()
    }

    func testNewCloudKitStoreWithSentWorkspace() async throws {
        let store = try await newTestCloudKitStore()
        _ = try await store.newWorkspace()
        let databaseChanges = await store.syncEngine.state.pendingDatabaseChanges
        let recordZoneChanges = await store.syncEngine.state.pendingRecordZoneChanges
        XCTAssertEqual(databaseChanges.count, 1)
        XCTAssertEqual(recordZoneChanges.count, 1)
        try await store.syncEngine.sendChanges()
        let databaseChanges2 = await store.syncEngine.state.pendingDatabaseChanges
        let recordZoneChanges2 = await store.syncEngine.state.pendingRecordZoneChanges
        XCTAssertEqual(databaseChanges2.count, 0)
        XCTAssertEqual(recordZoneChanges2.count, 0)
    }

    func testNewCloudKitStoresWithSyncedWorkspace() async throws {
        _ = try await newTestCloudKitStoresWithSyncedWorkspace()
    }

    func testSyncDocumentChangesFromAToB() async throws {
        let (aStore, aWorkspace, bStore, bWorkspace) = try await newTestCloudKitStoresWithSyncedWorkspace()
        try aWorkspace.index.increment(obj: .ROOT, key: "count", by: 1)
        try await aStore.commitChanges()
        try await aStore.syncEngine.sendChanges()
        try await bStore.syncEngine.fetchChanges()
        XCTAssertEqual(try bWorkspace.index.get(obj: .ROOT, key: "count"), .Scalar(.Counter(2)))
    }

    func testSyncDocumentChangesBetweenAAndB() async throws {
        let (aStore, aWorkspace, bStore, bWorkspace) = try await newTestCloudKitStoresWithSyncedWorkspace()

        try aWorkspace.index.increment(obj: .ROOT, key: "count", by: 1)
        try bWorkspace.index.increment(obj: .ROOT, key: "count", by: 1)
        try await aStore.commitChanges()
        try await bStore.commitChanges()
        try await aStore.syncEngine.sendChanges()
        try await bStore.syncEngine.sendChanges()

        try await aStore.syncEngine.fetchChanges()
        try await bStore.syncEngine.fetchChanges()
        XCTAssertEqual(try aWorkspace.index.get(obj: .ROOT, key: "count"), .Scalar(.Counter(3)))
        XCTAssertEqual(try bWorkspace.index.get(obj: .ROOT, key: "count"), .Scalar(.Counter(3)))
    }

    func newTestCloudKitStore() async throws -> AutomergeCloudKitStore {
        let temporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let url = temporaryDirectoryURL.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let automergeCloudKitStore = try await AutomergeCloudKitStore(
            container: container,
            database: container.privateCloudDatabase,
            automaticallySync: false,
            automergeStore: .init(url: url)
        )
        try await automergeCloudKitStore.syncEngine.fetchChanges()
        return automergeCloudKitStore
    }

    func newTestCloudKitStoresWithSyncedWorkspace() async throws -> (
        AutomergeCloudKitStore,
        AutomergeStore.Workspace,
        AutomergeCloudKitStore,
        AutomergeStore.Workspace
    ){
        let aStore = try await newTestCloudKitStore()
        let bStore = try await newTestCloudKitStore()

        let aIndex = Automerge.Document()
        try aIndex.put(obj: .ROOT, key: "count", value: .Counter(1))
        let aWorkspace = try await aStore.newWorkspace(index: aIndex)
        XCTAssert(aWorkspace.index === aIndex)
        
        try await aStore.commitChanges()
        try await aStore.syncEngine.sendChanges()
        
        let noWorspace = try? await bStore.openWorkspace(id: aWorkspace.id)
        XCTAssertNil(noWorspace)
        try await bStore.syncEngine.fetchChanges()
        let bWorkspace = try await bStore.openWorkspace(id: aWorkspace.id)
        XCTAssertNotNil(bWorkspace)
        
        XCTAssertEqual(
            try bWorkspace.index.get(obj: .ROOT, key: "count"),
            .Scalar(.Counter(1))
        )
        
        return (aStore, aWorkspace, bStore, bWorkspace)
    }
    
}
