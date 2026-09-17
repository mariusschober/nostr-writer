import Foundation

struct HWPAdmittedRelease {
    let reference: HWPReference
    let value: HWPValue
    let decision: HWPValue
    let model: HWPValue
    let profiles: [Data: HWPValue]
}
struct HWPAdmittedCapture {
    let reference: HWPReference
    let end: HWPValue
    let start: HWPValue
    let profile: HWPValue
    let keyID: Data
}

/// Confined to one verifier/issuance operation. The object store and independent
/// policy cannot mutate during validation. No author-selected executable callback.
final class HWPProtocolContext {
    typealias V = HWPProtocolValues
    struct Session: Hashable { let key: Data; let session: Data }
    let store: HWPObjectStore
    let policy: HWPVerificationPolicy
    let definition: HWPInstalledDefinition
    let forceRecompute: Bool
    private var releases: [Data: HWPAdmittedRelease] = [:]
    private var signatures: [HWPReference: HWPVerifiedSignature] = [:]
    private var captureEnds: [Session: Data] = [:]
    var activeProofs: Set<Data> = []
    var completedProofs: [Data: HWPValue] = [:]
    var lineages: [Data: Data] = [:]
    var proofSteps = 0

    init(store: HWPObjectStore, policy: HWPVerificationPolicy, forceRecompute: Bool = false) throws {
        self.store = store; self.policy = policy; self.forceRecompute = forceRecompute
        let definition = try HWPInstalledDefinition(); self.definition = definition
        try V.need(policy.protocolReference == definition.reference, "protocol-policy-binding")
        try V.need(get(definition.reference) == definition.bytes, "protocol-definition-binding")
    }
    func get(_ reference: HWPReference) throws -> Data {
        try Task.checkCancellation()
        try V.need(!policy.denied.contains(reference.sha256), "denied-object")
        return try store.get(reference)
    }
    func get(_ value: HWPValue?) throws -> Data { try get(V.reference(value)) }
    func object(_ reference: HWPReference) throws -> HWPValue { try HWPCBOR.decode(get(reference)) }
    func object(_ value: HWPValue?) throws -> HWPValue { try object(V.reference(value)) }
    func signed(_ reference: HWPReference) throws -> HWPVerifiedSignature {
        _ = try get(reference) // Ref length/digest and deny checks still run on a cache hit.
        if let result = signatures[reference] { return result }
        let result = try store.signed(reference)
        try V.need(!policy.denied.contains(result.keyID), "denied-key")
        signatures[reference] = result; return result
    }
    func signed(_ value: HWPValue?) throws -> HWPVerifiedSignature { try signed(V.reference(value)) }

    func checkRelease(_ reference: HWPReference) throws -> HWPAdmittedRelease {
        let raw = try get(reference)
        if let cached = releases[reference.sha256] { return cached }
        let release = try HWPCBOR.decode(raw)
        try V.typed(release, "release", V.releaseFields)
        try V.need(policy.releases.contains(reference), "release-not-authorized")
        try V.need(release.field("algorithm") == .text("hwp-a/v0") && release.field("protocol") == definition.reference.value, "release-protocol")
        let claim = try V.field(release, "claim"), stage = try V.field(release, "stage")
        try V.need([.text("fresh-composition"), .text("wording-origin")].contains(claim), "claim-semantics")
        try V.need([.text("conformance"), .text("empirical")].contains(stage), "release-stage")
        try V.need(policy.purpose != "production" || stage == .text("empirical"), "test-release-not-production")
        let artifacts = try V.field(release, "artifacts")
        try artifacts.requireFields(V.artifactNames)
        for name in V.artifactNames {
            let ref = try V.reference(artifacts.field(name)); _ = try get(ref)
            if let fixed = definition.fixed[name] { try V.need(ref == fixed, "uninstalled-computation") }
        }
        // Each archived reference denotes exact bytes of the frozen interpretation.
        // Included source is never imported, evaluated or used as a native callback.
        for ref in definition.programFiles + definition.normativeObjects { _ = try get(ref) }
        let model = try object(artifacts.field("model"))
        try V.jsonDomain(model); let validatedModel = try HWPAlgorithmModel(model)
        try V.need(validatedModel.purpose == "validated-release", "model-purpose")
        _ = try HWPAlgorithmJSON.snapshot(model, maximumBytes: 20_000_000)
        let decision = try object(artifacts.field("decision_policy"))
        try V.fields(decision, "threshold claim_kind allowed_domains")
        _ = try V.integer(decision.field("threshold"), low: HWPAlgorithmModel.scoreFloor + 1, high: 1_000_000_000)
        try V.need(decision.field("claim_kind") == claim, "decision-claim")
        let domains = try V.texts(decision.field("allowed_domains"))
        try V.need(Set(domains).isSubset(of: validatedModel.domainNames), "decision-model-domain")
        var groups: [AlgorithmText: Set<String>] = [:]
        for domain in domains {
            let parts = domain.string.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            try V.need(parts.count == 4, "domain-format")
            try V.need(["keyboard", "touch-tap", "ime", "gesture"].contains(parts[0]) && !parts[1].isEmpty && !parts[2].isEmpty && ["birth", "retained", "layout", "global"].contains(parts[3]), "domain-format")
            groups[AlgorithmText(parts.prefix(3).joined(separator: "|")), default: []].insert(parts[3])
        }
        try V.need(groups.values.allSatisfy { $0 == ["birth", "retained", "layout", "global"] }, "incomplete-view-domain")
        let profileRefs = try V.references(release.field("capture_profiles"), minimum: 1, maximum: 32)
        var profiles: [Data: HWPValue] = [:], captureDomains: Set<AlgorithmText> = []
        let assumptions = ["complete-document-observation", "faithful-device-origin", "faithful-monotonic-order", "native-delivery-binding", "no-hidden-prediction", "precommitted-release", "single-finalization"]
        for ref in profileRefs {
            let profile = try object(ref)
            try V.typed(profile, "capture-profile", "class domains max_resolution_us assumptions evaluation")
            let kind = try V.field(profile, "class")
            try V.need([.text("fixture"), .text("evaluated")].contains(kind), "capture-profile-class")
            try V.need(policy.purpose != "production" || kind == .text("evaluated"), "fixture-capture-not-production")
            let domains = try V.texts(profile.field("domains"))
            _ = try V.integer(profile.field("max_resolution_us"), low: 1, high: 10_000)
            try V.need(profile.field("assumptions") == .array(assumptions.map(HWPValue.text)), "capture-assumption-contract")
            for domain in domains {
                let parts = domain.string.split(separator: "|", omittingEmptySubsequences: false)
                try V.need(parts.count == 3, "capture-domain-format")
                try V.need(["keyboard", "touch-tap", "ime", "gesture"].contains(String(parts[0])) && !parts[1].isEmpty && !parts[2].isEmpty, "capture-domain-format")
            }
            if kind == .text("evaluated") { _ = try get(profile.field("evaluation")) }
            else { try V.need(profile.field("evaluation") == .null, "fixture-evaluation") }
            profiles[ref.sha256] = profile; captureDomains.formUnion(domains)
        }
        try V.need(Set(groups.keys).isSubset(of: captureDomains), "release-capture-domains")
        let dossier = try object(release.field("validation"))
        try V.typed(dossier, "validation-dossier", V.dossierFields)
        let bindings: [String: HWPValue] = ["stage": stage, "claim": claim, "model": try V.field(artifacts, "model"),
            "decision_policy": try V.field(artifacts, "decision_policy"), "program": try V.field(artifacts, "program"),
            "capture_profiles": try V.field(release, "capture_profiles"), "allowed_domains": try V.field(decision, "allowed_domains")]
        for (name, value) in bindings { try V.need(dossier.field(name) == value, "validation-dossier-binding") }
        for (name, pair) in [("risk_target", [1, 1000]), ("coverage_target", [1, 2]), ("confidence", [19, 20])] {
            try V.need(dossier.field(name) == .array(pair.map { .unsigned(UInt64($0)) }), "validation-targets")
        }
        let requiredRoles = ["adaptive", "annotation", "calibration", "capture", "heldout", "reproducibility"].map(AlgorithmText.init)
        var roles: [AlgorithmText] = []
        for report in try V.array(dossier.field("reports"), reason: "validation-reports") {
            try V.fields(report, "role artifact"); let role = try V.text(report.field("role"))
            try V.need(requiredRoles.contains(role), "validation-report-role")
            _ = try get(report.field("artifact")); roles.append(role)
        }
        try V.need(roles == Set(roles).sorted(), "validation-report-order")
        if stage == .text("empirical") { try V.need(roles == requiredRoles, "empirical-validation-incomplete") }
        else { try V.need(roles.isEmpty, "conformance-not-empirical") }
        if stage == .text("conformance") { try V.need(dossier.field("candidate") == .null, "conformance-candidate-pointer") }
        else {
            let candidate = try object(dossier.field("candidate"))
            try V.typed(candidate, "release", V.releaseFields)
            try V.need(candidate.field("stage") == .text("conformance"), "empirical-candidate-stage")
            for name in ["algorithm", "claim", "artifacts", "capture_profiles", "protocol"] {
                try V.need(candidate.field(name) == release.field(name), "empirical-candidate-operation-mismatch")
            }
            let prior = try object(candidate.field("validation"))
            try V.typed(prior, "validation-dossier", V.dossierFields)
            try V.need(prior.field("stage") == .text("conformance") && prior.field("candidate") == .null && prior.field("reports") == .array([]), "empirical-candidate-dossier")
            for name in ["claim", "model", "decision_policy", "program", "capture_profiles", "allowed_domains", "risk_target", "coverage_target", "confidence"] {
                try V.need(prior.field(name) == dossier.field(name), "empirical-candidate-dossier-mismatch")
            }
        }
        let result = HWPAdmittedRelease(reference: reference, value: release, decision: decision, model: model, profiles: profiles)
        releases[reference.sha256] = result; return result
    }

    func admit(_ statement: HWPValue) throws -> (release: HWPAdmittedRelease, captures: [Data: HWPAdmittedCapture]) {
        try V.typed(statement, "statement", V.statementFields)
        let release = try checkRelease(V.reference(statement.field("release")))
        let refs = try V.references(statement.field("captures"), minimum: 1, maximum: 32), target = try V.reference(statement.field("target_capture"))
        try V.need(refs.contains(target), "target-capture-binding")
        let artifacts = try V.field(release.value, "artifacts")
        let allowedProfiles = try V.references(release.value.field("capture_profiles"), minimum: 1, maximum: 32)
        var infos: [Data: HWPAdmittedCapture] = [:], sessions: Set<Session> = []
        for ref in refs {
            let signedEnd = try signed(ref), end = signedEnd.payload, kid = signedEnd.keyID
            try V.typed(end, "capture-end", "start count root complete participation document")
            let signedStart = try signed(end.field("start")), start = signedStart.payload
            try V.typed(start, "capture-start", "session profile adapter nonce subject release parents")
            try V.need(kid == signedStart.keyID, "capture-key-changed")
            let session = try V.bytes(start.field("session"), length: 32); _ = try V.bytes(start.field("nonce"), length: 32)
            try V.need(end.field("complete") == .boolean(true), "capture-not-complete")
            _ = try V.integer(end.field("count"), low: 2, high: 1_000_000); _ = try V.bytes(end.field("root"), length: 32)
            _ = try V.reference(end.field("document"))
            let profile = try V.reference(start.field("profile"))
            try V.need(allowedProfiles.contains(profile) && start.field("adapter") == artifacts.field("evidence_adapter"), "capture-release-binding")
            guard let grant = policy.captureGrants[profile.sha256], grant.profile == profile else { throw HWPReject("capture-authority") }
            var authorized = false
            for key in grant.keys where key.sha256 == kid { _ = try get(key); authorized = true }
            try V.need(authorized, "capture-authority")
            let original = try checkRelease(V.reference(start.field("release")))
            let originalArtifacts = try V.field(original.value, "artifacts")
            try V.need(originalArtifacts.field("evidence_adapter") == artifacts.field("evidence_adapter") && V.references(original.value.field("capture_profiles"), minimum: 1, maximum: 32).contains(profile), "original-capture-release")
            if ref == target {
                try V.need(start.field("release") == statement.field("release"), "release-not-precommitted")
                try V.need(end.field("document") == statement.field("document"), "capture-final-document")
                try V.need(start.field("subject") == statement.field("author"), "target-subject-binding")
            }
            let pair = Session(key: kid, session: session)
            try V.need(sessions.insert(pair).inserted, "duplicate-session")
            if let previous = captureEnds[pair] { try V.need(previous == ref.sha256, "capture-equivocation-in-bundle") }
            captureEnds[pair] = ref.sha256
            if start.field("subject") == .null { try V.need(end.field("participation") == .null, "unexpected-participation") }
            else {
                let subject = try V.reference(start.field("subject")); _ = try HWPCOSE.parsePublicKey(get(subject))
                let consent = try signed(end.field("participation")); try V.typed(consent.payload, "participation", "start")
                try V.need(consent.payload.field("start") == end.field("start") && consent.keyID == subject.sha256 && consent.keyID != kid, "participation-binding")
            }
            let parents = try V.array(start.field("parents"), maximum: 32, reason: "capture-parents")
            var parentRefs: [HWPReference] = []
            for parent in parents {
                try V.fields(parent, "capture proof"); let capture = try V.reference(parent.field("capture")); parentRefs.append(capture)
                if parent.field("proof") != .null {
                    let proof = try object(parent.field("proof")); try V.typed(proof, "proof", "statement appraisals author")
                    let state = try object(proof.field("statement"))
                    try V.need(state.field("target_capture") == capture.value, "planned-parent-proof-binding")
                }
            }
            _ = try V.references(V.referenceArray(parentRefs), maximum: 32)
            guard let profileValue = release.profiles[profile.sha256] else { throw HWPReject("capture-release-binding") }
            infos[ref.sha256] = HWPAdmittedCapture(reference: ref, end: end, start: start, profile: profileValue, keyID: kid)
        }
        var reached: Set<Data> = []
        func visit(_ ref: HWPReference, active: Set<Data>) throws {
            try Task.checkCancellation(); try V.need(!active.contains(ref.sha256), "capture-cycle")
            guard let info = infos[ref.sha256], info.reference == ref else { throw HWPReject("capture-parent-missing") }
            if reached.contains(ref.sha256) { return }; reached.insert(ref.sha256)
            for parent in try V.array(info.start.field("parents"), maximum: 32) {
                try visit(V.reference(parent.field("capture")), active: active.union([ref.sha256]))
            }
        }
        try visit(target, active: [])
        try V.need(reached == Set(infos.keys), "unrelated-capture")
        return (release, infos)
    }
}
