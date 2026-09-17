import Foundation
import CryptoKit

struct HWPDisclosureInputs {
    typealias V = HWPProtocolValues
    let logs: [Data: (reference: HWPReference, openings: [HWPValue])]
    let salts: [Data: (reference: HWPReference, salt: Data)]
    init(_ value: HWPValue) throws {
        try V.fields(value, "logs lineage_salts")
        var logs: [Data: (HWPReference, [HWPValue])] = [:], salts: [Data: (HWPReference, Data)] = [:]
        var events = 0, bytes = 0
        for entry in try V.array(value.field("logs"), maximum: 4096, reason: "disclosure-count") {
            try V.fields(entry, "capture openings"); let ref = try V.reference(entry.field("capture"))
            let openings = try V.array(entry.field("openings"), maximum: 1_000_000, reason: "disclosure-openings")
            try V.need(openings.count <= 1_000_000 - events, "disclosure-event-budget"); events += openings.count
            for opening in openings {
                try Task.checkCancellation(); try V.fields(opening, "index salt event")
                let event = try V.bytes(opening.field("event")); _ = try V.bytes(opening.field("salt"), length: 32)
                try V.need(event.count + 32 <= HWPCBOR.maximumBytes - bytes, "disclosure-byte-budget"); bytes += event.count + 32
            }
            try V.need(logs[ref.sha256] == nil, "duplicate-disclosed-session"); logs[ref.sha256] = (ref, openings)
        }
        for entry in try V.array(value.field("lineage_salts"), maximum: 64, reason: "disclosure-count") {
            try V.fields(entry, "statement salt"); let ref = try V.reference(entry.field("statement")), salt = try V.bytes(entry.field("salt"), length: 32)
            try V.need(salts[ref.sha256] == nil, "duplicate-lineage-salt"); salts[ref.sha256] = (ref, salt)
        }
        self.logs = logs; self.salts = salts
    }
    func evidence(_ infos: [Data: HWPAdmittedCapture]) throws -> [HWPValue] {
        try infos.values.sorted { $0.reference.sha256.lexicographicallyPrecedes($1.reference.sha256) }.map { info in
            guard let log = logs[info.reference.sha256], log.reference == info.reference else { throw HWPReject("missing-disclosed-session") }
            let events = try HWPTranscript.open(start: V.reference(info.end.field("start")), count: Int(V.integer(info.end.field("count"), low: 2, high: 1_000_000)),
                root: V.bytes(info.end.field("root"), length: 32), openings: log.openings)
            return V.object(["capture": info.reference.value, "events": .array(events)])
        }
    }
    func salt(_ statement: HWPReference) throws -> Data {
        guard let entry = salts[statement.sha256], entry.reference == statement else { throw HWPReject("missing-lineage-salt") }; return entry.salt
    }
}

extension HWPProtocolContext {
    func verify(_ proofReference: HWPReference, expectedDocument: Data? = nil, disclosures: HWPValue? = nil) throws -> HWPValue {
        _ = try get(proofReference)
        try V.need(!activeProofs.contains(proofReference.sha256), "cyclic-proof")
        if let cached = completedProofs[proofReference.sha256] {
            if let expectedDocument { try V.need(cached.field("_document") == .bytes(expectedDocument), "expected-document-mismatch") }
            return cached
        }
        try V.need(proofSteps < 64, "proof-graph-budget"); proofSteps += 1
        activeProofs.insert(proofReference.sha256); defer { activeProofs.remove(proofReference.sha256) }
        let proof = try object(proofReference); try V.typed(proof, "proof", "statement appraisals author")
        let statementReference = try V.reference(proof.field("statement")), state = try object(statementReference)
        let admission = try admit(state), release = admission.release, infos = admission.captures
        let document = try get(state.field("document")); try V.need(document.count <= 1024 * 1024, "document-size")
        if let expectedDocument { try V.need(document == expectedDocument, "expected-document-mismatch") }
        _ = try AlgorithmText(utf8: document)
        try V.need([.text("text/plain"), .text("text/markdown")].contains(try V.field(state, "media_type")), "document-media-type")
        _ = try V.bytes(state.field("lineage"), length: 32); _ = try V.bytes(state.field("nonce"), length: 32)
        let mode = try V.text(state.field("mode")); try V.need(policy.modes.contains(mode), "execution-mode-not-authorized")
        let scope = try object(state.field("scope")), selection = try HWPObservationBridge.selectedScope(scope, document: document)
        let captureRefs = Set(infos.values.map(\.reference)), captureKeys = Set(infos.values.map(\.keyID))
        var selected: [HWPValue] = []
        for range in selection.ranges where !range.excluded {
            selected.append(.array([.unsigned(UInt64(range.start)), .unsigned(UInt64(range.end))]))
            if range.origin[0] == .text("observed") {
                let refs = try V.references(range.origin[1], minimum: 1, maximum: 32)
                try V.need(refs.allSatisfy(captureRefs.contains), "origin-capture-binding")
                try V.need(refs.allSatisfy { infos[$0.sha256]?.start.field("subject") == state.field("author") }, "observed-subject-binding")
            } else {
                try V.need(release.value.field("claim") == .text("wording-origin"), "inherited-not-fresh")
                let parent = try verify(V.reference(range.origin[1]), disclosures: disclosures)
                let parentDocument = try V.bytes(parent.field("_document")), start = Int(try V.integer(range.origin[2], high: Int64(parentDocument.count)))
                let end = Int(try V.integer(range.origin[3], low: Int64(start) + 1, high: Int64(parentDocument.count)))
                try V.need(end - start == range.end - range.start && parentDocument[start..<end] == document[range.start..<range.end], "parent-text-binding")
                try V.need(covered(start: start, end: end, ranges: V.array(parent.field("ranges"))), "parent-range-not-certified")
            }
        }
        var evaluators: Set<Data> = []
        for ref in try V.references(proof.field("appraisals"), minimum: 1, maximum: 64) {
            let result = try signed(ref); try V.typed(result.payload, "appraisal", "statement result")
            try V.need(V.reference(result.payload.field("statement")) == statementReference && result.payload.field("result") == .text("HUMAN-WRITTEN"), "appraisal-result-or-statement")
            try V.need(!evaluators.contains(result.keyID), "evaluator-role-or-duplicate")
            var authorized = false
            for key in policy.evaluators where key.sha256 == result.keyID { _ = try get(key); authorized = true }
            try V.need(authorized, "evaluator-role-or-duplicate")
            try V.need(!captureKeys.contains(result.keyID), "capture-evaluator-key-separation"); evaluators.insert(result.keyID)
        }
        try V.need(evaluators.count >= policy.quorum, "evaluator-quorum")
        let recompute = mode == AlgorithmText("disclosed-v1") || forceRecompute
        if recompute {
            guard let disclosures else { throw HWPReject("missing-disclosed-evidence") }
            let inputs = try HWPDisclosureInputs(disclosures)
            let actual = try HWPObservationBridge.run(evidence: inputs.evidence(infos), release: release,
                target: V.reference(state.field("target_capture")), scope: scope, salt: inputs.salt(statementReference), infos: infos, store: store)
            try V.need(actual.result == Self.expectedComputation(state), "recomputed-output-mismatch")
            lineages[statementReference.sha256] = actual.lineage
        }
        var author: HWPValue = .text("none")
        if state.field("author") == .null {
            try V.need(proof.field("author") == .null && !policy.requiresAuthor, "author-required-or-unexpected")
        } else {
            let key = try V.reference(state.field("author")); _ = try HWPCOSE.parsePublicKey(get(key))
            try V.need(proof.field("author") != .null, "missing-author-endorsement")
            let endorsement = try signed(proof.field("author")); try V.typed(endorsement.payload, "author-endorsement", "statement identity")
            try V.need(V.reference(endorsement.payload.field("statement")) == statementReference && endorsement.keyID == key.sha256, "author-binding")
            try V.need(!captureKeys.contains(key.sha256) && !evaluators.contains(key.sha256), "author-authority-key-separation")
            author = .text("pseudonymous-key-endorsement")
            if endorsement.payload.field("identity") != .null {
                let identity = try signed(endorsement.payload.field("identity")); try V.typed(identity.payload, "identity-binding", "subject namespace identifier")
                var authorized = false
                for key in policy.identities where key.sha256 == identity.keyID { _ = try get(key); authorized = true }
                try V.need(authorized, "identity-authority")
                try V.need(V.reference(identity.payload.field("subject")) == key, "identity-key-binding")
                let namespace = try V.text(identity.payload.field("namespace"), minimum: 1, maximum: 256, reason: "identity-fields")
                let identifier = try V.text(identity.payload.field("identifier"), minimum: 1, maximum: 1024, reason: "identity-fields")
                author = V.object(["kind": .text("attested-key-controller"), "namespace": namespace.value, "identifier": identifier.value])
            }
        }
        let out = V.object(["status": .text("INTERNAL-CHECKED"), "result": .text("HUMAN-WRITTEN"), "claim": try V.field(release.value, "claim"),
            "scope": .text(selection.kind), "ranges": .array(selected), "proof": proofReference.value,
            "document": try V.field(state, "document"), "release": release.reference.value, "mode": mode.value,
            "policy_sha256": .bytes(policy.sha256), "policy_status_as_of": policy.statusAsOf, "author": author,
            "timestamp": .text("not-assessed"), "execution_checked": .text(recompute ? "recomputed" : "attestation"), "_document": .bytes(document)])
        completedProofs[proofReference.sha256] = out; return out
    }

    static func expectedComputation(_ state: HWPValue) throws -> HWPValue {
        var fields: [String: HWPValue] = ["result": .text("HUMAN-WRITTEN")]
        for name in ["document", "scope", "lineage", "release", "captures", "target_capture"] { fields[name] = try V.field(state, name) }
        return V.object(fields)
    }
    private func covered(start: Int, end: Int, ranges: [HWPValue]) throws -> Bool {
        var cursor = start
        for range in ranges {
            let pair = try V.array(range, minimum: 2, maximum: 2)
            let a = Int(try V.integer(pair[0])), b = Int(try V.integer(pair[1]))
            if b <= cursor { continue }; if a > cursor { return false }
            cursor = max(cursor, b); if cursor >= end { return true }
        }
        return false
    }
}

/// Native, offline P/V/R entry points. The public verdict always distinguishes
/// admitted production proofs from conditional conformance-only assertions.
public enum HWPProtocol {
    typealias V = HWPProtocolValues
    public static func verify(bundle: Data, document: Data, policyBytes: Data? = nil, policyPin: Data? = nil,
                              disclosures: HWPValue? = nil, recompute: Bool = false) throws -> HWPValue {
        do {
            guard let policyBytes, let policyPin else { throw HWPReject("no-external-trust-policy") }
            let policy = try HWPVerificationPolicy(bytes: policyBytes, expectedSHA256: policyPin)
            let unpacked = try HWPObjectStore.unpack(bundle), context = try HWPProtocolContext(store: unpacked.store, policy: policy, forceRecompute: recompute)
            let checked = try context.verify(unpacked.root, expectedDocument: document, disclosures: disclosures)
            guard case .map(let fields) = checked else { throw HWPReject("malformed-result") }
            var out: [String: HWPValue] = [:]
            for entry in fields {
                let name = try V.text(entry.key).string
                if !name.hasPrefix("_") { out[name] = entry.value }
            }
            let test = policy.purpose == "conformance"
            out["status"] = .text(test ? "TEST-ONLY" : "VALID-HWP")
            out["outcome"] = .text(test ? "NOT PROVABLE" : "HUMAN-WRITTEN")
            if test { out["result"] = .null }
            out["test_conformance"] = .boolean(test); out["protocol"] = .text("hwp/0"); out["authorship_inference"] = .null
            return V.object(out)
        } catch let error as HWPReject {
            return V.object(["protocol": .text("hwp/0"), "status": .text("NO-VALID-HWP"), "outcome": .text("NOT PROVABLE"), "reason": .text(error.reason), "authorship_inference": .null])
        }
        // Cancellation and operational errors remain thrown/unfinished. They
        // cannot be counted as completed empirical attack rejections by callers.
    }

    public static func evaluateStatement(store: HWPObjectStore, statement: HWPReference,
                                         policy: HWPVerificationPolicy, disclosures: HWPValue) throws -> (result: HWPValue, lineage: Data) {
        let context = try HWPProtocolContext(store: store, policy: policy, forceRecompute: true)
        let state = try context.object(statement), admission = try context.admit(state)
        let scope = try context.object(state.field("scope")), document = try context.get(state.field("document"))
        try V.need(document.count <= 1024 * 1024, "document-size")
        let selected = try HWPObservationBridge.selectedScope(scope, document: document), inputs = try HWPDisclosureInputs(disclosures)
        for range in selected.ranges where range.origin[0] == .text("inherited") {
            _ = try context.verify(V.reference(range.origin[1]), disclosures: disclosures)
        }
        return try HWPObservationBridge.run(evidence: inputs.evidence(admission.captures), release: admission.release,
            target: V.reference(state.field("target_capture")), scope: scope, salt: inputs.salt(statement), infos: admission.captures, store: store)
    }

    /// No signature is requested until the real native algorithm and all exact
    /// output bindings pass. The caller must persist these exact signature bytes.
    public static func issueAppraisal(store: inout HWPObjectStore, statement: HWPReference,
                                       policy: HWPVerificationPolicy, disclosures: HWPValue,
                                       evaluatorKey: Curve25519.Signing.PrivateKey) throws -> HWPReference {
        let computed = try evaluateStatement(store: store, statement: statement, policy: policy, disclosures: disclosures)
        let key = try HWPCOSE.publicKeyObject(evaluatorKey.publicKey.rawRepresentation), reference = try HWPReference(bytes: key)
        try V.need(policy.evaluators.contains(reference), "evaluator-not-authorized")
        try V.need(!policy.denied.contains(reference.sha256), "denied-key")
        let state = try store.object(statement)
        try V.need(policy.modes.contains(V.text(state.field("mode"))), "execution-mode-not-authorized")
        try V.need([.text("text/plain"), .text("text/markdown")].contains(try V.field(state, "media_type")), "document-media-type")
        _ = try V.bytes(state.field("nonce"), length: 32); _ = try V.bytes(state.field("lineage"), length: 32)
        try V.need(state.field("author") != reference.value, "author-authority-key-separation")
        for capture in try V.references(state.field("captures"), minimum: 1, maximum: 32) {
            try V.need(store.signed(capture).keyID != reference.sha256, "capture-evaluator-key-separation")
        }
        try V.need(computed.result == HWPProtocolContext.expectedComputation(state), "refuse-nonqualifying-or-mismatched-result")
        try Task.checkCancellation()
        let signed = try HWPCOSE.sign(V.object(["v": .text("hwp/0"), "type": .text("appraisal"), "statement": statement.value, "result": .text("HUMAN-WRITTEN")]), with: evaluatorKey)
        // Apply both additions atomically to the value store if its budget permits.
        var candidate = store; try candidate.add(key); let result = try candidate.add(signed); store = candidate; return result
    }

    /// Assemble on a private value copy and independently recompute the entire
    /// candidate before returning or retaining it as an issued proof. This does
    /// not publish anything. TEST-ONLY output remains NOT PROVABLE.
    public static func finalizeProof(store: inout HWPObjectStore, statement: HWPReference,
                                     appraisals: [HWPReference], authorEndorsement: HWPReference?,
                                     policy: HWPVerificationPolicy, disclosures: HWPValue) throws -> HWPProducedProof {
        var candidate = store
        let appraisalRefs = V.referenceArray(V.sortedReferences(appraisals))
        _ = try V.references(appraisalRefs, minimum: 1, maximum: 64)
        let proof = V.object(["v": .text("hwp/0"), "type": .text("proof"), "statement": statement.value,
            "appraisals": appraisalRefs, "author": authorEndorsement?.value ?? .null])
        let root = try candidate.put(proof), bundle = try candidate.pack(root: root)
        let document = try candidate.get(V.reference(candidate.object(statement).field("document")))
        let result = try verify(bundle: bundle, document: document, policyBytes: policy.bytes, policyPin: policy.sha256, disclosures: disclosures, recompute: true)
        try V.need([.text("TEST-ONLY"), .text("VALID-HWP")].contains(try V.field(result, "status")), "assembled-proof-not-valid")
        try Task.checkCancellation(); store = candidate
        return HWPProducedProof(reference: root, bundle: bundle, verification: result)
    }
}

public struct HWPProducedProof: Sendable {
    public let reference: HWPReference
    public let bundle: Data
    public let verification: HWPValue
}
