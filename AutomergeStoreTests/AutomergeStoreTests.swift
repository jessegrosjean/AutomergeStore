import XCTest
import Automerge
@testable import AutomergeStore

final class AutomergeStoreTests: XCTestCase {

    func testInit() async throws {
        let store = try await AutomergeStore(url: .devNull)
        let workspaceCount = await store.workspaceIds.count
        XCTAssert(workspaceCount == 0)
    }

    func testNewWorkspace() async  throws {
        let store = try await AutomergeStore(url: .devNull)
        let workspace = try await store.newWorkspace()
        let workspaceCount = await store.workspaceIds.count
        let handleCount = await store.documentHandles.count
        let index = await store.documentHandles[workspace.id]
        XCTAssertEqual(workspaceCount, 1)
        XCTAssertEqual(handleCount, 1)
        XCTAssertNotNil(index) // index doc
    }
    
    func testModifyWorkspaceDocument() async throws {
        let store = try await AutomergeStore(url: .devNull)
        let workspace = try await store.newWorkspace()
        let workspaceChunks = await store.viewContext.fetchWorkspaceChunks(id: workspace.id)
        try workspace.index.automerge.put(obj: .ROOT, key: "count", value: .Counter(1))
        let newWorkspaceChunks = await store.viewContext.fetchWorkspaceChunks(id: workspace.id)
        XCTAssertEqual(workspaceChunks, newWorkspaceChunks)
        try await store.transaction { $0.insertPendingChanges() }
        let newNewWorkspaceChunks = await store.viewContext.fetchWorkspaceChunks(id: workspace.id)
        XCTAssertNotEqual(workspaceChunks, newNewWorkspaceChunks)
    }

    func testModificationsMergedIntoSnapshot() async throws {
        let store = try await AutomergeStore(url: .devNull)
        let workspace = try await store.newWorkspace()
        
        for _ in 0..<1000 {
            try workspace.index.automerge.put(obj: .ROOT, key: "count", value: .Counter(1))
            try await store.transaction {
                $0.insertPendingChanges()
            }
        }

        let chunks = await store.viewContext.fetchWorkspaceChunks(id: workspace.id)
        XCTAssertTrue(chunks!.count < 10)
    }

    func testAddDocument() async throws {
        let store = try await AutomergeStore(url: .devNull)
        let workspace = try await store.newWorkspace()
        let workspaceChunks = await store.viewContext.fetchWorkspaceChunks(id: workspace.id)
        let document = try await store.newDocument(workspaceId: workspace.id)
        let handle = await store.documentHandles[document.id]
        let newWorkspaceChunks = await store.viewContext.fetchWorkspaceChunks(id: workspace.id)
        XCTAssertNotNil(handle)
        XCTAssertNotEqual(workspaceChunks, newWorkspaceChunks)
    }

    func testCloseDocument() async throws {
        let store = try await AutomergeStore(url: .devNull)
        let workspace = try await store.newWorkspace()
        let document = try await store.newDocument(workspaceId: workspace.id)
        let workspaceChunks = await store.viewContext.fetchWorkspaceChunks(id: workspace.id)
        try await store.closeDocument(id: document.id)
        let handle = await store.documentHandles[document.id]
        let newWorkspaceChunks = await store.viewContext.fetchWorkspaceChunks(id: workspace.id)
        XCTAssertNil(handle)
        XCTAssertEqual(workspaceChunks, newWorkspaceChunks)
    }

    func testCloseWorkspace() async throws {
        let store = try await AutomergeStore(url: .devNull)
        let workspace = try await store.newWorkspace()
        _ = try await store.newDocument(workspaceId: workspace.id)
        let workspaceChunks = await store.viewContext.fetchWorkspaceChunks(id: workspace.id)
        try await store.closeWorkspace(id: workspace.id)
        let handleCount = await store.documentHandles.count
        let newWorkspaceChunks = await store.viewContext.fetchWorkspaceChunks(id: workspace.id)
        XCTAssertEqual(handleCount, 0)
        XCTAssertEqual(workspaceChunks, newWorkspaceChunks)
    }

    @MainActor
    func testDeleteWorkspace() throws {
        let store = try AutomergeStore(url: .devNull)
        let workspace = try store.newWorkspace()
        let document = try store.newDocument(workspaceId: workspace.id)
        try store.deleteWorkspace(id: workspace.id)
        XCTAssertNil(try store.openDocument(workspaceId: workspace.id, documentId: document.id))
        XCTAssertEqual(store.documentHandles.count, 0)
        XCTAssertEqual(store.workspaceIds.count, 0)
    }

}
