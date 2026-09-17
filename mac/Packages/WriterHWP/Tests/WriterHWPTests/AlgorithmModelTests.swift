import XCTest
import BigInt
@testable import WriterHWP

final class AlgorithmModelTests: XCTestCase {
    struct Oracle: Decodable {
        struct Validation: Decodable { let id: String; let model: String; let reason: String? }
        struct Evaluation: Decodable { let id: String; let model: String?; let values: [Int64]; let score: Int64; let supported: Bool; let details: String }
        struct Floor: Decodable { let a: String; let b: String; let result: String }
        struct Ratio: Decodable { let a: String; let b: String; let result: Int64 }
        struct Correlation: Decodable { let xs: [Int64]; let ys: [Int64]; let result: Int64 }
        struct Quantile: Decodable { let values: [Int64]; let percent: Int; let result: Int64 }
        let domain: String; let validation: [Validation]; let evaluation: [Evaluation]
        let floor: [Floor]; let ratio: [Ratio]; let correlation: [Correlation]; let quantile: [Quantile]
    }
    private func oracle() throws -> Oracle {
        let path = try XCTUnwrap(Bundle.module.url(forResource: "model-oracle", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(Oracle.self, from: Data(contentsOf: path))
    }
    private func data(_ hex: String) throws -> Data {
        let bytes = Array(hex.utf8)
        guard bytes.count % 2 == 0 else { throw HWPReject("TEST_HEX") }
        return try Data(stride(from: 0, to: bytes.count, by: 2).map { i in
            try XCTUnwrap(UInt8(String(decoding: bytes[i..<i+2], as: UTF8.self), radix: 16))
        })
    }
    private func replace(_ object: HWPValue, field: String, with replacement: HWPValue) throws -> HWPValue {
        guard case .map(let entries) = object else { throw HWPReject("TEST_OBJECT") }
        return .map(entries.map { $0.key == .text(field) ? HWPEntry($0.key, replacement) : $0 })
    }

    func testEveryModelBranchAndSchemaRuleMatchesFrozenOracle() throws {
        let fixture = try oracle()
        XCTAssertEqual(HWPFeatureSchema.names.count, 179)
        XCTAssertGreaterThan(fixture.validation.count, 20)
        for row in fixture.validation {
            let value = try HWPCBOR.decode(data(row.model))
            if let reason = row.reason {
                XCTAssertThrowsError(try HWPAlgorithmModel(value), row.id) { error in
                    XCTAssertEqual((error as? HWPReject)?.reason, reason, row.id)
                }
            } else { XCTAssertNoThrow(try HWPAlgorithmModel(value), row.id) }
        }
    }
    func testModelScoresSupportRanksAndStrictBoundaryMatchFrozenOracle() throws {
        let fixture = try oracle()
        for row in fixture.evaluation {
            let model = try HWPAlgorithmModel(HWPCBOR.decode(data(row.model ?? fixture.validation[0].model)))
            let vector = try HWPFeatureVector(names: HWPFeatureSchema.names, values: row.values)
            let result = try model.evaluate(vector, domain: AlgorithmText(fixture.domain))
            XCTAssertEqual(result.score, row.score, row.id)
            XCTAssertEqual(result.supported, row.supported, row.id)
            XCTAssertEqual(try HWPCBOR.encode(result.details), try data(row.details), row.id)
        }
    }
    func testUnboundedIntegerIntermediatesMatchPythonFloorAndIsqrt() throws {
        let fixture = try oracle()
        for row in fixture.floor {
            let actual = try HWPFixedPoint.floorDivide(XCTUnwrap(BigInt(row.a)), XCTUnwrap(BigInt(row.b)))
            XCTAssertEqual(actual.description, row.result)
        }
        for row in fixture.ratio {
            XCTAssertEqual(try HWPFixedPoint.ratio(XCTUnwrap(BigInt(row.a)), XCTUnwrap(BigInt(row.b))), row.result)
        }
        for row in fixture.correlation {
            XCTAssertEqual(try HWPFixedPoint.correlation(row.xs, row.ys), row.result)
        }
        for row in fixture.quantile {
            XCTAssertEqual(try HWPFixedPoint.quantile(row.values, numerator: row.percent), row.result)
        }
        XCTAssertThrowsError(try HWPFixedPoint.floorDivide(1, 0))
    }
    func testUnicodeDomainsAndTokensRemainByteDistinct() throws {
        let fixture = try oracle(), base = try HWPCBOR.decode(data(fixture.validation[0].model))
        let artifact = try XCTUnwrap(base.field("domains")?.field(fixture.domain))
        let one = AlgorithmText("keyboard|p|é|birth"), two = AlgorithmText("keyboard|p|e\u{301}|birth")
        XCTAssertNotEqual(one, two)
        let updated = try replace(base, field: "domains", with: .map([
            HWPEntry(one.value, artifact), HWPEntry(two.value, artifact)
        ]))
        XCTAssertEqual(try HWPAlgorithmModel(updated).domainNames, Set([one, two]))
        let bom = try AlgorithmText(utf8: Data([0xef, 0xbb, 0xbf]))
        XCTAssertEqual(bom.scalars, [0xfeff])
        XCTAssertThrowsError(try HWPAlgorithmValues.integer(.boolean(true)))
        XCTAssertThrowsError(try HWPAlgorithmValues.text(.text(Data([0xc0, 0xaf]))))
    }
    func testVectorSchemaAndValuesCannotBypassValidation() throws {
        XCTAssertThrowsError(try HWPFeatureVector(names: HWPFeatureSchema.names.reversed(), values: Array(repeating: 0, count: 179)))
        XCTAssertThrowsError(try HWPFeatureVector(names: HWPFeatureSchema.names, values: Array(repeating: 10_001, count: 179)))
        let fixture = try oracle(), model = try HWPAlgorithmModel(HWPCBOR.decode(data(fixture.validation[0].model)))
        XCTAssertThrowsError(try model.evaluate(HWPFeatureVector(names: HWPFeatureSchema.names, values: Array(repeating: 0, count: 179)), domain: AlgorithmText("self-approved")))
    }
}
