import CryptoKit
import Foundation
import WriterFoundation
@testable import WriterStorage
import XCTest

final class EncryptionTests: XCTestCase {

    // MARK: - Plaintext containment

    func testWritingAndReceiptTextNeverAppearInStoreFiles() async throws {
        let workspace = try TempWorkspace()
        defer { workspace.remove() }
        let documentID = DocumentID()
        let draftCanary = "PRIVATE-DRAFT-CANARY-9F2A"
        let receiptCanary = "RECEIPT-CANARY-7B31"

        let store = try makeStore(workspace)
        let first = try makeSnapshot(documentID, 1, "line one\r\n\(draftCanary)\r\nline three\r\n")
        _ = try await store.persist(batch(first))

        let second = try makeSnapshot(
            documentID,
            2,
            Data([0xEF, 0xBB, 0xBF]) + Data("cafe\u{0301} ".utf8) + Data(draftCanary.utf8)
        )
        let command = EditCommand(
            id: UUID(),
            expectedRevision: second.revision,
            range: try ByteRange(lowerBound: second.utf8.count, upperBound: second.utf8.count),
            replacement: Data(receiptCanary.utf8),
            origin: .directNativeInput,
            undoGroup: UUID()
        )
        let receipt = try command.applying(to: second, completeness: .observed)
        _ = try await store.persist(batch(receipt.post, receipts: [receipt]))

        let needles = plaintextNeedles(draftCanary) + plaintextNeedles(receiptCanary)
        // Include the raw installation key bytes: no key material may be persisted.
        let keyBytes = testKey().withUnsafeBytes { Data($0) }
        let allNeedles = needles + [keyBytes]
        // Scan every file in the workspace, not only the three SQLite files, so a
        // stray backup, journal or log cannot hide plaintext writing.
        let openFiles = allFiles(in: workspace.root)
        XCTAssertGreaterThan(readIfPresent(workspace.databaseURL)?.count ?? 0, 0)
        XCTAssertFalse(openFiles.isEmpty)
        for needle in needles {
            let hits = filesContaining(needle, in: openFiles)
            XCTAssertEqual(hits, [], "Plaintext leaked into \(hits) while the store was open.")
        }
        XCTAssertEqual(
            filesContaining(keyBytes, in: openFiles),
            [],
            "Raw key material was written to the store."
        )

        try await store.close()
        for needle in allNeedles {
            let hits = filesContaining(needle, in: allFiles(in: workspace.root))
            XCTAssertEqual(hits, [], "Plaintext leaked into \(hits) after shutdown.")
        }

        // The canary text is still recoverable through the authenticated path.
        let reopened = try makeStore(workspace)
        let state = try await reopened.recover(documentID)
        guard case .complete(let durable) = state else {
            return XCTFail("Expected a complete recovery state after reopening.")
        }
        XCTAssertEqual(durable.source.utf8, receipt.post.utf8)
        try await reopened.close()
    }

    func testEncryptedSnapshotIsLongerThanItsPlaintext() async throws {
        let workspace = try TempWorkspace()
        defer { workspace.remove() }
        let store = try makeStore(workspace)
        let documentID = DocumentID()
        let snapshot = try makeSnapshot(documentID, 1, "abcdefghij")
        _ = try await store.persist(batch(snapshot))
        let index = try await store.recoveryIndex(for: documentID)
        XCTAssertEqual(index.first?.ciphertextBytes, snapshot.utf8.count + 16)
        XCTAssertEqual(index.first?.nonce.count, 12)
        try await store.close()
    }

    // MARK: - Nonces

    func testSystemNonceGeneratorDoesNotRepeatInASample() throws {
        let generator = SystemRecoveryNonceGenerator()
        var seen = Set<Data>()
        for _ in 0..<256 {
            let nonce = try generator.nextNonce()
            XCTAssertEqual(nonce.count, 12)
            XCTAssertTrue(seen.insert(nonce).inserted, "The system nonce generator repeated a nonce.")
        }
    }

    func testReusedNonceIsRefusedAndNothingIsWritten() async throws {
        let workspace = try TempWorkspace()
        defer { workspace.remove() }
        let store = try makeStore(workspace, nonceGenerator: RepeatingNonceGenerator())
        let documentID = DocumentID()
        _ = try await store.persist(batch(try makeSnapshot(documentID, 1, "one")))

        do {
            _ = try await store.persist(batch(try makeSnapshot(documentID, 2, "two")))
            XCTFail("A reused AEAD nonce must be refused.")
        } catch let error as StorageError {
            guard case .invariantViolation = error else {
                return XCTFail("Expected a nonce rejection, received \(error).")
            }
        }

        let index = try await store.recoveryIndex(for: documentID)
        XCTAssertEqual(index.count, 1)
        let metadata = try await store.documentMetadata(for: documentID)
        XCTAssertEqual(metadata?.latestRevision, Revision(1))
        try await store.close()
    }

    // MARK: - Tamper detection

    func testNewWriteRefusesToContinuePastDamagedRecovery() async throws {
        let workspace = try TempWorkspace()
        defer { workspace.remove() }
        let documentID = DocumentID()
        _ = try await seedTwoRevisions(workspace, key: testKey(), documentID: documentID)
        let raw = try RawDatabase(path: workspace.databaseURL.path)
        try raw.execute("UPDATE recovery_chunks SET sealed = zeroblob(length(sealed)) WHERE chunk_index = \(chunk(1))")
        let store = try makeStore(workspace)
        do {
            _ = try await store.persist(batch(try makeSnapshot(documentID, 3, "new content")))
            XCTFail("Damaged latest recovery must not be silently superseded.")
        } catch let error as StorageError {
            guard case .tamperDetected = error else { return XCTFail("Unexpected error: \(error)") }
        }
        let index = try await store.recoveryIndex(for: documentID)
        XCTAssertEqual(index.map(\.sourceRevision), [Revision(1), Revision(2)])
        let earlier = try await store.recoverSnapshot(documentID, revision: Revision(1))
        XCTAssertEqual(earlier.utf8, Data("AAAA".utf8))
        try await store.close()
    }

    func testCiphertextTamperIsDetected() async throws {
        try await assertTamperIsDetected(
            "UPDATE recovery_chunks SET sealed = zeroblob(length(sealed)) WHERE chunk_index = \(chunk(1))"
        )
    }

    func testNonceTamperIsDetected() async throws {
        try await assertTamperIsDetected(
            "UPDATE recovery_chunks SET nonce = zeroblob(12) WHERE chunk_index = \(chunk(1))"
        )
    }

    func testBoundSourceDigestTamperIsDetected() async throws {
        try await assertTamperIsDetected(
            "UPDATE recovery_chunks SET source_digest = zeroblob(32) WHERE chunk_index = \(chunk(1))"
        )
    }

    func testPreviousReferenceTamperIsDetected() async throws {
        try await assertTamperIsDetected(
            "UPDATE recovery_chunks SET previous_ref = zeroblob(32) WHERE chunk_index = \(chunk(1))"
        )
    }

    func testChunkReferenceTamperIsDetected() async throws {
        try await assertTamperIsDetected(
            "UPDATE recovery_chunks SET chunk_ref = zeroblob(32) WHERE chunk_index = \(chunk(1))"
        )
    }

    /// Copies a whole earlier snapshot over a later one and recomputes the row
    /// reference, so nonce, ciphertext and reference are internally consistent.
    /// Only the authenticated context can catch it, because document identity,
    /// chunk index, revision, digest and previous reference all differ.
    func testCrossSnapshotSubstitutionIsDetectedByAuthenticatedContext() async throws {
        let workspace = try TempWorkspace()
        defer { workspace.remove() }
        let key = testKey()
        let documentID = DocumentID()
        _ = try await seedTwoRevisions(workspace, key: key, documentID: documentID)

        let raw = try RawDatabase(path: workspace.databaseURL.path)
        let olderNonce = try XCTUnwrap(
            try raw.blob("SELECT nonce FROM recovery_chunks WHERE chunk_index = \(chunk(0))")
        )
        let olderSealed = try XCTUnwrap(
            try raw.blob("SELECT sealed FROM recovery_chunks WHERE chunk_index = \(chunk(0))")
        )
        let streamText = try XCTUnwrap(
            try raw.text("SELECT stream_id FROM recovery_chunks WHERE chunk_index = \(chunk(1))")
        )
        let streamID = RecoveryStreamID(try XCTUnwrap(UUID(uuidString: streamText)))
        let reference = RecoveryCipher.chunkReference(
            documentID: documentID,
            streamID: streamID,
            chunkIndex: 1,
            nonce: olderNonce,
            sealed: olderSealed
        )

        // The write path already refuses a duplicate nonce, so the substitution
        // is applied with that guard removed to reach the authenticated check.
        try raw.execute("DROP INDEX recovery_chunks_nonce")
        try raw.execute("""
            UPDATE recovery_chunks SET
                nonce = \(hexLiteral(olderNonce)),
                sealed = \(hexLiteral(olderSealed)),
                chunk_ref = \(hexLiteral(reference))
            WHERE chunk_index = \(chunk(1))
            """)

        let store = try makeStore(workspace, key: key)
        let state = try await store.recover(documentID)
        guard case .corrupt = state else {
            return XCTFail("A substituted snapshot must fail authentication, received \(state).")
        }
        try await store.close()
    }

    func testMissingIndexedSnapshotReportsPartialNotComplete() async throws {
        let workspace = try TempWorkspace()
        defer { workspace.remove() }
        let key = testKey()
        let documentID = DocumentID()
        _ = try await seedTwoRevisions(workspace, key: key, documentID: documentID)

        let raw = try RawDatabase(path: workspace.databaseURL.path)
        try raw.execute("DELETE FROM recovery_chunks WHERE chunk_index = \(chunk(1))")

        let store = try makeStore(workspace, key: key)
        let state = try await store.recover(documentID)
        guard case .localPartial(let snapshot, _) = state else {
            return XCTFail("A torn index must report a partial recovery, received \(state).")
        }
        XCTAssertEqual(snapshot.revision, Revision(1))
        XCTAssertEqual(snapshot.utf8, Data("AAAA".utf8))
        try await store.close()
    }

    /// The document index is not authenticated on its own. If it is downgraded
    /// to an older chunk while both authenticated snapshots stay readable, the
    /// store must not present that older snapshot as the current complete state.
    func testIndexThatDisagreesWithItsSnapshotIsNotReportedComplete() async throws {
        let workspace = try TempWorkspace()
        defer { workspace.remove() }
        let key = testKey()
        let documentID = DocumentID()
        _ = try await seedTwoRevisions(workspace, key: key, documentID: documentID)

        // Only the unauthenticated index pointer changes; both chunks stay intact.
        let raw = try RawDatabase(path: workspace.databaseURL.path)
        try raw.execute("""
            UPDATE documents SET latest_chunk_index = \(chunk(0)), latest_revision = \(chunk(1))
            WHERE document_id = '\(documentID.rawValue.uuidString)'
            """)

        let store = try makeStore(workspace, key: key)
        let state = try await store.recover(documentID)
        guard case .localPartial(let snapshot, let reason) = state else {
            return XCTFail("An index that disagrees with its snapshot must not report complete, received \(state).")
        }
        XCTAssertEqual(snapshot.revision, Revision(2))
        XCTAssertEqual(snapshot.utf8, Data("BBBB".utf8))
        XCTAssertFalse(reason.isEmpty)
        try await store.close()
    }

    /// A tampered index reference must never become the previous-chunk link of a
    /// new snapshot, because the chain would then record a reference to nothing.
    func testTamperedIndexReferenceIsRefusedRatherThanChained() async throws {
        let workspace = try TempWorkspace()
        defer { workspace.remove() }
        let key = testKey()
        let documentID = DocumentID()
        _ = try await seedTwoRevisions(workspace, key: key, documentID: documentID)

        let raw = try RawDatabase(path: workspace.databaseURL.path)
        let forged = hexLiteral(Data(repeating: 0, count: RecoveryCipher.referenceByteCount))
        try raw.execute("""
            UPDATE documents SET latest_chunk_ref = \(forged)
            WHERE document_id = '\(documentID.rawValue.uuidString)'
            """)

        let store = try makeStore(workspace, key: key)
        let next = try makeSnapshot(documentID, 3, "CCCC")
        do {
            _ = try await store.persist(batch(next))
            XCTFail("A tampered index reference must not be chained into a new snapshot.")
        } catch let error as StorageError {
            guard case .tamperDetected = error else {
                return XCTFail("Expected tamperDetected, received \(error).")
            }
        }
        let index = try await store.recoveryIndex(for: documentID)
        XCTAssertEqual(index.count, 2, "A refused write must not append a snapshot.")
        try await store.close()
    }

    // MARK: - Keys

    func testWrongKeyIsRefusedAndPreservesTheStoredSnapshot() async throws {
        let workspace = try TempWorkspace()
        defer { workspace.remove() }
        let documentID = DocumentID()
        let keyA = testKey(0x11)
        let keyB = testKey(0x22)
        let provider = InMemoryKeyProvider(key: keyA)
        let store = try makeStore(workspace, provider: provider)
        let first = try makeSnapshot(documentID, 1, "AAAA")
        _ = try await store.persist(batch(first))

        provider.useKey(keyB)
        let wrongKeyState = try await store.recover(documentID)
        guard case .keyUnavailable = wrongKeyState else {
            return XCTFail("A different available key must not decrypt the store, received \(wrongKeyState).")
        }
        do {
            _ = try await store.persist(batch(try makeSnapshot(documentID, 2, "BBBB")))
            XCTFail("A different available key must not be used to write.")
        } catch let error as StorageError {
            XCTAssertEqual(error, .keyMismatch)
        }
        let indexAfterAttempt = try await store.recoveryIndex(for: documentID)
        XCTAssertEqual(indexAfterAttempt.count, 1, "The wrong key must not write anything.")
        let metadata = try await store.documentMetadata(for: documentID)
        XCTAssertEqual(metadata?.latestRevision, Revision(1))

        provider.useKey(keyA)
        let restored = try await store.recover(documentID)
        guard case .complete(let durable) = restored else {
            return XCTFail("The original snapshot must survive unchanged, received \(restored).")
        }
        XCTAssertEqual(durable.source.utf8, first.utf8)
        XCTAssertEqual(durable.source.digest, first.digest)
        try await store.close()
    }

    func testUnavailableKeysAreTypedAndPreserveTheStoredSnapshot() async throws {
        let workspace = try TempWorkspace()
        defer { workspace.remove() }
        let documentID = DocumentID()
        let key = testKey()
        let provider = InMemoryKeyProvider(key: key)
        let store = try makeStore(workspace, provider: provider)
        let first = try makeSnapshot(documentID, 1, "preserve me")
        _ = try await store.persist(batch(first))

        let missing: RecoveryKeyError = .missing
        let denied: RecoveryKeyError = .denied("The user dismissed the prompt.")
        let locked: RecoveryKeyError = .locked("The keychain is locked.")

        for (failure, expected) in [
            (missing, StorageError.keyMissing),
            (denied, StorageError.keyDenied("The user dismissed the prompt.")),
            (locked, StorageError.keyLocked("The keychain is locked."))
        ] {
            provider.useFailure(failure)
            do {
                _ = try await store.persist(batch(try makeSnapshot(documentID, 2, "must not land")))
                XCTFail("An unavailable key must stop the write.")
            } catch let error as StorageError {
                XCTAssertEqual(error, expected)
            }
            let state = try await store.recover(documentID)
            guard case .keyUnavailable = state else {
                return XCTFail("An unavailable key must report keyUnavailable, received \(state).")
            }
            let status = await store.recoveryKeyStatus()
            XCTAssertTrue(status.isUnavailable, "Expected an unavailable key status, received \(status).")
        }

        provider.useKey(key)
        let restoredStatus = await store.recoveryKeyStatus()
        XCTAssertEqual(restoredStatus, .available)
        let recovered = try await store.recover(documentID)
        guard case .complete(let durable) = recovered else {
            return XCTFail("The stored snapshot must remain readable once the key returns.")
        }
        XCTAssertEqual(durable.source.utf8, first.utf8)
        let index = try await store.recoveryIndex(for: documentID)
        XCTAssertEqual(index.count, 1, "No replacement snapshot may be written while the key is unavailable.")
        try await store.close()
    }

    // MARK: - Authenticated context layout

    func testAuthenticatedContextHasFixedLayoutAndFullUInt64Range() throws {
        let documentID = DocumentID()
        let stream = RecoveryStreamID(UUID())
        let digest = SourceSnapshot.sha256(Data("x".utf8))

        let maximum = RecoveryCipher.aad(
            documentID: documentID,
            streamID: stream,
            chunkIndex: .max,
            revision: Revision(.max),
            sourceDigest: digest,
            byteCount: 1,
            previousReference: RecoveryCipher.genesisReference
        )
        XCTAssertEqual(maximum.count, RecoveryCipher.aadByteCount)
        XCTAssertEqual(maximum.count, 133)
        XCTAssertEqual(StorageEncoding.uint64(.max), Data(repeating: 0xFF, count: 8))
        let maximumBytes = try StorageEncoding.decodeUInt64(StorageEncoding.uint64(.max))
        XCTAssertEqual(maximumBytes, UInt64.max)

        let genesis = RecoveryCipher.aad(
            documentID: documentID,
            streamID: stream,
            chunkIndex: 0,
            revision: Revision(0),
            sourceDigest: digest,
            byteCount: 1,
            previousReference: RecoveryCipher.genesisReference
        )
        XCTAssertNotEqual(maximum, genesis)

        let otherDocument = RecoveryCipher.aad(
            documentID: DocumentID(),
            streamID: stream,
            chunkIndex: .max,
            revision: Revision(.max),
            sourceDigest: digest,
            byteCount: 1,
            previousReference: RecoveryCipher.genesisReference
        )
        XCTAssertNotEqual(maximum, otherDocument)

        let otherPrevious = RecoveryCipher.aad(
            documentID: documentID,
            streamID: stream,
            chunkIndex: .max,
            revision: Revision(.max),
            sourceDigest: digest,
            byteCount: 1,
            previousReference: Data(repeating: 0x5A, count: 32)
        )
        XCTAssertNotEqual(maximum, otherPrevious)
    }

    // MARK: - Helpers

    private func chunk(_ index: UInt64) -> String {
        hexLiteral(StorageEncoding.uint64(index))
    }

    private func seedTwoRevisions(
        _ workspace: TempWorkspace,
        key: SymmetricKey,
        documentID: DocumentID
    ) async throws -> (SourceSnapshot, SourceSnapshot) {
        let store = try makeStore(workspace, key: key)
        let first = try makeSnapshot(documentID, 1, "AAAA")
        let second = try makeSnapshot(documentID, 2, "BBBB")
        _ = try await store.persist(batch(first))
        _ = try await store.persist(batch(second))
        try await store.close()
        return (first, second)
    }

    private func assertTamperIsDetected(
        _ statement: String,
        function: String = #function
    ) async throws {
        let workspace = try TempWorkspace()
        defer { workspace.remove() }
        let key = testKey()
        let documentID = DocumentID()
        _ = try await seedTwoRevisions(workspace, key: key, documentID: documentID)

        let raw = try RawDatabase(path: workspace.databaseURL.path)
        try raw.execute(statement)

        let store = try makeStore(workspace, key: key)
        let state = try await store.recover(documentID)
        guard case .corrupt = state else {
            return XCTFail("\(function): tampered storage must report corruption, received \(state).")
        }
        try await store.close()
    }
}

private extension RecoveryKeyStatus {
    var isUnavailable: Bool {
        switch self {
        case .missing, .denied, .locked, .unavailable: return true
        case .available: return false
        }
    }
}
