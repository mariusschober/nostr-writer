import XCTest
@testable import WriterHWP

final class AlgorithmFeatureTests: XCTestCase {
    struct Oracle: Decodable {
        struct Unit: Decodable { let id: String; let adequate: Bool; let values: [Int64] }
        struct Case: Decodable { let id: String; let bundle: String; let units: [Unit] }
        let cases: [Case]
    }
    private func data(_ hex: String) throws -> Data {
        let bytes = Array(hex.utf8)
        guard bytes.count % 2 == 0 else { throw HWPReject("TEST_HEX") }
        return try Data(stride(from: 0, to: bytes.count, by: 2).map { i in
            try XCTUnwrap(UInt8(String(decoding: bytes[i..<i+2], as: UTF8.self), radix: 16))
        })
    }
    func testAllFeaturesAndAdequacyMatchFrozenPythonAcrossProfilesAndEdits() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "feature-oracle", withExtension: "json", subdirectory: "Fixtures"))
        let oracle = try JSONDecoder().decode(Oracle.self, from: Data(contentsOf: url))
        XCTAssertEqual(oracle.cases.count, 9)
        var vectorCount = 0
        for row in oracle.cases {
            let corpus = try HWPReplay.replay(HWPCBOR.decode(data(row.bundle)))
            var units: [AlgorithmUnit] = []
            for document in corpus.documentOrder { units += try HWPReplay.makeUnits(corpus, document: document).units }
            XCTAssertEqual(units.map(\.uid), row.units.map { AlgorithmText($0.id) }, row.id)
            guard units.count == row.units.count else { continue }
            for (unit, expected) in zip(units, row.units) {
                XCTAssertEqual(try HWPAlgorithmFeatures.adequate(corpus, unit: unit), expected.adequate, row.id + ":" + expected.id)
                let actual = try HWPAlgorithmFeatures.extract(corpus, unit: unit)
                XCTAssertEqual(actual.values.count, 179)
                for (index, pair) in zip(actual.values, expected.values).enumerated() where pair.0 != pair.1 {
                    XCTFail("\(row.id):\(expected.id):\(HWPFeatureSchema.names[index]) expected \(pair.1), got \(pair.0)")
                }
                vectorCount += 1
            }
        }
        XCTAssertGreaterThan(vectorCount, 200)
    }
}
