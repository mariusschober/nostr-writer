import CryptoKit
import Foundation
import WriterFoundation

// Separately-owned, consented, encrypted local writing-history journal.
//
// This store is **not** HWP telemetry and **not** the rolling recovery cache.
// Inside an explicit consent epoch it keeps the ordered edit records, honest
// gaps and source annotations that let the app show truthful local history and
// replay a document. Like recovery it seals bytes with AES-GCM before any
// SQLite call and loads (never generates) the installation key. Unlike recovery
// it is retained until the owner deletes it, warns at the configured warn size
// and pauses detailed recording at the pause size while the document itself
// stays fully editable.

/// Typed failures of the history journal. Messages carry no writing, keys or
/// document content; a journal failure must never leak private text.
public enum HistoryError: Error, Equatable, Sendable {
    case keyUnavailable(String)
    case capacityPaused(ciphertextBytes: Int, pauseBytes: Int)
    case corrupt(String)
    case epochUnknown
    case storeClosed
}

extension HistoryError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .keyUnavailable(let reason):
            "Local history is unavailable; your writing is unchanged and still editable. \(reason)"
        case .capacityPaused(let bytes, let pause):
            "Detailed history paused at its \(pause)-byte limit (currently \(bytes) bytes). Your writing and recovery are unaffected."
        case .corrupt(let reason):
            "The local history journal could not be read safely. \(reason)"
        case .epochUnknown:
            "The history epoch is not open, so no detailed record was written."
        case .storeClosed:
            "The local history journal is closed."
        }
    }
}

/// Capacity configuration for detailed history. Retention follows DATA: keep
/// until the owner deletes, warn at 1 GiB, pause detailed recording at 2 GiB.
public struct HistoryCapacity: Sendable, Equatable {
    public let warnBytes: Int
    public let pauseBytes: Int

    public init(warnBytes: Int, pauseBytes: Int) {
        precondition(pauseBytes > warnBytes && warnBytes > 0, "History capacity thresholds must be ordered and positive.")
        self.warnBytes = warnBytes
        self.pauseBytes = pauseBytes
    }

    public static let standard = HistoryCapacity(warnBytes: 1_073_741_824, pauseBytes: 2_147_483_648)
}

public enum HistoryRetentionState: Sendable, Equatable {
    case healthy
    case warning(ciphertextBytes: Int, warnBytes: Int)
    case pausedLimit(ciphertextBytes: Int, pauseBytes: Int)

    /// Whether new detailed records may still be written.
    public var acceptsNewRecords: Bool {
        if case .pausedLimit = self { return false }
        return true
    }
}

/// Compact, truthful summary for the passage inspector.
public struct HistorySummary: Sendable, Equatable {
    public let documentID: DocumentID
    public let recordCount: Int
    public let gapCount: Int
    public let annotationCount: Int
    public let ciphertextBytes: Int
    public let openEpochID: CaptureEpochID?
    public let lastGapReason: CaptureGapReason?
    public let retention: HistoryRetentionState
}

/// One retained, decrypted edit record as returned by the journal.
public struct HistoryRecordRow: Sendable, Equatable {
    public let record: LocalEditRecord
    public let chunkIndex: UInt64
}

/// Fixed authenticated framing for one history chunk. Byte-for-byte stable so
/// two writers can never silently disagree about what a chunk covers.
enum HistoryCipher {
    static let aadDomain = Data("NWHISTORY1".utf8)
    /// Version 2 authenticates the record's full interpretation (range, cause,
    /// assistance and post-digest), not just its deleted/inserted text.
    static let aadVersion: UInt16 = 2
    static let referenceDomain = Data("NWHISTREF1".utf8)
    static let chunkDomain = Data("NWHISTCHK1".utf8)
    static let annotationDomain = Data("NWHISTANN1".utf8)
    static let genesisReference = Data(repeating: 0, count: 32)

    static func aad(documentID: DocumentID, recordingID: UUID, epochID: CaptureEpochID,
                    chunkIndex: UInt64, revision: Revision, range: ByteRange,
                    originCategory: EditOriginCategory, assistanceKind: AssistanceKind?,
                    postDigest: Data, previousReference: Data) -> Data {
        var out = Data()
        out.append(aadDomain)
        out.append(StorageEncoding.uint16(aadVersion))
        out.append(StorageEncoding.uuid(documentID.rawValue))
        out.append(StorageEncoding.uuid(recordingID))
        out.append(StorageEncoding.uuid(epochID.rawValue))
        out.append(StorageEncoding.uint64(chunkIndex))
        out.append(StorageEncoding.uint64(revision.rawValue))
        // The interpretation of the record — its exact range, observed cause and
        // resulting digest — is authenticated. Those values live in plaintext
        // columns, so rewriting them must break authenticated decryption rather
        // than silently changing what the record claims happened.
        out.append(StorageEncoding.uint64(UInt64(bitPattern: Int64(range.lowerBound))))
        out.append(StorageEncoding.uint64(UInt64(bitPattern: Int64(range.upperBound))))
        out.append(field(Data(originCategory.rawValue.utf8)))
        out.append(field(assistanceKind.map { Data($0.rawValue.utf8) } ?? Data()))
        out.append(field(postDigest))
        out.append(previousReference)
        return out
    }

    /// Length-prefixed field so concatenated values can never be ambiguous.
    private static func field(_ data: Data) -> Data {
        StorageEncoding.uint64(UInt64(data.count)) + data
    }

    static func chunkReference(documentID: DocumentID, recordingID: UUID, epochID: CaptureEpochID,
                               chunkIndex: UInt64, nonce: Data, sealed: Data) -> Data {
        var out = Data()
        out.append(chunkDomain)
        out.append(StorageEncoding.uuid(documentID.rawValue))
        out.append(StorageEncoding.uuid(recordingID))
        out.append(StorageEncoding.uuid(epochID.rawValue))
        out.append(StorageEncoding.uint64(chunkIndex))
        out.append(nonce)
        out.append(sealed)
        return SourceSnapshot.sha256(out)
    }

    static func annotationAAD(documentID: DocumentID, annotationID: UUID, kind: AnnotationKind,
                              range: ByteRange, revision: Revision, isStale: Bool) -> Data {
        var out = Data()
        out.append(annotationDomain)
        out.append(StorageEncoding.uint16(aadVersion))
        out.append(StorageEncoding.uuid(documentID.rawValue))
        out.append(StorageEncoding.uuid(annotationID))
        out.append(field(Data(kind.rawValue.utf8)))
        out.append(StorageEncoding.uint64(UInt64(bitPattern: Int64(range.lowerBound))))
        out.append(StorageEncoding.uint64(UInt64(bitPattern: Int64(range.upperBound))))
        out.append(StorageEncoding.uint64(revision.rawValue))
        out.append(StorageEncoding.uint16(isStale ? 1 : 0))
        return out
    }

    static func seal(_ plaintext: Data, key: SymmetricKey, nonce: Data, aad: Data) throws -> Data {
        do {
            let box = try AES.GCM.seal(plaintext, using: key, nonce: try nonceBox(nonce), authenticating: aad)
            return box.ciphertext + box.tag
        } catch let error as HistoryError {
            throw error
        } catch {
            throw HistoryError.corrupt("A history record could not be sealed.")
        }
    }

    static func open(_ sealed: Data, key: SymmetricKey, nonce: Data, aad: Data) throws -> Data {
        guard sealed.count >= RecoveryCipher.tagByteCount else {
            throw HistoryError.corrupt("A stored history chunk is truncated.")
        }
        let ciphertext = sealed.prefix(sealed.count - RecoveryCipher.tagByteCount)
        let tag = sealed.suffix(RecoveryCipher.tagByteCount)
        do {
            let box = try AES.GCM.SealedBox(nonce: try nonceBox(nonce), ciphertext: ciphertext, tag: tag)
            return try AES.GCM.open(box, using: key, authenticating: aad)
        } catch let error as HistoryError {
            throw error
        } catch {
            throw HistoryError.corrupt("A history record failed authenticated decryption.")
        }
    }

    private static func nonceBox(_ data: Data) throws -> AES.GCM.Nonce {
        guard data.count == RecoveryCipher.nonceByteCount else {
            throw HistoryError.corrupt("A history nonce has an unexpected length.")
        }
        do { return try AES.GCM.Nonce(data: data) }
        catch { throw HistoryError.corrupt("A history nonce is not usable.") }
    }
}

/// The encrypted local writing-history journal.
public actor HistoryJournal {
    private let database: SQLiteConnection
    private let keyProvider: RecoveryKeyProviding
    private let capacity: HistoryCapacity
    private let clock: StorageClock
    private let uuidGenerator: StorageUUIDGenerating
    private let nonceGenerator: RecoveryNonceGenerating
    private var isClosed = false

    public init(
        configuration: DocumentStoreConfiguration,
        keyProvider: RecoveryKeyProviding,
        capacity: HistoryCapacity = .standard,
        clock: StorageClock = SystemStorageClock(),
        uuidGenerator: StorageUUIDGenerating = SystemStorageUUIDGenerator(),
        nonceGenerator: RecoveryNonceGenerating = SystemRecoveryNonceGenerator(),
        fileSystem: StorageFileSystem = SystemStorageFileSystem()
    ) throws {
        try fileSystem.createDirectory(at: configuration.databaseURL.deletingLastPathComponent())
        let database = try SQLiteConnection(
            path: configuration.databaseURL.path,
            busyTimeoutMilliseconds: configuration.busyTimeoutMilliseconds
        )
        do {
            try SchemaMigration.standard.run(on: database, databaseURL: configuration.databaseURL,
                                             fileSystem: fileSystem, clock: clock)
        } catch {
            database.close()
            throw error
        }
        self.database = database
        self.keyProvider = keyProvider
        self.capacity = capacity
        self.clock = clock
        self.uuidGenerator = uuidGenerator
        self.nonceGenerator = nonceGenerator
    }

    // MARK: - Epochs

    /// Opens a prospective consent epoch. `priorTextCompleteness` describes text
    /// that already existed; it is imported as descriptive, never freshly observed.
    @discardableResult
    public func beginEpoch(documentID: DocumentID, atRevision: Revision,
                           priorTextCompleteness: CaptureCompleteness,
                           gapReason: CaptureGapReason? = nil) throws -> CaptureEpoch {
        try ensureOpen()
        let epoch = CaptureEpoch(documentID: documentID, recordingUUID: uuidGenerator.nextUUID(),
                                 beganAtRevision: atRevision, beganAtEpochSeconds: clock.nowEpoch(),
                                 priorTextCompleteness: priorTextCompleteness, gapReason: gapReason)
        try database.withTransaction {
            let insert = try database.prepare("""
                INSERT INTO history_epochs
                (epoch_id, document_id, recording_id, began_revision, began_at, ended_at, prior_completeness, gap_reason, ciphertext_bytes)
                VALUES (?, ?, ?, ?, ?, NULL, ?, ?, 0)
                """)
            try insert.bindText(1, epoch.id.rawValue.uuidString)
            try insert.bindText(2, documentID.rawValue.uuidString)
            try insert.bindText(3, epoch.recordingUUID.uuidString)
            try insert.bindInt64(4, Int64(bitPattern: atRevision.rawValue))
            try insert.bindDouble(5, epoch.beganAtEpochSeconds)
            try insert.bindText(6, Self.encode(priorTextCompleteness))
            if let gapReason { try insert.bindText(7, gapReason.rawValue) } else { try insert.bindBlob(7, Data()) }
            _ = try insert.step()
            if let gapReason {
                try recordGap(CaptureGap(reason: gapReason, revision: atRevision,
                                         recordedAtEpochSeconds: epoch.beganAtEpochSeconds),
                              documentID: documentID, epochID: epoch.id)
            }
        }
        return epoch
    }

    public func endEpoch(_ id: CaptureEpochID) throws {
        try ensureOpen()
        try database.withTransaction {
            let update = try database.prepare("UPDATE history_epochs SET ended_at = ? WHERE epoch_id = ?")
            try update.bindDouble(1, clock.nowEpoch())
            try update.bindText(2, id.rawValue.uuidString)
            _ = try update.step()
        }
    }

    @discardableResult
    public func resumeOrOpenEpoch(documentID: DocumentID, atRevision: Revision,
                                  priorTextCompleteness: CaptureCompleteness) throws -> CaptureEpoch {
        try ensureOpen()
        if let open = try openEpoch(documentID: documentID) { return open }
        return try beginEpoch(documentID: documentID, atRevision: atRevision,
                              priorTextCompleteness: priorTextCompleteness, gapReason: .resumed)
    }

    public func openEpoch(documentID: DocumentID) throws -> CaptureEpoch? {
        try ensureOpen()
        let select = try database.prepare("""
            SELECT epoch_id, recording_id, began_revision, began_at, prior_completeness, gap_reason
            FROM history_epochs WHERE document_id = ? AND ended_at IS NULL
            ORDER BY began_at DESC LIMIT 1
            """)
        try select.bindText(1, documentID.rawValue.uuidString)
        guard try select.step() else { return nil }
        return try decodeEpoch(select, documentID: documentID)
    }

    // MARK: - Records

    /// Appends ordered edit records. Append-before-ack: this returns only after
    /// the enclosing transaction has committed. The key is loaded once, before
    /// any transaction, so no suspension happens inside SQLite.
    public func append(_ records: [LocalEditRecord]) async throws {
        try ensureOpen()
        guard let first = records.first else { return }
        // Records from several epochs are grouped so each uses its own recording
        // identity; the common case is one epoch.
        var index = 0
        while index < records.count {
            let epochID = records[index].epochID
            var end = index
            while end < records.count && records[end].epochID == epochID { end += 1 }
            try await appendGroup(Array(records[index..<end]))
            index = end
        }
        _ = first
    }

    private func appendGroup(_ records: [LocalEditRecord]) async throws {
        guard let first = records.first else { return }
        if !(try retentionState()).acceptsNewRecords { return }
        let key = try await loadKey()
        let epoch = try requireEpoch(first.epochID)
        try database.withTransaction {
            var index = try nextChunkIndex(documentID: epoch.documentID)
            var previous = try lastChunkReference(documentID: epoch.documentID) ?? HistoryCipher.genesisReference
            for record in records {
                let payload = try Self.encodePayload(deleted: record.deleted, inserted: record.inserted)
                let aad = HistoryCipher.aad(documentID: epoch.documentID, recordingID: epoch.recordingUUID,
                                            epochID: record.epochID, chunkIndex: index,
                                            revision: record.revision, range: record.range,
                                            originCategory: record.originCategory,
                                            assistanceKind: record.assistanceKind,
                                            postDigest: record.postDigest, previousReference: previous)
                let nonce = try nonceGenerator.nextNonce()
                let sealed = try HistoryCipher.seal(payload, key: key, nonce: nonce, aad: aad)
                let reference = HistoryCipher.chunkReference(documentID: epoch.documentID, recordingID: epoch.recordingUUID,
                                                              epochID: record.epochID, chunkIndex: index,
                                                              nonce: nonce, sealed: sealed)
                let insert = try database.prepare("""
                    INSERT INTO history_records
                    (record_id, epoch_id, document_id, chunk_index, source_revision, range_lower, range_upper,
                     origin, assistance, post_digest, nonce, sealed, chunk_ref, recorded_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """)
                try insert.bindText(1, record.id.uuidString)
                try insert.bindText(2, record.epochID.rawValue.uuidString)
                try insert.bindText(3, epoch.documentID.rawValue.uuidString)
                try insert.bindInt64(4, Int64(bitPattern: index))
                try insert.bindInt64(5, Int64(bitPattern: record.revision.rawValue))
                try insert.bindInt64(6, Int64(record.range.lowerBound))
                try insert.bindInt64(7, Int64(record.range.upperBound))
                try insert.bindText(8, record.originCategory.rawValue)
                if let assistance = record.assistanceKind { try insert.bindText(9, assistance.rawValue) }
                else { try insert.bindBlob(9, Data()) }
                try insert.bindBlob(10, record.postDigest)
                try insert.bindBlob(11, nonce)
                try insert.bindBlob(12, sealed)
                try insert.bindBlob(13, reference)
                try insert.bindDouble(14, record.recordedAtEpochSeconds)
                _ = try insert.step()
                previous = reference
                index += 1
            }
        }
    }

    public func records(documentID: DocumentID, epochID: CaptureEpochID? = nil) async throws -> [HistoryRecordRow] {
        try ensureOpen()
        let sql = epochID == nil
            ? "SELECT epoch_id, chunk_index, source_revision, range_lower, range_upper, origin, assistance, post_digest, nonce, sealed, recorded_at, record_id, chunk_ref FROM history_records WHERE document_id = ? ORDER BY chunk_index ASC"
            : "SELECT epoch_id, chunk_index, source_revision, range_lower, range_upper, origin, assistance, post_digest, nonce, sealed, recorded_at, record_id, chunk_ref FROM history_records WHERE document_id = ? AND epoch_id = ? ORDER BY chunk_index ASC"
        let statement = try database.prepare(sql)
        try statement.bindText(1, documentID.rawValue.uuidString)
        if let epochID { try statement.bindText(2, epochID.rawValue.uuidString) }
        let key = try await loadKey()
        var rows: [HistoryRecordRow] = []
        var previous = HistoryCipher.genesisReference
        while try statement.step() {
            let rowEpochID = try Self.uuid(from: statement.requiredText(0)).map(CaptureEpochID.init(rawValue:))
            guard let rowEpochID else { throw HistoryError.corrupt("A history row has no epoch identity.") }
            let chunkIndex = UInt64(bitPattern: statement.columnInt64(1))
            let revision = Revision(UInt64(bitPattern: statement.columnInt64(2)))
            let lower = Int(statement.columnInt64(3))
            let upper = Int(statement.columnInt64(4))
            let originText = try statement.requiredText(5)
            let origin = EditOriginCategory(rawValue: originText) ?? .unknown
            let assistance = statement.columnText(6).flatMap { AssistanceKind(rawValue: $0) }
            let postDigest = try statement.requiredBlob(7)
            let nonce = try statement.requiredBlob(8)
            let sealed = try statement.requiredBlob(9)
            let recordedAt = statement.columnDouble(10)
            let recordID = try Self.uuid(from: statement.requiredText(11)) ?? UUID()
            let epoch = try requireEpoch(rowEpochID)
            let byteRange = try ByteRange(lowerBound: lower, upperBound: upper)
            let aad = HistoryCipher.aad(documentID: documentID, recordingID: epoch.recordingUUID,
                                        epochID: rowEpochID, chunkIndex: chunkIndex, revision: revision,
                                        range: byteRange, originCategory: origin,
                                        assistanceKind: assistance, postDigest: postDigest,
                                        previousReference: previous)
            let payload = try HistoryCipher.open(sealed, key: key, nonce: nonce, aad: aad)
            let (deleted, inserted) = try Self.decodePayload(payload)
            let record = LocalEditRecord(id: recordID, epochID: rowEpochID, revision: revision,
                                         range: byteRange,
                                         deleted: deleted, inserted: inserted, originCategory: origin,
                                         assistanceKind: assistance, postDigest: postDigest,
                                         recordedAtEpochSeconds: recordedAt)
            rows.append(HistoryRecordRow(record: record, chunkIndex: chunkIndex))
            previous = try statement.requiredBlob(12)
        }
        return rows
    }

    // MARK: - Gaps

    public func appendGap(_ gap: CaptureGap, documentID: DocumentID, epochID: CaptureEpochID) throws {
        try ensureOpen()
        try database.withTransaction { try recordGap(gap, documentID: documentID, epochID: epochID) }
    }

    public func gaps(documentID: DocumentID) throws -> [CaptureGap] {
        try ensureOpen()
        let statement = try database.prepare("""
            SELECT reason, revision, recorded_at FROM history_gaps
            WHERE document_id = ? ORDER BY recorded_at ASC
            """)
        try statement.bindText(1, documentID.rawValue.uuidString)
        var result: [CaptureGap] = []
        while try statement.step() {
            let reasonText = try statement.requiredText(0)
            let reason = CaptureGapReason(rawValue: reasonText) ?? .opaqueInput
            let revision = Revision(UInt64(bitPattern: statement.columnInt64(1)))
            result.append(CaptureGap(reason: reason, revision: revision,
                                     recordedAtEpochSeconds: statement.columnDouble(2)))
        }
        return result
    }

    // MARK: - Annotations

    public func saveAnnotation(_ annotation: SourceAnnotation, documentID: DocumentID) async throws {
        try ensureOpen()
        let payload = try Self.encodeAnnotation(description: annotation.description, url: annotation.url)
        let nonce = try nonceGenerator.nextNonce()
        let key = try await loadKey()
        let aad = HistoryCipher.annotationAAD(documentID: documentID, annotationID: annotation.id,
                                              kind: annotation.kind, range: annotation.range,
                                              revision: annotation.revision, isStale: annotation.isStale)
        let sealed = try HistoryCipher.seal(payload, key: key, nonce: nonce, aad: aad)
        try database.withTransaction {
            let statement = try database.prepare("""
                INSERT INTO history_annotations
                (annotation_id, document_id, kind, range_lower, range_upper, revision, is_stale, nonce, sealed, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(annotation_id) DO UPDATE SET
                    kind = excluded.kind, range_lower = excluded.range_lower, range_upper = excluded.range_upper,
                    revision = excluded.revision, is_stale = excluded.is_stale,
                    nonce = excluded.nonce, sealed = excluded.sealed, updated_at = excluded.updated_at
                """)
            try statement.bindText(1, annotation.id.uuidString)
            try statement.bindText(2, documentID.rawValue.uuidString)
            try statement.bindText(3, annotation.kind.rawValue)
            try statement.bindInt64(4, Int64(annotation.range.lowerBound))
            try statement.bindInt64(5, Int64(annotation.range.upperBound))
            try statement.bindInt64(6, Int64(bitPattern: annotation.revision.rawValue))
            try statement.bindInt64(7, annotation.isStale ? 1 : 0)
            try statement.bindBlob(8, nonce)
            try statement.bindBlob(9, sealed)
            try statement.bindDouble(10, clock.nowEpoch())
            _ = try statement.step()
        }
    }

    public func annotations(documentID: DocumentID) async throws -> [SourceAnnotation] {
        try ensureOpen()
        let statement = try database.prepare("""
            SELECT annotation_id, kind, range_lower, range_upper, revision, is_stale, nonce, sealed
            FROM history_annotations WHERE document_id = ? ORDER BY range_lower ASC
            """)
        try statement.bindText(1, documentID.rawValue.uuidString)
        let key = try await loadKey()
        var result: [SourceAnnotation] = []
        while try statement.step() {
            let id = try Self.uuid(from: statement.requiredText(0)) ?? UUID()
            let kindText = try statement.requiredText(1)
            let kind = AnnotationKind(rawValue: kindText) ?? .imported
            let lower = Int(statement.columnInt64(2))
            let upper = Int(statement.columnInt64(3))
            let revision = Revision(UInt64(bitPattern: statement.columnInt64(4)))
            let isStale = statement.columnInt64(5) != 0
            let nonce = try statement.requiredBlob(6)
            let sealed = try statement.requiredBlob(7)
            let range = try ByteRange(lowerBound: lower, upperBound: upper)
            let payload = try HistoryCipher.open(sealed, key: key, nonce: nonce,
                                                 aad: HistoryCipher.annotationAAD(
                                                    documentID: documentID, annotationID: id, kind: kind,
                                                    range: range, revision: revision, isStale: isStale))
            let (description, url) = try Self.decodeAnnotation(payload)
            result.append(SourceAnnotation(id: id, kind: kind,
                                           range: range,
                                           description: description, url: url, revision: revision, isStale: isStale))
        }
        return result
    }

    public func deleteAnnotation(_ id: UUID) throws {
        try ensureOpen()
        try database.withTransaction {
            let statement = try database.prepare("DELETE FROM history_annotations WHERE annotation_id = ?")
            try statement.bindText(1, id.uuidString)
            _ = try statement.step()
        }
    }

    // MARK: - Capacity, summary and deletion

    public func retentionState() throws -> HistoryRetentionState {
        try ensureOpen()
        let bytes = try ciphertextBytes(documentID: nil)
        if bytes >= capacity.pauseBytes { return .pausedLimit(ciphertextBytes: bytes, pauseBytes: capacity.pauseBytes) }
        if bytes >= capacity.warnBytes { return .warning(ciphertextBytes: bytes, warnBytes: capacity.warnBytes) }
        return .healthy
    }

    public func ciphertextBytes(documentID: DocumentID?) throws -> Int {
        try ensureOpen()
        let sql = documentID == nil
            ? "SELECT COALESCE(SUM(LENGTH(sealed)), 0) FROM history_records"
            : "SELECT COALESCE(SUM(LENGTH(sealed)), 0) FROM history_records WHERE document_id = ?"
        let statement = try database.prepare(sql)
        if let documentID { try statement.bindText(1, documentID.rawValue.uuidString) }
        return try statement.step() ? Int(statement.columnInt64(0)) : 0
    }

    public func summary(documentID: DocumentID) throws -> HistorySummary {
        try ensureOpen()
        func count(_ sql: String) throws -> Int {
            let statement = try database.prepare(sql)
            try statement.bindText(1, documentID.rawValue.uuidString)
            return try statement.step() ? Int(statement.columnInt64(0)) : 0
        }
        let records = try count("SELECT COUNT(*) FROM history_records WHERE document_id = ?")
        let gaps = try count("SELECT COUNT(*) FROM history_gaps WHERE document_id = ?")
        let annotations = try count("SELECT COUNT(*) FROM history_annotations WHERE document_id = ?")
        let open = try openEpoch(documentID: documentID)
        return HistorySummary(documentID: documentID, recordCount: records, gapCount: gaps,
                              annotationCount: annotations, ciphertextBytes: try ciphertextBytes(documentID: documentID),
                              openEpochID: open?.id, lastGapReason: try self.gaps(documentID: documentID).last?.reason,
                              retention: try retentionState())
    }

    /// Deletes one document's detailed history. Source, recovery and unrelated
    /// documents are untouched.
    public func deleteLocalHistory(documentID: DocumentID) throws {
        try ensureOpen()
        try database.withTransaction {
            for table in ["history_records", "history_gaps", "history_annotations", "history_epochs"] {
                let statement = try database.prepare("DELETE FROM \(table) WHERE document_id = ?")
                try statement.bindText(1, documentID.rawValue.uuidString)
                _ = try statement.step()
            }
        }
    }

    public func close() {
        guard !isClosed else { return }
        isClosed = true
        database.close()
    }

    // MARK: - Internals

    private func ensureOpen() throws {
        guard !isClosed else { throw HistoryError.storeClosed }
    }

    private func loadKey() async throws -> SymmetricKey {
        do { return try await keyProvider.loadRecoveryKey() }
        catch let error as RecoveryKeyError {
            let reason: String
            switch error {
            case .missing: reason = "No installation key was found."
            case .denied(let detail), .locked(let detail), .unavailable(let detail): reason = detail
            }
            throw HistoryError.keyUnavailable(reason)
        } catch { throw HistoryError.keyUnavailable("The recovery key is unavailable.") }
    }

    private struct EpochRow {
        let documentID: DocumentID
        let recordingUUID: UUID
    }

    private func requireEpoch(_ id: CaptureEpochID) throws -> EpochRow {
        let statement = try database.prepare("SELECT document_id, recording_id FROM history_epochs WHERE epoch_id = ?")
        try statement.bindText(1, id.rawValue.uuidString)
        guard try statement.step() else { throw HistoryError.epochUnknown }
        guard let documentID = try Self.uuid(from: statement.requiredText(0)).map(DocumentID.init(rawValue:)),
              let recording = try Self.uuid(from: statement.requiredText(1)) else {
            throw HistoryError.corrupt("A history epoch row is malformed.")
        }
        return EpochRow(documentID: documentID, recordingUUID: recording)
    }

    private func decodeEpoch(_ statement: SQLiteStatement, documentID: DocumentID) throws -> CaptureEpoch {
        guard let epochID = try Self.uuid(from: statement.requiredText(0)).map(CaptureEpochID.init(rawValue:)),
              let recording = try Self.uuid(from: statement.requiredText(1)) else {
            throw HistoryError.corrupt("A history epoch row is malformed.")
        }
        let revision = Revision(UInt64(bitPattern: statement.columnInt64(2)))
        let priorText = try statement.requiredText(4)
        let prior = Self.decode(priorText)
        let gap = statement.columnText(5).flatMap { CaptureGapReason(rawValue: $0) }
        return CaptureEpoch(id: epochID, documentID: documentID, recordingUUID: recording,
                            beganAtRevision: revision, beganAtEpochSeconds: statement.columnDouble(3),
                            priorTextCompleteness: prior, gapReason: gap)
    }

    private func recordGap(_ gap: CaptureGap, documentID: DocumentID, epochID: CaptureEpochID) throws {
        let statement = try database.prepare("""
            INSERT INTO history_gaps (gap_id, document_id, epoch_id, reason, revision, recorded_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """)
        try statement.bindText(1, uuidGenerator.nextUUID().uuidString)
        try statement.bindText(2, documentID.rawValue.uuidString)
        try statement.bindText(3, epochID.rawValue.uuidString)
        try statement.bindText(4, gap.reason.rawValue)
        try statement.bindInt64(5, Int64(bitPattern: gap.revision.rawValue))
        try statement.bindDouble(6, gap.recordedAtEpochSeconds)
        _ = try statement.step()
    }

    private func nextChunkIndex(documentID: DocumentID) throws -> UInt64 {
        let statement = try database.prepare("SELECT COALESCE(MAX(chunk_index), -1) FROM history_records WHERE document_id = ?")
        try statement.bindText(1, documentID.rawValue.uuidString)
        guard try statement.step() else { return 0 }
        let latest = statement.columnInt64(0)
        // -1 means no records yet; any real value fits the non-negative range.
        return latest < 0 ? 0 : UInt64(latest) + 1
    }

    private func lastChunkReference(documentID: DocumentID) throws -> Data? {
        let statement = try database.prepare("SELECT chunk_ref FROM history_records WHERE document_id = ? ORDER BY chunk_index DESC LIMIT 1")
        try statement.bindText(1, documentID.rawValue.uuidString)
        guard try statement.step() else { return nil }
        return try statement.requiredBlob(0)
    }

    // MARK: - Encoding

    private struct RecordPayload: Codable { let deleted: Data; let inserted: Data }
    private struct AnnotationPayload: Codable { let description: String; let url: String? }

    private static func encodePayload(deleted: Data, inserted: Data) throws -> Data {
        try JSONEncoder().encode(RecordPayload(deleted: deleted, inserted: inserted))
    }

    private static func decodePayload(_ data: Data) throws -> (Data, Data) {
        do {
            let payload = try JSONDecoder().decode(RecordPayload.self, from: data)
            return (payload.deleted, payload.inserted)
        } catch { throw HistoryError.corrupt("A history record payload could not be decoded.") }
    }

    private static func encodeAnnotation(description: String, url: String?) throws -> Data {
        try JSONEncoder().encode(AnnotationPayload(description: description, url: url))
    }

    private static func decodeAnnotation(_ data: Data) throws -> (String, String?) {
        do {
            let payload = try JSONDecoder().decode(AnnotationPayload.self, from: data)
            return (payload.description, payload.url)
        } catch { throw HistoryError.corrupt("An annotation payload could not be decoded.") }
    }

    private static func uuid(from string: String) -> UUID? { UUID(uuidString: string) }

    private static func encode(_ completeness: CaptureCompleteness) -> String {
        switch completeness {
        case .observed: "observed"
        case .descriptiveOnly: "descriptiveOnly"
        case .gap(let reason): "gap:\(reason)"
        case .recordingOff: "recordingOff"
        }
    }

    private static func decode(_ value: String) -> CaptureCompleteness {
        if value == "observed" { return .observed }
        if value == "recordingOff" { return .recordingOff }
        if value.hasPrefix("gap:") { return .gap(String(value.dropFirst(4))) }
        return .descriptiveOnly
    }
}
