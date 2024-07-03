/*
 
 In theory these should work, but seems impossible to tell CoreData/CloudKit when it should sync, so tests hard to write
 
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

    func testNewSyncedStores() async throws {
        _ = try await newSyncedStores()
    }

    func testSyncChangesAToB() async throws {
        let (aStore, aWorkspace, _, bWorkspace) = try await newSyncedStores()
        try aWorkspace.index!.increment(obj: .ROOT, key: "count", by: 1)
        try await aStore.insertPendingChanges()
        try await aStore.viewContext.save()
        
        while true {
            try! await Task.sleep(nanoseconds: 1_000_000_000)
            if try bWorkspace.index?.get(obj: .ROOT, key: "count") == .Scalar(.Counter(2)) {
                break
            }
        }
    }

    func testMergeChangesBetweenAAndB() async throws {
        let (aStore, aWorkspace, bStore, bWorkspace) = try await newSyncedStores()

        try aWorkspace.index!.increment(obj: .ROOT, key: "count", by: 1)
        try bWorkspace.index!.increment(obj: .ROOT, key: "count", by: 1)

        while true {
            try! await Task.sleep(nanoseconds: 1_000_000_000)
            let aCount = try aWorkspace.index?.get(obj: .ROOT, key: "count")
            let bCount = try bWorkspace.index?.get(obj: .ROOT, key: "count")

            if
                aCount == .Scalar(.Counter(3)) &&
                bCount == .Scalar(.Counter(3))
            {
                break
            }
        }
    }

    func newSyncingStore() async throws -> AutomergeStore {
        let temporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let url = temporaryDirectoryURL.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        return try await AutomergeStore(url: url, containerIdentifier: container.containerIdentifier)
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
        let aWorkspace = try await aStore.newWorkspace(name: "test", index: aIndex)
        XCTAssert(aWorkspace.index === aIndex)
        
        try await aStore.viewContext.save()
                
        let noWorspace = try? await bStore.openWorkspace(id: aWorkspace.id)
        XCTAssertNil(noWorspace)
        
        while true {
            try! await Task.sleep(nanoseconds: 1_000_000_000)

            if let bWorkspace = try await bStore.openWorkspace(id: aWorkspace.id), let index = bWorkspace.index {
                XCTAssertEqual(
                    try index.get(obj: .ROOT, key: "count"),
                    .Scalar(.Counter(1))
                )
                return (aStore, aWorkspace, bStore, bWorkspace)
            }
        }
    }
    
}
*/
