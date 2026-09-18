import Foundation

// Stage 03 pure observation, ancestry and annotation contracts.
//
// These types are deliberately separate from the frozen HWP protocol and from
// the rolling recovery store. They describe *what the running application can
// actually observe* about local writing: an ordered, verifiable chain of edits
// with real pre/post bytes, exact scalar-aligned ranges and honest gaps. They
// never invent physical typing, key-up timing, hardware delivery or source
// parents that were not observed.
//
// Nothing here approves a Mac capture profile. Software-only observation is
// descriptive local history; the production approval set remains unchanged.

/// Stable identity of one prospective consented recording epoch.
public struct CaptureEpochID: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
    public init() { self.rawValue = UUID() }
    public var description: String { rawValue.uuidString }
}

/// Why detailed recording is not continuous at a boundary.
///
/// A gap is an honest statement that intermediate detail was not retained. It is
/// never repaired into a continuous chain, and a gap never means the text is
/// wrong: the source itself remains exact and editable.
public enum CaptureGapReason: String, Hashable, Sendable {
    case recordingOff
    case userPaused
    case resumed
    case opaqueInput
    case ancestryLost
    case storeFailure
    case resourceLimit
    case processRestart
    case boundarySave
    case boundaryClose
    case boundarySleep
    case boundaryInterruption
}

/// One honest discontinuity in an otherwise ordered journal.
public struct CaptureGap: Hashable, Sendable {
    public let reason: CaptureGapReason
    /// Revision the gap was observed at.
    public let revision: Revision
    public let recordedAtEpochSeconds: Double
    public init(reason: CaptureGapReason, revision: Revision, recordedAtEpochSeconds: Double) {
        self.reason = reason
        self.revision = revision
        self.recordedAtEpochSeconds = recordedAtEpochSeconds
    }
}

/// A prospective recording epoch.
///
/// Turning recording on starts a new epoch at the current revision. Text that
/// already existed is *pre-existing*: it is imported as `descriptiveOnly`, never
/// claimed as freshly observed. Pause, restart, resource or store failures and
/// consent changes establish boundaries rather than fabricating continuity.
public struct CaptureEpoch: Equatable, Sendable {
    public let id: CaptureEpochID
    public let documentID: DocumentID
    /// Journal stream identity, distinct from both document and HWP-run identity.
    public let recordingUUID: UUID
    public let beganAtRevision: Revision
    public let beganAtEpochSeconds: Double
    /// Completeness of the text that already existed when the epoch began.
    public let priorTextCompleteness: CaptureCompleteness
    public let gapReason: CaptureGapReason?

    public init(id: CaptureEpochID = CaptureEpochID(), documentID: DocumentID, recordingUUID: UUID,
                beganAtRevision: Revision, beganAtEpochSeconds: Double,
                priorTextCompleteness: CaptureCompleteness, gapReason: CaptureGapReason? = nil) {
        self.id = id
        self.documentID = documentID
        self.recordingUUID = recordingUUID
        self.beganAtRevision = beganAtRevision
        self.beganAtEpochSeconds = beganAtEpochSeconds
        self.priorTextCompleteness = priorTextCompleteness
        self.gapReason = gapReason
    }
}

/// Stable, persisted category of an observed edit cause.
///
/// This is the storage-safe projection of `EditOrigin`: it keeps the honest
/// category while the private source token (an in-memory `UUID`) is not written
/// to durable history. Classification always comes from an observed or declared
/// cause, never from the shape of the resulting text.
public enum EditOriginCategory: String, Hashable, Sendable, CaseIterable {
    case directNativeInput
    case nativeIMEUpdate
    case nativeIMECommit
    case assistance
    case pasteExternal
    case internalMove
    case internalCopy
    case undo
    case redo
    case formatting
    case findReplace
    case externalReload
    case recover
    case unknown

    /// Whether this category is an honest, explained cause. `unknown` is a gap.
    public var isExplained: Bool { self != .unknown }
}

public extension EditOrigin {
    /// Honest persisted category for this origin.
    var category: EditOriginCategory {
        switch self {
        case .directNativeInput: .directNativeInput
        case .nativeIMEUpdate: .nativeIMEUpdate
        case .nativeIMECommit: .nativeIMECommit
        case .knownAssistance: .assistance
        case .pasteExternal: .pasteExternal
        case .internalMove: .internalMove
        case .internalCopy: .internalCopy
        case .undo: .undo
        case .redo: .redo
        case .formatting: .formatting
        case .findReplace: .findReplace
        case .externalReload: .externalReload
        case .recover: .recover
        case .unknown: .unknown
        }
    }

    /// Assistance sub-kind, when this origin is known assistance.
    var assistanceKind: AssistanceKind? {
        if case .knownAssistance(let kind) = self { return kind }
        return nil
    }

    /// Private source token for internal move/copy, kept out of durable history.
    var ancestryTokenID: UUID? {
        switch self {
        case .internalMove(let id), .internalCopy(let id), .undo(let id), .redo(let id): id
        default: nil
        }
    }
}

/// One ordered, replayable local edit. It carries the exact bytes needed to
/// reconstruct the chain without trusting the live editor.
public struct LocalEditRecord: Hashable, Sendable {
    public let id: UUID
    public let epochID: CaptureEpochID
    /// Pre-edit revision; replay rejects a record whose revision does not match.
    public let revision: Revision
    /// Exact scalar-aligned half-open range in pre-edit UTF-8 bytes.
    public let range: ByteRange
    /// Bytes actually removed (empty for pure insertion).
    public let deleted: Data
    /// Bytes actually inserted (empty for pure deletion).
    public let inserted: Data
    public let originCategory: EditOriginCategory
    public let assistanceKind: AssistanceKind?
    /// Digest of the post-edit source, for cheap chain validation.
    public let postDigest: Data
    public let recordedAtEpochSeconds: Double

    public init(id: UUID = UUID(), epochID: CaptureEpochID, revision: Revision, range: ByteRange,
                deleted: Data, inserted: Data, originCategory: EditOriginCategory,
                assistanceKind: AssistanceKind? = nil, postDigest: Data, recordedAtEpochSeconds: Double) {
        self.id = id
        self.epochID = epochID
        self.revision = revision
        self.range = range
        self.deleted = deleted
        self.inserted = inserted
        self.originCategory = originCategory
        self.assistanceKind = assistanceKind
        self.postDigest = postDigest
        self.recordedAtEpochSeconds = recordedAtEpochSeconds
    }

    /// Builds a record from an actual receipt. The completeness cause is the
    /// caller's observed declaration; it is not re-derived from text.
    public init(epochID: CaptureEpochID, receipt: MutationReceipt, recordedAtEpochSeconds: Double) {
        self.init(
            epochID: epochID,
            revision: receipt.pre.revision,
            range: receipt.command.range,
            deleted: receipt.deleted,
            inserted: receipt.inserted,
            originCategory: receipt.command.origin.category,
            assistanceKind: receipt.command.origin.assistanceKind,
            postDigest: receipt.post.digest,
            recordedAtEpochSeconds: recordedAtEpochSeconds
        )
    }
}

/// Typed failures while replaying or validating a local edit chain.
public enum ReplayError: Error, Equatable, Sendable {
    case staleRevision(index: Int, expected: UInt64, found: UInt64)
    case deletedBytesMismatch(index: Int)
    case postDigestMismatch(index: Int)
    case notScalarAligned(index: Int)
    case revisionExhausted(index: Int)
}

/// Pure replay of an ordered local edit chain onto an exact source.
///
/// Replay never trusts the caller's "final text": it applies each record to the
/// previous snapshot, verifies the removed bytes equal what the record claims,
/// and verifies the resulting digest. A mismatch is a hard error, not a silent
/// repair. This is the same verification an interactive recovery uses.
public enum LocalReplay {
    /// Replays `records` starting from `initial`, returning the final snapshot.
    public static func replay(from initial: SourceSnapshot, records: [LocalEditRecord],
                              documentID: DocumentID? = nil) throws -> SourceSnapshot {
        var current = initial
        for (index, record) in records.enumerated() {
            guard current.revision == record.revision else {
                throw ReplayError.staleRevision(index: index, expected: current.revision.rawValue, found: record.revision.rawValue)
            }
            guard let next = current.revision.next else { throw ReplayError.revisionExhausted(index: index) }
            guard (try? current.nativeRange(for: record.range)) != nil else { throw ReplayError.notScalarAligned(index: index) }
            let existing = current.utf8.subdata(in: record.range.lowerBound..<record.range.upperBound)
            guard existing == record.deleted else { throw ReplayError.deletedBytesMismatch(index: index) }
            var bytes = current.utf8
            bytes.replaceSubrange(record.range.lowerBound..<record.range.upperBound, with: record.inserted)
            let nextID = documentID ?? current.documentID
            let post = try SourceSnapshot(documentID: nextID, revision: next, utf8: bytes)
            guard post.digest == record.postDigest else { throw ReplayError.postDigestMismatch(index: index) }
            current = post
        }
        return current
    }
}

// MARK: - Ancestry

/// An app-issued private token binding an internal copy/move to a real source
/// record and the exact bytes that were carried. Identical text alone never
/// earns ancestry; the payload digest must match exactly.
public struct AncestryToken: Hashable, Sendable {
    public let id: UUID
    public let originCategory: EditOriginCategory
    public let sourceRecordID: UUID
    public let payloadDigest: Data
    public init(id: UUID = UUID(), originCategory: EditOriginCategory, sourceRecordID: UUID, payloadDigest: Data) {
        self.id = id
        self.originCategory = originCategory
        self.sourceRecordID = sourceRecordID
        self.payloadDigest = payloadDigest
    }

    /// Whether a live payload actually matches this token's carried bytes.
    public func matches(payload: Data) -> Bool { SourceSnapshot.sha256(payload) == payloadDigest }
}

// MARK: - Annotations

/// Why a source span is marked as not-freshly-composed.
public enum AnnotationKind: String, Hashable, Sendable, CaseIterable {
    case quotation
    case citation
    case assisted
    case imported
}

/// One annotated source span, bound to an exact scalar-aligned range.
///
/// A visual expansion to a grapheme never expands the persisted claim scope, and
/// later replacement never inherits a favourable exclusion merely by occupying
/// the same character indexes.
public struct SourceAnnotation: Hashable, Sendable {
    public let id: UUID
    public let kind: AnnotationKind
    public let range: ByteRange
    public let description: String
    public let url: String?
    /// Revision the range was recorded against.
    public let revision: Revision
    /// Set when the bound range could not be preserved and needs review.
    public let isStale: Bool

    public init(id: UUID = UUID(), kind: AnnotationKind, range: ByteRange, description: String,
                url: String? = nil, revision: Revision, isStale: Bool = false) {
        self.id = id
        self.kind = kind
        self.range = range
        self.description = description
        self.url = url
        self.revision = revision
        self.isStale = isStale
    }
}

/// Outcome of mapping one annotated range across one edit.
public enum RangeMapping: Hashable, Sendable {
    /// The range survived as a single interval.
    case preserved(ByteRange)
    /// The range survived as several intervals (an edit split it).
    case split([ByteRange])
    /// The annotated wording did not survive; the annotation needs review.
    case stale
}

/// Pure lineage mapping from one edit record to surviving annotation ranges.
public enum SourceLineage {
    /// Maps `range` across `record`, which happened at the same revision.
    public static func map(_ range: ByteRange, through record: LocalEditRecord) -> RangeMapping {
        let lower = record.range.lowerBound
        let upper = record.range.upperBound
        let delta = record.inserted.count - record.deleted.count

        if range.upperBound <= lower { return .preserved(range) }
        if range.lowerBound >= upper {
            guard let shifted = try? ByteRange(lowerBound: range.lowerBound + delta, upperBound: range.upperBound + delta) else {
                return .stale
            }
            return .preserved(shifted)
        }
        var survivors: [ByteRange] = []
        if range.lowerBound < lower,
           let head = try? ByteRange(lowerBound: range.lowerBound, upperBound: min(range.upperBound, lower)) {
            survivors.append(head)
        }
        if range.upperBound > upper,
           let tail = try? ByteRange(lowerBound: max(range.lowerBound, upper) + delta, upperBound: range.upperBound + delta) {
            survivors.append(tail)
        }
        if survivors.isEmpty { return .stale }
        if survivors.count == 1 { return .preserved(survivors[0]) }
        return .split(survivors)
    }

    /// Maps one annotation across a whole ordered chain, returning the survivors
    /// (an empty array means the wording was replaced away and is now stale).
    public static func map(_ annotation: SourceAnnotation, through records: [LocalEditRecord]) -> [SourceAnnotation] {
        var ranges: [ByteRange] = [annotation.range]
        for record in records {
            var next: [ByteRange] = []
            for range in ranges {
                switch map(range, through: record) {
                case .preserved(let r): next.append(r)
                case .split(let rs): next.append(contentsOf: rs)
                case .stale: continue
                }
            }
            ranges = next
            if ranges.isEmpty { break }
        }
        guard !ranges.isEmpty else { return [] }
        return ranges.map {
            SourceAnnotation(id: annotation.id, kind: annotation.kind, range: $0,
                             description: annotation.description, url: annotation.url,
                             revision: annotation.revision, isStale: false)
        }
    }
}
