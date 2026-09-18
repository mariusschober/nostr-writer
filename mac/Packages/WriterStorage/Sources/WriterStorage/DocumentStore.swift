import CryptoKit
import Foundation
import WriterFoundation

/// Durable, encrypted recovery storage for writing sessions.
///
/// The store owns one serialized SQLite connection in WAL mode with
/// `synchronous=FULL`. Source bytes are sealed with AES-GCM before any SQLite
/// call, so neither the database file, the write-ahead log, nor a SQLite error
/// can carry plaintext writing. Key material comes from an injected, load-only
/// provider; the store never generates, rotates or replaces a key.
///
/// Ordering guarantees:
/// - Snapshots commit in strictly increasing `Revision` order per document.
/// - A repeated offer of the newest revision with identical bytes is idempotent
///   and returns the original commit identity.
/// - A repeated revision with different bytes, or any older revision, is rejected.
/// - A `DurableRevision` is only ever returned after the enclosing transaction has
///   committed. The durable index is re-read after awaiting a key, because the
///   actor can be reentered at that suspension point.
/// - Under `.rollingJournal`, each commit retains the configured newest checkpoints
///   (at least two). Superseded source checkpoints are pruned in that transaction.
///   These are disposable recovery copies, never private capture/history records.
///   If the required checkpoints exceed the global budget, the transaction rolls
///   back completely, including pruning, and preserves prior recovery.
public actor DocumentStore: DocumentPersistence {

    /// Schema version this build writes and understands.
    public static let currentSchemaVersion = 3

    /// Metadata key holding the installation key check value.
    static let keyCheckValueKey = "key_check_value"

    private let database: SQLiteConnection
    private let configuration: DocumentStoreConfiguration
    private let keyProvider: RecoveryKeyProviding
    private let clock: StorageClock
    private let uuidGenerator: StorageUUIDGenerating
    private let nonceGenerator: RecoveryNonceGenerating
    private let fileSystem: StorageFileSystem
    private let faultInjector: StorageFaultInjecting
    private var isClosed = false
    private var installationLease: RecoveryInstallationLease?

    func retainInstallationLease(_ lease: RecoveryInstallationLease) { installationLease = lease }

    public init(
        configuration: DocumentStoreConfiguration,
        keyProvider: RecoveryKeyProviding,
        clock: StorageClock = SystemStorageClock(),
        uuidGenerator: StorageUUIDGenerating = SystemStorageUUIDGenerator(),
        nonceGenerator: RecoveryNonceGenerating = SystemRecoveryNonceGenerator(),
        fileSystem: StorageFileSystem = SystemStorageFileSystem(),
        faultInjector: StorageFaultInjecting = NoStorageFaultInjection()
    ) throws {
        guard configuration.minimumRetainedSnapshotsPerDocument >= 2 else {
            throw StorageError.invariantViolation("At least two recovery snapshots per document must be retained.")
        }
        guard configuration.recoveryCiphertextBudget > 0 else {
            throw StorageError.invariantViolation("The recovery ciphertext budget must be positive.")
        }
        guard (1...8 * 1024 * 1024).contains(configuration.maximumSourceBytes),
              (1...1_000_000).contains(configuration.maximumSourceScalars) else {
            throw StorageError.invariantViolation("Recovery input bounds must be positive and within the product limits.")
        }
        try fileSystem.createDirectory(at: configuration.databaseURL.deletingLastPathComponent())
        let database = try SQLiteConnection(
            path: configuration.databaseURL.path,
            busyTimeoutMilliseconds: configuration.busyTimeoutMilliseconds
        )
        do {
            try SchemaMigration.standard.run(
                on: database,
                databaseURL: configuration.databaseURL,
                fileSystem: fileSystem,
                clock: clock
            )
        } catch {
            database.close()
            throw error
        }
        self.database = database
        self.configuration = configuration
        self.keyProvider = keyProvider
        self.clock = clock
        self.uuidGenerator = uuidGenerator
        self.nonceGenerator = nonceGenerator
        self.fileSystem = fileSystem
        self.faultInjector = faultInjector
    }

    func catalogConnection() throws -> SQLiteConnection {
        guard !isClosed else { throw StorageError.storeClosed }
        return database
    }

    // MARK: - DocumentPersistence

    public func persist(_ batch: RecoveryBatch) async throws -> DurableRevision {
        guard !isClosed else { throw StorageError.storeClosed }
        try Self.validate(receipts: batch.receipts, against: batch.source)
        // The product's hard editor input bound is enforced before a key is
        // loaded or any bytes are encrypted, so an oversized source is refused
        // rather than being stored, truncated or silently skipped.
        try configuration.validateInputBound(
            byteCount: batch.source.utf8.count,
            scalarCount: batch.source.scalarCount
        )

        // The key is loaded before any transaction, and no await happens inside
        // the SQLite critical section below. A concurrent caller can therefore
        // only interleave at this suspension point, which `performPersist`
        // handles by re-reading the durable index.
        let key = try await loadRecoveryKey()
        let keyCheck = try RecoveryCipher.keyCheckValue(for: key)
        // `performPersist` re-checks `isClosed` and re-reads the durable index, so
        // a close or a concurrent commit during the key await cannot be missed.
        return try performPersist(batch: batch, key: key, keyCheck: keyCheck)
    }

    public func recover(_ id: DocumentID) async throws -> RecoveryState {
        guard !isClosed else { throw StorageError.storeClosed }

        // Fail fast on an unusable index, and report an unknown document without
        // loading a key. The pointer read below is the authoritative one.
        let initialPointer: StoredPointer?
        do {
            initialPointer = try readDocumentPointer(id)
        } catch let error as StorageError {
            return .corrupt(Self.summary(error))
        }
        guard initialPointer != nil else { return .absent }

        let key: SymmetricKey
        let keyCheck: Data
        do {
            key = try await loadRecoveryKey()
            keyCheck = try RecoveryCipher.keyCheckValue(for: key)
        } catch let error as StorageError {
            return .keyUnavailable(Self.summary(error))
        }

        // The actor was reentrant across the key await. A concurrent write may have
        // advanced the index, and another caller may have closed the store, so the
        // pre-await pointer must not be trusted to describe the current state.
        guard !isClosed else { throw StorageError.storeClosed }
        let pointer: StoredPointer?
        do {
            pointer = try readDocumentPointer(id)
        } catch let error as StorageError {
            return .corrupt(Self.summary(error))
        }
        guard let pointer else { return .absent }

        do {
            guard let storedKeyCheck = try readKeyCheckValue() else {
                return .corrupt("The recovery index has no installation key check value.")
            }
            guard storedKeyCheck == keyCheck else {
                return .keyUnavailable("The available recovery key does not match this store's recorded key.")
            }
            guard let chunk = try readChunk(
                documentID: id,
                streamID: pointer.streamID,
                chunkIndex: pointer.chunkIndex
            ) else {
                // The indexed latest snapshot is gone. Surface the newest still
                // readable snapshot as partial rather than claiming it is current.
                return try newestAuthenticatedPartial(
                    id,
                    key: key,
                    reasonPrefix: "The indexed recovery snapshot is missing."
                )
            }
            let snapshot = try decrypt(chunk, key: key)
            // The document index is an unauthenticated convenience row. It may
            // only confirm a snapshot it agrees with; if it disagrees with the
            // authenticated payload the store cannot call the result current.
            guard snapshot.revision == pointer.revision,
                  snapshot.digest == pointer.digest,
                  chunk.chunkReference == pointer.chunkReference else {
                return try newestAuthenticatedPartial(
                    id,
                    key: key,
                    reasonPrefix: "The recovery index disagrees with its authenticated snapshot."
                )
            }
            return .complete(
                DurableRevision(source: snapshot, recoveryCommit: chunk.commitID, savedFile: nil)
            )
        } catch let error as StorageError {
            return .corrupt(Self.summary(error))
        } catch {
            return .corrupt("The recovery snapshot could not be read.")
        }
    }

    /// Newest authenticated snapshot for a document, reported explicitly as
    /// partial. Used whenever the stored index cannot be trusted to describe the
    /// current state, so an older snapshot is never presented as current.
    private func newestAuthenticatedPartial(
        _ id: DocumentID,
        key: SymmetricKey,
        reasonPrefix: String
    ) throws -> RecoveryState {
        guard let newest = try readNewestChunk(documentID: id) else {
            return .corrupt("\(reasonPrefix) No recovery snapshot is readable.")
        }
        let snapshot = try decrypt(newest, key: key)
        return .localPartial(
            snapshot,
            reason: "\(reasonPrefix) The newest readable snapshot is revision \(snapshot.revision.rawValue)."
        )
    }

    // MARK: - Recovery and listing

    /// Decrypts one retained snapshot by revision. Callers can offer older
    /// authenticated snapshots without touching the document source.
    public func recoverSnapshot(_ id: DocumentID, revision: Revision) async throws -> SourceSnapshot {
        guard !isClosed else { throw StorageError.storeClosed }
        let key = try await loadRecoveryKey()
        // The store can be closed by another caller while this key load is
        // suspended, so the closed state is rechecked after the await.
        guard !isClosed else { throw StorageError.storeClosed }
        try requireMatchingKey(key)
        guard let chunk = try readChunk(documentID: id, revision: revision) else {
            throw StorageError.revisionNotFound
        }
        return try decrypt(chunk, key: key)
    }

    /// Durable index facts for every known document. Contains no writing.
    public func allDocumentMetadata() throws -> [DocumentMetadata] {
        guard !isClosed else { throw StorageError.storeClosed }
        let statement = try database.prepare("""
            SELECT d.document_id, d.latest_revision, d.latest_digest, d.stream_id,
                   d.latest_chunk_index, d.latest_commit_id, d.updated_at,
                   (SELECT COUNT(*) FROM recovery_chunks c WHERE c.document_id = d.document_id),
                   (SELECT COALESCE(SUM(length(c.sealed)), 0) FROM recovery_chunks c WHERE c.document_id = d.document_id)
            FROM documents d
            ORDER BY d.updated_at DESC, d.document_id ASC
            """)
        var result: [DocumentMetadata] = []
        while try statement.step() {
            result.append(try documentMetadata(from: statement))
        }
        return result
    }

    public func documentMetadata(for id: DocumentID) throws -> DocumentMetadata? {
        guard !isClosed else { throw StorageError.storeClosed }
        let statement = try database.prepare("""
            SELECT d.document_id, d.latest_revision, d.latest_digest, d.stream_id,
                   d.latest_chunk_index, d.latest_commit_id, d.updated_at,
                   (SELECT COUNT(*) FROM recovery_chunks c WHERE c.document_id = d.document_id),
                   (SELECT COALESCE(SUM(length(c.sealed)), 0) FROM recovery_chunks c WHERE c.document_id = d.document_id)
            FROM documents d
            WHERE d.document_id = ?
            """)
        try statement.bindText(1, id.rawValue.uuidString)
        guard try statement.step() else { return nil }
        return try documentMetadata(from: statement)
    }

    /// Retained snapshot index for one document, oldest first. Contains no writing.
    public func recoveryIndex(for id: DocumentID) throws -> [RecoveryChunkInfo] {
        guard !isClosed else { throw StorageError.storeClosed }
        let statement = try database.prepare("""
            SELECT stream_id, chunk_index, source_revision, source_digest, byte_count,
                   nonce, length(sealed), commit_id, committed_at
            FROM recovery_chunks
            WHERE document_id = ?
            ORDER BY chunk_index ASC
            """)
        try statement.bindText(1, id.rawValue.uuidString)
        var result: [RecoveryChunkInfo] = []
        while try statement.step() {
            guard let streamUUID = try Self.uuid(from: statement, column: 0) else {
                throw StorageError.corruptDatabase("A recovery index row has an unusable stream identifier.")
            }
            guard let commitID = try Self.uuid(from: statement, column: 7) else {
                throw StorageError.corruptDatabase("A recovery index row has an unusable commit identifier.")
            }
            result.append(
                RecoveryChunkInfo(
                    streamID: RecoveryStreamID(streamUUID),
                    chunkIndex: try StorageEncoding.decodeUInt64(statement.requiredBlob(1)),
                    sourceRevision: Revision(try StorageEncoding.decodeUInt64(statement.requiredBlob(2))),
                    sourceDigest: try statement.requiredBlob(3),
                    byteCount: Int(statement.columnInt64(4)),
                    nonce: try statement.requiredBlob(5),
                    ciphertextBytes: Int(statement.columnInt64(6)),
                    commitID: commitID,
                    committedAt: statement.columnDouble(8)
                )
            )
        }
        return result
    }

    /// Distinguishes missing, denied, locked and unmatched keys without exposing
    /// any key material.
    public func recoveryKeyStatus() async -> RecoveryKeyStatus {
        guard !isClosed else { return .unavailable("The recovery store is closed.") }
        let key: SymmetricKey
        let keyCheck: Data
        do {
            key = try await loadRecoveryKey()
            keyCheck = try RecoveryCipher.keyCheckValue(for: key)
        } catch let error as StorageError {
            switch error {
            case .keyMissing: return .missing
            case .keyDenied(let reason): return .denied(reason)
            case .keyLocked(let reason): return .locked(reason)
            default: return .unavailable(Self.summary(error))
            }
        } catch {
            return .unavailable("The recovery key provider failed.")
        }
        // The store may have been closed while the key load was suspended.
        guard !isClosed else { return .unavailable("The recovery store is closed.") }
        do {
            if let stored = try readKeyCheckValue() {
                guard stored == keyCheck else {
                    return .unavailable("The available recovery key does not match this store's recorded key.")
                }
                return .available
            }
            // No key check value is recorded yet because nothing has been
            // committed. Nothing contradicts this key, so it is usable; it is
            // recorded with the first successful commit.
            return .available
        } catch let error as StorageError {
            // A key check that cannot be read is never reported as available.
            return .unavailable(Self.summary(error))
        } catch {
            return .unavailable("The recovery store key check could not be read.")
        }
    }

    // MARK: - Explicit retention cleanup

    /// Deliberately removes the oldest retained snapshots so the store fits a
    /// ciphertext budget.
    ///
    /// Writes normally prune superseded recovery checkpoints atomically. This
    /// explicit cleanup also handles a lowered retention setting after reopening.
    /// It never removes a snapshot while its document still holds the
    /// configured minimum, never removes a document's newest snapshot, and never
    /// touches a document source file. The caller sees exactly what was removed.
    @discardableResult
    public func pruneRecoverySnapshots(toFitBudget budget: Int? = nil) throws -> RecoveryPruneReport {
        guard !isClosed else { throw StorageError.storeClosed }
        let limit = budget ?? configuration.recoveryCiphertextBudget
        guard limit >= 0 else {
            throw StorageError.invariantViolation("The retention budget must not be negative.")
        }
        let floor = configuration.minimumRetainedSnapshotsPerDocument
        var remainingBytes = try totalCiphertextBytes()
        var removedSnapshots = 0
        var removedBytes = 0
        return try database.withTransaction {
            var remaining = try self.totalCiphertextBytes()
            if remaining > limit {
                for candidate in try self.prunableChunks(keepNewestPerDocument: floor) {
                    try self.deleteChunk(candidate)
                    remaining -= candidate.ciphertextBytes
                    removedSnapshots += 1
                    removedBytes += candidate.ciphertextBytes
                    if remaining <= limit { break }
                }
            }
            remainingBytes = remaining
            return RecoveryPruneReport(
                removedSnapshots: removedSnapshots,
                removedCiphertextBytes: removedBytes,
                remainingSnapshots: try self.totalSnapshotCount(),
                remainingCiphertextBytes: remainingBytes
            )
        }
    }

    // MARK: - Teardown

    /// Flushes the write-ahead log and closes the connection.
    public func close() throws {
        guard !isClosed else { return }
        isClosed = true
        try database.checkpointAndClose()
        installationLease = nil
    }

    // MARK: - Persist critical section (synchronous, no await)

    private func performPersist(batch: RecoveryBatch, key: SymmetricKey, keyCheck: Data) throws -> DurableRevision {
        guard !isClosed else { throw StorageError.storeClosed }
        let source = batch.source

        if let storedKeyCheck = try readKeyCheckValue(), storedKeyCheck != keyCheck {
            throw StorageError.keyMismatch
        }

        try faultInjector.checkpoint(.beforeInsert)

        // Re-read the durable index after the key await: another caller may have
        // committed while this call was suspended.
        let latest = try readDocumentPointer(source.documentID)
        if let latest {
            if source.revision < latest.revision {
                throw StorageError.staleRevision(
                    latest: latest.revision.rawValue,
                    attempted: source.revision.rawValue
                )
            }
            if source.revision == latest.revision {
                if source.digest == latest.digest {
                    // Idempotent retry: confirm the stored snapshot really
                    // decrypts to these bytes, then return the original identity.
                    guard let chunk = try readChunk(
                        documentID: source.documentID,
                        streamID: latest.streamID,
                        chunkIndex: latest.chunkIndex
                    ) else {
                        throw StorageError.tamperDetected("The durable recovery snapshot is missing.")
                    }
                    let snapshot = try decrypt(chunk, key: key)
                    guard snapshot.revision == source.revision, snapshot.digest == source.digest else {
                        throw StorageError.tamperDetected("The durable recovery snapshot does not match the offered source.")
                    }
                    return DurableRevision(source: snapshot, recoveryCommit: latest.commitID, savedFile: nil)
                }
                throw StorageError.conflictingRevision(revision: source.revision.rawValue)
            }
        }

        let streamID = latest?.streamID ?? RecoveryStreamID(uuidGenerator.nextUUID())
        let chunkIndex: UInt64
        if let latest {
            let (next, overflow) = latest.chunkIndex.addingReportingOverflow(1)
            guard !overflow else {
                throw StorageError.invariantViolation("The recovery chunk index is exhausted.")
            }
            chunkIndex = next
            // Bind the new snapshot to the previous one only when the index and
            // the stored row agree; otherwise the chain would silently record a
            // reference to nothing. Fail closed instead of writing past tamper.
            guard let previous = try readChunk(
                documentID: source.documentID,
                streamID: latest.streamID,
                chunkIndex: latest.chunkIndex
            ), previous.chunkReference == latest.chunkReference else {
                throw StorageError.tamperDetected("The stored recovery index does not match the committed snapshot.")
            }
            let authenticatedPrevious = try decrypt(previous, key: key)
            guard authenticatedPrevious.revision == latest.revision,
                  authenticatedPrevious.digest == latest.digest else {
                throw StorageError.tamperDetected("The durable index disagrees with its authenticated previous snapshot.")
            }
        } else {
            chunkIndex = 0
        }
        let previousReference = latest?.chunkReference ?? RecoveryCipher.genesisReference

        let aad = RecoveryCipher.aad(
            documentID: source.documentID,
            streamID: streamID,
            chunkIndex: chunkIndex,
            revision: source.revision,
            sourceDigest: source.digest,
            byteCount: source.utf8.count,
            previousReference: previousReference
        )
        let nonce = try nonceGenerator.nextNonce()
        guard nonce.count == RecoveryCipher.nonceByteCount else {
            throw StorageError.invariantViolation("A recovery nonce must be exactly 12 bytes.")
        }
        let sealed = try RecoveryCipher.seal(source.utf8, key: key, nonce: nonce, aad: aad)
        let chunkReference = RecoveryCipher.chunkReference(
            documentID: source.documentID,
            streamID: streamID,
            chunkIndex: chunkIndex,
            nonce: nonce,
            sealed: sealed
        )
        let commitID = uuidGenerator.nextUUID()
        let now = clock.nowEpoch()

        try database.withTransaction {
            try self.checkNonceIsFresh(nonce)
            if try self.readKeyCheckValue() == nil {
                try self.writeKeyCheckValue(keyCheck)
            }
            try self.insertChunk(
                documentID: source.documentID,
                streamID: streamID,
                chunkIndex: chunkIndex,
                revision: source.revision,
                sourceDigest: source.digest,
                byteCount: source.utf8.count,
                previousReference: previousReference,
                nonce: nonce,
                sealed: sealed,
                chunkReference: chunkReference,
                commitID: commitID,
                committedAt: now
            )
            try self.upsertDocumentPointer(
                documentID: source.documentID,
                revision: source.revision,
                digest: source.digest,
                streamID: streamID,
                chunkIndex: chunkIndex,
                chunkReference: chunkReference,
                commitID: commitID,
                byteCount: source.utf8.count,
                timestamp: now
            )
            // Only disposable source recovery checkpoints are pruned. Detailed
            // capture/history is a separate store and never enters this table.
            // A subsequent failure rolls this pruning back with the new write.
            try self.pruneSupersededCheckpoints(for: source.documentID)
            let storedBytes = try self.totalCiphertextBytes()
            guard storedBytes <= self.configuration.recoveryCiphertextBudget else {
                throw StorageError.recoveryBudgetExceeded(
                    limit: self.configuration.recoveryCiphertextBudget,
                    required: storedBytes
                )
            }
            try self.faultInjector.checkpoint(.beforeCommit)
        }

        try faultInjector.checkpoint(.afterCommit)
        return DurableRevision(source: source, recoveryCommit: commitID, savedFile: nil)
    }

    // MARK: - Receipt consistency

    /// The recovery store keeps source, not descriptive capture. Supplied receipts
    /// are checked for chain consistency and then deliberately not stored.
    private static func validate(receipts: [MutationReceipt], against source: SourceSnapshot) throws {
        var previous: SourceSnapshot?
        for receipt in receipts {
            guard receipt.pre.documentID == source.documentID,
                  receipt.post.documentID == source.documentID else {
                throw StorageError.receiptInconsistency("A receipt belongs to a different document.")
            }
            guard let expectedPost = receipt.pre.revision.next,
                  receipt.post.revision == expectedPost else {
                throw StorageError.receiptInconsistency("A receipt does not advance exactly one revision.")
            }
            if let previous {
                guard receipt.pre.revision == previous.revision,
                      receipt.pre.digest == previous.digest else {
                    throw StorageError.receiptInconsistency("The receipts are not a contiguous chain.")
                }
            }
            guard receipt.post.revision <= source.revision else {
                throw StorageError.receiptInconsistency("A receipt is newer than the recovery source.")
            }
            previous = receipt.post
        }
        if let last = receipts.last, last.post.revision == source.revision {
            guard last.post.digest == source.digest else {
                throw StorageError.receiptInconsistency("The final receipt does not match the recovery source.")
            }
        }
    }

    // MARK: - Key handling

    private func loadRecoveryKey() async throws -> SymmetricKey {
        do {
            return try await keyProvider.loadRecoveryKey()
        } catch let error as RecoveryKeyError {
            throw StorageError(keyError: error)
        } catch {
            throw StorageError.keyUnavailable("The recovery key provider failed.")
        }
    }

    private func requireMatchingKey(_ key: SymmetricKey) throws {
        let keyCheck = try RecoveryCipher.keyCheckValue(for: key)
        guard let stored = try readKeyCheckValue() else {
            throw StorageError.corruptDatabase("The recovery store has no installation key check value.")
        }
        guard stored == keyCheck else { throw StorageError.keyMismatch }
    }

    private func readKeyCheckValue() throws -> Data? {
        let statement = try database.prepare("SELECT value FROM storage_meta WHERE key = ?")
        try statement.bindText(1, Self.keyCheckValueKey)
        guard try statement.step() else { return nil }
        return try statement.requiredBlob(0)
    }

    private func writeKeyCheckValue(_ value: Data) throws {
        let statement = try database.prepare("""
            INSERT INTO storage_meta (key, value) VALUES (?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value
            """)
        try statement.bindText(1, Self.keyCheckValueKey)
        try statement.bindBlob(2, value)
        try statement.step()
    }

    // MARK: - Index reads

    private func readDocumentPointer(_ id: DocumentID) throws -> StoredPointer? {
        let statement = try database.prepare("""
            SELECT latest_revision, latest_digest, stream_id, latest_chunk_index,
                   latest_chunk_ref, latest_commit_id
            FROM documents
            WHERE document_id = ?
            """)
        try statement.bindText(1, id.rawValue.uuidString)
        guard try statement.step() else { return nil }
        guard let streamUUID = try Self.uuid(from: statement, column: 2) else {
            throw StorageError.corruptDatabase("The stored recovery stream identifier is unusable.")
        }
        guard let commitID = try Self.uuid(from: statement, column: 5) else {
            throw StorageError.corruptDatabase("The stored recovery commit identifier is unusable.")
        }
        return StoredPointer(
            revision: Revision(try StorageEncoding.decodeUInt64(statement.requiredBlob(0))),
            digest: try statement.requiredBlob(1),
            streamID: RecoveryStreamID(streamUUID),
            chunkIndex: try StorageEncoding.decodeUInt64(statement.requiredBlob(3)),
            chunkReference: try statement.requiredBlob(4),
            commitID: commitID
        )
    }

    private func readChunk(
        documentID: DocumentID,
        streamID: RecoveryStreamID,
        chunkIndex: UInt64
    ) throws -> StoredChunk? {
        let statement = try database.prepare("""
            SELECT source_revision, source_digest, byte_count, previous_ref, nonce,
                   sealed, chunk_ref, commit_id, committed_at
            FROM recovery_chunks
            WHERE document_id = ? AND stream_id = ? AND chunk_index = ?
            """)
        try statement.bindText(1, documentID.rawValue.uuidString)
        try statement.bindText(2, streamID.rawValue.uuidString)
        try statement.bindBlob(3, StorageEncoding.uint64(chunkIndex))
        guard try statement.step() else { return nil }
        return try storedChunk(
            from: statement,
            documentID: documentID,
            streamID: streamID,
            chunkIndex: chunkIndex,
            offset: 0
        )
    }

    private func readNewestChunk(documentID: DocumentID) throws -> StoredChunk? {
        // `chunk_index` is a big-endian 8-byte BLOB, so byte order equals numeric
        // order and SQLite's ORDER BY is a correct numeric ordering.
        let statement = try database.prepare("""
            SELECT stream_id, chunk_index, source_revision, source_digest, byte_count,
                   previous_ref, nonce, sealed, chunk_ref, commit_id, committed_at
            FROM recovery_chunks
            WHERE document_id = ?
            ORDER BY chunk_index DESC
            LIMIT 1
            """)
        try statement.bindText(1, documentID.rawValue.uuidString)
        guard try statement.step() else { return nil }
        guard let streamUUID = try Self.uuid(from: statement, column: 0) else {
            throw StorageError.corruptDatabase("A recovery row has an unusable stream identifier.")
        }
        return try storedChunk(
            from: statement,
            documentID: documentID,
            streamID: RecoveryStreamID(streamUUID),
            chunkIndex: try StorageEncoding.decodeUInt64(statement.requiredBlob(1)),
            offset: 2
        )
    }

    private func readChunk(documentID: DocumentID, revision: Revision) throws -> StoredChunk? {
        let statement = try database.prepare("""
            SELECT stream_id, chunk_index, source_revision, source_digest, byte_count,
                   previous_ref, nonce, sealed, chunk_ref, commit_id, committed_at
            FROM recovery_chunks
            WHERE document_id = ? AND source_revision = ?
            LIMIT 1
            """)
        try statement.bindText(1, documentID.rawValue.uuidString)
        try statement.bindBlob(2, StorageEncoding.uint64(revision.rawValue))
        guard try statement.step() else { return nil }
        guard let streamUUID = try Self.uuid(from: statement, column: 0) else {
            throw StorageError.corruptDatabase("A recovery row has an unusable stream identifier.")
        }
        return try storedChunk(
            from: statement,
            documentID: documentID,
            streamID: RecoveryStreamID(streamUUID),
            chunkIndex: try StorageEncoding.decodeUInt64(statement.requiredBlob(1)),
            offset: 2
        )
    }

    /// Reads the shared tail of a recovery row beginning at `offset`.
    private func storedChunk(
        from statement: SQLiteStatement,
        documentID: DocumentID,
        streamID: RecoveryStreamID,
        chunkIndex: UInt64,
        offset: Int32
    ) throws -> StoredChunk {
        guard let commitID = try Self.uuid(from: statement, column: offset + 7) else {
            throw StorageError.corruptDatabase("A recovery row has an unusable commit identifier.")
        }
        // Bound the untrusted stored blob before it is copied out of SQLite, and
        // bound the recorded plaintext length before any decryption is attempted.
        // A row larger than one admissible snapshot is treated as corruption
        // rather than being allocated and decrypted.
        let sealedByteCount = statement.columnByteCount(offset + 5)
        guard sealedByteCount <= configuration.maximumCiphertextBytes else {
            throw StorageError.tamperDetected(
                "A stored recovery snapshot of \(sealedByteCount) bytes exceeds the maximum accepted size."
            )
        }
        let recordedByteCount = Int(statement.columnInt64(offset + 2))
        guard recordedByteCount >= 0, recordedByteCount <= configuration.maximumSourceBytes else {
            throw StorageError.tamperDetected(
                "A stored recovery snapshot declares \(recordedByteCount) source bytes beyond the accepted bound."
            )
        }
        return StoredChunk(
            documentID: documentID,
            streamID: streamID,
            chunkIndex: chunkIndex,
            revision: Revision(try StorageEncoding.decodeUInt64(statement.requiredBlob(offset))),
            sourceDigest: try statement.requiredBlob(offset + 1),
            byteCount: Int(statement.columnInt64(offset + 2)),
            previousReference: try statement.requiredBlob(offset + 3),
            nonce: try statement.requiredBlob(offset + 4),
            sealed: try statement.requiredBlob(offset + 5),
            chunkReference: try statement.requiredBlob(offset + 6),
            commitID: commitID,
            committedAt: statement.columnDouble(offset + 8)
        )
    }

    private func documentMetadata(from statement: SQLiteStatement) throws -> DocumentMetadata {
        guard let documentUUID = try Self.uuid(from: statement, column: 0) else {
            throw StorageError.corruptDatabase("A document row has an unusable identifier.")
        }
        guard let streamUUID = try Self.uuid(from: statement, column: 3) else {
            throw StorageError.corruptDatabase("A document row has an unusable stream identifier.")
        }
        guard let commitID = try Self.uuid(from: statement, column: 5) else {
            throw StorageError.corruptDatabase("A document row has an unusable commit identifier.")
        }
        return DocumentMetadata(
            documentID: DocumentID(documentUUID),
            latestRevision: Revision(try StorageEncoding.decodeUInt64(statement.requiredBlob(1))),
            latestDigest: try statement.requiredBlob(2),
            streamID: RecoveryStreamID(streamUUID),
            latestChunkIndex: try StorageEncoding.decodeUInt64(statement.requiredBlob(4)),
            latestCommitID: commitID,
            updatedAt: statement.columnDouble(6),
            chunkCount: Int(statement.columnInt64(7)),
            ciphertextBytes: Int(statement.columnInt64(8))
        )
    }

    private static func uuid(from statement: SQLiteStatement, column: Int32) throws -> UUID? {
        guard let text = statement.columnText(column) else { return nil }
        return UUID(uuidString: text)
    }

    // MARK: - Decryption

    private func decrypt(_ chunk: StoredChunk, key: SymmetricKey) throws -> SourceSnapshot {
        let aad = RecoveryCipher.aad(
            documentID: chunk.documentID,
            streamID: chunk.streamID,
            chunkIndex: chunk.chunkIndex,
            revision: chunk.revision,
            sourceDigest: chunk.sourceDigest,
            byteCount: chunk.byteCount,
            previousReference: chunk.previousReference
        )
        let expectedReference = RecoveryCipher.chunkReference(
            documentID: chunk.documentID,
            streamID: chunk.streamID,
            chunkIndex: chunk.chunkIndex,
            nonce: chunk.nonce,
            sealed: chunk.sealed
        )
        guard expectedReference == chunk.chunkReference else {
            throw StorageError.tamperDetected("The stored recovery snapshot does not match its recorded reference.")
        }
        let plaintext = try RecoveryCipher.open(chunk.sealed, key: key, nonce: chunk.nonce, aad: aad)
        guard plaintext.count == chunk.byteCount else {
            throw StorageError.tamperDetected("The recovered snapshot length does not match its recorded length.")
        }
        guard SourceSnapshot.sha256(plaintext) == chunk.sourceDigest else {
            throw StorageError.tamperDetected("The recovered snapshot does not match its recorded digest.")
        }
        do {
            return try SourceSnapshot(documentID: chunk.documentID, revision: chunk.revision, utf8: plaintext)
        } catch {
            throw StorageError.tamperDetected("The recovered snapshot is not valid UTF-8 source.")
        }
    }

    // MARK: - Index writes

    private func checkNonceIsFresh(_ nonce: Data) throws {
        let statement = try database.prepare("SELECT 1 FROM recovery_chunks WHERE nonce = ? LIMIT 1")
        try statement.bindBlob(1, nonce)
        if try statement.step() {
            throw StorageError.invariantViolation("This recovery nonce was already used; AES-GCM requires a fresh nonce.")
        }
    }

    private func insertChunk(
        documentID: DocumentID,
        streamID: RecoveryStreamID,
        chunkIndex: UInt64,
        revision: Revision,
        sourceDigest: Data,
        byteCount: Int,
        previousReference: Data,
        nonce: Data,
        sealed: Data,
        chunkReference: Data,
        commitID: UUID,
        committedAt: Double
    ) throws {
        let statement = try database.prepare("""
            INSERT INTO recovery_chunks
                (document_id, stream_id, chunk_index, source_revision, source_digest,
                 byte_count, previous_ref, nonce, sealed, chunk_ref, commit_id, committed_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """)
        try statement.bindText(1, documentID.rawValue.uuidString)
        try statement.bindText(2, streamID.rawValue.uuidString)
        try statement.bindBlob(3, StorageEncoding.uint64(chunkIndex))
        try statement.bindBlob(4, StorageEncoding.uint64(revision.rawValue))
        try statement.bindBlob(5, sourceDigest)
        try statement.bindInt64(6, Int64(byteCount))
        try statement.bindBlob(7, previousReference)
        try statement.bindBlob(8, nonce)
        try statement.bindBlob(9, sealed)
        try statement.bindBlob(10, chunkReference)
        try statement.bindText(11, commitID.uuidString)
        try statement.bindDouble(12, committedAt)
        try statement.step()
    }

    private func upsertDocumentPointer(
        documentID: DocumentID,
        revision: Revision,
        digest: Data,
        streamID: RecoveryStreamID,
        chunkIndex: UInt64,
        chunkReference: Data,
        commitID: UUID,
        byteCount: Int,
        timestamp: Double
    ) throws {
        let statement = try database.prepare("""
            INSERT INTO documents
                (document_id, latest_revision, latest_digest, stream_id, latest_chunk_index,
                 latest_chunk_ref, latest_commit_id, latest_byte_count, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(document_id) DO UPDATE SET
                latest_revision = excluded.latest_revision,
                latest_digest = excluded.latest_digest,
                stream_id = excluded.stream_id,
                latest_chunk_index = excluded.latest_chunk_index,
                latest_chunk_ref = excluded.latest_chunk_ref,
                latest_commit_id = excluded.latest_commit_id,
                latest_byte_count = excluded.latest_byte_count,
                updated_at = excluded.updated_at
            """)
        try statement.bindText(1, documentID.rawValue.uuidString)
        try statement.bindBlob(2, StorageEncoding.uint64(revision.rawValue))
        try statement.bindBlob(3, digest)
        try statement.bindText(4, streamID.rawValue.uuidString)
        try statement.bindBlob(5, StorageEncoding.uint64(chunkIndex))
        try statement.bindBlob(6, chunkReference)
        try statement.bindText(7, commitID.uuidString)
        try statement.bindInt64(8, Int64(byteCount))
        try statement.bindDouble(9, timestamp)
        try statement.bindDouble(10, timestamp)
        try statement.step()
    }

    // MARK: - Retention indexing

    private func pruneSupersededCheckpoints(for id: DocumentID) throws {
        let statement = try database.prepare("""
            DELETE FROM recovery_chunks
            WHERE document_id = ? AND chunk_index NOT IN (
                SELECT chunk_index FROM recovery_chunks
                WHERE document_id = ? ORDER BY chunk_index DESC LIMIT ?
            )
            """)
        try statement.bindText(1, id.rawValue.uuidString)
        try statement.bindText(2, id.rawValue.uuidString)
        try statement.bindInt64(3, Int64(configuration.minimumRetainedSnapshotsPerDocument))
        try statement.step()
    }

    private func totalCiphertextBytes() throws -> Int {
        let statement = try database.prepare("SELECT COALESCE(SUM(length(sealed)), 0) FROM recovery_chunks")
        guard try statement.step() else { return 0 }
        return Int(statement.columnInt64(0))
    }

    private func totalSnapshotCount() throws -> Int {
        let statement = try database.prepare("SELECT COUNT(*) FROM recovery_chunks")
        guard try statement.step() else { return 0 }
        return Int(statement.columnInt64(0))
    }

    /// Snapshots eligible for explicit cleanup: everything older than each
    /// document's newest `floor` snapshots, oldest first. Read-only.
    private func prunableChunks(keepNewestPerDocument floor: Int) throws -> [PrunableChunk] {
        let statement = try database.prepare("""
            SELECT document_id, stream_id, chunk_index, length(sealed)
            FROM (
                SELECT document_id, stream_id, chunk_index, sealed, committed_at,
                       ROW_NUMBER() OVER (PARTITION BY document_id ORDER BY chunk_index DESC) AS row_rank
                FROM recovery_chunks
            )
            WHERE row_rank > ?
            ORDER BY committed_at ASC, document_id ASC, chunk_index ASC
            """)
        try statement.bindInt64(1, Int64(floor))
        var result: [PrunableChunk] = []
        while try statement.step() {
            guard let documentUUID = try Self.uuid(from: statement, column: 0),
                  let streamUUID = try Self.uuid(from: statement, column: 1) else {
                throw StorageError.corruptDatabase("A recovery row has an unusable identifier.")
            }
            result.append(
                PrunableChunk(
                    documentID: DocumentID(documentUUID),
                    streamID: RecoveryStreamID(streamUUID),
                    chunkIndex: try StorageEncoding.decodeUInt64(statement.requiredBlob(2)),
                    ciphertextBytes: Int(statement.columnInt64(3))
                )
            )
        }
        return result
    }

    private func deleteChunk(_ chunk: PrunableChunk) throws {
        let statement = try database.prepare("""
            DELETE FROM recovery_chunks
            WHERE document_id = ? AND stream_id = ? AND chunk_index = ?
            """)
        try statement.bindText(1, chunk.documentID.rawValue.uuidString)
        try statement.bindText(2, chunk.streamID.rawValue.uuidString)
        try statement.bindBlob(3, StorageEncoding.uint64(chunk.chunkIndex))
        try statement.step()
    }

    // MARK: - Test hooks

    /// Caps the SQLite page count so a test can provoke a real SQLITE_FULL.
    func setMaximumPageCountForTesting(_ pages: Int) throws {
        guard !isClosed else { throw StorageError.storeClosed }
        guard (1...10_000_000).contains(pages) else {
            throw StorageError.invariantViolation("The page count is outside the supported range.")
        }
        try database.execute("PRAGMA max_page_count = \(pages)")
    }

    func pageCountForTesting() throws -> Int {
        guard !isClosed else { throw StorageError.storeClosed }
        let statement = try database.prepare("PRAGMA page_count")
        guard try statement.step() else { return 0 }
        return Int(statement.columnInt64(0))
    }

    func maximumPageCountForTesting() throws -> Int {
        guard !isClosed else { throw StorageError.storeClosed }
        let statement = try database.prepare("PRAGMA max_page_count")
        guard try statement.step() else { return 0 }
        return Int(statement.columnInt64(0))
    }

    /// The durability pragmas as SQLite reports them on the live connection.
    func durabilityReportForTesting() throws -> DurabilityReport {
        guard !isClosed else { throw StorageError.storeClosed }
        return try database.durabilityReport()
    }

    // MARK: - Helpers

    private static func summary(_ error: any Error) -> String {
        (error as? StorageError)?.errorDescription ?? "The recovery store reported an unspecified failure."
    }

    // MARK: - Private value types

    private struct StoredPointer {
        let revision: Revision
        let digest: Data
        let streamID: RecoveryStreamID
        let chunkIndex: UInt64
        let chunkReference: Data
        let commitID: UUID
    }

    private struct StoredChunk {
        let documentID: DocumentID
        let streamID: RecoveryStreamID
        let chunkIndex: UInt64
        let revision: Revision
        let sourceDigest: Data
        let byteCount: Int
        let previousReference: Data
        let nonce: Data
        let sealed: Data
        let chunkReference: Data
        let commitID: UUID
        let committedAt: Double
    }

    private struct PrunableChunk {
        let documentID: DocumentID
        let streamID: RecoveryStreamID
        let chunkIndex: UInt64
        let ciphertextBytes: Int
    }
}
