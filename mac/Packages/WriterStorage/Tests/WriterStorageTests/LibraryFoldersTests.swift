import Foundation
import XCTest
import os
@testable import WriterStorage

@MainActor
final class LibraryFoldersTests: XCTestCase {
    private final class Grant: SourceBookmarkProviding, Sendable {
        let root: URL, stale: Bool, allowed: Bool
        let counts = OSAllocatedUnfairLock(initialState: (starts: 0, stops: 0))
        init(_ root: URL, stale: Bool = false, allowed: Bool = true) { self.root = root; self.stale = stale; self.allowed = allowed }
        func create(for selectedURL: URL) throws -> Data { XCTFail("Listing must not renew grants"); return Data() }
        func resolve(_ bookmark: Data) throws -> ResolvedSourceBookmark { .init(url: root, isStale: stale) }
        func start(_ url: URL) -> Bool { counts.withLock { $0.starts += 1 }; return allowed }
        func stop(_ url: URL) { counts.withLock { $0.stops += 1 } }
    }

    func testListsOnlySelectedSourceFilesAndRejectsSymlinkEscape() async throws {
        let workspace = try TempWorkspace(); defer { workspace.remove() }
        let root = workspace.url("selected").standardizedFileURL.resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try Data("source".utf8).write(to: root.appendingPathComponent("A.md"))
        try Data("text".utf8).write(to: root.appendingPathComponent("sub/B.txt"))
        try Data("unrelated".utf8).write(to: root.appendingPathComponent("photo.jpg"))
        try Data("hidden".utf8).write(to: root.appendingPathComponent(".deleted.md"))
        let outside = workspace.url("outside.md"); try Data("outside body".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("linked.md"), withDestinationURL: outside)
        let grant = Grant(root), library = LibraryFolders(bookmarks: grant)
        let listing = try await library.list(.bookmark(Data([1])))
        XCTAssertEqual(listing.entries.map(\.relativePath), ["A.md", "sub/B.txt"])
        XCTAssertFalse(LibraryFolders.contains(outside, in: root))
        XCTAssertFalse(LibraryFolders.contains(root.appendingPathComponent("linked.md"), in: root))
        XCTAssertFalse(LibraryFolders.contains(workspace.url("selected-other/secret.md"), in: root))
        XCTAssertEqual(grant.counts.withLock { $0.starts }, 1)
        XCTAssertEqual(grant.counts.withLock { $0.stops }, 1)
    }

    func testSearchReadsCurrentBytesAndReportsDepthLimit() async throws {
        let workspace = try TempWorkspace(); defer { workspace.remove() }
        let root = workspace.root.standardizedFileURL.resolvingSymlinksInPath()
        let file = root.appendingPathComponent("Current.md")
        try Data("old synthetic body".utf8).write(to: file)
        let library = LibraryFolders(bookmarks: Grant(root))
        let old = try await library.list(.bookmark(Data([1])), query: "old synthetic")
        XCTAssertEqual(old.entries.count, 1)
        try Data("new Cafe\u{301}\r\n".utf8).write(to: file, options: .atomic)
        let stale = try await library.list(.bookmark(Data([1])), query: "old synthetic")
        XCTAssertTrue(stale.entries.isEmpty)
        let current = try await library.list(.bookmark(Data([1])), query: "new")
        XCTAssertEqual(current.entries.map(\.relativePath), ["Current.md"])
        let deep = root.appendingPathComponent("1/2/3/4/5/6/7/8/9")
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        try Data("deep".utf8).write(to: deep.appendingPathComponent("deep.md"))
        let limited = try await library.list(.bookmark(Data([1])))
        XCTAssertTrue(limited.limited)
        XCTAssertFalse(limited.entries.contains { $0.relativePath.hasSuffix("deep.md") })
    }

    func testStaleOrDeniedGrantNeverListsAndNeverRenews() async throws {
        let missing = URL(fileURLWithPath: "/nonexistent-synthetic-folder")
        for stale in [true, false] {
            let grant = Grant(missing, stale: stale, allowed: false)
            do { _ = try await LibraryFolders(bookmarks: grant).list(.bookmark(Data([1]))); XCTFail("Unusable grant listed") }
            catch { XCTAssertEqual(error as? SourceAccessError, stale ? .staleBookmark : .permissionDenied) }
            XCTAssertEqual(grant.counts.withLock { $0.starts }, stale ? 0 : 1)
            XCTAssertEqual(grant.counts.withLock { $0.stops }, 0)
        }
    }
}
