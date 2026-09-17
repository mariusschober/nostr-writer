import Foundation
import BigInt

/// All 179 fixed-point features from the frozen joined algorithm. Text is only
/// used to contextualize observed edits; this computes no prose/AI classifier.
public enum HWPAlgorithmFeatures {
    private static let gapEdges: [Int64] = [50_000, 150_000, 400_000, 1_000_000, 3_000_000, 10_000_000, 30_000_000]
    private static let lengthEdges: [Int64] = [0, 1, 4, 16, 64]
    private static let kinds = ["insert", "delete", "replace", "move", "undo", "redo"]
    private static let q: Int64 = 10_000
    private static func ratio(_ n: Int, _ d: Int) throws -> Int64 { try HWPFixedPoint.ratio(BigInt(n), BigInt(d)) }
    private static func scale(_ n: Int64, _ cap: Int64) throws -> Int64 { try HWPFixedPoint.scale(BigInt(n), cap: cap) }
    private static func bucket(_ n: Int64, _ edges: [Int64]) -> Int { edges.firstIndex { n <= $0 } ?? edges.count }
    private static func kind(_ e: AlgorithmEffect) -> String {
        e.op != .splice ? e.op.rawValue : !e.old.isEmpty && !e.new.isEmpty ? "replace" : !e.old.isEmpty ? "delete" : "insert"
    }
    private static func stats(_ f: inout [String: Int64], _ prefix: String, _ values: [Int64], _ cap: Int64) throws {
        f[prefix + ".present"] = values.isEmpty ? 0 : q
        for p in [10, 50, 90] { f[prefix + ".p\(p)"] = try scale(HWPFixedPoint.quantile(values, numerator: p), cap) }
        let sum = values.reduce(BigInt(0)) { $0 + BigInt($1) }
        f[prefix + ".mean"] = try values.isEmpty ? 0 : HWPFixedPoint.scale(HWPFixedPoint.floorDivide(sum, BigInt(values.count)), cap: cap)
        f[prefix + ".spread"] = try scale(HWPFixedPoint.quantile(values, numerator: 90) - HWPFixedPoint.quantile(values, numerator: 10), cap)
    }
    private static func histogram(_ f: inout [String: Int64], _ prefix: String, _ values: [Int64], _ edges: [Int64]) throws {
        var counts = [Int](repeating: 0, count: edges.count + 1)
        for value in values { counts[bucket(value, edges)] += 1 }
        for index in counts.indices { f[prefix + ".\(index)"] = try ratio(counts[index], values.count) }
    }

    public static func extract(_ corpus: AlgorithmCorpus, unit: AlgorithmUnit) throws -> HWPFeatureVector {
        guard let document = corpus.documents[unit.doc] else { throw HWPReject("TARGET") }
        let effects = try HWPReplay.related(corpus, unit: unit), roots = Set(unit.roots)
        let n = effects.count
        var f: [String: Int64] = [:]
        for view in ["birth", "retained", "layout", "global"] { f["view." + view] = unit.view.rawValue == view ? q : 0 }
        f["roots"] = try scale(Int64(roots.count), 256)
        f["events"] = try scale(Int64(n), 1024)
        let productions = effects.filter { !roots.isDisjoint(with: $0.born) }
        f["production.events"] = try scale(Int64(productions.count), 256)
        f["production.per_root"] = try ratio(productions.count, roots.count)
        f["resolution"] = try scale(document.resolution, 10_000)
        f["syntactic.barrier_fraction"] = try ratio(effects.filter(\.barrier).count, n)
        for op in kinds { f["op." + op] = try ratio(effects.filter { kind($0) == op }.count, n) }
        for source in ["direct", "spelling", "paste", "generated", "unknown", "control"] {
            f["source." + source] = try ratio(effects.filter { $0.source.rawValue == source }.count, n)
        }
        try histogram(&f, "insert.length", effects.map { Int64($0.new.count) }, lengthEdges)
        try histogram(&f, "delete.length", effects.map { Int64($0.old.count) }, lengthEdges)
        let splices = effects.filter { $0.op == .splice }
        let inserted = splices.reduce(BigInt(0)) { $0 + BigInt($1.new.count) }
        let deleted = splices.reduce(BigInt(0)) { $0 + BigInt($1.old.count) }
        f["deleted.per_inserted"] = try HWPFixedPoint.ratio(deleted, inserted)
        f["surviving.evidence_fraction"] = try HWPFixedPoint.ratio(BigInt(roots.count), productions.reduce(BigInt(0)) { $0 + BigInt($1.born.count) })
        f["at_document_front"] = try ratio(effects.filter { $0.pos * 4 < max(1, $0.beforeLength) }.count, n)
        f["at_document_tail"] = try ratio(effects.filter { $0.pos >= $0.beforeLength }.count, n)
        try stats(&f, "navigation", effects.map(\.navigation), 4096)
        try stats(&f, "revision.age", effects.flatMap(\.ages).filter { $0 > 0 }, 4096)
        var touchedCounts: [AlgorithmText: Int] = [:]
        for e in effects {
            try Task.checkCancellation()
            for r in e.touched where roots.contains(r) { touchedCounts[r, default: 0] += 1 }
        }
        f["revisited.roots"] = try ratio(touchedCounts.values.filter { $0 > 1 }.count, roots.count)
        f["revisited.repeat_fraction"] = try ratio(touchedCounts.values.reduce(0) { $0 + max(0, $1 - 1) }, touchedCounts.values.reduce(0, +))

        var gaps: [Int64] = [], contexts: [Int64] = [], pairs: [(AlgorithmEffect, AlgorithmEffect)] = []
        var uncertain = 0, excluded = 0
        for (a, b) in zip(effects, effects.dropFirst()) {
            try Task.checkCancellation()
            if b.index != a.index + 1 || a.run != b.run || b.barrier { excluded += 1; continue }
            let gap = b.time - a.time, lo = max(0, gap - 2 * document.resolution), hi = gap + 2 * document.resolution
            if hi > gapEdges[gapEdges.count - 1] || bucket(lo, gapEdges) != bucket(hi, gapEdges) { uncertain += 1; continue }
            gaps.append(gap); contexts.append(b.preceding); pairs.append((a, b))
        }
        f["gap.censored"] = try ratio(uncertain + excluded, max(0, n - 1))
        try stats(&f, "gap", gaps, gapEdges[gapEdges.count - 1])
        try histogram(&f, "gap.bin", gaps, gapEdges)
        for context in 0..<4 {
            let local = zip(gaps, contexts).filter { $0.1 == context }.map(\.0)
            f["context.\(context).present"] = local.isEmpty ? 0 : q
            f["context.\(context).pause"] = try scale(HWPFixedPoint.quantile(local, numerator: 50), 3_000_000)
            for b in 0...gapEdges.count {
                f["context.\(context).gap.\(b)"] = try ratio(zip(gaps, contexts).filter { $0.1 == context && bucket($0.0, gapEdges) == b }.count, gaps.count)
            }
        }
        f["gap.identical_adjacent"] = try ratio(zip(gaps, gaps.dropFirst()).filter { $0 == $1 }.count, max(0, gaps.count - 1))
        var gapCounts: [Int64: Int] = [:]
        for g in gaps { gapCounts[g, default: 0] += 1 }
        f["gap.concentration"] = try HWPFixedPoint.ratio(gapCounts.values.reduce(BigInt(0)) { $0 + BigInt($1) * BigInt($1) }, BigInt(gaps.count) * BigInt(gaps.count))
        for a in kinds {
            for b in kinds { f["transition.\(a).\(b)"] = try ratio(pairs.filter { kind($0.0) == a && kind($0.1) == b }.count, pairs.count) }
        }
        var durations: [Int64: Int64] = [:]
        for duration in document.durations { durations[duration.index] = duration.duration }
        let causes = Set(productions.flatMap(\.causes))
        var motor = causes
        for cause in causes {
            guard let index = Int(exactly: cause), document.observations.indices.contains(index) else { throw HWPReject("CAUSES") }
            motor.formUnion(document.observations[index].basis ?? [])
        }
        let dwells = motor.compactMap { durations[$0] }
        try stats(&f, "motor.dwell", dwells, 1_000_000)
        f["motor.coverage"] = try ratio(dwells.count, motor.count)
        f["motor.actions_per_production"] = try scale(Int64(motor.count / max(1, productions.count)), 32)
        let movements = zip(effects, effects.dropFirst()).map { abs($1.pos - $0.pos - Int64($0.new.count)) }
        try stats(&f, "edit.distance", movements, 4096)
        f["edit.backward"] = try ratio(zip(effects, effects.dropFirst()).filter { $1.pos < $0.pos }.count, max(0, n - 1))
        f["edit.remote"] = try ratio(movements.filter { $0 > 32 }.count, movements.count)

        var cancel = 0, propagation = 0, opportunities = 0
        var coupling: [Int64] = []
        for (i, e) in effects.enumerated() {
            try Task.checkCancellation()
            if e.op == .splice && !e.new.isEmpty {
                if effects[max(0, i - 8)..<i].contains(where: { $0.old == e.new && !$0.old.isEmpty && e.time - $0.time <= 5_000_000 }) { cancel += 1 }
            }
            if e.op == .splice && !e.old.isEmpty && !e.new.isEmpty && e.old != e.new && max(e.old.count, e.new.count) <= 64 {
                opportunities += 1
                let following = effects[(i + 1)..<min(n, i + 65)]
                if following.contains(where: { $0.old == e.old && $0.new == e.new && abs($0.pos - e.pos) > 32 }) { propagation += 1 }
                let first = shingles(e.new.scalars)
                let later = Array(following.prefix(8).flatMap { $0.new.scalars }.prefix(128))
                let second = shingles(later)
                if !first.isEmpty && !second.isEmpty { coupling.append(try ratio(first.intersection(second).count, first.union(second).count)) }
            }
        }
        f["revision.cancel_fraction"] = try ratio(cancel, n)
        f["revision.propagation_present"] = opportunities == 0 ? 0 : q
        f["revision.propagation_fraction"] = try ratio(propagation, opportunities)
        try stats(&f, "revision.lexical_coupling", coupling, q)
        var bursts: [Int64] = [], current: Int64 = 0
        for (i, e) in effects.enumerated() {
            if i > 0 && (e.index != effects[i - 1].index + 1 || e.run != effects[i - 1].run || e.time - effects[i - 1].time > 1_000_000) {
                if current > 0 { bursts.append(current) }; current = 0
            }
            current += Int64(roots.intersection(e.born).count)
        }
        if current > 0 { bursts.append(current) }
        try stats(&f, "burst.roots", bursts, 256)
        f["pause.next_insert_correlation"] = try HWPFixedPoint.correlation(gaps, pairs.map { Int64($0.1.new.count) })
        var quarterGaps: [Int64] = [], quarterRevisions: [Int64] = []
        for k in 0..<4 {
            let part = effects[(n * k / 4)..<(n * (k + 1) / 4)]
            let pg = zip(part, part.dropFirst()).filter { $1.index == $0.index + 1 && $0.run == $1.run && !$1.barrier && $1.time - $0.time <= 30_000_000 }.map { $1.time - $0.time }
            if !pg.isEmpty { quarterGaps.append(try scale(HWPFixedPoint.quantile(pg, numerator: 50), 3_000_000)) }
            if !part.isEmpty { quarterRevisions.append(try ratio(part.filter { ["delete", "replace", "move", "undo", "redo"].contains(kind($0)) }.count, part.count)) }
        }
        f["shift.gap"] = (quarterGaps.max() ?? 0) - (quarterGaps.min() ?? 0)
        f["shift.revision"] = (quarterRevisions.max() ?? 0) - (quarterRevisions.min() ?? 0)
        guard Set(f.keys) == Set(HWPFeatureSchema.names) else { throw HWPReject("FEATURE_SCHEMA") }
        return try HWPFeatureVector(names: HWPFeatureSchema.names, values: HWPFeatureSchema.names.map { f[$0]! })
    }

    private static func shingles(_ scalars: [UInt32]) -> Set<[UInt32]> {
        guard scalars.count >= 3 else { return [] }
        return Set((0..<(scalars.count - 2)).map { Array(scalars[$0..<$0 + 3]) })
    }

    /// Connected motor episodes, including held-key repeats, count once for the
    /// minimum independent local evidence; arbitrary event count is insufficient.
    public static func adequate(_ corpus: AlgorithmCorpus, unit: AlgorithmUnit) throws -> Bool {
        let roots = Set(unit.roots)
        if roots.count < 64 { return false }
        guard let document = corpus.documents[unit.doc] else { throw HWPReject("TARGET") }
        let effects = try HWPReplay.related(corpus, unit: unit)
        struct Token: Hashable { let kind: String; let token: AlgorithmText }
        var parents: [Int] = [], owners: [Token: Int] = [:]
        func find(_ index: Int) -> Int {
            var i = index
            while parents[i] != i { parents[i] = parents[parents[i]]; i = parents[i] }
            return i
        }
        for e in effects where !roots.isDisjoint(with: e.born) {
            try Task.checkCancellation()
            let current = parents.count; parents.append(current)
            for cause in e.causes {
                guard let index = Int(exactly: cause), document.observations.indices.contains(index) else { throw HWPReject("CAUSES") }
                let observation = document.observations[index]
                let token = Token(kind: observation.kind == .repeatKey ? "press" : observation.kind.rawValue, token: observation.token)
                if let owner = owners[token] {
                    let currentRoot = find(current), ownerRoot = find(owner)
                    parents[currentRoot] = ownerRoot
                }
                else { owners[token] = current }
            }
        }
        let minimum = (unit.profile == .keyboard || unit.profile == .touchTap) ? 16 : 4
        return Set(parents.indices.map { find($0) }).count >= minimum
    }
}
