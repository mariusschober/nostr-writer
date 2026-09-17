import CSQLite
import CryptoKit
import Foundation
import WriterFoundation
import WriterStorage

// MARK: - Injected seams for deterministic tests

enum TestFault: Error, Equatable {
    case boom(StorageFaultPoint)
}

/// Load-only key provider with a controllable outcome. Never generates a key.
final class InMemoryKeyProvider: RecoveryKeyProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var outcome: Result<SymmetricKey, RecoveryKeyError>

    init(key: SymmetricKey) {
        self.outcome = .success(key)
    }

    init(failure: RecoveryKeyError) {
        self.outcome = .failure(failure)
    }

    func useKey(_ key: SymmetricKey) {
        lock.lock(); defer { lock.unlock() }
        outcome = .success(key)
    }

    func useFailure(_ failure: RecoveryKeyError) {
        lock.lock(); defer { lock.unlock() }
        outcome = .failure(failure)
    }

    func loadRecoveryKey() async throws -> SymmetricKey {
        try lock.withLock {
            switch outcome {
            case .success(let key): return key
            case .failure(let error): throw error
            }
        }
    }
}

/// Monotonic injected clock so retention ordering is deterministic.
final class MonotonicClock: StorageClock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Double

    init(start: Double = 1_000) { self.current = start }

    func nowEpoch() -> Double {
        lock.lock(); defer { lock.unlock() }
        current += 1
        return current
    }
}

final class CountingUUIDGenerator: StorageUUIDGenerating, @unchecked Sendable {
    private let lock = NSLock()
    private var counter: UInt64 = 0

    func nextUUID() -> UUID {
        lock.lock(); defer { lock.unlock() }
        counter += 1
        let suffix = String(format: "%012llX", counter)
        return UUID(uuidString: "00000000-0000-4000-8000-\(suffix)")!
    }
}

/// Distinct deterministic nonces.
final class CountingNonceGenerator: RecoveryNonceGenerating, @unchecked Sendable {
    private let lock = NSLock()
    private var counter: UInt64 = 0

    func nextNonce() throws -> Data {
        lock.lock(); defer { lock.unlock() }
        counter += 1
        var out = Data(repeating: 0, count: 12)
        out.replaceSubrange(4..<12, with: withUnsafeBytes(of: counter.bigEndian) { Data($0) })
        return out
    }
}

/// Always returns the same nonce, to prove the store refuses AEAD nonce reuse.
final class RepeatingNonceGenerator: RecoveryNonceGenerating, @unchecked Sendable {
    private let nonce: Data
    init(nonce: Data = Data(repeating: 0xAB, count: 12)) { self.nonce = nonce }
    func nextNonce() throws -> Data { nonce }
}

/// Load-only key provider that parks a chosen number of upcoming key loads, so a
/// test can act while the store is suspended at exactly that point.
final class GatedKeyProvider: RecoveryKeyProviding, @unchecked Sendable {
    private let lock = NSLock()
    private let key: SymmetricKey
    private var gate = 0
    private var parked = 0
    private var open = true

    init(key: SymmetricKey) { self.key = key }

    /// Parks the next `count` key loads. Later loads are unaffected.
    func gateNextLoads(_ count: Int) {
        lock.lock(); defer { lock.unlock() }
        gate = count
        parked = 0
        open = count == 0
    }

    /// Lets every parked load finish.
    func openGate() {
        lock.lock(); defer { lock.unlock() }
        open = true
        gate = 0
    }

    var parkedLoads: Int {
        lock.lock(); defer { lock.unlock() }
        return parked
    }

    func loadRecoveryKey() async throws -> SymmetricKey {
        let shouldPark: Bool = lock.withLock {
            guard gate > 0 else { return false }
            gate -= 1
            parked += 1
            return true
        }
        if shouldPark {
            while !(lock.withLock { open }) {
                try await Task.sleep(nanoseconds: 1_000_000)
            }
        }
        return key
    }

    /// Waits until `count` loads are parked, or reports that they never parked.
    func waitForParkedLoads(_ count: Int) async -> Bool {
        for _ in 0..<4_000 {
            if parkedLoads >= count { return true }
            try? await Task.sleep(nanoseconds: 500_000)
        }
        return parkedLoads >= count
    }
}

final class ScriptedFaultInjector: StorageFaultInjecting, @unchecked Sendable {
    private let points: Set<StorageFaultPoint>
    init(_ points: Set<StorageFaultPoint>) { self.points = points }
    func checkpoint(_ point: StorageFaultPoint) throws {
        if points.contains(point) { throw TestFault.boom(point) }
    }
}

// MARK: - Fixtures

/// Pre-migration backup files present in a store directory, oldest first.
func backupFiles(in directory: URL) -> [URL] {
    allFiles(in: directory)
        .filter { $0.lastPathComponent.contains(".backup-v") && $0.pathExtension == "sqlite" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
}

struct TempWorkspace {
    let root: URL

    init() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("WriterStorageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    var databaseURL: URL { root.appendingPathComponent("recovery.sqlite") }
    func url(_ name: String) -> URL { root.appendingPathComponent(name) }
    func remove() { try? FileManager.default.removeItem(at: root) }
}

func testKey(_ byte: UInt8 = 0x11) -> SymmetricKey {
    SymmetricKey(data: Data(repeating: byte, count: 32))
}

func makeSnapshot(_ documentID: DocumentID, _ revision: UInt64, _ bytes: Data) throws -> SourceSnapshot {
    try SourceSnapshot(documentID: documentID, revision: Revision(revision), utf8: bytes)
}

func makeSnapshot(_ documentID: DocumentID, _ revision: UInt64, _ text: String) throws -> SourceSnapshot {
    try makeSnapshot(documentID, revision, Data(text.utf8))
}

func batch(_ snapshot: SourceSnapshot, receipts: [MutationReceipt] = []) -> RecoveryBatch {
    RecoveryBatch(source: snapshot, receipts: receipts)
}

func configuration(
    _ workspace: TempWorkspace,
    budget: Int = 256 * 1024 * 1024,
    floor: Int = 2
) -> DocumentStoreConfiguration {
    DocumentStoreConfiguration(
        databaseURL: workspace.databaseURL,
        recoveryCiphertextBudget: budget,
        minimumRetainedSnapshotsPerDocument: floor
    )
}

func makeStore(
    _ workspace: TempWorkspace,
    key: SymmetricKey = testKey(),
    budget: Int = 256 * 1024 * 1024,
    floor: Int = 2,
    nonceGenerator: RecoveryNonceGenerating = CountingNonceGenerator(),
    faultInjector: StorageFaultInjecting = NoStorageFaultInjection(),
    fileSystem: StorageFileSystem = SystemStorageFileSystem()
) throws -> DocumentStore {
    try DocumentStore(
        configuration: configuration(workspace, budget: budget, floor: floor),
        keyProvider: InMemoryKeyProvider(key: key),
        clock: MonotonicClock(),
        uuidGenerator: CountingUUIDGenerator(),
        nonceGenerator: nonceGenerator,
        fileSystem: fileSystem,
        faultInjector: faultInjector
    )
}

func makeStore(
    _ workspace: TempWorkspace,
    provider: RecoveryKeyProviding,
    budget: Int = 256 * 1024 * 1024,
    floor: Int = 2
) throws -> DocumentStore {
    try DocumentStore(
        configuration: configuration(workspace, budget: budget, floor: floor),
        keyProvider: provider,
        clock: MonotonicClock(),
        uuidGenerator: CountingUUIDGenerator(),
        nonceGenerator: CountingNonceGenerator(),
        fileSystem: SystemStorageFileSystem(),
        faultInjector: NoStorageFaultInjection()
    )
}

// MARK: - Raw file and database inspection

/// Files that make up the SQLite store: database, write-ahead log, shared memory.
func storeFiles(_ databaseURL: URL) -> [URL] {
    [
        databaseURL,
        URL(fileURLWithPath: databaseURL.path + "-wal"),
        URL(fileURLWithPath: databaseURL.path + "-shm")
    ]
}

/// Every regular file under `root`, recursively. Used to prove that no auxiliary
/// file - backup, journal, log or stray temp copy - carries plaintext writing.
func allFiles(in root: URL) -> [URL] {
    guard let enumerator = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: [.isRegularFileKey]
    ) else { return [] }
    var files: [URL] = []
    for case let url as URL in enumerator {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
        if values?.isRegularFile == true { files.append(url) }
    }
    return files
}

func readIfPresent(_ url: URL) -> Data? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    return try? Data(contentsOf: url)
}

/// Names of store files whose raw bytes contain `needle`.
func filesContaining(_ needle: Data, in urls: [URL]) -> [String] {
    urls.compactMap { url in
        guard let bytes = readIfPresent(url) else { return nil }
        return bytes.range(of: needle) == nil ? nil : url.lastPathComponent
    }
}

/// Every plausible raw encoding of a plaintext marker.
func plaintextNeedles(_ text: String) -> [Data] {
    let utf8 = Data(text.utf8)
    var needles = [utf8]
    if let utf16 = text.data(using: .utf16) { needles.append(utf16) }
    if let utf16le = text.data(using: .utf16LittleEndian) { needles.append(utf16le) }
    if let utf16be = text.data(using: .utf16BigEndian) { needles.append(utf16be) }
    return needles
}

func hexLiteral(_ data: Data) -> String {
    "X'" + data.map { String(format: "%02X", $0) }.joined() + "'"
}

/// Minimal raw SQLite access. Test-only: production exposes no SQL surface.
final class RawDatabase {
    private var handle: OpaquePointer?

    init(path: String) throws {
        var handle: OpaquePointer?
        let result = sqlite3_open_v2(path, &handle, SQLITE_OPEN_READWRITE, nil)
        guard result == SQLITE_OK, let handle else {
            throw StorageError.ioFailure("The test could not open the database directly.")
        }
        self.handle = handle
    }

    deinit {
        if let handle { sqlite3_close_v2(handle) }
    }

    func execute(_ sql: String) throws {
        guard let handle else { throw StorageError.storeClosed }
        var error: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(handle, sql, nil, nil, &error)
        guard result == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "unknown"
            if let error { sqlite3_free(error) }
            throw StorageError.ioFailure("Raw statement failed: \(message)")
        }
    }

    func integer(_ sql: String) throws -> Int {
        guard let handle else { throw StorageError.storeClosed }
        var statement: OpaquePointer?
        let prepared = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard prepared == SQLITE_OK, let statement else {
            throw StorageError.ioFailure("Raw query could not be prepared.")
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw StorageError.ioFailure("Raw query returned no row.")
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    func blob(_ sql: String) throws -> Data? {
        guard let handle else { throw StorageError.storeClosed }
        var statement: OpaquePointer?
        let prepared = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard prepared == SQLITE_OK, let statement else {
            throw StorageError.ioFailure("Raw query could not be prepared.")
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        guard let bytes = sqlite3_column_blob(statement, 0) else { return nil }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
    }

    func text(_ sql: String) throws -> String? {
        guard let handle else { throw StorageError.storeClosed }
        var statement: OpaquePointer?
        let prepared = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard prepared == SQLITE_OK, let statement else {
            throw StorageError.ioFailure("Raw query could not be prepared.")
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        guard let pointer = sqlite3_column_text(statement, 0) else { return nil }
        return String(cString: pointer)
    }
}
