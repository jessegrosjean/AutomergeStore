import XCTest
import Automerge
@testable import AutomergeStore

final class AutomergeStoreTests: XCTestCase {
    
    func testInit() {
        _ = AutomergeStore()
    }
    
    /*
    let testDocumentId = "test"
    let container: CKContainer = CKContainer(identifier: "iCloud.com.hogbaysoftware.AutomergeCloudkit")

    override func setUp() async throws {
        let zoneID = CKRecordZone.ID(zoneName: testDocumentId)
        try await container.privateCloudDatabase.deleteRecordZone(withID: zoneID)
    }

    func testSyncDocumentFromAToB() async throws {
        _ = try await newTestReposWithSyncedDocument()
    }

    func testSyncDocumentChangesFromAToB() async throws {
        let (a, aDoc, b, bDoc) = try await newTestReposWithSyncedDocument()
        try aDoc.increment(obj: .ROOT, key: "count", by: 1)
        try await Task.sleep(nanoseconds: 100_000_000) // wait for changes to save
        try await a.syncEngine.sendChanges()
        try await b.syncEngine.fetchChanges()
        XCTAssertEqual(try bDoc.get(obj: .ROOT, key: "count"), .Scalar(.Counter(2)))
    }

    func testSyncDocumentChangesBetweenAAndB() async throws {
        let (a, aDoc, b, bDoc) = try await newTestReposWithSyncedDocument()

        try aDoc.increment(obj: .ROOT, key: "count", by: 1)
        try bDoc.increment(obj: .ROOT, key: "count", by: 1)
        try await Task.sleep(nanoseconds: 100_000_000) // wait for changes to saves
        try await a.syncEngine.sendChanges()
        try await b.syncEngine.sendChanges()

        try await a.syncEngine.fetchChanges()
        try await b.syncEngine.fetchChanges()
        XCTAssertEqual(try aDoc.get(obj: .ROOT, key: "count"), .Scalar(.Counter(3)))
        XCTAssertEqual(try bDoc.get(obj: .ROOT, key: "count"), .Scalar(.Counter(3)))
    }
    
    func newTestReposWithSyncedDocument() async throws -> (
        AutomergeCloudKit,
        Automerge.Document,
        AutomergeCloudKit,
        Automerge.Document
    ){
        let a = try await newTestRepo()
        let b = try await newTestRepo()

        let aDoc = Automerge.Document()
        try aDoc.put(obj: .ROOT, key: "count", value: .Counter(1))
        let returnedADoc = try await a.addDocument(id: testDocumentId, doc: aDoc)
        XCTAssert(aDoc === returnedADoc)
        
        try await a.syncEngine.sendChanges()
        
        let noDoc = await b.loadDocument(id: testDocumentId)
        XCTAssertNil(noDoc)
        try await b.syncEngine.fetchChanges()
        let bDoc = await b.loadDocument(id: testDocumentId)
        XCTAssertNotNil(bDoc)
        
        return (a, aDoc, b, bDoc!)
    }
        
    func newTestRepo() async throws -> AutomergeStore {
        let temporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let local = temporaryDirectoryURL.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let automergeCloudKit = try AutomergeCloudKit(local: local, container: container, automaticallySync: false)
        try await automergeCloudKit.syncEngine.fetchChanges()
        return automergeCloudKit
    }
    */

}
