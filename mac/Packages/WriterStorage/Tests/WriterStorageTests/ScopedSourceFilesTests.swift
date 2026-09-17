import XCTest
import Foundation
import os
@testable import WriterStorage
import WriterFoundation

@MainActor
final class ScopedSourceFilesTests: XCTestCase {
    private final class Bookmarks: SourceBookmarkProviding, Sendable {
        struct Counts { var resolves = 0; var creates = 0; var starts = 0; var stops = 0 }
        let state = OSAllocatedUnfairLock(initialState: Counts())
        let url: URL, stale: Bool, granted: Bool
        init(url: URL, stale: Bool = false, granted: Bool = true) { self.url = url; self.stale = stale; self.granted = granted }
        func create(for selectedURL: URL) throws -> Data { state.withLock { $0.creates += 1 }; return Data([1,2,3]) }
        func resolve(_ bookmark: Data) throws -> ResolvedSourceBookmark { state.withLock { $0.resolves += 1 }; return .init(url: url, isStale: stale) }
        func start(_ url: URL) -> Bool { state.withLock { $0.starts += 1 }; return granted }
        func stop(_ url: URL) { state.withLock { $0.stops += 1 } }
        var counts: Counts { state.withLock { $0 } }
    }
    private struct CancelBeforeReplace: SourceFileFaultInjecting {
        func checkpoint(_ point: SourceFileFaultPoint) throws { if point == .beforeReplace { withUnsafeCurrentTask { $0?.cancel() } } }
    }
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("nw-grants-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }; return url
    }
    func testStaleDeniedAndInvalidBookmarksNeverOpenOrRenew() async throws {
        let url = try directory().appendingPathComponent("source.md")
        for stale in [true, false] {
            let bookmarks = Bookmarks(url: url, stale: stale, granted: false), files = ScopedSourceFiles(bookmarks: bookmarks)
            do { _ = try await files.read(.bookmark(Data([1]))); XCTFail("Unusable grant accepted") }
            catch { XCTAssertEqual(error as? SourceAccessError, stale ? .staleBookmark : .permissionDenied) }
            XCTAssertEqual(bookmarks.counts.creates, 0); XCTAssertEqual(bookmarks.counts.stops, 0)
            XCTAssertEqual(bookmarks.counts.starts, stale ? 0 : 1)
        }
        let bookmarks = Bookmarks(url: url), files = ScopedSourceFiles(bookmarks: bookmarks)
        for data in [Data(), Data(repeating: 0, count: ScopedSourceFiles.maximumBookmarkBytes+1)] {
            do { _ = try await files.read(.bookmark(data)); XCTFail("Invalid bookmark accepted") }
            catch { XCTAssertEqual(error as? SourceAccessError, .invalidBookmark) }
        }
        XCTAssertEqual(bookmarks.counts.resolves, 0); XCTAssertEqual(bookmarks.counts.starts, 0)
    }
    func testAccessIsBalancedAcrossSuccessAndFileFailure() async throws {
        let url = try directory().appendingPathComponent("source.md"), source = try SourceSnapshot(documentID: DocumentID(), revision: Revision(0), utf8: Data("exact\r\ne\u{301}".utf8))
        let bookmarks = Bookmarks(url: url), files = ScopedSourceFiles(bookmarks: bookmarks)
        _ = try await files.create(source, at: .bookmark(Data([1])))
        let read = try await files.read(.bookmark(Data([1]))); XCTAssertEqual(read.bytes, source.utf8)
        do { _ = try await files.create(source, at: .bookmark(Data([1]))); XCTFail("Overwrote an existing file") }
        catch { XCTAssertEqual(error as? SourceFileError, .alreadyExists) }
        XCTAssertEqual(bookmarks.counts.starts, 3); XCTAssertEqual(bookmarks.counts.stops, 3)
        XCTAssertEqual(bookmarks.counts.creates, 0)
    }
    func testExplicitSelectionCanWorkWithoutAnAdditionalScopeAndRenewOnlyOnRequest() async throws {
        let url = try directory().appendingPathComponent("source.txt"); try Data("selected".utf8).write(to: url)
        let bookmarks = Bookmarks(url: url, granted: false), files = ScopedSourceFiles(bookmarks: bookmarks)
        let read = try await files.read(.selectedURL(url)); XCTAssertEqual(read.bytes, Data("selected".utf8))
        XCTAssertEqual(bookmarks.counts.resolves, 0); XCTAssertEqual(bookmarks.counts.creates, 0); XCTAssertEqual(bookmarks.counts.stops, 0)
        let data = try await files.bookmarkForExplicitSelection(url); XCTAssertEqual(data, Data([1,2,3]))
        XCTAssertEqual(bookmarks.counts.creates, 1); XCTAssertEqual(bookmarks.counts.stops, 0)
    }
    func testCancellationReleasesAcquiredAccessAndLeavesNoFile() async throws {
        let url = try directory().appendingPathComponent("source.txt"), source = try SourceSnapshot(documentID: DocumentID(), revision: Revision(0), utf8: Data("temporary fixture".utf8))
        let bookmarks = Bookmarks(url: url), files = ScopedSourceFiles(bookmarks: bookmarks, files: CoordinatedSourceFiles(faults: CancelBeforeReplace()))
        let task = Task.detached { try await files.create(source, at: .bookmark(Data([1]))) }
        do { _ = try await task.value; XCTFail("Cancelled create succeeded") }
        catch is CancellationError {} catch { XCTFail("Wrong cancellation result") }
        XCTAssertEqual(bookmarks.counts.starts, 1); XCTAssertEqual(bookmarks.counts.stops, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}
