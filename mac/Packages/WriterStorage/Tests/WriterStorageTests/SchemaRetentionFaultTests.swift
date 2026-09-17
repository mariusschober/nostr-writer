import CryptoKit
import Foundation
import WriterFoundation
@testable import WriterStorage
import XCTest

final class SchemaRetentionFaultTests: XCTestCase {

    // MARK: - Schema lifecycle

    func testCorruptDatabaseFileIsRejectedWithATypedError() throws {
        let workspace = try TempWorkspace()
        defer { workspace.remove() }
        try Data(repeating: 0x41, count: 8192).write(to: workspace.databaseURL)

        XCTAssertThrowsError(try makeStore(workspace)) { error in
            guard case StorageError.corruptDatabase = error else {
                return XCTFail("Expected corruptDatabase, received \(error).")
            }
        }
    }

    func testCurrentSchemaIsCreatedOnceAndReopensCleanly() async throws {
        let workspace = try TempWorkspace()
        defer { workspace.remove() }
        let key = testKey()
        let documentID = DocumentID()

        let store = try makeStore(workspace, key: key)
        _ = try await store.persist(batch(try makeSnapshot(documentID, 1, "kept")))
        try await store.close()

        let raw = try RawDatabase(path: workspace.databaseURL.path)
        XCTAssertEqual(try raw.integer("PRAGMA user_version"), DocumentStore.currentSchemaVersion)
        XCTAssertEqual(
            try raw.integer("""
                SELECT COUNT(*) FROM sqlite_master WHERE type = 'table'
                AND name IN ('storage_meta', 'documents', 'recovery_chunks')
                """),
            3
        )

        let reopened = try makeStore(workspace, key: key)
        let state = try await reopened.recover(documentID)
        guard case .complete(let durable) = state else {
            return XCTFail("A current-version store must reopen without a migration, received \(state).")
        }
        XCTAssertEqual(durable.source.utf8, Data("kept".utf8))
        try await reopened.close()
    }

    func testUnsupportedHigherSchemaVersionIsRejectedWithoutChange() async throws {
        let workspace = try TempWorkspace()
        defer { workspace.remove() }
        let key = testKey()
        let documentID = DocumentID()

        let store = try makeStore(workspace, key: key)
        _ = try await store.persist(batch(try makeSnapshot(documentID, 1, "abc")))
        try await store.close()

        let raw = try RawDatabase(path: workspace.databaseURL.path)
        try raw.execute("PRAGMA user_version = 99")

        XCTAssertThrowsError(try makeStore(workspace, key: key)) { error in
            guard case StorageError.unsupportedSchemaVersion(let found, let supported) = error else {
                return XCTFail("Expected unsupportedSchemaVersion, received \(error).")
            }
            XCTAssertEqual(found, 99)
            XCTAssertEqual(supported, DocumentStore.currentSchemaVersion)
        }

        let after = try RawDatabase(path: workspace.databaseURL.path)
        XCTAssertEqual(try after.integer("PRAGMA user_version"), 99)
        XCTAssertEqual(try after.integer("SELECT COUNT(*) FROM recovery_chunks"), 1)
    }

    // MARK: - Migration machinery (synthetic plan; not a product schema)

    func testSyntheticMigrationBacksUpFirstThenApplies() async throws {
        let workspace = try TempWorkspace()
        defer { workspace.remove() }
        let key = testKey()
        let documentID = DocumentID()

        let store = try makeStore(workspace, key: key)
        _ = try await store.persist(batch(try makeSnapshot(documentID, 1, "survives migration")))
        try await store.close()

        let migration = SchemaMigration(
            steps: [
                SchemaMigration.Step(fromVersion: DocumentStore.currentSchemaVersion, toVersion: DocumentStore.currentSchemaVersion + 1) { database in
                    try database.execute("CREATE TABLE synthetic_step (id INTEGER PRIMARY KEY)")
                }
            ],
            supportedVersion: DocumentStore.currentSchemaVersion + 1
        )
        let connection = try SQLiteConnection(path: workspace.databaseURL.path, busyTimeoutMilliseconds: 1_000)
        try migration.run(
            on: connection,
            databaseURL: workspace.databaseURL,
            fileSystem: SystemStorageFileSystem(),
            clock: MonotonicClock()
        )
        XCTAssertEqual(try connection.userVersion(), DocumentStore.currentSchemaVersion + 1)
        XCTAssertTrue(try connection.tableNames().contains("synthetic_step"))
        try connection.checkpointAndClose()

        // The backup is discovered on disk: it is written by SQLite's backup API,
        // not by a file copy the test could observe through a seam.
        let backups = backupFiles(in: workspace.root)
        XCTAssertEqual(backups.count, 1)
        let backupURL = try XCTUnwrap(backups.first)
        XCTAssertGreaterThan(try SystemStorageFileSystem().fileSize(at: backupURL), 0)

        // The backup is a complete pre-migration copy and the migrated store keeps
        // the original encrypted snapshot.
        let backup = try RawDatabase(path: backupURL.path)
        XCTAssertEqual(try backup.integer("PRAGMA user_version"), DocumentStore.currentSchemaVersion)
        XCTAssertEqual(try backup.integer("SELECT COUNT(*) FROM recovery_chunks"), 1)
        let migrated = try RawDatabase(path: workspace.databaseURL.path)
        XCTAssertEqual(try migrated.integer("PRAGMA user_version"), DocumentStore.currentSchemaVersion + 1)
        XCTAssertEqual(try migrated.integer("SELECT COUNT(*) FROM recovery_chunks"), 1)
    }

    /// A pre-migration backup is never allowed to replace an existing file.
    func testBackupRefusesAnExistingDestinationWithoutReplacingIt() throws {
        let workspace = try TempWorkspace()
        defer { workspace.remove() }
        let destination = workspace.url("existing.sqlite")
        let original = Data("an earlier artifact that must survive".utf8)
        try original.write(to: destination)

        let connection = try SQLiteConnection(
            path: workspace.databaseURL.path,
            busyTimeoutMilliseconds: 1_000
        )
        defer { connection.close() }
        XCTAssertThrowsError(try connection.backup(to: destination.path)) { error in
            guard case StorageError.migrationFailed = error else {
                return XCTFail("Expected migrationFailed, received \(error).")
            }
        }
        XCTAssertEqual(
            try Data(contentsOf: destination),
            original,
            "An existing backup must never be replaced."
        )
    }

    func testFailedSyntheticMigrationRollsBackAndLeavesVersionOneUsable() async throws {
        let workspace = try TempWorkspace()
        defer { workspace.remove() }
        let key = testKey()
        let documentID = DocumentID()

        let store = try makeStore(workspace, key: key)
        _ = try await store.persist(batch(try makeSnapshot(documentID, 1, "still readable")))
        try await store.close()

        let migration = SchemaMigration(
            steps: [
                SchemaMigration.Step(fromVersion: DocumentStore.currentSchemaVersion, toVersion: DocumentStore.currentSchemaVersion + 1) { database in
                    try database.execute("CREATE TABLE synthetic_step (id INTEGER PRIMARY KEY)")
                    throw StorageError.migrationFailed("Synthetic step failure.")
                }
            ],
            supportedVersion: DocumentStore.currentSchemaVersion + 1
        )
        let connection = try SQLiteConnection(path: workspace.databaseURL.path, busyTimeoutMilliseconds: 1_000)
        XCTAssertThrowsError(
            try migration.run(
                on: connection,
                databaseURL: workspace.databaseURL,
                fileSystem: SystemStorageFileSystem(),
                clock: MonotonicClock()
            )
        ) { error in
            guard case StorageError.migrationFailed = error else {
                return XCTFail("Expected migrationFailed, received \(error).")
            }
        }
        XCTAssertEqual(try connection.userVersion(), DocumentStore.currentSchemaVersion)
        XCTAssertFalse(try connection.tableNames().contains("synthetic_step"))
        try connection.checkpointAndClose()

        // The current-version store is still fully usable, including key handling.
        let reopened = try makeStore(workspace, key: key)
        let state = try await reopened.recover(documentID)
        guard case .complete(let durable) = state else {
            return XCTFail("A failed migration must leave the current version usable, received \(state).")
        }
        XCTAssertEqual(durable.source.utf8, Data("still readable".utf8))
        try await reopened.close()
    }

    func testMissingMigrationStepIsReportedInsteadOfInventingASchema() async throws {
        let workspace = try TempWorkspace()
        defer { workspace.remove() }
        let store = try makeStore(workspace)
        try await store.close()

        let migration = SchemaMigration(steps: [], supportedVersion: DocumentStore.currentSchemaVersion + 1)
        let connection = try SQLiteConnection(path: workspace.databaseURL.path, busyTimeoutMilliseconds: 1_000)
        XCTAssertThrowsError(
            try migration.run(
                on: connection,
                databaseURL: workspace.databaseURL,
                fileSystem: SystemStorageFileSystem(),
                clock: MonotonicClock()
            )
        ) { error in
            guard case StorageError.migrationFailed = error else {
                return XCTFail("Expected migrationFailed, received \(error).")
            }
        }
        XCTAssertEqual(try connection.userVersion(), DocumentStore.currentSchemaVersion)
        try connection.checkpointAndClose()
    }

    // MARK: - Injected faults

    func testFaultsBeforeInsertAndBeforeCommitRollBackCompletely() async throws {
        for point in [StorageFaultPoint.beforeInsert, .beforeCommit] {
            let workspace = try TempWorkspace()
            defer { workspace.remove() }
            let store = try makeStore(workspace, faultInjector: ScriptedFaultInjector([point]))
            let documentID = DocumentID()

            do {
                _ = try await store.persist(batch(try makeSnapshot(documentID, 1, "never durable")))
                XCTFail("\(point) must stop the write.")
            } catch let error as TestFault {
                XCTAssertEqual(error, .boom(point))
            }

            let state = try await store.recover(documentID)
            guard case .absent = state else {
                return XCTFail("\(point): nothing may be durable, received \(state).")
            }
            let all = try await store.allDocumentMetadata()
            XCTAssertEqual(all.count, 0, "\(point): no index row may survive.")
            try await store.close()
        }
    }

    func testFaultAfterCommitLeavesTheRevisionDurableAndRecoverable() async throws {
        let workspace = try TempWorkspace()
        defer { workspace.remove() }
        let store = try makeStore(workspace, faultInjector: ScriptedFaultInjector([.afterCommit]))
        let documentID = DocumentID()
        let snapshot = try makeSnapshot(documentID, 1, "durable despite the surfaced error")

        do {
            _ = try await store.persist(batch(snapshot))
            XCTFail("The injected after-commit failure must surface.")
        } catch let error as TestFault {
            XCTAssertEqual(error, .boom(.afterCommit))
        }

        let state = try await store.recover(documentID)
        guard case .complete(let durable) = state else {
            return XCTFail("A committed revision must never be lost, received \(state).")
        }
        XCTAssertEqual(durable.source.utf8, snapshot.utf8)
        XCTAssertEqual(durable.source.digest, snapshot.digest)
        let metadata = try await store.documentMetadata(for: documentID)
        XCTAssertEqual(metadata?.latestRevision, Revision(1))
        try await store.close()
    }

    // MARK: - Concurrency and actor reentrancy

    func testConcurrentIdenticalWritesProduceExactlyOneSnapshot() async throws {
        let workspace = try TempWorkspace()
        defer { workspace.remove() }
        let store = try makeStore(workspace)
        let documentID = DocumentID()
        let snapshot = try makeSnapshot(documentID, 5, "one and the same revision")

        let results = await withTaskGroup(of: Result<DurableRevision, Error>.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    do {
                        return .success(try await store.persist(batch(snapshot)))
                    } catch {
                        return .failure(error)
                    }
                }
            }
            var collected: [Result<DurableRevision, Error>] = []
            for await result in group { collected.append(result) }
            return collected
        }

        XCTAssertEqual(results.count, 8)
        let commits = try results.map { try $0.get().recoveryCommit }
        XCTAssertEqual(Set(commits).count, 1, "Concurrent identical retries must share one commit identity.")
        let index = try await store.recoveryIndex(for: documentID)
        XCTAssertEqual(index.count, 1)
        try await store.close()
    }

    func testConcurrentIncreasingWritesKeepTheHighestRevision() async throws {
        let workspace = try TempWorkspace()
        defer { workspace.remove() }
        let store = try makeStore(workspace)
        let documentID = DocumentID()
        let snapshots = try (1...8).map { revision in
            try makeSnapshot(documentID, UInt64(revision), "revision \(revision) bytes")
        }

        let results = await withTaskGroup(of: Result<DurableRevision, Error>.self) { group in
            for snapshot in snapshots {
                group.addTask {
                    do {
                        return .success(try await store.persist(batch(snapshot)))
                    } catch {
                        return .failure(error)
                    }
                }
            }
            var collected: [Result<DurableRevision, Error>] = []
            for await result in group { collected.append(result) }
            return collected
        }

        var successes = 0
        for result in results {
            switch result {
            case .success:
                successes += 1
            case .failure(let error):
                guard let storageError = error as? StorageError,
                      case .staleRevision = storageError else {
                    return XCTFail("Racing writes may only fail as stale, received \(error).")
                }
            }
        }

        let metadata = try await store.documentMetadata(for: documentID)
        XCTAssertEqual(metadata?.latestRevision, Revision(8), "The highest offered revision must win.")
        XCTAssertEqual(metadata?.latestDigest, snapshots[7].digest)
        let index = try await store.recoveryIndex(for: documentID)
        XCTAssertEqual(index.count, min(successes, 2))
        let state = try await store.recover(documentID)
        guard case .complete(let durable) = state else {
            return XCTFail("Expected a complete recovery state.")
        }
        XCTAssertEqual(durable.source.utf8, snapshots[7].utf8)
        try await store.close()
    }

    // MARK: - Bounded retention

    func testRollingRecoveryStaysBoundedAndBudgetFailurePreservesBothDocuments() async throws {
        let workspace = try TempWorkspace()
        defer { workspace.remove() }
        let store = try makeStore(workspace, budget: 2_000)
        let documentID = DocumentID()
        for revision in 1...20 {
            let bytes = Data(repeating: 0x41, count: 512)
            _ = try await store.persist(batch(try makeSnapshot(documentID, UInt64(revision), bytes)))
        }
        let checkpoints = try await store.recoveryIndex(for: documentID)
        XCTAssertEqual(checkpoints.map(\.sourceRevision), [Revision(19), Revision(20)])
        XCTAssertEqual(checkpoints.map(\.chunkIndex), [18, 19])
        let report = try await store.pruneRecoverySnapshots(toFitBudget: 0)
        XCTAssertEqual(report.removedSnapshots, 0)
        XCTAssertEqual(report.remainingCiphertextBytes, 1_056)

        let secondDocument = DocumentID()
        _ = try await store.persist(batch(try makeSnapshot(secondDocument, 1, Data(repeating: 0x42, count: 512))))
        do {
            _ = try await store.persist(batch(try makeSnapshot(secondDocument, 2, Data(repeating: 0x43, count: 512))))
            XCTFail("Two mandatory checkpoints per document cannot fit this budget.")
        } catch let error as StorageError {
            guard case .recoveryBudgetExceeded(let limit, let required) = error else {
                return XCTFail("Expected recoveryBudgetExceeded, received \(error).")
            }
            XCTAssertEqual(limit, 2_000)
            XCTAssertEqual(required, 2_112)
        }
        let firstIndex = try await store.recoveryIndex(for: documentID)
        let secondIndex = try await store.recoveryIndex(for: secondDocument)
        XCTAssertEqual(firstIndex.map(\.sourceRevision), [Revision(19), Revision(20)])
        XCTAssertEqual(secondIndex.map(\.sourceRevision), [Revision(1)])
        try await store.close()
    }

    func testPruningRollsBackWhenCommitFails() async throws {
        let workspace = try TempWorkspace()
        defer { workspace.remove() }
        let nonces = CountingNonceGenerator()
        let documentID = DocumentID()
        let original = try makeStore(workspace, nonceGenerator: nonces)
        for revision in 1...2 {
            _ = try await original.persist(batch(try makeSnapshot(documentID, UInt64(revision), "revision \(revision)")))
        }
        try await original.close()
        let failing = try makeStore(workspace, nonceGenerator: nonces,
                                    faultInjector: ScriptedFaultInjector([.beforeCommit]))
        do {
            _ = try await failing.persist(batch(try makeSnapshot(documentID, 3, "new revision")))
            XCTFail("The injected failure must abort the whole transaction.")
        } catch let error as TestFault {
            XCTAssertEqual(error, .boom(.beforeCommit))
        }
        let index = try await failing.recoveryIndex(for: documentID)
        XCTAssertEqual(index.map(\.sourceRevision), [Revision(1), Revision(2)])
        let recovered = try await failing.recoverSnapshot(documentID, revision: Revision(1))
        XCTAssertEqual(recovered.utf8, Data("revision 1".utf8))
        try await failing.close()
    }

    // MARK: - Real disk exhaustion

    func testRealSQLiteFullIsReportedAsDiskFullAndRollsBack() async throws {
        let workspace = try TempWorkspace()
        defer { workspace.remove() }
        let key = testKey()
        let documentID = DocumentID()
        let small = try makeSnapshot(documentID, 1, "small")

        // One generator across both store instances: a deterministic nonce source
        // must not hand the same nonce to a second writer for the same key.
        let nonces = CountingNonceGenerator()
        var store = try makeStore(workspace, key: key, nonceGenerator: nonces)
        _ = try await store.persist(batch(small))
        try await store.close()

        store = try makeStore(workspace, key: key, nonceGenerator: nonces)
        let pages = try await store.pageCountForTesting()
        try await store.setMaximumPageCountForTesting(pages + 4)
        let maximum = try await store.maximumPageCountForTesting()
        XCTAssertLessThanOrEqual(maximum, pages + 4, "The page limit must be applied for a real SQLITE_FULL.")

        let oversized = try SourceSnapshot(
            documentID: documentID,
            revision: Revision(2),
            utf8: Data(repeating: 0x42, count: 512 * 1024)
        )
        do {
            _ = try await store.persist(batch(oversized))
            XCTFail("A database that cannot grow must report SQLITE_FULL.")
        } catch let error as StorageError {
            guard case .diskFull = error else {
                return XCTFail("Expected diskFull for SQLITE_FULL, received \(error).")
            }
        }

        // The failed write must roll back completely and leave the store usable.
        let index = try await store.recoveryIndex(for: documentID)
        XCTAssertEqual(index.count, 1)
        let metadata = try await store.documentMetadata(for: documentID)
        XCTAssertEqual(metadata?.latestRevision, Revision(1))
        let state = try await store.recover(documentID)
        guard case .complete(let durable) = state else {
            return XCTFail("The previous snapshot must survive disk exhaustion.")
        }
        XCTAssertEqual(durable.source.utf8, small.utf8)
        try await store.close()
    }
}
