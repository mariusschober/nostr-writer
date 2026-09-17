import CSQLite
import Foundation

/// SQLite asks for a copy of bound memory by being given this sentinel destructor.
private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// The durability configuration this store requires, as SQLite reports it back.
/// Values are read from the live connection, not assumed from the statements sent.
struct DurabilityReport: Equatable, Sendable {
    let journalMode: String
    let synchronous: Int
    let fullfsync: Int

    static let synchronousFull = 2

    var isAsRequired: Bool {
        #if os(macOS)
        return journalMode.lowercased() == "wal"
            && synchronous == Self.synchronousFull
            && fullfsync == 1
        #else
        return journalMode.lowercased() == "wal" && synchronous == Self.synchronousFull
        #endif
    }
}

/// One serialized connection to the application-private recovery database.
///
/// The actor that owns this object is the only caller, so every statement runs
/// on one connection. All SQL text is a compile-time constant; caller data is
/// only ever bound as a parameter. The single exception is a schema version
/// number written through `PRAGMA user_version`, which SQLite cannot bind and
/// which is range-checked before use.
final class SQLiteConnection {
    private var handle: OpaquePointer?
    let path: String

    init(path: String, busyTimeoutMilliseconds: Int) throws {
        self.path = path
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(path, &handle, flags, nil)
        guard result == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "The database could not be opened."
            if let handle { sqlite3_close_v2(handle) }
            throw StorageError.fromSQLite(code: result, message: message)
        }
        self.handle = handle
        sqlite3_busy_timeout(handle, Int32(clamping: max(0, busyTimeoutMilliseconds)))
        do {
            try configureDurability()
            try execute("PRAGMA foreign_keys = ON")
        } catch {
            close()
            throw error
        }
    }

    deinit { close() }

    /// WAL with synchronous=FULL, plus fullfsync on macOS, then verifies that
    /// SQLite reports the values back. `PRAGMA fullfsync` defaults to off, so a
    /// commit would otherwise be durable against power loss only after an
    /// ordinary `fsync`; this store promises the stronger primitive.
    private func configureDurability() throws {
        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA synchronous = FULL")
        #if os(macOS)
        try execute("PRAGMA fullfsync = ON")
        #endif
        let report = try durabilityReport()
        guard report.isAsRequired else {
            throw StorageError.durabilitySettingsUnavailable(
                "journal_mode=\(report.journalMode), synchronous=\(report.synchronous), fullfsync=\(report.fullfsync)."
            )
        }
    }

    /// The durability pragmas as SQLite reports them, for verification and tests.
    func durabilityReport() throws -> DurabilityReport {
        let journal = try prepare("PRAGMA journal_mode")
        let journalMode = try journal.step() ? (journal.columnText(0) ?? "") : ""
        let synchronous = try prepare("PRAGMA synchronous")
        let synchronousValue = try synchronous.step() ? Int(synchronous.columnInt64(0)) : -1
        let fullfsync = try prepare("PRAGMA fullfsync")
        let fullfsyncValue = try fullfsync.step() ? Int(fullfsync.columnInt64(0)) : -1
        return DurabilityReport(
            journalMode: journalMode,
            synchronous: synchronousValue,
            fullfsync: fullfsyncValue
        )
    }

    private var rawHandle: OpaquePointer {
        get throws {
            guard let handle else { throw StorageError.storeClosed }
            return handle
        }
    }

    // MARK: - Statements and execution

    func execute(_ sql: String) throws {
        let handle = try rawHandle
        var errorPointer: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(handle, sql, nil, nil, &errorPointer)
        guard result == SQLITE_OK else {
            let message = errorPointer.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(handle))
            if let errorPointer { sqlite3_free(errorPointer) }
            throw StorageError.fromSQLite(code: result, message: message)
        }
    }

    func prepare(_ sql: String) throws -> SQLiteStatement {
        try SQLiteStatement(connection: try rawHandle, sql: sql)
    }

    func withTransaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let value = try body()
            try execute("COMMIT")
            return value
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    // MARK: - Schema helpers

    func userVersion() throws -> Int {
        let statement = try prepare("PRAGMA user_version")
        guard try statement.step() else { return 0 }
        return Int(statement.columnInt64(0))
    }

    func setUserVersion(_ version: Int) throws {
        // PRAGMA values cannot be bound. The version is an internal, range-checked
        // integer, never caller or document data.
        guard (0...1_000_000).contains(version) else {
            throw StorageError.invariantViolation("The schema version is outside the supported range.")
        }
        try execute("PRAGMA user_version = \(version)")
    }

    func tableNames() throws -> Set<String> {
        let statement = try prepare("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'")
        var names: Set<String> = []
        while try statement.step() {
            if let name = statement.columnText(0) { names.insert(name) }
        }
        return names
    }

    // MARK: - Teardown

    /// Flushes the write-ahead log into the database file, then closes.
    func checkpointAndClose() throws {
        guard handle != nil else { return }
        try execute("PRAGMA wal_checkpoint(TRUNCATE)")
        close()
    }

    // MARK: - Consistent backup

    /// Writes a consistent snapshot of this database into a new file using
    /// SQLite's online backup API.
    ///
    /// This is deliberately not a file copy: a copy can miss committed content
    /// still sitting in the write-ahead log. The destination is never an existing
    /// file, and the completed copy is verified for page count and integrity
    /// before it is accepted as a rollback point.
    func backup(to destinationPath: String) throws {
        let source = try rawHandle
        guard !FileManager.default.fileExists(atPath: destinationPath) else {
            throw StorageError.migrationFailed("A pre-migration backup already exists at that path; it was not overwritten.")
        }
        var destination: OpaquePointer?
        let openResult = sqlite3_open_v2(
            destinationPath,
            &destination,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard openResult == SQLITE_OK, let destination else {
            if let destination { sqlite3_close_v2(destination) }
            throw StorageError.fromSQLite(code: openResult, message: String(cString: sqlite3_errmsg(source)))
        }
        defer { sqlite3_close_v2(destination) }

        guard let backup = sqlite3_backup_init(destination, "main", source, "main") else {
            throw StorageError.migrationFailed(
                "The pre-migration backup could not start: \(String(cString: sqlite3_errmsg(destination)))"
            )
        }
        var stepResult = SQLITE_OK
        var attempts = 0
        while attempts < 20_000 {
            stepResult = sqlite3_backup_step(backup, 64)
            if stepResult == SQLITE_DONE { break }
            if stepResult == SQLITE_OK || stepResult == SQLITE_BUSY || stepResult == SQLITE_LOCKED {
                attempts += 1
                if stepResult != SQLITE_OK { sqlite3_sleep(10) }
                continue
            }
            break
        }
        let finishResult = sqlite3_backup_finish(backup)
        guard stepResult == SQLITE_DONE, finishResult == SQLITE_OK else {
            throw StorageError.migrationFailed(
                "The pre-migration backup did not complete: \(String(cString: sqlite3_errmsg(destination)))"
            )
        }

        // Verify the copy independently: same page count as the source, and a
        // clean integrity check on the destination file itself.
        let sourcePages = try scalarInt("PRAGMA page_count", on: source)
        let backupPages = try scalarInt("PRAGMA page_count", on: destination)
        guard sourcePages > 0, sourcePages == backupPages else {
            throw StorageError.migrationFailed(
                "The pre-migration backup has \(backupPages) pages where the database has \(sourcePages)."
            )
        }
        guard try integrityCheckIsClean(on: destination) else {
            throw StorageError.migrationFailed("The pre-migration backup failed its integrity check.")
        }
    }

    /// Reads `PRAGMA user_version` from a database file without changing it.
    static func readUserVersion(at path: String) throws -> Int {
        var handle: OpaquePointer?
        let result = sqlite3_open_v2(path, &handle, SQLITE_OPEN_READONLY, nil)
        guard result == SQLITE_OK, let handle else {
            if let handle { sqlite3_close_v2(handle) }
            throw StorageError.migrationFailed("The database file could not be opened for verification.")
        }
        defer { sqlite3_close_v2(handle) }
        let statement = try SQLiteStatement(connection: handle, sql: "PRAGMA user_version")
        guard try statement.step() else {
            throw StorageError.migrationFailed("The database file reported no schema version.")
        }
        return Int(statement.columnInt64(0))
    }

    private func scalarInt(_ sql: String, on handle: OpaquePointer) throws -> Int {
        let statement = try SQLiteStatement(connection: handle, sql: sql)
        guard try statement.step() else {
            throw StorageError.migrationFailed("An internal database check returned no row.")
        }
        return Int(statement.columnInt64(0))
    }

    private func integrityCheckIsClean(on handle: OpaquePointer) throws -> Bool {
        let statement = try SQLiteStatement(connection: handle, sql: "PRAGMA integrity_check")
        guard try statement.step() else { return false }
        return statement.columnText(0)?.lowercased() == "ok"
    }

    func close() {
        guard let handle else { return }
        self.handle = nil
        sqlite3_close_v2(handle)
    }
}

/// One prepared statement with bound parameters and typed column access.
final class SQLiteStatement {
    private let connection: OpaquePointer
    private let statement: OpaquePointer

    init(connection: OpaquePointer, sql: String) throws {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(connection, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else {
            throw StorageError.fromSQLite(code: result, message: String(cString: sqlite3_errmsg(connection)))
        }
        self.connection = connection
        self.statement = statement
    }

    deinit { sqlite3_finalize(statement) }

    // MARK: - Binding

    func bindBlob(_ index: Int32, _ value: Data) throws {
        let result: Int32
        if value.isEmpty {
            result = sqlite3_bind_zeroblob(statement, index, 0)
        } else {
            result = value.withUnsafeBytes { buffer in
                sqlite3_bind_blob(statement, index, buffer.baseAddress, Int32(buffer.count), sqliteTransient)
            }
        }
        try check(result)
    }

    func bindText(_ index: Int32, _ value: String) throws {
        try check(sqlite3_bind_text(statement, index, value, -1, sqliteTransient))
    }

    func bindInt64(_ index: Int32, _ value: Int64) throws {
        try check(sqlite3_bind_int64(statement, index, value))
    }

    func bindDouble(_ index: Int32, _ value: Double) throws {
        try check(sqlite3_bind_double(statement, index, value))
    }

    func clearBindings() {
        sqlite3_clear_bindings(statement)
        sqlite3_reset(statement)
    }

    // MARK: - Reading

    /// Advances the statement. Returns `true` when a row is available.
    @discardableResult
    func step() throws -> Bool {
        switch sqlite3_step(statement) {
        case SQLITE_ROW:
            return true
        case SQLITE_DONE:
            return false
        case let code:
            throw StorageError.fromSQLite(code: code, message: String(cString: sqlite3_errmsg(connection)))
        }
    }

    func columnBlob(_ index: Int32) -> Data? {
        guard let bytes = sqlite3_column_blob(statement, index) else { return nil }
        let count = Int(sqlite3_column_bytes(statement, index))
        guard count > 0 else { return Data() }
        return Data(bytes: bytes, count: count)
    }

    /// Declared byte length of a column without copying it out of SQLite. Used to
    /// apply a size bound to an untrusted stored blob before it is allocated.
    func columnByteCount(_ index: Int32) -> Int {
        Int(sqlite3_column_bytes(statement, index))
    }

    func requiredBlob(_ index: Int32) throws -> Data {
        guard let value = columnBlob(index) else {
            throw StorageError.corruptDatabase("A required stored value is missing.")
        }
        return value
    }

    func columnText(_ index: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: pointer)
    }

    func requiredText(_ index: Int32) throws -> String {
        guard let value = columnText(index) else {
            throw StorageError.corruptDatabase("A required stored value is missing.")
        }
        return value
    }

    func columnInt64(_ index: Int32) -> Int64 { sqlite3_column_int64(statement, index) }
    func columnDouble(_ index: Int32) -> Double { sqlite3_column_double(statement, index) }

    private func check(_ result: Int32) throws {
        guard result == SQLITE_OK else {
            throw StorageError.fromSQLite(code: result, message: String(cString: sqlite3_errmsg(connection)))
        }
    }
}
