import XCTest
import CryptoKit
@testable import WriterHWP

@MainActor
final class AlgorithmAssessmentTests: XCTestCase {
    struct Oracle: Decodable {
        struct Context: Decodable {
            struct Pin: Decodable { let id: String; let snapshot: String }
            let admissible: [String]; let release: Bool; let threshold: Int64?; let domains: [String]
            let documents: [Pin]; let fresh: [String]; let model: String?; let claim: String
        }
        struct Case: Decodable {
            let id: String; let bundle: String; let model: String; let threshold: Int64; let claim: String
            let excluded: String; let context: Context; let expected: String
        }
        struct Snapshot: Decodable { let value: String; let snapshot: String }
        let cases: [Case]; let json: [Snapshot]
        let blobs: [String: String]; let snapshots: [String: String]
    }
    private func oracle() throws -> Oracle {
        let path = try XCTUnwrap(Bundle.module.url(forResource: "assessment-oracle", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(Oracle.self, from: Data(contentsOf: path))
    }
    private func data(_ hex: String) throws -> Data {
        let bytes = Array(hex.utf8)
        guard bytes.count % 2 == 0 else { throw HWPReject("TEST_HEX") }
        return try Data(stride(from: 0, to: bytes.count, by: 2).map { i in
            try XCTUnwrap(UInt8(String(decoding: bytes[i..<i+2], as: UTF8.self), radix: 16))
        })
    }
    private func blob(_ reference: String, _ oracle: Oracle) throws -> HWPValue {
        let raw = try data(XCTUnwrap(oracle.blobs[reference]))
        XCTAssertEqual(SHA256.hash(data: raw).map { String(format: "%02x", $0) }.joined(), reference)
        return try HWPCBOR.decode(raw)
    }
    private func snapshot(_ reference: String, _ oracle: Oracle) throws -> Data {
        let raw = try Data(XCTUnwrap(oracle.snapshots[reference]).utf8)
        XCTAssertEqual(SHA256.hash(data: raw).map { String(format: "%02x", $0) }.joined(), reference)
        return raw
    }
    private func context(_ value: Oracle.Context, _ oracle: Oracle) throws -> HWPAlgorithmTrustedInputs {
        var context = HWPAlgorithmTrustedInputs()
        context.admissibleDocuments = Set(value.admissible.map(AlgorithmText.init))
        context.approvedRelease = value.release; context.approvedThreshold = value.threshold
        context.allowedDomains = Set(value.domains.map(AlgorithmText.init))
        context.documentSnapshots = try value.documents.map { .init(document: AlgorithmText($0.id), snapshot: try snapshot($0.snapshot, oracle)) }
        context.freshDocuments = Set(value.fresh.map(AlgorithmText.init))
        context.modelSnapshot = try value.model.map { try snapshot($0, oracle) }; context.approvedClaim = value.claim
        return context
    }
    func testCompleteConditionalAssessmentBytesMatchFrozenPython() throws {
        let oracle = try oracle()
        XCTAssertGreaterThan(oracle.cases.count, 20)
        for row in oracle.cases {
            let actual = try HWPAlgorithmAssessment.verify(
                bundle: blob(row.bundle, oracle), model: blob(row.model, oracle),
                threshold: row.threshold, context: context(row.context, oracle),
                excluded: HWPCBOR.decode(data(row.excluded)), claim: row.claim)
            let expected = try data(row.expected)
            XCTAssertEqual(try HWPCBOR.encode(actual), expected, row.id)
        }
    }
    func testExactSnapshotFormatMatchesPythonIncludingByteDistinctTextAndIntegerKeys() throws {
        for row in try oracle().json {
            XCTAssertEqual(try HWPAlgorithmJSON.snapshot(HWPCBOR.decode(data(row.value))), Data(row.snapshot.utf8))
        }
        XCTAssertThrowsError(try HWPAlgorithmJSON.snapshot(.bytes(Data([0]))))
        XCTAssertThrowsError(try HWPAlgorithmJSON.snapshot(.text("too large"), maximumBytes: 2))
        XCTAssertThrowsError(try HWPAlgorithmJSON.snapshot(.map([HWPEntry(.text("a"), .null), HWPEntry(.unsigned(1), .null)])))
    }
    private actor Gate {
        var released = false
        var continuation: CheckedContinuation<Void, Never>?
        func wait() async {
            if released { return }
            await withCheckedContinuation { continuation = $0 }
        }
        func open() { released = true; continuation?.resume(); continuation = nil }
    }
    func testCancellationRemainsUnfinishedRatherThanReturningAnAssessment() async throws {
        let oracle = try oracle(), fixture = oracle.cases[0]
        let bundle = try blob(fixture.bundle, oracle), model = try blob(fixture.model, oracle)
        let gate = Gate()
        let task = Task.detached {
            await gate.wait()
            return try HWPAlgorithmAssessment.verify(bundle: bundle, model: model)
        }
        task.cancel()
        await gate.open()
        do {
            _ = try await task.value
            XCTFail("Cancelled computation must not return a finished assessment.")
        } catch is CancellationError { }
    }
    func testDefaultContextCannotUseConditionalFixtureAsProductionApproval() throws {
        let oracle = try oracle(), fixture = oracle.cases[0]
        let result = try HWPAlgorithmAssessment.verify(bundle: blob(fixture.bundle, oracle), model: blob(fixture.model, oracle))
        XCTAssertEqual(result.field("verdict"), .text("NOT PROVABLE"))
        XCTAssertEqual(result.field("contribution_verdict"), .text("NOT PROVABLE"))
        XCTAssertEqual(result.field("certification_enabled"), .boolean(false))
        let missingModel = try HWPAlgorithmAssessment.verify(bundle: blob(fixture.bundle, oracle))
        XCTAssertEqual(missingModel.field("reason"), .text("MODEL_UNAVAILABLE"))
    }
}
