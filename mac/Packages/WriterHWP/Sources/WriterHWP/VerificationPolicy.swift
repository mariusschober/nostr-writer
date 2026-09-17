import Foundation

/// The relying party supplies both exact policy bytes and an independently chosen
/// pin. A policy carried beside an author's proof must never choose this argument.
public struct HWPVerificationPolicy: Sendable {
    struct CaptureGrant: Sendable { let profile: HWPReference; let keys: [HWPReference] }
    public let bytes: Data
    public let sha256: Data
    public let value: HWPValue
    let protocolReference: HWPReference
    let purpose: String
    let releases: [HWPReference]
    let evaluators: [HWPReference]
    let identities: [HWPReference]
    let captureGrants: [Data: CaptureGrant]
    let denied: Set<Data>
    let quorum: Int
    let modes: Set<AlgorithmText>
    let requiresAuthor: Bool
    let statusAsOf: HWPValue

    public init(bytes: Data, expectedSHA256: Data) throws {
        typealias V = HWPProtocolValues
        try V.need(expectedSHA256.count == 32 && HWPMerkle.digest(bytes) == expectedSHA256, "external-policy-pin")
        let value = try HWPCBOR.decode(bytes)
        try V.typed(value, "verification-policy", "label releases capture_authorities evaluators quorum modes require_author identity_authorities denied status_as_of protocol purpose")
        let purpose = try V.text(value.field("purpose")).string
        try V.need(["production", "conformance"].contains(purpose), "policy-purpose")
        _ = try V.text(value.field("label"), minimum: 1, maximum: 256, reason: "policy-label")
        let releases = try V.references(value.field("releases")), evaluators = try V.references(value.field("evaluators"), maximum: 64)
        let quorum = try V.integer(value.field("quorum"), low: 1, high: 64)
        let modes = try V.texts(value.field("modes"))
        try V.need(Set(modes).isSubset(of: [AlgorithmText("attested-v1"), AlgorithmText("disclosed-v1")]), "policy-modes")
        guard case .boolean(let author) = value.field("require_author") else { throw HWPReject("policy-author") }
        let identities = try V.references(value.field("identity_authorities"), maximum: 64)
        let deny = try V.array(value.field("denied"), reason: "policy-deny-list").map { try V.bytes($0, length: 32) }
        try V.need(deny == Set(deny).sorted { $0.lexicographicallyPrecedes($1) }, "policy-deny-list")
        let status = try V.field(value, "status_as_of")
        if status != .null { _ = try V.integer(status) }
        var grants: [Data: CaptureGrant] = [:], previous: Data?
        for entry in try V.array(value.field("capture_authorities"), maximum: 64, reason: "capture-authorities") {
            try V.fields(entry, "profile keys")
            let profile = try V.reference(entry.field("profile")), keys = try V.references(entry.field("keys"), minimum: 1, maximum: 64)
            if let previous { try V.need(previous.lexicographicallyPrecedes(profile.sha256), "capture-authority-order") }
            grants[profile.sha256] = CaptureGrant(profile: profile, keys: keys); previous = profile.sha256
        }
        self.bytes = bytes; self.sha256 = expectedSHA256; self.value = value
        self.protocolReference = try V.reference(value.field("protocol")); self.purpose = purpose
        self.releases = releases; self.evaluators = evaluators; self.identities = identities
        self.captureGrants = grants; self.denied = Set(deny); self.quorum = Int(quorum)
        self.modes = Set(modes); self.requiresAuthor = author; self.statusAsOf = status
    }
}

/// Only immutable definition artifacts and the empty production policy ship here.
/// No fixture key, permissive model, conformance policy or executable is installed.
public enum HWPInstalledProtocol {
    static let definitionDigest = "58efebeb46689cfafd597230facda03a9541d423b244d36b84cff35b2fc8c6d4"
    static let defaultPolicyDigest = "70db9cedf0bcd4b584025ef5c23ed1a57087e7fc2e305b631665345b76c426be"
    static func hex(_ value: String) -> Data {
        let bytes = Array(value.utf8)
        return Data(stride(from: 0, to: bytes.count, by: 2).map { UInt8(String(decoding: bytes[$0..<$0+2], as: UTF8.self), radix: 16)! })
    }
    static func resource(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "ProtocolAnchors") else { throw HWPReject("installed-anchor-unavailable") }
        let raw = try Data(contentsOf: url)
        try HWPProtocolValues.need(raw.count <= HWPCBOR.maximumBytes, "installed-anchor-size")
        return raw
    }
    public static func defaultPolicy() throws -> HWPVerificationPolicy {
        try HWPVerificationPolicy(bytes: resource("production-default.cbor"), expectedSHA256: hex(defaultPolicyDigest))
    }
}

struct HWPInstalledDefinition: Sendable {
    let bytes: Data
    let reference: HWPReference
    let fixed: [String: HWPReference]
    let programFiles: [HWPReference]
    let normativeObjects: [HWPReference]
    init() throws {
        typealias V = HWPProtocolValues
        let bytes = try HWPInstalledProtocol.resource("protocol.cbor"), reference = try HWPReference(bytes: bytes)
        try V.need(reference.sha256 == HWPInstalledProtocol.hex(HWPInstalledProtocol.definitionDigest), "installed-definition")
        let definition = try HWPCBOR.decode(bytes)
        try V.typed(definition, "protocol-definition", "name revision artifacts")
        try V.need(definition.field("name") == .text("Human Writing Protocol") && definition.field("revision") == .text("0.0.0"), "installed-definition")
        let artifacts = try V.field(definition, "artifacts")
        var fixed: [String: HWPReference] = [:]
        for (name, file) in [("algorithm_spec", "algorithm-spec.md"), ("program", "program.cbor"), ("evidence_adapter", "evidence-adapter.md"), ("output_contract", "output-contract.md")] {
            let raw = try HWPInstalledProtocol.resource(file), r = try V.reference(artifacts.field(name))
            try V.need(HWPReference(bytes: raw) == r, "installed-artifact-changed"); fixed[name] = r
        }
        let program = try HWPCBOR.decode(HWPInstalledProtocol.resource("program.cbor"))
        try V.typed(program, "program", "algorithm files")
        try V.need(program.field("algorithm") == .text("hwp-a/v0"), "installed-program")
        var files: [HWPReference] = [], paths: Set<AlgorithmText> = []
        for entry in try V.array(program.field("files")) {
            try V.fields(entry, "path ref"); let path = try V.text(entry.field("path"))
            try V.need(path.string.hasPrefix("hwp0/") && !path.string.split(separator: "/").contains("..") && paths.insert(path).inserted, "installed-path")
            files.append(try V.reference(entry.field("ref")))
        }
        guard case .map(let entries) = artifacts else { throw HWPReject("installed-definition") }
        self.bytes = bytes; self.reference = reference; self.fixed = fixed; self.programFiles = files
        self.normativeObjects = try entries.map { try V.reference($0.value) }
    }
}
