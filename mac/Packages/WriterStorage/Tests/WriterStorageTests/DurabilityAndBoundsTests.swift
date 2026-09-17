import CryptoKit
import Foundation
import WriterFoundation
@testable import WriterStorage
import XCTest

/// Repairs from review: suspension-safe reads, honest key status, the required
/// durability configuration, and the input/size bounds.
final class DurabilityAndBoundsTests: XCTestCase {

    // MARK: - Suspension safety

    /// `recover` reads the index, then awaits the key. A write that commits during
    /// that suspension must not be reported as superseded.
    func testRecoverRereadsTheIndexAfterTheKeySuspension() async throws {
        let workspace = try TempWorkspace()
        defer { workspace.remove() }
        let key = testKey()
        let documentID = DocumentID()
        let provider = GatedKeyProvider(key: key)
        let store = try makeStore(workspace, provider: provider)
        _ = try await store.persist(batch(try makeSnapshot(documentID, 1, "AAAA")))

        provider.gateNextLoads(1)
        let recovering = Task { try await store.recover(documentID) }
        let parked = await provider.waitForParkedLoads(1)
        XCTAssertTrue(parked, "The recovery key load must park.")

        // Commit revision 2 while the recovery is suspended on its key load, then
        // release it. The key is already parked, so this write is not gated.
        _ = try await store.persist(batch(try makeSnapshot(documentID, 2, "BBBB")))
        provider.openGate()

        let state = try await recovering.value
        guard case .complete(let durable) = state else {
            return XCTFail("Expected a complete recovery state, received \(state).")
        }
        XCTAssertEqual(
            durable.source.revision,
            Revision(2),
            "A revision committed during the key suspension must not be reported as superseded."
        )
        XCTAssertEqual(durable.source.utf8, Data("BBBB".utf8))
        try await store.close()
    }

    func testReadsCloseAfterTheKeySuspensionInsteadOfTouchingAClosedStore() async throws {
        let workspace = try TempWorkspace()
        defer { workspace.remove() }
        let key = testKey()
        let documentID = DocumentID()

        // recover: a closed store is a typed failure, not a pretend state.
        do {
            let provider = GatedKeyProvider(key: key)
            let store = try makeStore(workspace, provider: provider)
            _ = try await store.persist(batch(try makeSnapshot(documentID, 1, "AAAA")))
            provider.gateNextLoads(1)
            let recovering = Task { try await store.recover(documentID) }
            let parked = await provider.waitForParkedLoads(1)
            XCTAssertTrue(parked)
            try await store.close()
            provider.openGate()
            do {
                _ = try await recovering.value
                XCTFail("Recovery on a concurrently closed store must fail.")
            } catch let error as StorageError {
                XCTAssertEqual(error, .storeClosed)
            }
        }

        // recoverSnapshot: same guarantee on the snapshot read path.
        do {
            let provider = GatedKeyProvider(key: key)
            let store = try makeStore(workspace, provider: provider)
            provider.gateNextLoads(1)
            let reading = Task { try await store.recoverSnapshot(documentID, revision: Revision(1)) }
            let parked = await provider.waitForParkedLoads(1)
            XCTAssertTrue(parked)
            try await store.close()
            provider.openGate()
            do {
                _ = try await reading.value
                XCTFail("A snapshot read on a concurrently closed store must fail.")
            } catch let error as StorageError {
                XCTAssertEqual(error, .storeClosed)
            }
        }

        // recoveryKeyStatus: reports unavailable rather than claiming a usable key.
        do {
            let provider = GatedKeyProvider(key: key)
            let store = try makeStore(workspace, provider: provider)
            provider.gateNextLoads(1)
            let status = Task { await store.recoveryKeyStatus() }
            let parked = await provider.waitForParkedLoads(1)
            XCTAssertTrue(parked)
            try await store.close()
            provider.openGate()
            guard case .unavailable = await status.value else {
                return XCTFail("Key status on a closed store must be unavailable.")
            }
        }
    }

    // MARK: - Key status honesty

    /// A key check that cannot be read is never reported as an available key.
    func testKeyStatusIsUnavailableWhenTheKeyCheckCannotBeRead() async throws {
        let workspace = try TempWorkspace()
        defer { workspace.remove() }
        let key = testKey()
        let documentID = DocumentID()

        let store = try makeStore(workspace, key: key)
        _ = try await store.persist(batch(try makeSnapshot(documentID, 1, "AAAA")))
        try await store.close()

        let raw = try RawDatabase(path: workspace.databaseURL.path)
        try raw.execute("DROP TABLE storage_meta")

        let reopened = try makeStore(workspace, key: key)
        let status = await reopened.recoveryKeyStatus()
        guard case .unavailable = status else {
            return XCTFail(
                "A store whose key check cannot be read must not report the key as available, received \(status)."
            )
        }
        // Recovery of an unreadable index is reported as corrupt, never complete.
        let state = try await reopened.recover(documentID)
        guard case .corrupt = state else {
            return XCTFail("Expected a corrupt recovery state, received \(state).")
        }
        try await reopened.close()
    }

    // MARK: - Durability configuration

    /// WAL with synchronous=FULL, and fullfsync on macOS, verified as reported by
    /// SQLite on the live connection rather than assumed from the statements sent.
    func testRequiredDurabilityPragmasAreEffective() async throws {
        let workspace = try TempWorkspace()
        defer { workspace.remove() }
        let store = try makeStore(workspace)
        let report = try await store.durabilityReportForTesting()
        XCTAssertEqual(report.journalMode.lowercased(), "wal")
        XCTAssertEqual(report.synchronous, DurabilityReport.synchronousFull)
        #if os(macOS)
        XCTAssertEqual(report.fullfsync, 1, "fullfsync defaults to off and must be turned on explicitly.")
        #endif
        XCTAssertTrue(report.isAsRequired)
        try await store.close()
    }

    // MARK: - Input and ciphertext bounds

    func testInvalidConfiguredBoundsFailBeforeOpeningDatabase() throws {
        let workspace = try TempWorkspace()
        defer { workspace.remove() }
        for bound in [-1, 0, Int.max] {
            XCTAssertThrowsError(try DocumentStore(
                configuration: DocumentStoreConfiguration(databaseURL: workspace.databaseURL,
                                                          maximumSourceBytes: bound),
                keyProvider: InMemoryKeyProvider(key: testKey())))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.databaseURL.path))
    }

    func testSourceBeyondTheInputBoundIsRefusedBeforeEncryption() async throws {
        let workspace = try TempWorkspace()
        defer { workspace.remove() }
        let documentID = DocumentID()
        // A small byte bound keeps the test cheap; the product default is 8 MiB.
        let store = try DocumentStore(
            configuration: DocumentStoreConfiguration(
                databaseURL: workspace.databaseURL,
                maximumSourceBytes: 1_024,
                maximumSourceScalars: 100
            ),
            keyProvider: InMemoryKeyProvider(key: testKey()),
            clock: MonotonicClock(),
            uuidGenerator: CountingUUIDGenerator(),
            nonceGenerator: CountingNonceGenerator()
        )

        // Too many bytes, within the scalar bound.
        do {
            _ = try await store.persist(batch(try makeSnapshot(documentID, 1, Data(repeating: 0x41, count: 1_025))))
            XCTFail("A source beyond the byte bound must be refused.")
        } catch let error as StorageError {
            guard case .sourceBeyondInputBound(let byteCount, _, let maximumBytes, _) = error else {
                return XCTFail("Expected sourceBeyondInputBound, received \(error).")
            }
            XCTAssertEqual(byteCount, 1_025)
            XCTAssertEqual(maximumBytes, 1_024)
        }

        // Too many scalars, within the byte bound.
        do {
            _ = try await store.persist(batch(try makeSnapshot(documentID, 2, String(repeating: "a", count: 101))))
            XCTFail("A source beyond the scalar bound must be refused.")
        } catch let error as StorageError {
            guard case .sourceBeyondInputBound(let byteCount, let scalarCount, _, let maximumScalars) = error else {
                return XCTFail("Expected sourceBeyondInputBound, received \(error).")
            }
            XCTAssertEqual(byteCount, 101)
            XCTAssertEqual(scalarCount, 101)
            XCTAssertEqual(maximumScalars, 100)
        }

        // A refused source leaves nothing durable.
        let metadata = try await store.documentMetadata(for: documentID)
        XCTAssertNil(metadata)

        // A source inside both bounds is accepted.
        let accepted = try await store.persist(batch(try makeSnapshot(documentID, 3, "ok")))
        XCTAssertEqual(accepted.source.revision, Revision(3))
        try await store.close()
    }

    /// A stored blob larger than one admissible snapshot is refused before it is
    /// copied out of SQLite or decrypted.
    func testOversizedStoredCiphertextIsRefusedAsCorrupt() async throws {
        let workspace = try TempWorkspace()
        defer { workspace.remove() }
        let key = testKey()
        let documentID = DocumentID()
        let store = try makeStore(workspace, key: key)
        _ = try await store.persist(batch(try makeSnapshot(documentID, 1, "AAAA")))
        try await store.close()

        let raw = try RawDatabase(path: workspace.databaseURL.path)
        let oversized = 8 * 1024 * 1024 + RecoveryCipher.tagByteCount + 1
        try raw.execute("UPDATE recovery_chunks SET sealed = zeroblob(\(oversized))")

        let reopened = try makeStore(workspace, key: key)
        let state = try await reopened.recover(documentID)
        guard case .corrupt(let reason) = state else {
            return XCTFail("An oversized stored snapshot must be reported as corrupt, received \(state).")
        }
        XCTAssertTrue(
            reason.contains("exceeds the maximum accepted size"),
            "The refusal must be the size bound, received: \(reason)"
        )
        try await reopened.close()
    }
}
