import XCTest
@testable import WriterHWP

final class AlgorithmReplayTests: XCTestCase {
    struct Oracle: Decodable {
        struct Row: Decodable {
            let name: String; let kind: String; let bundle_cbor: String
            let normalized_cbor: String?; let reason: String?
        }
        let cases: [Row]; let helpers_cbor: String
    }
    private func oracle() throws -> Oracle {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "replay-oracle", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(Oracle.self, from: Data(contentsOf: url))
    }
    private func data(_ hex: String) throws -> Data {
        let bytes = Array(hex.utf8)
        guard bytes.count % 2 == 0 else { throw HWPReject("TEST_HEX") }
        return try Data(stride(from: 0, to: bytes.count, by: 2).map { i in
            try XCTUnwrap(UInt8(String(decoding: bytes[i..<i+2], as: UTF8.self), radix: 16))
        })
    }
    private func object(_ fields: [String: HWPValue]) -> HWPValue {
        .map(fields.map { HWPEntry(.text($0.key), $0.value) })
    }
    private func texts(_ values: some Sequence<AlgorithmText>) -> HWPValue { .array(values.map(\.value)) }
    private func integers(_ values: some Sequence<Int64>) -> HWPValue { .array(values.map(HWPValue.integer)) }
    private func scalars(_ text: AlgorithmText) -> HWPValue { .array(text.scalars.map { .unsigned(UInt64($0)) }) }
    private func atom(_ a: AlgorithmAtom) -> HWPValue {
        object(["char": scalars(a.char), "roots": texts(a.roots.sorted()), "kind": .text(a.kind.rawValue),
                "home": a.home.value, "birth": .integer(a.birth), "run": a.run.value,
                "profile": .text(a.profile.rawValue), "requirements": texts(a.requirements.sorted()), "spelling": .boolean(a.spelling)])
    }
    private func effect(_ e: AlgorithmEffect) -> HWPValue {
        object(["index": .integer(e.index), "time": .integer(e.time), "op": .text(e.op.rawValue),
                "source": .text(e.source.rawValue), "profile": .text(e.profile.rawValue), "run": e.run.value,
                "pos": .integer(e.pos), "before_length": .integer(e.beforeLength), "old": scalars(e.old),
                "new": scalars(e.new), "born": texts(e.born), "touched": texts(e.touched.sorted()),
                "causes": integers(e.causes), "preceding": .integer(e.preceding), "navigation": .integer(e.navigation),
                "ages": integers(e.ages.sorted()), "barrier": .boolean(e.barrier)])
    }
    private func observation(_ o: AlgorithmObservation) -> HWPValue {
        var fields: [String: HWPValue] = ["i": .integer(o.index), "t": .integer(o.time), "seq": .integer(o.sequence),
            "kind": .text(o.kind.rawValue), "token": o.token.value, "source": .text(o.source.rawValue), "profile": .text(o.profile.rawValue)]
        if let basis = o.basis { fields["basis"] = integers(basis) }
        if let effect = o.effect { fields["effect"] = effect }
        return object(fields)
    }
    private func document(_ d: AlgorithmDocument) -> HWPValue {
        object(["did": d.did.value, "language": d.language.value, "resolution": .integer(d.resolution),
                "observations": .array(d.observations.map(observation)), "effects": .array(d.effects.map(effect)),
                "live": texts(d.live), "text": scalars(d.text), "gap": .boolean(d.gap),
                "runs": .array(d.runs.map { .array([$0.run.value, texts($0.atoms)]) }),
                "paths": .array(d.pathOrder.map { .array([.text($0.rawValue), d.paths[$0]!.value]) }),
                "durations": .array(d.durations.map { .array([.integer($0.index), .integer($0.duration)]) }),
                "unsafe_control": .boolean(d.unsafeControl)])
    }
    private func normalized(_ c: AlgorithmCorpus) throws -> HWPValue {
        var units: [AlgorithmUnit] = [], members: [AlgorithmText: [AlgorithmText]] = [:]
        for id in c.documentOrder {
            let group = try HWPReplay.makeUnits(c, document: id)
            units += group.units
            for (root, values) in group.members { members[root, default: []] += values }
        }
        let unitValues = units.map { u in object(["uid": u.uid.value, "doc": u.doc.value,
            "view": .text(u.view.rawValue), "roots": texts(u.roots), "profile": .text(u.profile.rawValue), "language": u.language.value]) }
        var related: [HWPValue] = []
        for u in units {
            let effects = try HWPReplay.related(c, unit: u)
            related.append(object(["uid": u.uid.value, "analysis_edges": .integer(c.analysisEdges), "indices": integers(effects.map(\.index))]))
        }
        let blocked = try c.documentOrder.map { id in
            HWPValue.array([id.value, texts(try HWPReplay.observedSourceMatches(c, document: id).sorted())])
        }
        return object([
            "version": .text("hwp-a-replay-normalized/1"), "documents": .array(c.documentOrder.map { document(c.documents[$0]!) }),
            "atoms": .array(c.atoms.keys.sorted().map { .array([$0.value, atom(c.atoms[$0]!)]) }),
            "external": .array(c.external.map { .array([$0.owner.value, .integer($0.transaction), $0.text.value]) }),
            "counters": object(["external_scalars": .integer(c.externalScalars), "effect_edges": .integer(c.effectEdges),
                                "analysis_edges": .integer(c.analysisEdges), "stored_ids": .integer(c.storedIDs)]),
            "units": .array(unitValues), "members": .array(members.keys.sorted().map { .array([$0.value, texts(members[$0]!)]) }),
            "related": .array(related), "observed_source_matches": .array(blocked)
        ])
    }
    func testCompleteReplayStatesAndUnitsMatchFrozenPython() throws {
        let rows = try oracle().cases.filter { $0.kind == "ok" }
        XCTAssertEqual(rows.count, 19)
        for row in rows {
            let c = try HWPReplay.replay(HWPCBOR.decode(data(row.bundle_cbor)))
            let actual = try HWPCBOR.encode(normalized(c))
            let expected = try data(XCTUnwrap(row.normalized_cbor))
            XCTAssertEqual(actual, expected, row.name)
        }
    }
    func testMalformedHistoriesMatchFrozenFirstRejection() throws {
        let rows = try oracle().cases.filter { $0.kind == "reject" }
        XCTAssertGreaterThan(rows.count, 30)
        for row in rows {
            let bundle = try HWPCBOR.decode(data(row.bundle_cbor))
            XCTAssertThrowsError(try HWPReplay.replay(bundle), row.name) { error in
                XCTAssertEqual((error as? HWPReject)?.reason, row.reason, row.name)
            }
        }
    }
    private func scalarText(_ value: HWPValue?) throws -> AlgorithmText {
        let values = try HWPAlgorithmValues.array(value)
        return try AlgorithmText(scalars: values.map { UInt32(try HWPAlgorithmValues.integer($0, high: 0x10ffff)) })
    }
    func testScalarRangesWindowsAndSpellingDistancesMatchFrozenPython() throws {
        let helpers = try HWPCBOR.decode(data(oracle().helpers_cbor))
        for row in try HWPAlgorithmValues.array(helpers.field("scalar_ranges")) {
            let text = try scalarText(row.field("text")), start = try HWPAlgorithmValues.integer(row.field("start")), end = try HWPAlgorithmValues.integer(row.field("end"))
            if let reason = row.field("reject") {
                XCTAssertThrowsError(try HWPReplay.scalarRange(text, start: start, end: end)) { error in
                    XCTAssertEqual(.text((error as? HWPReject)?.reason ?? "unexpected"), reason)
                }
            } else {
                let range = try HWPReplay.scalarRange(text, start: start, end: end)
                XCTAssertEqual(integers([range.start, range.end]), row.field("result"))
            }
        }
        for row in try HWPAlgorithmValues.array(helpers.field("windows")) {
            let items = try HWPAlgorithmValues.array(row.field("items")), width = try HWPAlgorithmValues.integer(row.field("width")), stride = try HWPAlgorithmValues.integer(row.field("stride"))
            XCTAssertEqual(.array(try HWPReplay.windows(items, width: width, stride: stride).map(HWPValue.array)), row.field("result"))
        }
        for row in try HWPAlgorithmValues.array(helpers.field("edit_distances")) {
            let a = try scalarText(row.field("a")), b = try scalarText(row.field("b"))
            if let reason = row.field("reject") {
                XCTAssertThrowsError(try HWPReplay.editDistance(a, b)) { error in
                    XCTAssertEqual(.text((error as? HWPReject)?.reason ?? "unexpected"), reason)
                }
            } else { XCTAssertEqual(.integer(try HWPReplay.editDistance(a, b)), row.field("result")) }
        }
        XCTAssertThrowsError(try HWPReplay.windows([1], width: 0, stride: 1))
        XCTAssertThrowsError(try HWPReplay.windows([1,2], width: 1, stride: 0))
        XCTAssertEqual(try HWPReplay.windows([1,2,3], width: 1, stride: Int64.max), [[1], [3]])
    }
    func testRawClockOrderingDoesNotOverflowOrReverseLargeValues() {
        let large = HWPReplay.PyInt.large(UInt64(Int64.max) + 1), small = HWPReplay.PyInt.small(42)
        XCTAssertLessThan(small, large)
        XCTAssertFalse(large < small)
        XCTAssertFalse(large < large)
    }
}
