import Foundation

struct HWPScopeRange {
    let start: Int
    let end: Int
    let origin: [HWPValue]
    var excluded: Bool { origin.first == .text("excluded") }
}
struct HWPSelectedScope {
    let kind: String
    let ranges: [HWPScopeRange]
    let exclusions: HWPValue
}
struct HWPReconstructedRecords {
    let bundle: HWPValue
    let corpus: AlgorithmCorpus
    let recordCaptures: [AlgorithmText: HWPReference]
    let captureRecords: [Data: AlgorithmText]
    let target: AlgorithmText
}

/// Fixed hwp-a-v0-cbor/1 adapter. Serialization preserves supplied observations;
/// it does not synthesize a native delivery or authenticate a software recorder.
enum HWPObservationBridge {
    typealias V = HWPProtocolValues
    static let adapter = "hwp-a-v0-cbor/1", output = "hwp-a-v0-output/1"

    static func recordEvents(_ record: HWPValue) throws -> [HWPValue] {
        try V.fields(record, "id language resolution_us paths observations transactions final_text")
        try V.jsonDomain(record)
        var stream: [(sequence: Int64, kind: String, value: HWPValue)] = []
        for (field, kind) in [("observations", "observation"), ("transactions", "transaction")] {
            for value in try V.array(record.field(field), maximum: 500_000) {
                stream.append((try V.integer(value.field("seq")), kind, value))
            }
        }
        stream.sort { $0.sequence < $1.sequence }
        var header: [String: HWPValue] = ["kind": .text("header"), "adapter": .text(adapter)]
        for name in ["id", "language", "resolution_us", "paths"] { header[name] = try V.field(record, name) }
        var events = [V.object(header)]
        for (index, item) in stream.enumerated() {
            try Task.checkCancellation(); try V.need(item.sequence == Int64(index), "adapter-event-order")
            events.append(V.object(["kind": .text(item.kind), "value": item.value]))
        }
        events.append(V.object(["kind": .text("end"), "final_text": try V.field(record, "final_text")]))
        return events
    }

    static func decodeRecord(_ events: [HWPValue]) throws -> HWPValue {
        try V.need((2...1_000_000).contains(events.count), "adapter-event-count")
        let header = events[0], end = events[events.count - 1]
        try V.fields(header, "kind adapter id language resolution_us paths"); try V.fields(end, "kind final_text")
        try V.need(header.field("kind") == .text("header") && header.field("adapter") == .text(adapter) && end.field("kind") == .text("end"), "adapter-markers")
        var observations: [HWPValue] = [], transactions: [HWPValue] = []
        for (sequence, wrapper) in events.dropFirst().dropLast().enumerated() {
            try Task.checkCancellation(); try V.fields(wrapper, "kind value")
            let value = try V.field(wrapper, "value"), kind = try V.field(wrapper, "kind")
            try V.need(kind == .text("observation") || kind == .text("transaction"), "adapter-wrapper")
            try V.need(V.integer(value.field("seq")) == Int64(sequence), "adapter-event-order")
            if kind == .text("observation") { observations.append(value) } else { transactions.append(value) }
        }
        var fields: [String: HWPValue] = ["observations": .array(observations), "transactions": .array(transactions), "final_text": try V.field(end, "final_text")]
        for name in ["id", "language", "resolution_us", "paths"] { fields[name] = try V.field(header, name) }
        let record = V.object(fields); try V.jsonDomain(record); return record
    }

    static func reconstruct(_ evidence: [HWPValue], infos: [Data: HWPAdmittedCapture], target: HWPReference) throws -> HWPReconstructedRecords {
        try V.need((1...32).contains(evidence.count), "adapter-record-count")
        var records: [AlgorithmText: HWPValue] = [:], byID: [AlgorithmText: HWPReference] = [:], byCapture: [Data: AlgorithmText] = [:]
        for item in evidence {
            try V.fields(item, "capture events"); let capture = try V.reference(item.field("capture"))
            guard let meta = infos[capture.sha256], meta.reference == capture else { throw HWPReject("adapter-capture-set") }
            let record = try decodeRecord(V.array(item.field("events"), minimum: 2, maximum: 1_000_000))
            let id = try V.text(record.field("id")), final = try V.text(record.field("final_text"))
            try V.need(records[id] == nil, "duplicate-record-id"); try V.need(byCapture[capture.sha256] == nil, "duplicate-capture")
            try V.need(HWPReference(bytes: final.utf8).value == meta.end.field("document"), "capture-replayed-document")
            _ = try V.integer(record.field("resolution_us"), low: 1, high: V.integer(meta.profile.field("max_resolution_us")))
            let domains = Set(try V.texts(meta.profile.field("domains")))
            guard case .map(let paths) = record.field("paths") else { throw HWPReject("capture-paths") }
            for entry in paths {
                let profile = try V.text(entry.key), path = try V.text(entry.value), language = try V.text(record.field("language"))
                let domain = AlgorithmText(profile.string + "|" + path.string + "|" + language.string)
                try V.need(domains.contains(domain), "capture-path-not-admitted")
            }
            records[id] = record; byID[id] = capture; byCapture[capture.sha256] = id
        }
        try V.need(Set(byCapture.keys) == Set(infos.keys), "adapter-capture-set")
        guard let targetID = byCapture[target.sha256], infos[target.sha256]?.reference == target else { throw HWPReject("adapter-target") }
        var dependencies: [AlgorithmText: Set<AlgorithmText>] = [:]
        for (id, record) in records {
            var deps: Set<AlgorithmText> = []
            for tx in try V.array(record.field("transactions"), maximum: 500_000) where tx.field("op") == .text("copy") {
                let from = try V.text(tx.field("from_doc")); if from != id { deps.insert(from) }
            }
            try V.need(deps.isSubset(of: Set(records.keys)), "unknown-record-dependency")
            guard let ref = byID[id], let meta = infos[ref.sha256] else { throw HWPReject("adapter-capture-set") }
            let expected = V.sortedReferences(try deps.map { try byID[$0].orReject("unknown-record-dependency") })
            let declared = try V.array(meta.start.field("parents"), maximum: 32).map { try V.reference($0.field("capture")) }
            try V.need(expected == declared, "captured-dependencies-mismatch"); dependencies[id] = deps
        }
        var needed: Set<AlgorithmText> = []
        func visit(_ id: AlgorithmText, active: Set<AlgorithmText>) throws {
            try Task.checkCancellation(); try V.need(!active.contains(id), "record-cycle")
            if needed.contains(id) { return }; needed.insert(id)
            for parent in dependencies[id] ?? [] { try visit(parent, active: active.union([id])) }
        }
        try visit(targetID, active: []); try V.need(needed == Set(records.keys), "unrelated-record")
        var order: [AlgorithmText] = [], remaining = Set(records.keys)
        while !remaining.isEmpty {
            try Task.checkCancellation()
            let ready = remaining.filter { (dependencies[$0] ?? []).isSubset(of: Set(order)) }.sorted()
            guard let id = ready.first else { throw HWPReject("record-cycle") }; order.append(id); remaining.remove(id)
        }
        let bundle = V.object(["version": .text("hwp-a/v0"), "documents": .array(try order.map { try records[$0].orReject("adapter-record-count") }), "target": targetID.value])
        return try HWPReconstructedRecords(bundle: bundle, corpus: HWPReplay.replay(bundle), recordCaptures: byID, captureRecords: byCapture, target: targetID)
    }

    static func selectedScope(_ scope: HWPValue, document: Data) throws -> HWPSelectedScope {
        try V.typed(scope, "scope", "document kind ranges")
        try V.need(HWPReference(bytes: document).value == scope.field("document"), "scope-document-binding")
        let text = try AlgorithmText(utf8: document), kind = try V.text(scope.field("kind")).string
        try V.need(["whole-document", "selected-ranges"].contains(kind), "scope-kind")
        var offset = 0, boundaries: Set<Int> = [0]
        for scalar in text.string.unicodeScalars { offset += scalar.utf8.count; boundaries.insert(offset) }
        var previous = 0, meaningful = false, ranges: [HWPScopeRange] = [], exclusions: [HWPValue] = []
        for item in try V.array(scope.field("ranges"), minimum: 1, maximum: 10_000, reason: "scope-range-count") {
            try Task.checkCancellation(); try V.fields(item, "start end origin")
            let start = Int(try V.integer(item.field("start"), high: Int64(document.count)))
            let end = Int(try V.integer(item.field("end"), low: Int64(start) + 1, high: Int64(document.count)))
            try V.need(start == previous && boundaries.contains(start) && boundaries.contains(end), "scope-partition"); previous = end
            let origin = try V.array(item.field("origin"), minimum: 1, reason: "origin-structure")
            if origin[0] == .text("excluded") {
                try V.need(origin.count == 2, "exclusion-reason")
                _ = try V.text(origin[1], minimum: 1, maximum: 1024, reason: "exclusion-reason")
                exclusions.append(V.object(["start": .integer(Int64(start)), "end": .integer(Int64(end)), "source": origin[1]]))
            } else {
                meaningful = meaningful || String(decoding: document[start..<end], as: UTF8.self).unicodeScalars.contains { !V.spaces.contains($0.value) }
                if origin[0] == .text("observed") {
                    try V.need(origin.count == 2, "observed-origin"); _ = try V.references(origin[1], minimum: 1, maximum: 32)
                } else if origin[0] == .text("inherited") {
                    try V.need(origin.count == 4, "inherited-origin"); _ = try V.reference(origin[1])
                    let a = try V.integer(origin[2]), b = try V.integer(origin[3], low: a + 1)
                    try V.need(b - a == Int64(end - start), "inherited-length")
                } else { throw HWPReject("unsupported-origin") }
            }
            if let p = ranges.last?.origin {
                let same = p == origin && origin[0] != .text("inherited")
                let contiguous = p[0] == .text("inherited") && origin[0] == .text("inherited") && p[1] == origin[1] && p[3] == origin[2]
                try V.need(!same && !contiguous, "scope-not-maximal")
            }
            ranges.append(HWPScopeRange(start: start, end: end, origin: origin))
        }
        try V.need(previous == document.count && meaningful, "scope-completeness-or-vacuity")
        try V.need((kind == "whole-document") == exclusions.isEmpty, "whole-document-scope")
        return HWPSelectedScope(kind: kind, ranges: ranges, exclusions: .array(exclusions))
    }

    static func run(evidence: [HWPValue], release: HWPAdmittedRelease, target: HWPReference, scope: HWPValue,
                    salt: Data, infos: [Data: HWPAdmittedCapture], store: HWPObjectStore) throws -> (result: HWPValue, lineage: Data) {
        let records = try reconstruct(evidence, infos: infos, target: target), corpus = records.corpus
        guard let targetDocument = corpus.documents[records.target] else { throw HWPReject("adapter-target") }
        let document = targetDocument.text.utf8, selected = try selectedScope(scope, document: document)
        var assumptions = HWPAlgorithmTrustedInputs()
        assumptions.admissibleDocuments = Set(records.recordCaptures.keys); assumptions.freshDocuments = assumptions.admissibleDocuments
        assumptions.approvedRelease = true
        assumptions.approvedThreshold = try V.integer(release.decision.field("threshold"), low: HWPAlgorithmModel.scoreFloor + 1, high: 1_000_000_000)
        assumptions.approvedClaim = try V.text(release.value.field("claim")).string
        assumptions.allowedDomains = Set(try V.texts(release.decision.field("allowed_domains")))
        assumptions.modelSnapshot = try HWPAlgorithmJSON.snapshot(release.model, maximumBytes: 20_000_000)
        for record in try V.array(records.bundle.field("documents"), maximum: 32) {
            assumptions.documentSnapshots.append(.init(document: try V.text(record.field("id")), snapshot: try HWPAlgorithmJSON.snapshot(record)))
        }
        let assessment = try HWPAlgorithmAssessment.verify(bundle: records.bundle, model: release.model,
            threshold: assumptions.approvedThreshold!, context: assumptions, excluded: selected.exclusions, claim: assumptions.approvedClaim)
        let verdict = selected.kind == "whole-document" ? "verdict" : "contribution_verdict"
        try V.need(assessment.field(verdict) == .text("HUMAN-WRITTEN"), "hwp-not-qualifying")
        for range in selected.ranges where !range.excluded {
            let indices = try HWPReplay.scalarRange(targetDocument.text, start: Int64(range.start), end: Int64(range.end))
            let atoms = try targetDocument.live[Int(indices.start)..<Int(indices.end)].map { try corpus.atoms[$0].orReject("unknown-atom") }
            try V.need(atoms.allSatisfy { !$0.roots.isEmpty }, "unsupported-selected-origin")
            if range.origin[0] == .text("observed") {
                try V.need(atoms.allSatisfy { $0.roots.allSatisfy { corpus.atoms[$0]?.home == records.target } }, "observed-origin-laundering")
                let required = atoms.reduce(into: Set<AlgorithmText>()) { $0.formUnion($1.requirements) }
                let refs = V.sortedReferences(try required.map { try records.recordCaptures[$0].orReject("adapter-capture-set") })
                try V.need(V.referenceArray(refs) == range.origin[1], "observed-dependencies-not-exact")
            } else {
                try V.need(assumptions.approvedClaim == "wording-origin", "inherited-not-fresh")
                let proofRef = try V.reference(range.origin[1]), proof = try store.object(proofRef)
                try V.typed(proof, "proof", "statement appraisals author")
                let state = try store.object(V.reference(proof.field("statement"))), parentCap = try V.reference(state.field("target_capture"))
                guard let id = records.captureRecords[parentCap.sha256], records.recordCaptures[id] == parentCap, id != records.target,
                      let parent = corpus.documents[id] else { throw HWPReject("parent-not-captured-source") }
                var planned = false
                for info in infos.values {
                    for link in try V.array(info.start.field("parents"), maximum: 32) where link.field("capture") == parentCap.value && link.field("proof") == proofRef.value { planned = true }
                }
                try V.need(planned, "unplanned-parent-proof")
                let bounds = try HWPReplay.scalarRange(parent.text, start: V.integer(range.origin[2]), end: V.integer(range.origin[3]))
                let originals = try parent.live[Int(bounds.start)..<Int(bounds.end)].map { try corpus.atoms[$0].orReject("unknown-atom") }
                try V.need(atoms.count == originals.count && zip(atoms, originals).allSatisfy { $0.char == $1.char && $0.roots == $1.roots }, "parent-is-not-actual-lineage")
            }
        }
        let recordCaptures = try V.array(records.bundle.field("documents"), maximum: 32).map { record in
            let id = try V.text(record.field("id"))
            return V.object(["id": id.value, "capture": try records.recordCaptures[id].orReject("adapter-capture-set").value])
        }
        let lineage = try HWPCBOR.encode(V.object(["adapter": .text(output), "target_record_id": records.target.value,
            "record_captures": .array(recordCaptures), "assessment": assessment]))
        let result = try V.object(["document": HWPReference(bytes: document).value, "scope": HWPReference(bytes: HWPCBOR.encode(scope)).value,
            "lineage": .bytes(HWPMerkle.lineageCommitment(salt: salt, lineage: lineage)), "release": release.reference.value,
            "captures": V.referenceArray(V.sortedReferences(infos.values.map(\.reference))), "target_capture": target.value, "result": .text("HUMAN-WRITTEN")])
        return (result, lineage)
    }
}

extension Optional {
    func orReject(_ reason: String) throws -> Wrapped { guard let value = self else { throw HWPReject(reason) }; return value }
}
