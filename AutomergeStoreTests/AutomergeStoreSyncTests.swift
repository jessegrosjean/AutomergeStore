/*
import CloudKit
import XCTest
import Automerge
@testable import AutomergeStore

final class AutomergeStoreSyncTests: XCTestCase {
    
    let container: CKContainer = CKContainer(identifier: "iCloud.com.hogbaysoftware.AutomergeStore.testing")

    override func setUp() async throws {
        for zone in try await container.privateCloudDatabase.allRecordZones() {
            try await container.privateCloudDatabase.deleteRecordZone(withID: zone.zoneID)
        }
    }

    func testNewSyncingStore() async throws {
        _ = try await newSyncingStore()
    }

    func testStoreWithSentWorkspace() async throws {
        let store = try await newSyncingStore()
        _ = try await store.newWorkspace()
        let databaseChanges = await store.sync!.engine.state.pendingDatabaseChanges
        let recordZoneChanges = await store.sync!.engine.state.pendingRecordZoneChanges
        XCTAssertEqual(databaseChanges.count, 1)
        XCTAssertEqual(recordZoneChanges.count, 1)
        try await store.sendChanges()
        let databaseChanges2 = await store.sync!.engine.state.pendingDatabaseChanges
        let recordZoneChanges2 = await store.sync!.engine.state.pendingRecordZoneChanges
        XCTAssertEqual(databaseChanges2.count, 0)
        XCTAssertEqual(recordZoneChanges2.count, 0)
    }

    func testNewSyncedStores() async throws {
        _ = try await newSyncedStores()
    }

    func testSyncChangesAToB() async throws {
        let (aStore, aWorkspace, bStore, bWorkspace) = try await newSyncedStores()
        try aWorkspace.index!.automerge.increment(obj: .ROOT, key: "count", by: 1)
        try await aStore.insertPendingChanges()
        try await aStore.sendChanges()
        try await bStore.fetchChanges()
        XCTAssertEqual(try bWorkspace.index!.automerge.get(obj: .ROOT, key: "count"), .Scalar(.Counter(2)))
    }

    func testMergeChangesBetweenAAndB() async throws {
        let (aStore, aWorkspace, bStore, bWorkspace) = try await newSyncedStores()

        try aWorkspace.index!.automerge.increment(obj: .ROOT, key: "count", by: 1)
        try bWorkspace.index!.automerge.increment(obj: .ROOT, key: "count", by: 1)
        try await aStore.insertPendingChanges()
        try await bStore.insertPendingChanges()
        try await aStore.sendChanges()
        try await bStore.sendChanges()

        try await aStore.fetchChanges()
        try await bStore.fetchChanges()
        XCTAssertEqual(try aWorkspace.index!.automerge.get(obj: .ROOT, key: "count"), .Scalar(.Counter(3)))
        XCTAssertEqual(try bWorkspace.index!.automerge.get(obj: .ROOT, key: "count"), .Scalar(.Counter(3)))
    }

    func newSyncingStore() async throws -> AutomergeStore {
        let temporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let url = temporaryDirectoryURL.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let automergeStore = try await AutomergeStore(url: url, syncConfiguration: .init(
            container: container,
            database: container.privateCloudDatabase,
            automaticallySync: false
        ))
        try await automergeStore.fetchChanges()
        return automergeStore
    }

    func newSyncedStores() async throws -> (
        AutomergeStore,
        AutomergeStore.Workspace,
        AutomergeStore,
        AutomergeStore.Workspace
    ){
        let aStore = try await newSyncingStore()
        let bStore = try await newSyncingStore()

        let aIndex = Automerge.Document()
        try aIndex.put(obj: .ROOT, key: "count", value: .Counter(1))
        let aWorkspace = try await aStore.newWorkspace(index: aIndex)
        XCTAssert(aWorkspace.index!.automerge === aIndex)
        
        try await aStore.insertPendingChanges()
        try await aStore.sendChanges()
        
        let noWorspace = try? await bStore.openWorkspace(id: aWorkspace.id)
        XCTAssertNil(noWorspace)
        try await bStore.fetchChanges()
        try! await Task.sleep(nanoseconds: 1_000_000)

        let bWorkspace = try await bStore.openWorkspace(id: aWorkspace.id)
        XCTAssertNotNil(bWorkspace)
        
        XCTAssertEqual(
            try bWorkspace.index!.automerge.get(obj: .ROOT, key: "count"),
            .Scalar(.Counter(1))
        )
        
        return (aStore, aWorkspace, bStore, bWorkspace)
    }
    
}
*/
