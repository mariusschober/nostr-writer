import Foundation

public enum ContractError: Error, Equatable, Sendable {
    case invalidDigest
    case invalidScope
    case unsupported(String)
    case staleRevision
    case revisionExhausted
    case invalidProofResult
}

extension ContractError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidDigest: "The content identity is invalid or does not match."
        case .invalidScope: "The selected proof range is invalid."
        case .unsupported(let reason): reason
        case .staleRevision: "The document changed before this operation completed."
        case .revisionExhausted: "This session cannot create another revision. Preserve your text in a new document."
        case .invalidProofResult: "No verified proof is available for this result."
        }
    }
}

public struct Digest256: Hashable, Sendable {
    public let bytes: Data
    public init(_ bytes: Data) throws {
        guard bytes.count == 32 else { throw ContractError.invalidDigest }
        self.bytes = bytes
    }
    public static func hash(_ bytes: Data) -> Self { Self(unchecked: SourceSnapshot.sha256(bytes)) }
    private init(unchecked bytes: Data) { self.bytes = bytes }
}

public enum RecordingState: Equatable, Sendable {
    case off, observing, gap(String), pausedLimit, paused
}
public enum AssessmentState: Equatable, Sendable {
    case idle, running, unsupported(String), notProvable(String), completed
}
public enum ProofMode: String, Sendable { case attested = "V", disclosed = "R" }
public enum ProofClaim: String, Sendable { case freshComposition, wordingOrigin }
public enum ProofVerdict: String, Sendable { case validHWP, testOnly, noValidHWP }
public enum ProofContext: String, Sendable { case production, conformance, experimental }

public enum ProofScope: Hashable, Sendable {
    case wholeDocument
    case selected([ByteRange])

    public func validate(in source: SourceSnapshot) throws {
        if case .selected(let ranges) = self {
            guard !ranges.isEmpty else { throw ContractError.invalidScope }
            var previousEnd = 0
            for range in ranges {
                guard range.lowerBound >= previousEnd, range.upperBound > range.lowerBound else {
                    throw ContractError.invalidScope
                }
                _ = try source.nativeRange(for: range)
                previousEnd = range.upperBound
            }
        }
    }
}

/// Output of the native verifier, never decoded directly from an author's proof metadata.
/// This value and its presentation helper do not themselves verify HWP.
public struct ProofResult: Equatable, Sendable {
    public let source: SourceSnapshot
    public let scope: ProofScope
    public let claim: ProofClaim
    public let mode: ProofMode
    public let context: ProofContext
    public let verdict: ProofVerdict
    public let policy: Digest256
    public let release: Digest256
    public let proofDigest: Digest256?
    public let authorityIdentities: [Digest256]
    public let limitations: [String]

    public init(source: SourceSnapshot, scope: ProofScope, claim: ProofClaim, mode: ProofMode,
                context: ProofContext, verdict: ProofVerdict, policy: Digest256, release: Digest256,
                proofDigest: Digest256?, authorityIdentities: [Digest256], limitations: [String]) throws {
        try scope.validate(in: source)
        self.source = source; self.scope = scope; self.claim = claim; self.mode = mode
        self.context = context; self.verdict = verdict; self.policy = policy; self.release = release
        self.proofDigest = proofDigest; self.authorityIdentities = authorityIdentities; self.limitations = limitations
    }
}

/// Independently selected application trust, supplied separately from proof contents.
/// Stage 04 must populate this only from actually verified/pinned policy semantics.
/// User preferences and imported author metadata must never populate admission sets.
public struct IndependentTrustSelection: Sendable {
    public let policy: Digest256
    public let context: ProofContext
    public let admittedReleases: Set<Digest256>
    public init(policy: Digest256, context: ProofContext, admittedReleases: Set<Digest256>) {
        self.policy = policy; self.context = context; self.admittedReleases = admittedReleases
    }
}

public enum ProofDisplay: Equatable, Sendable {
    case notProvable(String)
    case testOnly
    case earlierRevision
    case humanWritten(scope: ProofScope, claim: ProofClaim, mode: ProofMode)

    public var canExportHumanWritingProof: Bool {
        if case .humanWritten = self { return true }
        return false
    }
}

public enum ProofPresentation {
    public static func project(current: SourceSnapshot, selectedScope: ProofScope, selectedClaim: ProofClaim,
                               result: ProofResult?, trust: IndependentTrustSelection) -> ProofDisplay {
        guard let result else { return .notProvable("No verified proof for this revision.") }
        guard result.source == current else { return .earlierRevision }
        guard result.scope == selectedScope, result.claim == selectedClaim else {
            return .notProvable("The verified scope or claim differs from this selection.")
        }
        if result.context == .conformance || result.verdict == .testOnly { return .testOnly }
        guard result.context == .production, trust.context == .production,
              result.verdict == .validHWP, result.policy == trust.policy,
              trust.admittedReleases.contains(result.release), result.proofDigest != nil,
              !result.authorityIdentities.isEmpty else {
            return .notProvable("No complete proof admitted by the independently selected production policy.")
        }
        return .humanWritten(scope: result.scope, claim: result.claim, mode: result.mode)
    }
}
