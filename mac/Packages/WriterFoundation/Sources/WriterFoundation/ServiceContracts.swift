import Foundation

public enum EditOrigin: Equatable, Sendable {
    case directNativeInput
    case nativeIMEUpdate, nativeIMECommit
    case knownAssistance(AssistanceKind)
    case pasteExternal
    case internalMove(UUID), internalCopy(UUID)
    case undo(UUID), redo(UUID)
    case formatting, findReplace, externalReload, recover, unknown
}
public enum AssistanceKind: String, Sendable { case spelling, grammar, completion, dictation, translation, generated }
public enum CaptureCompleteness: Equatable, Sendable { case observed, descriptiveOnly, gap(String), recordingOff }

public struct EditCommand: Sendable {
    public let id: UUID
    public let expectedRevision: Revision
    public let range: ByteRange
    public let replacement: Data
    public let origin: EditOrigin
    public let nativeCauseIDs: [UUID]
    public let undoGroup: UUID
    public init(id: UUID, expectedRevision: Revision, range: ByteRange, replacement: Data,
                origin: EditOrigin, nativeCauseIDs: [UUID] = [], undoGroup: UUID) {
        self.id = id; self.expectedRevision = expectedRevision; self.range = range
        self.replacement = replacement; self.origin = origin; self.nativeCauseIDs = nativeCauseIDs; self.undoGroup = undoGroup
    }
    public func applying(to source: SourceSnapshot, completeness: CaptureCompleteness) throws -> MutationReceipt {
        guard source.revision == expectedRevision else { throw ContractError.staleRevision }
        guard let next = source.revision.next else { throw ContractError.revisionExhausted }
        _ = try source.nativeRange(for: range)
        // Validate the replacement independently; it must never complete a split scalar.
        _ = try SourceSnapshot(documentID: source.documentID, revision: next, utf8: replacement)
        var bytes = source.utf8
        let deleted = bytes.subdata(in: range.lowerBound..<range.upperBound)
        bytes.replaceSubrange(range.lowerBound..<range.upperBound, with: replacement)
        let post = try SourceSnapshot(documentID: source.documentID, revision: next, utf8: bytes)
        return MutationReceipt(command: self, pre: source, post: post, deleted: deleted, inserted: replacement, completeness: completeness)
    }
}

public struct MutationReceipt: Sendable {
    public let command: EditCommand
    public let pre: SourceSnapshot
    public let post: SourceSnapshot
    public let deleted: Data
    public let inserted: Data
    public let completeness: CaptureCompleteness
}

public enum ObservationBoundary: String, Sendable { case save, close, sleep, interruption, proof, historyExport, pause, limit }
public struct CapturedRecordHandle: Hashable, Sendable {
    public let id: UUID
    public let source: SourceSnapshot
    public init(id: UUID, source: SourceSnapshot) { self.id = id; self.source = source }
}
@MainActor public protocol DocumentEditing: AnyObject {
    var snapshot: SourceSnapshot { get }
    func apply(_ command: EditCommand) throws
    func finalizeObservation(reason: ObservationBoundary) async throws -> CapturedRecordHandle?
}

public struct SavedFileRevision: Sendable {
    public let source: SourceSnapshot
    public let url: URL
    public init(source: SourceSnapshot, url: URL) { self.source = source; self.url = url }
}
public struct DurableRevision: Sendable {
    public let source: SourceSnapshot
    public let recoveryCommit: UUID
    public let savedFile: SavedFileRevision?
    public init(source: SourceSnapshot, recoveryCommit: UUID, savedFile: SavedFileRevision?) {
        self.source = source; self.recoveryCommit = recoveryCommit; self.savedFile = savedFile
    }
}
public struct RecoveryBatch: Sendable {
    public let source: SourceSnapshot
    public let receipts: [MutationReceipt]
    public init(source: SourceSnapshot, receipts: [MutationReceipt]) { self.source = source; self.receipts = receipts }
}
public enum RecoveryState: Sendable {
    case complete(DurableRevision)
    case localPartial(SourceSnapshot, reason: String)
    case conflict(local: SourceSnapshot, external: SourceSnapshot)
    case corrupt(String), keyUnavailable(String), absent
}
public protocol DocumentPersistence: Sendable {
    func persist(_ batch: RecoveryBatch) async throws -> DurableRevision
    func recover(_ id: DocumentID) async throws -> RecoveryState
}

public struct AssessmentInput: Sendable {
    public let source: SourceSnapshot
    public let scope: ProofScope
    public let record: CapturedRecordHandle?
    public init(source: SourceSnapshot, scope: ProofScope, record: CapturedRecordHandle?) {
        self.source = source; self.scope = scope; self.record = record
    }
}
public struct AssessmentResult: Sendable {
    public let source: SourceSnapshot
    public let state: AssessmentState
    public init(source: SourceSnapshot, state: AssessmentState) { self.source = source; self.state = state }
}
public struct VerificationInput: Sendable {
    public let source: SourceSnapshot
    public let proof: Data
    public let externalPolicy: Data
    public let selectedPolicyDigest: Digest256
    public let mode: ProofMode
    public let disclosure: Data?
    public init(source: SourceSnapshot, proof: Data, externalPolicy: Data, selectedPolicyDigest: Digest256,
                mode: ProofMode, disclosure: Data?) {
        self.source = source; self.proof = proof; self.externalPolicy = externalPolicy
        self.selectedPolicyDigest = selectedPolicyDigest; self.mode = mode; self.disclosure = disclosure
    }
}
public struct IssuanceInput: Sendable {
    public let source: SourceSnapshot
    public let record: CapturedRecordHandle
    public let scope: ProofScope
    public let plannedRelease: Digest256
    public let selectedPolicy: Digest256
    public let plannedParents: [Digest256]
    public init(source: SourceSnapshot, record: CapturedRecordHandle, scope: ProofScope,
                plannedRelease: Digest256, selectedPolicy: Digest256, plannedParents: [Digest256]) {
        self.source = source; self.record = record; self.scope = scope; self.plannedRelease = plannedRelease
        self.selectedPolicy = selectedPolicy; self.plannedParents = plannedParents
    }
}
public struct VerifiedProofArtifact: Sendable {
    public let bytes: Data
    public let result: ProofResult
    public init(bytes: Data, result: ProofResult) throws {
        guard result.verdict != .noValidHWP, !result.authorityIdentities.isEmpty else {
            throw ContractError.invalidProofResult
        }
        guard result.proofDigest == Digest256.hash(bytes) else { throw ContractError.invalidDigest }
        self.bytes = bytes; self.result = result
    }
}
public protocol ProofChecking: Sendable {
    func assess(_ input: AssessmentInput) async -> AssessmentResult
    func verify(_ input: VerificationInput) async -> ProofResult
    func issue(_ input: IssuanceInput) async throws -> VerifiedProofArtifact
}

public enum ExportFormat: String, Sendable { case source, pdf, docx, documentBundle }
public enum ExportTemplate: String, Sendable { case editorial, manuscript }
public enum PaperSize: String, Sendable { case a4, letter }
public struct ExportSnapshot: Sendable {
    public let jobID: UUID
    public let source: SourceSnapshot
    public let template: ExportTemplate
    public let paper: PaperSize
    public let metadata: [String: String]
    public let assets: [String: Data]
    public let proof: VerifiedProofArtifact?
    public init(jobID: UUID, source: SourceSnapshot, template: ExportTemplate, paper: PaperSize,
                metadata: [String: String], assets: [String: Data], proof: VerifiedProofArtifact?) {
        self.jobID = jobID; self.source = source; self.template = template; self.paper = paper
        self.metadata = metadata; self.assets = assets; self.proof = proof
    }
}
public typealias ExportRequest = ExportSnapshot
public struct ExportArtifact: Sendable {
    public let jobID: UUID
    public let source: SourceSnapshot
    public let format: ExportFormat
    public let bytes: Data
    public let digest: Digest256
    public let warnings: [String]
    public init(jobID: UUID, source: SourceSnapshot, format: ExportFormat, bytes: Data, warnings: [String]) {
        self.jobID = jobID; self.source = source; self.format = format; self.bytes = bytes
        self.digest = .hash(bytes); self.warnings = warnings
    }
}
public protocol DocumentExporting: Sendable {
    func render(_ snapshot: ExportSnapshot, format: ExportFormat) async throws -> ExportArtifact
}

public struct OutboxID: Hashable, Sendable {
    public let rawValue: UUID
    public init(_ rawValue: UUID) { self.rawValue = rawValue }
}
public struct PublishIntent: Sendable {
    public let id: OutboxID
    public let source: SourceSnapshot
    public let identityID: UUID
    public let kind: UInt32
    public let metadata: [String: String]
    public let destinationURLs: [URL]
    public init(id: OutboxID, source: SourceSnapshot, identityID: UUID, kind: UInt32,
                metadata: [String: String], destinationURLs: [URL]) {
        self.id = id; self.source = source; self.identityID = identityID; self.kind = kind
        self.metadata = metadata; self.destinationURLs = destinationURLs
    }
}
public enum DeliveryState: Sendable {
    case durableIntent, signedPersisted(Digest256), sending
    case acceptedAtLeastOne(accepted: Int, total: Int)
    case failed(String), pausedIdentity, cancelledRetries
}
public protocol NostrPublishing: Sendable {
    func enqueue(_ intent: PublishIntent) async throws -> OutboxID
    func retry(_ id: OutboxID) async throws
    func observe(_ id: OutboxID) async -> AsyncStream<DeliveryState>
}
