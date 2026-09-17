import Foundation

/// Versioned schema handling for the application-private recovery store.
///
/// Schema version 1 is the first schema this project has ever written. No
/// earlier schema is invented. Forward steps are explicit, must advance exactly
/// one version, and always take a verified backup of the database file first.
struct SchemaMigration {
    /// One forward-only migration step.
    struct Step {
        let fromVersion: Int
        let toVersion: Int
        let apply: (SQLiteConnection) throws -> Void
    }

    let steps: [Step]
    let supportedVersion: Int

    /// Version 2 adds bounded document-location metadata. Existing version 1
    /// recovery is backed up by the common migration path before any change.
    static var standard: SchemaMigration {
        SchemaMigration(steps: [Step(fromVersion: 1, toVersion: 2, apply: createCatalog)], supportedVersion: DocumentStore.currentSchemaVersion)
    }

    func run(
        on database: SQLiteConnection,
        databaseURL: URL,
        fileSystem: StorageFileSystem,
        clock: StorageClock
    ) throws {
        let existingTables = try database.tableNames()
        let version = try database.userVersion()

        if version == 0 {
            guard existingTables.isEmpty else {
                throw StorageError.corruptDatabase("The database has tables but declares schema version 0.")
            }
            try database.withTransaction {
                try Self.createSchemaVersion1(on: database)
                var installed = 1
                while installed < supportedVersion {
                    guard let step = steps.first(where: { $0.fromVersion == installed }), step.toVersion == installed + 1 else {
                        throw StorageError.migrationFailed("The initial schema has no defined next step.")
                    }
                    try step.apply(database); installed = step.toVersion
                }
                try database.setUserVersion(installed)
            }
            return
        }

        guard version <= supportedVersion else {
            throw StorageError.unsupportedSchemaVersion(found: version, supported: supportedVersion)
        }

        var current = version
        while current < supportedVersion {
            guard let step = steps.first(where: { $0.fromVersion == current }) else {
                throw StorageError.migrationFailed("No migration step is defined from schema version \(current).")
            }
            guard step.toVersion == current + 1 else {
                throw StorageError.migrationFailed("A migration step must advance exactly one schema version.")
            }
            try backup(
                database: database,
                databaseURL: databaseURL,
                fromVersion: current,
                fileSystem: fileSystem,
                clock: clock
            )
            try database.withTransaction {
                try step.apply(database)
                try database.setUserVersion(step.toVersion)
            }
            // A failed step rolls back inside `withTransaction`, so an applied
            // version different from the step target is an honest hard failure.
            let applied = try database.userVersion()
            guard applied == step.toVersion else {
                throw StorageError.migrationFailed("The database did not record the migrated schema version.")
            }
            current = applied
        }
    }

    private static func createCatalog(on database: SQLiteConnection) throws {
        try database.execute("""
            CREATE TABLE document_catalog (
                document_id TEXT PRIMARY KEY,
                location_key TEXT UNIQUE,
                metadata BLOB NOT NULL,
                updated_at REAL NOT NULL
            )
            """)
    }

    // MARK: - Backup

    /// Writes a verified, collision-safe pre-migration backup before any schema
    /// change.
    ///
    /// The copy uses SQLite's online backup API rather than a file copy, so
    /// content still held in the write-ahead log is included. An existing file is
    /// never replaced, and the finished backup must report the pre-migration
    /// schema version before the migration is allowed to proceed.
    private func backup(
        database: SQLiteConnection,
        databaseURL: URL,
        fromVersion: Int,
        fileSystem: StorageFileSystem,
        clock: StorageClock
    ) throws {
        let stamp = Int(clock.nowEpoch())
        let directory = databaseURL.deletingLastPathComponent()
        let base = "\(databaseURL.lastPathComponent).backup-v\(fromVersion)-\(stamp)"
        var backupURL = directory.appendingPathComponent("\(base).sqlite")
        var suffix = 0
        while fileSystem.fileExists(at: backupURL) {
            suffix += 1
            guard suffix <= 1_000 else {
                throw StorageError.migrationFailed("No unused pre-migration backup name was available.")
            }
            backupURL = directory.appendingPathComponent("\(base)-\(suffix).sqlite")
        }

        try database.backup(to: backupURL.path)

        let backupSize = try fileSystem.fileSize(at: backupURL)
        guard backupSize > 0 else {
            throw StorageError.migrationFailed("The pre-migration backup is empty.")
        }
        let recordedVersion = try SQLiteConnection.readUserVersion(at: backupURL.path)
        guard recordedVersion == fromVersion else {
            throw StorageError.migrationFailed(
                "The pre-migration backup records schema version \(recordedVersion) instead of \(fromVersion)."
            )
        }
    }

    // MARK: - Schema version 1

    private static let schemaVersion1Statements = [
        """
        CREATE TABLE storage_meta (
            key TEXT PRIMARY KEY,
            value BLOB NOT NULL
        )
        """,
        """
        CREATE TABLE documents (
            document_id TEXT PRIMARY KEY,
            latest_revision BLOB NOT NULL,
            latest_digest BLOB NOT NULL,
            stream_id TEXT NOT NULL,
            latest_chunk_index BLOB NOT NULL,
            latest_chunk_ref BLOB NOT NULL,
            latest_commit_id TEXT NOT NULL,
            latest_byte_count INTEGER NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        )
        """,
        """
        CREATE TABLE recovery_chunks (
            document_id TEXT NOT NULL,
            stream_id TEXT NOT NULL,
            chunk_index BLOB NOT NULL,
            source_revision BLOB NOT NULL,
            source_digest BLOB NOT NULL,
            byte_count INTEGER NOT NULL,
            previous_ref BLOB NOT NULL,
            nonce BLOB NOT NULL,
            sealed BLOB NOT NULL,
            chunk_ref BLOB NOT NULL,
            commit_id TEXT NOT NULL,
            committed_at REAL NOT NULL,
            PRIMARY KEY (document_id, stream_id, chunk_index)
        )
        """,
        // Reusing a nonce with one key breaks AES-GCM, so the store refuses it.
        "CREATE UNIQUE INDEX recovery_chunks_nonce ON recovery_chunks(nonce)",
        // Deterministic oldest-first order for bounded retention pruning.
        "CREATE INDEX recovery_chunks_commit_order ON recovery_chunks(committed_at, document_id, chunk_index)"
    ]

    /// Note: `chunk_index` and `source_revision` are 8-byte big-endian BLOBs, not
    /// INTEGERs, so the full UInt64 range survives and byte order equals numeric
    /// order. Future outbox/history tables belong in a later schema step; none is
    /// created here.
    private static func createSchemaVersion1(on database: SQLiteConnection) throws {
        for statement in schemaVersion1Statements {
            try database.execute(statement)
        }
    }
}
