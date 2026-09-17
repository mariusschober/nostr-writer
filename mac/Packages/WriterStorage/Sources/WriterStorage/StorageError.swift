import CSQLite
import Foundation

/// Typed failures of the encrypted recovery storage core.
///
/// Every case is an outcome the caller can act on. Messages deliberately carry
/// no source text, key material or document content: the recovery store must not
/// leak private writing through an error path.
public enum StorageError: Error, Equatable, Sendable {
    /// The installation recovery key does not exist. This is never a request to create one.
    case keyMissing
    /// The key provider denied access to the recovery key.
    case keyDenied(String)
    /// The key provider is locked, for example a locked keychain or session.
    case keyLocked(String)
    /// The key provider failed for another reason.
    case keyUnavailable(String)
    /// A key is available but does not match this store's recorded installation key.
    case keyMismatch
    /// The offered revision is older than the durable latest revision.
    case staleRevision(latest: UInt64, attempted: UInt64)
    /// The offered revision equals the durable latest revision but with different bytes.
    case conflictingRevision(revision: UInt64)
    /// Authenticated decryption failed, or stored identity metadata disagrees with the payload.
    case tamperDetected(String)
    /// The file is not a usable database, or its schema is not the expected one.
    case corruptDatabase(String)
    /// The file declares a schema version this build does not understand.
    case unsupportedSchemaVersion(found: Int, supported: Int)
    /// A migration could not be applied. The original database is left intact.
    case migrationFailed(String)
    /// The recovery ciphertext budget cannot hold another authenticated snapshot.
    case recoveryBudgetExceeded(limit: Int, required: Int)
    /// SQLite reported SQLITE_FULL.
    case diskFull(String)
    /// A filesystem or SQLite operation failed.
    case ioFailure(String)
    /// The connection could not be put into the durability configuration this
    /// store requires, so a commit could not be promised as durable.
    case durabilitySettingsUnavailable(String)
    /// The offered source is larger than the product's hard editor input bound.
    case sourceBeyondInputBound(byteCount: Int, scalarCount: Int, maximumBytes: Int, maximumScalars: Int)
    /// No retained recovery snapshot matches the requested revision.
    case revisionNotFound
    /// The supplied mutation receipts are not a consistent chain for the source.
    case receiptInconsistency(String)
    /// A caller-supplied value cannot be used by this store.
    case invariantViolation(String)
    /// The store was already closed.
    case storeClosed
}

extension StorageError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .keyMissing:
            return "The recovery key for this installation was not found. Writing was not changed and no replacement key was created."
        case .keyDenied(let reason):
            return "Access to the recovery key was denied. Private work is preserved. \(reason)"
        case .keyLocked(let reason):
            return "The recovery key is locked and cannot be used yet. Private work is preserved. \(reason)"
        case .keyUnavailable(let reason):
            return "The recovery key is not available. Private work is preserved. \(reason)"
        case .keyMismatch:
            return "The available recovery key does not match the key recorded for this store. Nothing was overwritten."
        case .staleRevision:
            return "A newer revision of this document is already stored, so this older revision was not written."
        case .conflictingRevision:
            return "This revision number is already stored with different content. The stored snapshot was kept."
        case .tamperDetected(let reason):
            return "The stored recovery snapshot failed authentication and was not used. \(reason)"
        case .corruptDatabase(let reason):
            return "The recovery store could not be read as a valid database. \(reason)"
        case .unsupportedSchemaVersion(let found, let supported):
            return "The recovery store uses schema version \(found); this build supports up to \(supported). It was not modified."
        case .migrationFailed(let reason):
            return "A recovery store migration could not be completed. The previous database is preserved. \(reason)"
        case .recoveryBudgetExceeded(let limit, let required):
            return "The recovery store cannot hold another encrypted snapshot within its \(limit)-byte budget (needs \(required)). Nothing was deleted from the document source."
        case .diskFull(let reason):
            return "There is not enough space to store the recovery snapshot. Your writing was not changed. \(reason)"
        case .ioFailure(let reason):
            return "The recovery store could not complete the storage operation. \(reason)"
        case .durabilitySettingsUnavailable(let reason):
            return "The recovery store could not be placed into its required durable configuration, so nothing was written. \(reason)"
        case .sourceBeyondInputBound(let byteCount, let scalarCount, let maximumBytes, let maximumScalars):
            return "This source (\(byteCount) bytes, \(scalarCount) scalars) is beyond the editor input bound of \(maximumBytes) bytes and \(maximumScalars) scalars, so it was not stored for recovery. The document itself was not changed."
        case .revisionNotFound:
            return "No retained recovery snapshot matches that revision."
        case .receiptInconsistency(let reason):
            return "The supplied editing receipts do not form a consistent chain for this source. \(reason)"
        case .invariantViolation(let reason):
            return "The recovery store rejected an unusable value. \(reason)"
        case .storeClosed:
            return "The recovery store is closed."
        }
    }
}

extension StorageError {
    /// Maps a SQLite result code to a typed storage failure.
    static func fromSQLite(code: Int32, message: String) -> StorageError {
        switch code & 0xFF {
        case SQLITE_FULL:
            return .diskFull(message)
        case SQLITE_CORRUPT, SQLITE_NOTADB:
            return .corruptDatabase(message)
        case SQLITE_CONSTRAINT:
            return .invariantViolation("SQLite rejected a constraint: \(message)")
        default:
            return .ioFailure(message)
        }
    }

    /// Maps an injected key-provider failure, keeping missing/denied/locked distinct.
    init(keyError: RecoveryKeyError) {
        switch keyError {
        case .missing: self = .keyMissing
        case .denied(let reason): self = .keyDenied(reason)
        case .locked(let reason): self = .keyLocked(reason)
        case .unavailable(let reason): self = .keyUnavailable(reason)
        }
    }
}
