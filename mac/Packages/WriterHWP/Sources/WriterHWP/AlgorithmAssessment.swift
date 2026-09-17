import Foundation

/// Externally supplied algorithm assumptions. Only a future authenticated protocol
/// bridge can establish these for production; telemetry never imports its own trust.
/// An algorithm positive alone is not a valid HWP certificate or UI badge.
public struct HWPAlgorithmTrustedInputs: Sendable {
    public struct DocumentPin: Sendable {
        public let document: AlgorithmText
        public let snapshot: Data
        public init(document: AlgorithmText, snapshot: Data) { self.document = document; self.snapshot = snapshot }
    }
    public var admissibleDocuments: Set<AlgorithmText> = []
    public var approvedRelease = false
    public var approvedThreshold: Int64?
    public var allowedDomains: Set<AlgorithmText> = []
    public var documentSnapshots: [DocumentPin] = []
    public var freshDocuments: Set<AlgorithmText> = []
    public var modelSnapshot: Data?
    public var approvedClaim = "fresh-composition"
    public init() {}
}

public enum HWPAlgorithmAssessment {
    public static let human = "HUMAN-WRITTEN", notProvable = "NOT PROVABLE"
    private static let floor = HWPAlgorithmModel.scoreFloor
    private static let spaces: Set<UInt32> = [9,10,11,12,13,32,0x85,0xa0,0x1680,0x2000,0x2001,0x2002,0x2003,0x2004,0x2005,0x2006,0x2007,0x2008,0x2009,0x200a,0x2028,0x2029,0x202f,0x205f,0x3000]
    private struct UnitReport { let score: Int64; let reason: String? }
    private struct Scored {
        let target: AlgorithmText
        let text: AlgorithmText
        let offsets: [Int]
        let values: [Int64]
        let reasons: [String?]
        let originTypes: [String]
        let originDocuments: [[AlgorithmText]]
        let modelSnapshot: Data
        let modelPurpose: String
        let claim: String
    }
    private static func negative(_ reason: String) -> HWPValue {
        .map([HWPEntry(.text("verdict"), .text(notProvable)), HWPEntry(.text("contribution_verdict"), .text(notProvable)), HWPEntry(.text("ranges"), .array([])), HWPEntry(.text("reason"), .text(reason))])
    }
    private static func optional(_ string: String?) -> HWPValue { string.map { .text($0) } ?? .null }

    /// Exact frozen algorithm assessment. No proof is issued, signed, or published.
    /// Cancellation throws and must remain unfinished in the UI, not a scientific negative.
    public static func verify(bundle: HWPValue, model: HWPValue? = nil, threshold: Int64 = 0,
                              context: HWPAlgorithmTrustedInputs = .init(), excluded: HWPValue? = nil,
                              claim: String = "fresh-composition") throws -> HWPValue {
        do {
            let scored = try score(bundle: bundle, model: model, context: context, claim: claim)
            let enabled = context.approvedRelease && context.approvedThreshold == threshold && context.approvedClaim == claim
                && context.modelSnapshot == scored.modelSnapshot && scored.modelPurpose == "validated-release"
            return try decide(scored, threshold: threshold, enabled: enabled, excluded: excluded, claim: claim)
        } catch let error as HWPReject { return negative(error.reason) }
    }

    private static func score(bundle original: HWPValue, model originalModel: HWPValue?, context: HWPAlgorithmTrustedInputs, claim: String) throws -> Scored {
        try HWPAlgorithmValues.need(["fresh-composition", "wording-origin"].contains(claim), "CLAIM_KIND")
        _ = try HWPAlgorithmJSON.snapshot(original)
        let bundle = try HWPAlgorithmJSON.normalized(original)
        var rawModel: HWPValue?
        if let originalModel {
            do { _ = try HWPAlgorithmJSON.snapshot(originalModel, maximumBytes: 20_000_000) }
            catch let error as HWPReject where error.reason == "INPUT_SIZE_LIMIT" { throw HWPReject("MODEL_SIZE_LIMIT") }
            rawModel = try HWPAlgorithmJSON.normalized(originalModel)
        }
        let corpus = try HWPReplay.replay(bundle)
        let targetID = try HWPAlgorithmValues.text(bundle.field("target"))
        guard let target = corpus.documents[targetID] else { throw HWPReject("TARGET") }
        guard let rawModel else { throw HWPReject("MODEL_UNAVAILABLE") }
        let model = try HWPAlgorithmModel(rawModel)
        var admitted: Set<AlgorithmText> = []
        for record in try HWPAlgorithmValues.array(bundle.field("documents")) {
            let id = try HWPAlgorithmValues.text(record.field("id")), snapshot = try HWPAlgorithmJSON.snapshot(record)
            if context.admissibleDocuments.contains(id) && context.freshDocuments.contains(id)
                && context.documentSnapshots.contains(where: { $0.document == id && $0.snapshot == snapshot }) { admitted.insert(id) }
        }
        var reports: [AlgorithmText: UnitReport] = [:], units: [AlgorithmText: AlgorithmUnit] = [:]
        var members: [AlgorithmText: [AlgorithmText]] = [:]
        for documentID in corpus.documentOrder {
            guard let document = corpus.documents[documentID] else { throw HWPReject("TARGET") }
            let group = try HWPReplay.makeUnits(corpus, document: documentID)
            // Python dict.update replaces the previous membership list for a repeated key.
            for (root, list) in group.members { members[root] = list }
            for unit in group.units {
                try Task.checkCancellation()
                units[unit.uid] = unit
                guard let path = document.paths[unit.profile] else { throw HWPReject("UNDECLARED_INPUT_PATH") }
                let domain = AlgorithmText(unit.profile.rawValue + "|" + path.string + "|" + unit.language.string + "|" + unit.view.rawValue)
                var value = floor, reason: String?
                if !admitted.contains(documentID) || document.gap || document.unsafeControl { reason = "CAPTURE_NOT_ADMISSIBLE" }
                else if !context.allowedDomains.contains(domain) || !model.domainNames.contains(domain) { reason = "UNSUPPORTED_DOMAIN" }
                else if try !HWPAlgorithmFeatures.adequate(corpus, unit: unit) { reason = "INSUFFICIENT_LOCAL_EVIDENCE" }
                else {
                    let evaluation = try model.evaluate(HWPAlgorithmFeatures.extract(corpus, unit: unit), domain: domain)
                    if evaluation.supported { value = evaluation.score }
                    else { reason = "OUTSIDE_SUPPORTED_PROCESS" }
                }
                reports[unit.uid] = UnitReport(score: value, reason: reason)
            }
        }
        var rootScores: [AlgorithmText: Int64] = [:], rootReasons: [AlgorithmText: String] = [:]
        for (root, atom) in corpus.atoms where atom.kind == .candidate && atom.roots == Set([root]) {
            try Task.checkCancellation()
            let ids = members[root] ?? [], views = Set(ids.compactMap { units[$0]?.view })
            if !Set([HWPUnitView.birth, .retained, .layout, .global]).isSubset(of: views) {
                rootScores[root] = floor; rootReasons[root] = "NO_COMPLETE_ORIGIN_NEIGHBOURHOOD"
            } else {
                let ordered = ids.sorted { left, right in
                    let a = reports[left]?.score ?? floor, b = reports[right]?.score ?? floor
                    return a == b ? left < right : a < b
                }
                guard let worst = ordered.first, let report = reports[worst] else { throw HWPReject("MALFORMED_INPUT") }
                rootScores[root] = report.score; rootReasons[root] = report.reason
            }
        }
        var blockedRoots: Set<AlgorithmText> = [], blockedOccurrences: [AlgorithmText: Set<AlgorithmText>] = [:]
        for id in corpus.documentOrder {
            let blocked = try HWPReplay.observedSourceMatches(corpus, document: id); blockedOccurrences[id] = blocked
            for aid in blocked { if let atom = corpus.atoms[aid] { blockedRoots.formUnion(atom.roots) } }
        }
        var values: [Int64] = [], reasons: [String?] = [], originTypes: [String] = [], originDocuments: [[AlgorithmText]] = []
        for aid in target.live {
            try Task.checkCancellation()
            guard let atom = corpus.atoms[aid] else { throw HWPReject("MALFORMED_INPUT") }
            var value = floor, reason: String?
            if !atom.requirements.isSubset(of: admitted) || atom.requirements.contains(where: { corpus.documents[$0]?.gap != false || corpus.documents[$0]?.unsafeControl != false }) { reason = "CAPTURE_NOT_ADMISSIBLE" }
            else if atom.roots.isEmpty { reason = "EXTERNAL_OR_UNKNOWN_ORIGIN" }
            else if (blockedOccurrences[targetID] ?? []).contains(aid) || !atom.roots.isDisjoint(with: blockedRoots) { reason = "OBSERVED_SOURCE_REUSE" }
            else {
                value = atom.roots.map { rootScores[$0] ?? floor }.min() ?? floor
                if let worst = atom.roots.sorted().first(where: { (rootScores[$0] ?? floor) == value }) { reason = rootReasons[worst] }
            }
            if claim == "fresh-composition" && (atom.roots != Set([aid]) || atom.home != targetID) { value = floor; reason = "NOT_FRESH_COMPOSITION" }
            values.append(value); reasons.append(reason)
            originTypes.append(atom.roots.isEmpty ? "external" : atom.spelling ? "spelling" : atom.roots == Set([aid]) ? "direct" : "inherited")
            originDocuments.append(Set(atom.roots.compactMap { corpus.atoms[$0]?.home }).sorted())
        }
        var offsets = [0]
        for scalar in target.text.string.unicodeScalars { offsets.append(offsets[offsets.count - 1] + scalar.utf8.count) }
        return Scored(target: targetID, text: target.text, offsets: offsets, values: values, reasons: reasons,
                      originTypes: originTypes, originDocuments: originDocuments,
                      modelSnapshot: try HWPAlgorithmJSON.snapshot(rawModel), modelPurpose: model.purpose, claim: claim)
    }

    private struct RangeMetadata: Equatable {
        let verdict: String; let excluded: Bool; let exclusion: Int?; let reason: String?; let origin: String; let documents: [AlgorithmText]
    }
    private static func decide(_ scored: Scored, threshold: Int64, enabled: Bool, excluded: HWPValue?, claim: String) throws -> HWPValue {
        try HWPAlgorithmValues.need((floor + 1...1_000_000_000).contains(threshold), "INTEGER_DOMAIN")
        try HWPAlgorithmValues.need(["fresh-composition", "wording-origin"].contains(claim) && claim == scored.claim, "CLAIM_KIND")
        let scalars = scored.text.scalars, count = scalars.count
        var values = scored.values
        if claim == "fresh-composition" {
            for i in 0..<count where scored.originTypes[i] != "direct" || scored.originDocuments[i] != [scored.target] { values[i] = floor }
        }
        var mask = [Bool](repeating: false, count: count), exclusionIDs = [Int?](repeating: nil, count: count), previous = 0
        var exclusionValues: [HWPValue] = []
        if let excluded, excluded != .null { exclusionValues = try HWPAlgorithmValues.array(excluded, reason: "EXCLUSION_LIST") }
        let positions = Dictionary(uniqueKeysWithValues: scored.offsets.enumerated().map { ($0.element, $0.offset) })
        for (index, value) in exclusionValues.enumerated() {
            do { try HWPAlgorithmValues.shape(value, required: ["start", "end", "source"]) }
            catch is HWPReject { throw HWPReject("EXCLUSION_FIELDS") }
            let start = try HWPAlgorithmValues.integer(value.field("start"), high: Int64(scored.text.utf8.count))
            let end = try HWPAlgorithmValues.integer(value.field("end"), low: start, high: Int64(scored.text.utf8.count))
            guard let a = positions[Int(start)], let b = positions[Int(end)] else { throw HWPReject("SPLIT_UNICODE_SCALAR") }
            guard case .text(let sourceBytes) = value.field("source") else { throw HWPReject("EXCLUSION_PARTITION") }
            let source = try AlgorithmText(utf8: sourceBytes)
            try HWPAlgorithmValues.need(a < b && a >= previous && !source.isEmpty, "EXCLUSION_PARTITION")
            for i in a..<b { mask[i] = true; exclusionIDs[i] = index }; previous = b
        }
        let passed = values.map { enabled && $0 >= threshold }
        let meaningful = scalars.contains { !spaces.contains($0) }
        let whole = !values.isEmpty && passed.allSatisfy { $0 } && !mask.contains(true) && meaningful
        let contribution = (0..<count).contains { !mask[$0] && !spaces.contains(scalars[$0]) } && (0..<count).allSatisfy { mask[$0] || passed[$0] }
        var ranges: [(start: Int, end: Int, metadata: RangeMetadata)] = []
        for i in 0..<count {
            try Task.checkCancellation()
            let freshBlocked = claim == "fresh-composition" && (scored.originTypes[i] != "direct" || scored.originDocuments[i] != [scored.target])
            let initialReason = freshBlocked ? "NOT_FRESH_COMPOSITION" : scored.reasons[i]
            let reason = initialReason ?? (!enabled ? "RELEASE_NOT_APPROVED" : !passed[i] ? "BELOW_THRESHOLD" : nil)
            let metadata = RangeMetadata(verdict: passed[i] ? human : notProvable, excluded: mask[i], exclusion: exclusionIDs[i], reason: reason, origin: scored.originTypes[i], documents: scored.originDocuments[i])
            if let last = ranges.last, last.metadata == metadata { ranges[ranges.count - 1].end = scored.offsets[i + 1] }
            else { ranges.append((scored.offsets[i], scored.offsets[i + 1], metadata)) }
        }
        return .map([
            HWPEntry(.text("verdict"), .text(whole ? human : notProvable)),
            HWPEntry(.text("contribution_verdict"), .text(contribution ? human : notProvable)),
            HWPEntry(.text("ranges"), .array(ranges.map { range in .map([
                HWPEntry(.text("start"), .unsigned(UInt64(range.start))), HWPEntry(.text("end"), .unsigned(UInt64(range.end))),
                HWPEntry(.text("verdict"), .text(range.metadata.verdict)), HWPEntry(.text("excluded"), .boolean(range.metadata.excluded)),
                HWPEntry(.text("exclusion"), range.metadata.exclusion.map { .unsigned(UInt64($0)) } ?? .null),
                HWPEntry(.text("reason"), optional(range.metadata.reason)), HWPEntry(.text("origin"), .text(range.metadata.origin)),
                HWPEntry(.text("origin_documents"), .array(range.metadata.documents.map(\.value)))
            ]) })),
            HWPEntry(.text("reason"), .null),
            HWPEntry(.text("candidate_document_pass"), .boolean(!values.isEmpty && (values.min() ?? floor) >= threshold && meaningful)),
            HWPEntry(.text("certification_enabled"), .boolean(enabled)), HWPEntry(.text("claim_kind"), .text(claim)),
            HWPEntry(.text("algorithm_version"), .text("hwp-a/v0"))
        ])
    }
}
