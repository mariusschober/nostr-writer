import Foundation
import WriterFoundation

/// Identity of one explicit recovery stream.
///
/// A recovery stream is the recovery store's own recording identity. It is
/// deliberately not an HWP capture-run identity; the two must not be conflated.
public struct RecoveryStreamID: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: UUID

    public init(rawValue: UUID) { self.rawValue = rawValue }
    public init(_ rawValue: UUID) { self.rawValue = rawValue }

    public var description: String { rawValue.uuidString }
}

/// How the durable set of recovery checkpoints is bounded.
///
/// This store holds *disposable recovery checkpoints* of a document source, not
/// consented private capture history. Selecting `rollingJournal` is an explicit
/// owner decision to treat them as a bounded, renewable set; it must never be
/// selected for immutable capture history, which is a separate store.
public enum RecoveryRetentionPolicy: Sendable, Equatable {
    /// Nothing is removed implicitly. Space is reclaimed only through an explicit
    /// `pruneRecoverySnapshots` call, which reports exactly what it removed.
    case keepAllCheckpoints
    /// A commit removes the checkpoints it supersedes, inside the same
    /// transaction that makes its replacement durable, keeping only the newest
    /// `minimumRetainedSnapshotsPerDocument` for that document.
    case rollingJournal
}

/// Configuration for one application-private recovery store.
public struct DocumentStoreConfiguration: Sendable {
    /// Location of the application-private SQLite file. Never a document file.
    public let databaseURL: URL
    /// Reserved global ceiling on authenticated recovery ciphertext, in bytes.
    ///
    /// A snapshot that would push the store past this ceiling is refused with
    /// `StorageError.recoveryBudgetExceeded` and the commit rolls back. Under
    /// `.rollingJournal` the superseded checkpoints have already been reclaimed
    /// inside that transaction, so the ceiling applies to the bounded set; under
    /// `.keepAllCheckpoints` space is reclaimed only by an explicit
    /// `pruneRecoverySnapshots` call.
    public let recoveryCiphertextBudget: Int
    /// Number of newest recovery checkpoints retained per document (at least two).
    /// This is also the hard floor for explicit cleanup. It does not govern the
    /// retention of detailed private writing history, which is a separate store.
    public let minimumRetainedSnapshotsPerDocument: Int
    /// SQLite busy timeout, so a second reader/writer can finish.
    public let busyTimeoutMilliseconds: Int
    /// Hard bound on one accepted source, in bytes. Matches the product's editor
    /// input bound (8 MiB); a larger source is refused rather than truncated.
    public let maximumSourceBytes: Int
    /// Hard bound on one accepted source, in Unicode scalars. Matches the
    /// product's editor input bound.
    public let maximumSourceScalars: Int
    /// Whether superseded recovery checkpoints are reclaimed by the commit that
    /// supersedes them, or retained until an explicit owner prune.
    public let retentionPolicy: RecoveryRetentionPolicy

    public init(
        databaseURL: URL,
        recoveryCiphertextBudget: Int = 256 * 1024 * 1024,
        minimumRetainedSnapshotsPerDocument: Int = 2,
        busyTimeoutMilliseconds: Int = 5_000,
        maximumSourceBytes: Int = 8 * 1024 * 1024,
        maximumSourceScalars: Int = 1_000_000,
        retentionPolicy: RecoveryRetentionPolicy = .keepAllCheckpoints
    ) {
        self.databaseURL = databaseURL
        self.recoveryCiphertextBudget = recoveryCiphertextBudget
        self.minimumRetainedSnapshotsPerDocument = minimumRetainedSnapshotsPerDocument
        self.busyTimeoutMilliseconds = busyTimeoutMilliseconds
        self.maximumSourceBytes = maximumSourceBytes
        self.maximumSourceScalars = maximumSourceScalars
        self.retentionPolicy = retentionPolicy
    }

    /// Largest ciphertext this store will accept for one snapshot: the plaintext
    /// bound plus the AES-GCM tag. Checked before any untrusted blob is read, so
    /// a hostile row cannot make the store allocate unbounded memory.
    var maximumCiphertextBytes: Int {
        maximumSourceBytes + RecoveryCipher.tagByteCount
    }

    /// Rejects a source beyond the product's hard editor input bound.
    func validateInputBound(byteCount: Int, scalarCount: Int) throws {
        guard byteCount <= maximumSourceBytes, scalarCount <= maximumSourceScalars else {
            throw StorageError.sourceBeyondInputBound(
                byteCount: byteCount,
                scalarCount: scalarCount,
                maximumBytes: maximumSourceBytes,
                maximumScalars: maximumSourceScalars
            )
        }
    }
}

/// Durable index facts about one document. Contains no writing.
public struct DocumentMetadata: Sendable, Equatable {
    public let documentID: DocumentID
    public let latestRevision: Revision
    public let latestDigest: Data
    public let streamID: RecoveryStreamID
    public let latestChunkIndex: UInt64
    public let latestCommitID: UUID
    public let updatedAt: Double
    public let chunkCount: Int
    public let ciphertextBytes: Int
}

/// Durable index facts about one retained authenticated recovery snapshot.
public struct RecoveryChunkInfo: Sendable, Equatable {
    public let streamID: RecoveryStreamID
    public let chunkIndex: UInt64
    public let sourceRevision: Revision
    public let sourceDigest: Data
    public let byteCount: Int
    public let nonce: Data
    public let ciphertextBytes: Int
    public let commitID: UUID
    public let committedAt: Double
}

/// Outcome of an explicit retention cleanup. Reported so the owner can see
/// exactly what was removed by explicit recovery cleanup.
public struct RecoveryPruneReport: Sendable, Equatable {
    public let removedSnapshots: Int
    public let removedCiphertextBytes: Int
    public let remainingSnapshots: Int
    public let remainingCiphertextBytes: Int
}

/// Distinguishes missing, denied, locked and otherwise-unavailable keys without
/// exposing key material.
public enum RecoveryKeyStatus: Sendable, Equatable {
    case available
    case missing
    case denied(String)
    case locked(String)
    case unavailable(String)
}

/// Fixed-width, explicitly ordered encoding for every value that is bound into
/// authenticated context or stored in SQLite.
enum StorageEncoding {
    static func uint16(_ value: UInt16) -> Data {
        var out = Data(capacity: 2)
        out.append(UInt8(truncatingIfNeeded: value >> 8))
        out.append(UInt8(truncatingIfNeeded: value))
        return out
    }

    /// Big-endian UInt64. Full 64-bit range is preserved; byte order matches
    /// numeric order, so a SQLite BLOB comparison is also a numeric comparison.
    static func uint64(_ value: UInt64) -> Data {
        var out = Data(capacity: 8)
        for shift in stride(from: 56, through: 0, by: -8) {
            out.append(UInt8(truncatingIfNeeded: value >> UInt64(shift)))
        }
        return out
    }

    static func decodeUInt64(_ data: Data) throws -> UInt64 {
        guard data.count == 8 else {
            throw StorageError.corruptDatabase("A stored 64-bit value does not have 8 bytes.")
        }
        var value: UInt64 = 0
        for byte in data { value = (value << 8) | UInt64(byte) }
        return value
    }

    static func uuid(_ value: UUID) -> Data {
        let parts = value.uuid
        return Data([
            parts.0, parts.1, parts.2, parts.3, parts.4, parts.5, parts.6, parts.7,
            parts.8, parts.9, parts.10, parts.11, parts.12, parts.13, parts.14, parts.15
        ])
    }

    static func uuidString(_ value: UUID) -> String { value.uuidString }

    static func decodeUUID(_ data: Data) throws -> UUID {
        guard data.count == 16 else {
            throw StorageError.corruptDatabase("A stored identifier does not have 16 bytes.")
        }
        let bytes = [UInt8](data)
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
