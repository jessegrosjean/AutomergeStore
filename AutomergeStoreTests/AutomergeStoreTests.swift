import XCTest
import Automerge
@testable import AutomergeStore

final class AutomergeStoreTests: XCTestCase {
    
    func testInit() throws {
        let store = try AutomergeStore(url: .devNull)
        XCTAssert(store.workspaceIds.count == 0)
    }

    func testNewWorkspace() throws {
        let store = try AutomergeStore(url: .devNull)
        let workspace = try store.newWorkspace()
        XCTAssert(store.workspaceIds.count == 1)
        XCTAssertNotNil(store.documentHandles[workspace.id]) // index doc
    }
    
    func testModifyWorkspaceDocument() throws {
        let store = try AutomergeStore(url: .devNull)
        let workspace = try store.newWorkspace()
        let workspaceChunks = store.fetchWorkspaceChunks(id: workspace.id)
        try workspace.index.put(obj: .ROOT, key: "count", value: .Counter(1))
        XCTAssertEqual(workspaceChunks, store.fetchWorkspaceChunks(id: workspace.id))
        try store.commitChanges()
        XCTAssertNotEqual(workspaceChunks, store.fetchWorkspaceChunks(id: workspace.id))
    }

    func testAddDocument() throws {
        let store = try AutomergeStore(url: .devNull)
        let workspace = try store.newWorkspace()
        let workspaceChunks = store.fetchWorkspaceChunks(id: workspace.id)
        let document = try store.newDocument(workspaceId: workspace.id)
        XCTAssertNotNil(store.documentHandles[document.id])
        XCTAssertNotEqual(workspaceChunks, store.fetchWorkspaceChunks(id: workspace.id))
    }

    func testCloseDocument() throws {
        let store = try AutomergeStore(url: .devNull)
        let workspace = try store.newWorkspace()
        let document = try store.newDocument(workspaceId: workspace.id)
        let workspaceChunks = store.fetchWorkspaceChunks(id: workspace.id)
        try store.closeDocument(id: document.id)
        XCTAssertNil(store.documentHandles[document.id])
        XCTAssertEqual(workspaceChunks, store.fetchWorkspaceChunks(id: workspace.id))
    }

    func testCloseWorkspace() throws {
        let store = try AutomergeStore(url: .devNull)
        let workspace = try store.newWorkspace()
        _ = try store.newDocument(workspaceId: workspace.id)
        let workspaceChunks = store.fetchWorkspaceChunks(id: workspace.id)
        try store.closeWorkspace(id: workspace.id)
        XCTAssertEqual(store.documentHandles.count, 0)
        XCTAssertEqual(workspaceChunks, store.fetchWorkspaceChunks(id: workspace.id))
    }

}
