import XCTest
import CryptoKit
@testable import WriterFoundation

final class SourceSnapshotTests: XCTestCase {

    private let documentID = DocumentID(rawValue: UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!)

    private func snapshot(
        bytes: [UInt8],
        revision: UInt64 = 1,
        documentID: DocumentID? = nil
    ) throws -> SourceSnapshot {
        try SourceSnapshot(
            documentID: documentID ?? self.documentID,
            revision: Revision(revision),
            utf8: Data(bytes)
        )
    }

    private func snapshot(_ text: String, revision: UInt64 = 1) throws -> SourceSnapshot {
        try snapshot(bytes: Array(text.utf8), revision: revision)
    }

    // MARK: - Exact bytes and digest

    func testEmptySourceIsValidAndDigestsToSHA256OfEmptyInput() throws {
        let empty = try snapshot(bytes: [])

        XCTAssertEqual(empty.byteCount, 0)
        XCTAssertEqual(empty.scalarCount, 0)
        XCTAssertEqual(empty.digest.count, 32)
        XCTAssertEqual(
            empty.digestHex,
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
        XCTAssertEqual(empty.string, "")
    }

    func testDigestIsSHA256OfExactBytesNotOfDecodedString() throws {
        // "abc": well-known SHA-256 vector.
        let abc = try snapshot("abc")
        XCTAssertEqual(abc.digest.count, 32)
        XCTAssertEqual(
            abc.digestHex,
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )

        // Cross-check the helper against CryptoKit called independently here.
        let raw = Data("abc".utf8)
        XCTAssertEqual(abc.digest, Data(SHA256.hash(data: raw)))
        XCTAssertEqual(SourceSnapshot.sha256(raw).count, 32)
    }

    func testSourceBytesArePreservedExactly() throws {
        // Tab, CRLF, trailing newline and a multi-byte scalar must survive verbatim.
        let original = "line1\tvalue\r\nline2\n\u{2028}end\u{E9}\n"
        let snap = try snapshot(original)
        XCTAssertEqual(Array(snap.utf8), Array(original.utf8))
        XCTAssertEqual(snap.string, original)
        XCTAssertEqual(snap.byteCount, original.utf8.count)
    }

    // MARK: - No canonical normalisation

    func testCanonicallyEquivalentSpellingsStayDistinct() throws {
        let precomposed = "\u{E9}"            // U+00E9
        let decomposed = "e\u{0301}"          // U+0065 U+0301

        let composedSnap = try snapshot(precomposed)
        let decomposedSnap = try snapshot(decomposed)

        XCTAssertEqual(Array(composedSnap.utf8), [0xC3, 0xA9])
        XCTAssertEqual(Array(decomposedSnap.utf8), [0x65, 0xCC, 0x81])

        // Swift's String `==` is canonical equivalence: it reports these as equal.
        // That is exactly why the contract forbids it for integrity.
        XCTAssertEqual(composedSnap.string, decomposedSnap.string)

        // Snapshot identity is byte identity, so the values remain distinct.
        XCTAssertNotEqual(composedSnap, decomposedSnap)
        XCTAssertNotEqual(composedSnap.digest, decomposedSnap.digest)
        XCTAssertFalse(composedSnap.hasIdenticalBytes(to: decomposedSnap))
    }

    func testLineEndingsAreNotNormalised() throws {
        let crlf = try snapshot("a\r\nb")
        let lf = try snapshot("a\nb")
        XCTAssertNotEqual(crlf.digest, lf.digest)
        XCTAssertEqual(Array(crlf.utf8), [0x61, 0x0D, 0x0A, 0x62])
    }

    // MARK: - Identity versus content

    func testRevisionAndDocumentIdentityAreNotContentIdentity() throws {
        let revisionOne = try snapshot("same bytes", revision: 1)
        let revisionTwo = try snapshot("same bytes", revision: 2)
        XCTAssertNotEqual(revisionOne, revisionTwo)
        XCTAssertEqual(revisionOne.digest, revisionTwo.digest)
        XCTAssertTrue(revisionOne.hasIdenticalBytes(to: revisionTwo))

        let otherDocument = DocumentID()
        let foreign = try snapshot(
            bytes: Array("same bytes".utf8),
            revision: 1,
            documentID: otherDocument
        )
        XCTAssertNotEqual(revisionOne, foreign)
        XCTAssertEqual(revisionOne.digest, foreign.digest)
    }

    func testRevisionOrderingAndOverflow() {
        XCTAssertLessThan(Revision(1), Revision(2))
        XCTAssertEqual(Revision(1).next, Revision(2))
        XCTAssertNil(Revision(rawValue: UInt64.max).next)
        XCTAssertEqual(DocumentID(rawValue: documentID.rawValue), documentID)
    }

    func testFreshDocumentIdentifiersAreDistinct() {
        XCTAssertNotEqual(DocumentID(), DocumentID())
    }

    // MARK: - Rejection of malformed UTF-8

    func testInvalidUTF8IsRejectedAtExactOffset() throws {
        let cases: [(name: String, bytes: [UInt8], offset: Int)] = [
            ("stray continuation", [0x61, 0x62, 0x80], 2),
            ("overlong two byte", [0x61, 0xC0, 0xAF], 1),
            ("overlong three byte", [0xE0, 0x80, 0xAF], 0),
            ("truncated two byte", [0x61, 0xC3], 1),
            ("truncated three byte", [0x61, 0xE2, 0x82], 1),
            ("truncated four byte", [0xF0, 0x9F, 0x98], 0),
            ("surrogate lead ED A0 80", [0xED, 0xA0, 0x80], 0),
            ("beyond U+10FFFF F4 90", [0xF4, 0x90, 0x80, 0x80], 0),
            ("value 0xF5", [0xF5, 0x80, 0x80, 0x80], 0),
            ("value 0xFF", [0x61, 0xFF], 1),
            ("bad continuation byte", [0xE2, 0x28, 0xA1], 0),
        ]

        for testCase in cases {
            XCTAssertThrowsError(
                try snapshot(bytes: testCase.bytes),
                "\(testCase.name) should be rejected"
            ) { error in
                XCTAssertEqual(
                    error as? SourceSnapshotError,
                    .invalidUTF8(byteOffset: testCase.offset),
                    "\(testCase.name) offset"
                )
            }
        }
    }

    func testValidatorAgreesWithStandardDecoderOnEveryOneAndTwoByteSequence() {
        // 256 single-byte and 65,536 two-byte sequences: complete coverage of the
        // shortest encodings, which is where overlong and stray-continuation
        // errors live.
        var mismatches: [String] = []

        func agrees(_ bytes: [UInt8]) -> Bool {
            let data = Data(bytes)
            let myVerdict = SourceSnapshot.firstInvalidUTF8Offset(in: data) == nil
            // `String(validating:as:)` is macOS 15+; the package deploys to 14.
            let standardVerdict = String(data: data, encoding: .utf8) != nil
            return myVerdict == standardVerdict
        }

        for first in 0...255 {
            let bytes = [UInt8(first)]
            if !agrees(bytes) { mismatches.append("\(bytes)") }
        }
        for first in 0...255 {
            for second in 0...255 {
                let bytes = [UInt8(first), UInt8(second)]
                if !agrees(bytes) { mismatches.append("\(bytes)") }
            }
        }

        XCTAssertTrue(mismatches.isEmpty, "validator disagreed with String(validating:) for \(mismatches.prefix(10))")
    }

    func testValidatorAcceptsEveryScalarItDecodes() {
        // Spot-check the boundaries of each UTF-8 length class.
        let accepted: [String] = [
            "\u{0000}", "\u{007F}", "\u{0080}", "\u{07FF}",
            "\u{0800}", "\u{D7FF}", "\u{E000}", "\u{FFFF}",
            "\u{10000}", "\u{10FFFF}",
        ]
        for text in accepted {
            XCTAssertNoThrow(
                try snapshot(text),
                "U+\(text.unicodeScalars.first!.value) should be accepted"
            )
        }
    }

    func testNoncharactersAreAcceptedUnchanged() throws {
        // U+FFFE and U+FFFF are valid UTF-8 though not assigned characters.
        let text = "a\u{FFFE}b\u{FFFF}"
        let snap = try snapshot(text)
        XCTAssertEqual(Array(snap.utf8), Array(text.utf8))
    }
}
