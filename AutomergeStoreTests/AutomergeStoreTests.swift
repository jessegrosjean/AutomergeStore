import XCTest
import Automerge
import Foundation
@testable import AutomergeStore

final class AutomergeStoreTests: XCTestCase {
    
    @MainActor
    func testInit() async throws {
        try await withStore { store in
            let workspaceCount = store.workspaces.count
            XCTAssertEqual(workspaceCount, 0)
        }
    }

    func testNewWorkspace() async  throws {
        try await withStore { store in
            let workspace = try await store.newWorkspace(name: "")
            let workspaceCount = await store.workspaces.count
            let workspaceHandleCount = await store.workspaceHandles.count
            let documentHandleCount = await store.documentHandles.count
            let workspaceHandle = await store.workspaceHandles[workspace.id]
            let documentHandle = await store.documentHandles[workspace.id]
            XCTAssertEqual(workspaceCount, 1)
            XCTAssertEqual(workspaceHandleCount, 1)
            XCTAssertEqual(documentHandleCount, 1)
            XCTAssertNotNil(workspaceHandle) // index doc
            XCTAssertNotNil(documentHandle) // index doc
            XCTAssert(workspaceHandle!.indexPublisher === documentHandle!.automergePublisher)
        }
    }
    
    func testModifyWorkspaceDocument() async throws {
        try await withStore { store in
            let workspace = try await store.newWorkspace(name: "")
            let workspaceChunks = await store.viewContext.fetchWorkspaceChunks(id: workspace.id)
            try workspace.index?.put(obj: .ROOT, key: "count", value: .Counter(1))
            let newWorkspaceChunks = await store.viewContext.fetchWorkspaceChunks(id: workspace.id)
            XCTAssertEqual(workspaceChunks, newWorkspaceChunks)
            try await store.insertPendingChanges()
            let newNewWorkspaceChunks = await store.viewContext.fetchWorkspaceChunks(id: workspace.id)
            XCTAssertNotEqual(workspaceChunks, newNewWorkspaceChunks)
        }
    }

    func testModificationsMergedIntoSnapshot() async throws {
        try await withStore { store in
            let workspace = try await store.newWorkspace(name: "")
            
            for _ in 0..<1000 {
                try workspace.index?.put(obj: .ROOT, key: "count", value: .Counter(1))
                try await store.insertPendingChanges()
            }

            let chunks = await store.viewContext.fetchWorkspaceChunks(id: workspace.id)
            XCTAssertTrue(chunks!.count < 10)
        }
    }

    func testAddDocument() async throws {
        try await withStore { store in
            let workspace = try await store.newWorkspace(name: "")
            let workspaceChunks = await store.viewContext.fetchWorkspaceChunks(id: workspace.id)
            let document = try await store.newDocument(workspaceId: workspace.id)
            let newDocumentHandle = await store.documentHandles[document.id]
            let newWorkspaceChunks = await store.viewContext.fetchWorkspaceChunks(id: workspace.id)
            let workspaceHandleCount = await store.workspaceHandles.count
            let documentHandleCount = await store.documentHandles.count
            XCTAssertNotNil(newDocumentHandle)
            XCTAssertNotEqual(workspaceChunks, newWorkspaceChunks)
            XCTAssertEqual(workspaceHandleCount, 1)
            XCTAssertEqual(documentHandleCount, 2)
        }
    }

    func testCloseDocument() async throws {
        try await withStore { store in
            let workspace = try await store.newWorkspace(name: "")
            let document = try await store.newDocument(workspaceId: workspace.id)
            try await store.closeDocument(id: document.id)
            let newDocumentHandle = await store.documentHandles[document.id]
            let workspaceHandleCount = await store.workspaceHandles.count
            let documentHandleCount = await store.documentHandles.count
            XCTAssertNil(newDocumentHandle)
            XCTAssertEqual(workspaceHandleCount, 1)
            XCTAssertEqual(documentHandleCount, 1)
        }
    }
    
    func testCloseWorkspaceIndexDocument() async throws {
        try await withStore { store in
            let workspace = try await store.newWorkspace(name: "")
            XCTAssertNotNil(workspace.index)
            try await store.closeDocument(id: workspace.id)
            let workspaceHandleCount = await store.workspaceHandles.count
            let documentHandleCount = await store.documentHandles.count
            XCTAssertNil(workspace.index)
            XCTAssertEqual(workspaceHandleCount, 1)
            XCTAssertEqual(documentHandleCount, 0)
        }
    }

    func testCloseWorkspace() async throws {
        try await withStore { store in
            let workspace = try await store.newWorkspace(name: "")
            _ = try await store.newDocument(workspaceId: workspace.id)
            let workspaceChunks = await store.viewContext.fetchWorkspaceChunks(id: workspace.id)
            try await store.closeWorkspace(id: workspace.id)
            let workspaceHandleCount = await store.workspaceHandles.count
            let documentHandleCount = await store.documentHandles.count
            let newWorkspaceChunks = await store.viewContext.fetchWorkspaceChunks(id: workspace.id)
            XCTAssertEqual(workspaceHandleCount, 0)
            XCTAssertEqual(documentHandleCount, 0)
            XCTAssertEqual(workspaceChunks, newWorkspaceChunks)
        }
    }

    @MainActor
    func testDeleteWorkspace() async throws {
        try await withStore { store in
            let workspace = try store.newWorkspace(name: "")
            let document = try store.newDocument(workspaceId: workspace.id)
            try store.deleteWorkspace(id: workspace.id)
            XCTAssertNil(try store.openDocument(id: document.id))
            XCTAssertEqual(store.documentHandles.count, 0)
            XCTAssertEqual(store.workspaces.count, 0)
        }
    }

    func withStore(_ storeCallback: (AutomergeStore) async throws ->()) async throws {
        let fileManager = FileManager.default
        let tempDirectoryURL = fileManager.temporaryDirectory
        let directoryName = UUID().uuidString
        let temporaryDirectoryURL = tempDirectoryURL.appendingPathComponent(directoryName, isDirectory: true)
        try fileManager.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true, attributes: nil)
        let store = try await AutomergeStore(url: tempDirectoryURL, containerIdentifier: nil)
        try await storeCallback(store)
        try fileManager.removeItem(at: tempDirectoryURL)
    }

}
