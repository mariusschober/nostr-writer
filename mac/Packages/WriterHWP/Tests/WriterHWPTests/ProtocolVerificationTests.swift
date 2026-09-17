import XCTest
import CryptoKit
@testable import WriterHWP

final class ProtocolVerificationTests: XCTestCase {
    typealias V = HWPProtocolValues
    private func compare(_ actual: HWPValue, _ expected: Data, _ name: String) throws {
        let reference = try HWPCBOR.decode(expected)
        if reference.field("status") == .text("NO-VALID-HWP") {
            XCTAssertEqual(actual.field("status"), .text("NO-VALID-HWP"), "\(name): \(actual.field("reason") ?? .null)")
            XCTAssertEqual(actual.field("outcome"), .text("NOT PROVABLE"), name)
            XCTAssertEqual(actual.field("authorship_inference"), .null, name)
        } else { XCTAssertEqual(try HWPCBOR.encode(actual), expected, name) }
    }
    func testAllFrozenPublicAndRecomputationResults() throws {
        let fixture = try ProtocolFixture()
        XCTAssertEqual(fixture.vector.cases.count, 16)
        for expected in fixture.oracle.cases {
            let row = try fixture.row(expected.id)
            for (label, audit, disclosed, hex) in [("public", false, true, expected.public), ("R", true, true, expected.recomputation), ("V", false, false, expected.no_witness)] {
                let result = try HWPProtocol.verify(bundle: fixture.bytes(row.bundle), document: fixture.bytes(row.document),
                    policyBytes: fixture.bytes(row.policy), policyPin: ProtocolFixture.hex(row.policy_pin),
                    disclosures: disclosed ? fixture.privateValue(row) : nil, recompute: audit)
                try compare(result, ProtocolFixture.hex(hex), row.id + "/" + label)
                if label == "V" { XCTAssertEqual(result.field("status"), .text(row.expected_class_v), row.id) }
            }
        }
    }
    func testFrozenProducerComputationsAndExactPrivateLineage() throws {
        let fixture = try ProtocolFixture()
        for expected in fixture.oracle.cases {
            let row = try fixture.row(expected.id), unpacked = try HWPObjectStore.unpack(fixture.bytes(row.bundle))
            let proof = try unpacked.store.object(unpacked.root), statement = try V.reference(proof.field("statement"))
            if let output = expected.computed, let lineage = expected.lineage {
                let got = try HWPProtocol.evaluateStatement(store: unpacked.store, statement: statement, policy: fixture.policy(row), disclosures: fixture.privateValue(row))
                XCTAssertEqual(try HWPCBOR.encode(got.result), try ProtocolFixture.hex(output), row.id)
                XCTAssertEqual(got.lineage, try ProtocolFixture.hex(lineage), row.id)
            } else {
                XCTAssertThrowsError(try HWPProtocol.evaluateStatement(store: unpacked.store, statement: statement, policy: fixture.policy(row), disclosures: fixture.privateValue(row)), row.id)
            }
        }
    }
    func testNativeAppraisalRoundTripsThroughVAndR() throws {
        let fixture = try ProtocolFixture(), row = try fixture.row("keyboard")
        var unpacked = try HWPObjectStore.unpack(fixture.bytes(row.bundle))
        let proof = try unpacked.store.object(unpacked.root)
        let statement = try V.reference(proof.field("statement")), policy = try fixture.policy(row), disclosures = try fixture.privateValue(row)
        let appraisal = try HWPProtocol.issueAppraisal(store: &unpacked.store, statement: statement, policy: policy,
            disclosures: disclosures, evaluatorKey: ProtocolFixture.fixtureKey("evaluator"))
        let produced = try HWPProtocol.finalizeProof(store: &unpacked.store, statement: statement, appraisals: [appraisal],
            authorEndorsement: nil, policy: policy, disclosures: disclosures)
        let bundle = produced.bundle
        XCTAssertEqual(produced.verification.field("execution_checked"), .text("recomputed"))
        for audit in [false] {
            let result = try HWPProtocol.verify(bundle: bundle, document: fixture.bytes(row.document), policyBytes: policy.bytes,
                policyPin: policy.sha256, disclosures: disclosures, recompute: audit)
            XCTAssertEqual(result.field("status"), .text("TEST-ONLY"))
            XCTAssertEqual(result.field("result"), .null)
            XCTAssertEqual(result.field("execution_checked"), .text(audit ? "recomputed" : "attestation"))
        }
        // Optional public synthetic output for an independent frozen Python check.
        if let path = ProcessInfo.processInfo.environment["HWP_NATIVE_PROTOCOL_SAMPLE"] {
            let directory = URL(fileURLWithPath: path, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for (name, raw) in [("proof.hwp", bundle), ("document.txt", try fixture.bytes(row.document)), ("policy.cbor", policy.bytes), ("private.cbor", try HWPCBOR.encode(disclosures)), ("private.hwp", try HWPDisclosure.pack(disclosures))] {
                try raw.write(to: directory.appendingPathComponent(name), options: .atomic)
            }
        }
    }
    func testDefaultPolicyAndAuthorityFailuresNeverIssue() throws {
        let fixture = try ProtocolFixture(), row = try fixture.row("keyboard"), defaultPolicy = try HWPInstalledProtocol.defaultPolicy()
        XCTAssertTrue(defaultPolicy.releases.isEmpty); XCTAssertTrue(defaultPolicy.captureGrants.isEmpty); XCTAssertTrue(defaultPolicy.evaluators.isEmpty)
        let result = try HWPProtocol.verify(bundle: fixture.bytes(row.bundle), document: fixture.bytes(row.document), policyBytes: defaultPolicy.bytes, policyPin: defaultPolicy.sha256)
        XCTAssertEqual(result.field("status"), .text("NO-VALID-HWP"))
        var unpacked = try HWPObjectStore.unpack(fixture.bytes(row.bundle))
        let statement = try V.reference(unpacked.store.object(unpacked.root).field("statement")), policy = try fixture.policy(row)
        let original = try unpacked.store.pack(root: unpacked.root)
        XCTAssertThrowsError(try HWPProtocol.issueAppraisal(store: &unpacked.store, statement: statement, policy: defaultPolicy,
            disclosures: fixture.privateValue(row), evaluatorKey: ProtocolFixture.fixtureKey("evaluator")))
        XCTAssertThrowsError(try HWPProtocol.issueAppraisal(store: &unpacked.store, statement: statement, policy: policy,
            disclosures: fixture.privateValue(row), evaluatorKey: ProtocolFixture.fixtureKey("other")))
        XCTAssertThrowsError(try HWPProtocol.finalizeProof(store: &unpacked.store, statement: statement,
            appraisals: [], authorEndorsement: nil, policy: policy, disclosures: fixture.privateValue(row)))
        XCTAssertEqual(try unpacked.store.pack(root: unpacked.root), original)
    }
    func testQuorumAuthorityAndKeyDenialMutationsReject() throws {
        let fixture = try ProtocolFixture(), row = try fixture.row("keyboard"), base = try HWPCBOR.decode(fixture.bytes(row.policy))
        let captures = try V.array(base.field("capture_authorities")), keys = try V.references(captures[0].field("keys"))
        let changes: [(String, HWPValue)] = [("quorum", .unsigned(2)), ("evaluators", .array([])), ("capture_authorities", .array([])),
            ("require_author", .boolean(true)), ("denied", .array([.bytes(keys[0].sha256)]))]
        for (field, value) in changes {
            let raw = try HWPCBOR.encode(ProtocolFixture.replacing(base, field, value))
            let result = try HWPProtocol.verify(bundle: fixture.bytes(row.bundle), document: fixture.bytes(row.document), policyBytes: raw,
                policyPin: HWPMerkle.digest(raw), disclosures: fixture.privateValue(row), recompute: true)
            XCTAssertEqual(result.field("status"), .text("NO-VALID-HWP"), field)
        }
    }
}
