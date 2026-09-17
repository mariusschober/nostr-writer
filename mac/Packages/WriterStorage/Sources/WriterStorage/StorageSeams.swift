import CryptoKit
import Foundation

/// Injected, load-only source of the installation recovery key.
///
/// The core never generates, rotates or replaces a key. A missing, denied or
/// locked key is a distinct failure that preserves whatever is already stored.
public protocol RecoveryKeyProviding: Sendable {
    func loadRecoveryKey() async throws -> SymmetricKey
}

/// Typed reasons a key provider may fail. The core keeps them distinct.
public enum RecoveryKeyError: Error, Equatable, Sendable {
    case missing
    case denied(String)
    case locked(String)
    case unavailable(String)
}

/// Injected wall clock. Kept as epoch seconds so tests can be deterministic.
public protocol StorageClock: Sendable {
    func nowEpoch() -> Double
}

public struct SystemStorageClock: StorageClock {
    public init() {}
    public func nowEpoch() -> Double { Date().timeIntervalSince1970 }
}

/// Injected UUID source for recovery-stream and commit identities.
public protocol StorageUUIDGenerating: Sendable {
    func nextUUID() -> UUID
}

public struct SystemStorageUUIDGenerator: StorageUUIDGenerating {
    public init() {}
    public func nextUUID() -> UUID { UUID() }
}

/// Injected AEAD nonce source. Production uses the system random generator; a
/// test can substitute a deterministic sequence to exercise nonce handling.
public protocol RecoveryNonceGenerating: Sendable {
    func nextNonce() throws -> Data
}

public struct SystemRecoveryNonceGenerator: RecoveryNonceGenerating {
    public init() {}
    public func nextNonce() throws -> Data { Data(AES.GCM.Nonce()) }
}

/// Narrow filesystem surface needed by the core: creating the store directory
/// and inspecting backup files. No user document file is ever touched, and this
/// seam deliberately has no copy or delete operation: pre-migration backups are
/// written by SQLite's backup API and are never replaced.
public protocol StorageFileSystem: Sendable {
    func createDirectory(at url: URL) throws
    func fileExists(at url: URL) -> Bool
    func fileSize(at url: URL) throws -> Int
}

public struct SystemStorageFileSystem: StorageFileSystem {
    public init() {}

    public func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func fileSize(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = attributes[.size] as? NSNumber else {
            throw StorageError.ioFailure("The file size could not be read.")
        }
        return size.intValue
    }
}

/// Explicit fault-injection points for tests. Production installs the no-op.
public enum StorageFaultPoint: String, Equatable, Sendable {
    case beforeInsert, beforeCommit, afterCommit
}

public protocol StorageFaultInjecting: Sendable {
    func checkpoint(_ point: StorageFaultPoint) throws
}

public struct NoStorageFaultInjection: StorageFaultInjecting {
    public init() {}
    public func checkpoint(_ point: StorageFaultPoint) throws {}
}
