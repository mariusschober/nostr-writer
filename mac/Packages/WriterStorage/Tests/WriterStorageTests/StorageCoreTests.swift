import CryptoKit
import Foundation
import WriterFoundation
import WriterStorage
import XCTest

final class StorageCoreTests: XCTestCase {

    // MARK: - Round trip

    func testPersistThenRecoverReturnsExactBytes() async throws {
        let workspace = try TempWorkspace()
        defer { workspace.remove() }
        let store = try makeStore(workspace)
        let documentID = DocumentID()
        let bytes = Data([0xEF, 0xBB, 0xBF]) + Data("Hallo\r\nWelt\r\n".utf8)
        let snapshot = try makeSnapshot(documentID, 1, bytes)

        let durable = try await store.persist(batch(snapshot))
        XCTAssertEqual(durable.source.digest, snapshot.digest)
        XCTAssertEqual(durable.source.revision, Revision(1))
        XCTAssertNil(durable.savedFile)

        let state = try await store.recover(documentID)
        guard case .complete(let recovered) = state else {
            return XCTFail("Expected a complete recovery state, received \(state).")
        }
        XCTAssertEqual(recovered.source.utf8, bytes)
        XCTAssertEqual(recovered.source.digest, snapshot.digest)
        XCTAssertEqual(recovered.recoveryCommit, durable.recoveryCommit)

        let absent = try await store.recover(DocumentID())
        guard case .absent = absent else {
            return XCTFail("An unknown document must be absent, received \(absent).")
        }
        try await store.close()
    }

    func testExactSourceBytesSurviveCloseAndReopen() async throws {
        let workspace = try TempWorkspace()
        defer { workspace.remove() }
        let key = testKey()
        let documentID = DocumentID()

        let bomWithCRLF = Data([0xEF, 0xBB, 0xBF]) + Data("Zeile eins\r\nZeile zwei\r\n".utf8)
        let decomposed = Data("cafe\u{0301}".utf8)
        let composed = Data("café".utf8)
        let first = try makeSnapshot(documentID, 1, bomWithCRLF)
        let second = try makeSnapshot(documentID, 2, decomposed)
        let third = try makeSnapshot(documentID, 3, composed)
        // Canonically equivalent text must not be treated as identical content.
        XCTAssertNotEqual(second.digest, third.digest)

        var store = try makeStore(workspace, key: key, floor: 3)
        for snapshot in [first, second, third] {
            _ = try await store.persist(batch(snapshot))
        }
        try await store.close()

        store = try makeStore(workspace, key: key, floor: 3)
        let state = try await store.recover(documentID)
        guard case .complete(let durable) = state else {
            return XCTFail("Expected a complete recovery state, received \(state).")
        }
        XCTAssertEqual(durable.source.utf8, composed)
        XCTAssertEqual(durable.source.revision, Revision(3))

        let restoredFirst = try await store.recoverSnapshot(documentID, revision: Revision(1))
        let restoredSecond = try await store.recoverSnapshot(documentID, revision: Revision(2))
        XCTAssertEqual(restoredFirst.utf8, bomWithCRLF)
        XCTAssertEqual(restoredSecond.utf8, decomposed)
        XCTAssertEqual(restoredFirst.digest, first.digest)
        XCTAssertEqual(restoredSecond.digest, second.digest)
        try await store.close()
    }

    // MARK: - Ordering and idempotency

    func testIdempotentRetryReturnsTheOriginalCommitIdentity() async throws {
        let workspace = try TempWorkspace()
        defer { workspace.remove() }
        let key = testKey()
        let documentID = DocumentID()
        let snapshot = try makeSnapshot(documentID, 1, "abc")

        let first = try makeStore(workspace, key: key)
        let original = try await first.persist(batch(snapshot))
        // Same revision, same bytes: idempotent, one stored snapshot, same commit.
        let retry = try await first.persist(batch(snapshot))
        XCTAssertEqual(retry.recoveryCommit, original.recoveryCommit)
        let index = try await first.recoveryIndex(for: documentID)
        XCTAssertEqual(index.count, 1)
        try await first.close()

        let second = try makeStore(workspace, key: key)
        let afterReopen = try await second.persist(batch(snapshot))
        XCTAssertEqual(afterReopen.recoveryCommit, original.recoveryCommit)
        let indexAfterReopen = try await second.recoveryIndex(for: documentID)
        XCTAssertEqual(indexAfterReopen.count, 1)
        try await second.close()
    }

    func testStaleAndSameRevisionConflictAreRejected() async throws {
        let workspace = try TempWorkspace()
        defer { workspace.remove() }
        let store = try makeStore(workspace)
        let documentID = DocumentID()
        let second = try makeSnapshot(documentID, 2, "second")
        let _ = try await store.persist(batch(second))

        let stale = try makeSnapshot(documentID, 1, "first")
        do {
            _ = try await store.persist(batch(stale))
            XCTFail("An older revision must be rejected.")
        } catch let error as StorageError {
            XCTAssertEqual(error, .staleRevision(latest: 2, attempted: 1))
        }

        let conflict = try makeSnapshot(documentID, 2, "second-but-different")
        do {
            _ = try await store.persist(batch(conflict))
            XCTFail("The same revision with different bytes must be rejected.")
        } catch let error as StorageError {
            XCTAssertEqual(error, .conflictingRevision(revision: 2))
        }

        let metadata = try await store.documentMetadata(for: documentID)
        XCTAssertEqual(metadata?.latestRevision, Revision(2))
        XCTAssertEqual(metadata?.latestDigest, second.digest)
        XCTAssertEqual(metadata?.chunkCount, 1)
        try await store.close()
    }

    func testUInt64MaximumRevisionIsStoredWithoutTruncation() async throws {
        let workspace = try TempWorkspace()
        defer { workspace.remove() }
        let key = testKey()
        let documentID = DocumentID()
        let first = try makeSnapshot(documentID, 1, "start")
        let maximum = try makeSnapshot(documentID, .max, "final")

        var store = try makeStore(workspace, key: key)
        _ = try await store.persist(batch(first))
        let durable = try await store.persist(batch(maximum))
        XCTAssertEqual(durable.source.revision.rawValue, UInt64.max)
        try await store.close()

        store = try makeStore(workspace, key: key)
        let metadata = try await store.documentMetadata(for: documentID)
        XCTAssertEqual(metadata?.latestRevision.rawValue, UInt64.max)
        XCTAssertEqual(metadata?.latestChunkIndex, 1)

        let retry = try await store.persist(batch(maximum))
        XCTAssertEqual(retry.recoveryCommit, durable.recoveryCommit)

        let conflicting = try makeSnapshot(documentID, .max, "different")
        do {
            _ = try await store.persist(batch(conflicting))
            XCTFail("The maximum revision with different bytes must conflict.")
        } catch let error as StorageError {
            XCTAssertEqual(error, .conflictingRevision(revision: UInt64.max))
        }

        let older = try makeSnapshot(documentID, 7, "older")
        do {
            _ = try await store.persist(batch(older))
            XCTFail("An older revision must stay stale after the maximum revision.")
        } catch let error as StorageError {
            XCTAssertEqual(error, .staleRevision(latest: UInt64.max, attempted: 7))
        }

        let state = try await store.recover(documentID)
        guard case .complete(let recovered) = state else {
            return XCTFail("Expected the maximum revision to recover.")
        }
        XCTAssertEqual(recovered.source.utf8, maximum.utf8)
        try await store.close()
    }

    // MARK: - Receipts

    func testReceiptsAreCheckedForConsistencyAndNeverStored() async throws {
        let workspace = try TempWorkspace()
        defer { workspace.remove() }
        let documentID = DocumentID()
        let marker = "RECEIPT-ONLY-MARKER-DO-NOT-STORE"

        let start = try makeSnapshot(documentID, 1, "A")
        let firstReceipt = try receipt(from: start, inserting: marker, at: 1)
        let secondReceipt = try receipt(from: firstReceipt.post, inserting: "Y", at: firstReceipt.post.utf8.count)
        let source = secondReceipt.post

        let store = try makeStore(workspace)
        _ = try await store.persist(batch(source, receipts: [firstReceipt, secondReceipt]))

        // A receipt newer than the offered source is not a consistent chain.
        let inconsistent = batch(try makeSnapshot(documentID, 2, "short"), receipts: [firstReceipt, secondReceipt])
        do {
            _ = try await store.persist(inconsistent)
            XCTFail("An inconsistent receipt chain must be rejected.")
        } catch let error as StorageError {
            guard case .receiptInconsistency = error else {
                return XCTFail("Expected a receipt inconsistency, received \(error).")
            }
        }

        // Broken chain: two independent receipts that do not link.
        let detached = try receipt(from: start, inserting: "Z", at: 1)
        do {
            _ = try await store.persist(batch(secondReceipt.post, receipts: [detached, secondReceipt]))
            XCTFail("A detached receipt chain must be rejected.")
        } catch let error as StorageError {
            guard case .receiptInconsistency = error else {
                return XCTFail("Expected a receipt inconsistency, received \(error).")
            }
        }

        let metadata = try await store.documentMetadata(for: documentID)
        XCTAssertEqual(metadata?.latestRevision, source.revision)

        // Receipt text must never be written to disk, encrypted or not.
        for needle in plaintextNeedles(marker) {
            let hits = filesContaining(needle, in: storeFiles(workspace.databaseURL))
            XCTAssertEqual(hits, [], "Receipt text leaked into \(hits).")
        }
        try await store.close()
    }

    // MARK: - Listing

    func testIndexAndMetadataReportDurableFacts() async throws {
        let workspace = try TempWorkspace()
        defer { workspace.remove() }
        let store = try makeStore(workspace)
        let documentID = DocumentID()
        let first = try makeSnapshot(documentID, 1, "one")
        let second = try makeSnapshot(documentID, 2, "two")
        _ = try await store.persist(batch(first))
        let durable = try await store.persist(batch(second))

        let index = try await store.recoveryIndex(for: documentID)
        XCTAssertEqual(index.count, 2)
        XCTAssertEqual(index.map(\.sourceRevision), [Revision(1), Revision(2)])
        XCTAssertEqual(index.map(\.chunkIndex), [0, 1])
        XCTAssertEqual(index[1].sourceDigest, second.digest)
        XCTAssertEqual(index[1].byteCount, second.utf8.count)
        XCTAssertEqual(index[1].commitID, durable.recoveryCommit)
        XCTAssertEqual(Set(index.map(\.nonce)).count, 2, "Every snapshot needs its own nonce.")
        XCTAssertEqual(Set(index.map(\.streamID)).count, 1, "Chunks belong to one explicit recovery stream.")
        XCTAssertEqual(index[0].ciphertextBytes, second.utf8.count + 16)

        let metadata = try await store.documentMetadata(for: documentID)
        XCTAssertEqual(metadata?.chunkCount, 2)
        XCTAssertEqual(metadata?.latestRevision, Revision(2))
        XCTAssertEqual(metadata?.latestChunkIndex, 1)
        XCTAssertEqual(metadata?.ciphertextBytes, (first.utf8.count + 16) + (second.utf8.count + 16))

        let all = try await store.allDocumentMetadata()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.documentID, documentID)
        try await store.close()
    }

    // MARK: - Lifecycle

    func testClosedStoreRejectsFurtherWork() async throws {
        let workspace = try TempWorkspace()
        defer { workspace.remove() }
        let store = try makeStore(workspace)
        let documentID = DocumentID()
        let snapshot = try makeSnapshot(documentID, 1, "abc")
        _ = try await store.persist(batch(snapshot))
        try await store.close()
        try await store.close() // idempotent

        do {
            _ = try await store.persist(batch(try makeSnapshot(documentID, 2, "more")))
            XCTFail("A closed store must reject writes.")
        } catch let error as StorageError {
            XCTAssertEqual(error, .storeClosed)
        }
        do {
            _ = try await store.recoveryIndex(for: documentID)
            XCTFail("A closed store must reject reads.")
        } catch let error as StorageError {
            XCTAssertEqual(error, .storeClosed)
        }
    }

    // MARK: - Helpers

    private func receipt(from pre: SourceSnapshot, inserting text: String, at offset: Int) throws -> MutationReceipt {
        let command = EditCommand(
            id: UUID(),
            expectedRevision: pre.revision,
            range: try ByteRange(lowerBound: offset, upperBound: offset),
            replacement: Data(text.utf8),
            origin: .directNativeInput,
            undoGroup: UUID()
        )
        return try command.applying(to: pre, completeness: .observed)
    }
}
