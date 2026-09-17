import XCTest
@testable import WriterFoundation

final class ProofPresentationTests: XCTestCase {
    let policy = Digest256.hash(Data("independent-policy".utf8))
    let release = Digest256.hash(Data("synthetic-release".utf8))
    func source(_ text: String = "Cafe\u{301}", revision: UInt64 = 3, id: DocumentID) throws -> SourceSnapshot {
        try SourceSnapshot(documentID: id, revision: Revision(revision), utf8: Data(text.utf8))
    }
    func result(_ source: SourceSnapshot, context: ProofContext = .production,
                verdict: ProofVerdict = .validHWP, scope: ProofScope = .wholeDocument,
                proof: Bool = true) throws -> ProofResult {
        try ProofResult(source: source, scope: scope, claim: .freshComposition, mode: .disclosed,
                        context: context, verdict: verdict, policy: policy, release: release,
                        proofDigest: proof ? .hash(Data("fixture proof".utf8)) : nil,
                        authorityIdentities: [.hash(Data("fixture authority".utf8))], limitations: ["Synthetic presentation test, not protocol verification."])
    }
    func project(_ current: SourceSnapshot, _ result: ProofResult?, admissions: Set<Digest256>? = nil,
                 selectedPolicy: Digest256? = nil, scope: ProofScope = .wholeDocument) -> ProofDisplay {
        ProofPresentation.project(current: current, selectedScope: scope, selectedClaim: .freshComposition,
                                  result: result, trust: .init(policy: selectedPolicy ?? policy, context: .production,
                                                              admittedReleases: admissions ?? [release]))
    }
    func testEmptyProductionApprovalSetNeverEnablesProof() throws {
        let s = try source(id: DocumentID())
        XCTAssertFalse(project(s, try result(s), admissions: []).canExportHumanWritingProof)
        XCTAssertFalse(project(s, nil).canExportHumanWritingProof)
    }
    func testConditionalProjectionRequiresCurrentIdentityExactBytesAndIndependentPolicy() throws {
        let id = DocumentID(); let s = try source(id: id); let r = try result(s)
        XCTAssertEqual(project(s, r), .humanWritten(scope: .wholeDocument, claim: .freshComposition, mode: .disclosed))
        XCTAssertEqual(project(try source("Café", id: id), r), .earlierRevision)
        XCTAssertEqual(project(try source(revision: 4, id: id), r), .earlierRevision)
        XCTAssertEqual(project(try source(id: DocumentID()), r), .earlierRevision)
        XCTAssertFalse(project(s, r, selectedPolicy: .hash(Data("author-selected".utf8))).canExportHumanWritingProof)
        XCTAssertFalse(project(s, try result(s, proof: false)).canExportHumanWritingProof)
    }
    func testConformanceAndNegativeResultsNeverProjectHuman() throws {
        let s = try source(id: DocumentID())
        XCTAssertEqual(project(s, try result(s, context: .conformance)), .testOnly)
        XCTAssertEqual(project(s, try result(s, verdict: .testOnly)), .testOnly)
        XCTAssertFalse(project(s, try result(s, verdict: .noValidHWP)).canExportHumanWritingProof)
        XCTAssertFalse(project(s, try result(s, context: .experimental)).canExportHumanWritingProof)
    }
    func testScopeRemainsExplicitAndScalarAligned() throws {
        let s = try source(id: DocumentID())
        let selected = ProofScope.selected([try ByteRange(lowerBound: 0, upperBound: 3)])
        let r = try result(s, scope: selected)
        XCTAssertFalse(project(s, r).canExportHumanWritingProof)
        XCTAssertEqual(project(s, r, scope: selected), .humanWritten(scope: selected, claim: .freshComposition, mode: .disclosed))
        XCTAssertThrowsError(try result(s, scope: .selected([])))
        XCTAssertThrowsError(try result(s, scope: .selected([try ByteRange(lowerBound: 4, upperBound: 5)])))
        XCTAssertThrowsError(try result(s, scope: .selected([try ByteRange(lowerBound: 0, upperBound: 3), try ByteRange(lowerBound: 2, upperBound: 4)])))
        XCTAssertThrowsError(try Digest256(Data(repeating: 0, count: 31)))
    }

    func testNegativeResultCannotBePackagedAsVerifiedArtifact() throws {
        let s = try source(id: DocumentID())
        XCTAssertThrowsError(try VerifiedProofArtifact(bytes: Data("fixture proof".utf8), result: result(s, verdict: .noValidHWP)))
        XCTAssertThrowsError(try VerifiedProofArtifact(bytes: Data("substituted proof".utf8), result: result(s)))
    }
}
