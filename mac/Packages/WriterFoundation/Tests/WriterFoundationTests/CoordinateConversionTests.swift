import XCTest
@testable import WriterFoundation

/// Coordinate conversion contract: UTF-8 byte offsets and UTF-16 AppKit offsets
/// describe the same scalar-aligned intervals, and no split scalar is ever
/// silently rounded.
///
/// Non-ASCII samples are written as `\u{...}` escapes so the exact scalars under
/// test are explicit in the source.
final class CoordinateConversionTests: XCTestCase {

    private let documentID = DocumentID(rawValue: UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!)

    /// "a" + U+00E9 + U+6F22 + U+1F642 + "b"
    /// 11 UTF-8 bytes, 6 UTF-16 code units, 5 scalars.
    private let mixedScalars = "a\u{E9}\u{6F22}\u{1F642}b"

    /// U+1F468 U+200D U+1F469: one grapheme, three scalars.
    private let zwjGrapheme = "\u{1F468}\u{200D}\u{1F469}"

    /// U+6F22 U+5B57, space, then U+0645 U+0631 U+062D U+0628 U+0627.
    private let cjkAndArabic = "\u{6F22}\u{5B57} \u{645}\u{631}\u{62D}\u{628}\u{627}"

    private func snapshot(_ text: String, revision: UInt64 = 1) throws -> SourceSnapshot {
        try SourceSnapshot(
            documentID: documentID,
            revision: Revision(revision),
            utf8: Data(text.utf8)
        )
    }

    private func byteRange(_ lower: Int, _ upper: Int) throws -> ByteRange {
        try ByteRange(lowerBound: lower, upperBound: upper)
    }

    private func nativeRange(_ location: Int, _ length: Int) throws -> NativeRange {
        try NativeRange(location: location, length: length)
    }

    // MARK: - Range construction

    func testRangeConstructionRejectsMalformedIntervals() {
        XCTAssertThrowsError(try ByteRange(lowerBound: -1, upperBound: 3)) { error in
            XCTAssertEqual(error as? CoordinateError, .negativeBound(-1))
        }
        XCTAssertThrowsError(try ByteRange(lowerBound: 4, upperBound: 3)) { error in
            XCTAssertEqual(error as? CoordinateError, .invertedRange(lower: 4, upper: 3))
        }
        XCTAssertThrowsError(try NativeRange(location: 0, length: -2)) { error in
            XCTAssertEqual(error as? CoordinateError, .negativeBound(-2))
        }

        // Empty ranges are well formed in both spaces.
        XCTAssertNoThrow(try ByteRange(lowerBound: 3, upperBound: 3))
        XCTAssertNoThrow(try NativeRange(location: 3, length: 0))
    }

    func testRangeAccessors() throws {
        let bytes = try byteRange(2, 7)
        XCTAssertEqual(bytes.count, 5)
        XCTAssertFalse(bytes.isEmpty)

        let native = try nativeRange(3, 4)
        XCTAssertEqual(native.lowerBound, 3)
        XCTAssertEqual(native.upperBound, 7)
        XCTAssertEqual(native.count, 4)
        XCTAssertFalse(native.isEmpty)
        XCTAssertTrue(try nativeRange(3, 0).isEmpty)
    }

    func testNativeRangeRejectsLengthOverflow() throws {
        // `location + length` must not overflow before any receiver sees it.
        XCTAssertThrowsError(try NativeRange(location: Int.max, length: 1)) { error in
            XCTAssertEqual(
                error as? CoordinateError,
                .rangeOverflow(location: Int.max, length: 1)
            )
        }
        XCTAssertThrowsError(try NativeRange(location: Int.max - 1, length: 2)) { error in
            XCTAssertEqual(
                error as? CoordinateError,
                .rangeOverflow(location: Int.max - 1, length: 2)
            )
        }

        // The largest representable end offset is still valid.
        let maximal = try NativeRange(location: Int.max, length: 0)
        XCTAssertEqual(maximal.upperBound, Int.max)

        // A maximal but well-formed range is reported as out of bounds by a
        // snapshot rather than trapping inside the initializer.
        let snap = try snapshot("hello")
        XCTAssertThrowsError(try snap.byteRange(for: maximal)) { error in
            XCTAssertEqual(error as? CoordinateError, .outOfBounds(limit: 5, requested: Int.max))
        }
    }

    // MARK: - ASCII

    func testASCIIConversionIsIdentity() throws {
        let snap = try snapshot("hello world")
        XCTAssertEqual(try snap.nativeRange(for: byteRange(0, 11)), try nativeRange(0, 11))
        XCTAssertEqual(try snap.nativeRange(for: byteRange(6, 11)), try nativeRange(6, 5))
        XCTAssertEqual(try snap.byteRange(for: nativeRange(0, 11)), try byteRange(0, 11))
        XCTAssertEqual(try snap.byteRange(for: nativeRange(6, 5)), try byteRange(6, 11))
    }

    // MARK: - Mixed scalar widths

    func testMultibyteScalarBoundaries() throws {
        let snap = try snapshot(mixedScalars)
        XCTAssertEqual(snap.utf8Count, 11)
        XCTAssertEqual(snap.utf16Count, 6)
        XCTAssertEqual(snap.scalarCount, 5)

        let expectations: [(byteLower: Int, byteUpper: Int, nativeLocation: Int, nativeLength: Int)] = [
            (0, 1, 0, 1),    // "a"
            (1, 3, 1, 1),    // U+00E9      2-byte scalar
            (3, 6, 2, 1),    // U+6F22      3-byte scalar
            (6, 10, 3, 2),   // U+1F642     4-byte scalar, surrogate pair
            (10, 11, 5, 1),  // "b"
            (0, 11, 0, 6),   // whole document
        ]

        for expectation in expectations {
            let bytes = try byteRange(expectation.byteLower, expectation.byteUpper)
            let native = try nativeRange(expectation.nativeLocation, expectation.nativeLength)
            XCTAssertEqual(try snap.nativeRange(for: bytes), native, "UTF-8 to UTF-16")
            XCTAssertEqual(try snap.byteRange(for: native), bytes, "UTF-16 to UTF-8")
        }
    }

    func testCombiningMarksAreScalarBoundariesNotGraphemeBoundaries() throws {
        // U+0065 U+0301: one grapheme cluster, two scalars.
        let snap = try snapshot("e\u{0301}")
        XCTAssertEqual(snap.utf8Count, 3)
        XCTAssertEqual(snap.utf16Count, 2)
        XCTAssertEqual(snap.string.count, 1, "one grapheme cluster")

        // The combining mark alone is a legal scalar-aligned interval.
        XCTAssertEqual(try snap.nativeRange(for: byteRange(1, 3)), try nativeRange(1, 1))
        XCTAssertEqual(try snap.byteRange(for: nativeRange(1, 1)), try byteRange(1, 3))

        // A split inside the combining mark's own bytes is still rejected.
        XCTAssertThrowsError(try snap.nativeRange(for: byteRange(2, 3))) { error in
            XCTAssertEqual(error as? CoordinateError, .notScalarAligned(offset: 2, encoding: .utf8))
        }
    }

    func testZWJGraphemeSplitsOnlyAtScalarBoundaries() throws {
        let snap = try snapshot(zwjGrapheme)
        XCTAssertEqual(snap.scalarCount, 3)
        XCTAssertEqual(snap.utf8Count, 11)   // 4 + 3 + 4
        XCTAssertEqual(snap.utf16Count, 5)   // 2 + 1 + 2
        XCTAssertEqual(snap.string.count, 1)

        // Scalar-aligned splits inside the grapheme are permitted: protocol
        // coordinates are scalar-based, and highlights are a presentation layer.
        XCTAssertEqual(try snap.nativeRange(for: byteRange(0, 4)), try nativeRange(0, 2))
        XCTAssertEqual(try snap.nativeRange(for: byteRange(4, 7)), try nativeRange(2, 1))
        XCTAssertEqual(try snap.nativeRange(for: byteRange(7, 11)), try nativeRange(3, 2))

        // Splitting the leading emoji's surrogate pair is rejected.
        XCTAssertThrowsError(try snap.byteRange(for: nativeRange(1, 1))) { error in
            XCTAssertEqual(error as? CoordinateError, .notScalarAligned(offset: 1, encoding: .utf16))
        }
    }

    func testCJKAndRTLTextConvertExactly() throws {
        let snap = try snapshot(cjkAndArabic)
        // 3 + 3 + 1 + (5 x 2) bytes; 1 + 1 + 1 + 5 UTF-16 units.
        XCTAssertEqual(snap.utf8Count, 17)
        XCTAssertEqual(snap.utf16Count, 8)

        // First CJK scalar.
        XCTAssertEqual(try snap.nativeRange(for: byteRange(0, 3)), try nativeRange(0, 1))
        // The RTL run begins at byte 7 and covers 5 UTF-16 units.
        XCTAssertEqual(try snap.nativeRange(for: byteRange(7, 17)), try nativeRange(3, 5))
        XCTAssertEqual(try snap.byteRange(for: nativeRange(3, 5)), try byteRange(7, 17))
    }

    // MARK: - Rejected splits

    func testByteRangeSplittingAMultibyteScalarIsRejected() throws {
        let snap = try snapshot(mixedScalars)

        let cases: [(lower: Int, upper: Int, offset: Int)] = [
            (2, 3, 2),    // inside U+00E9
            (1, 2, 2),    // upper bound inside U+00E9
            (4, 6, 4),    // inside U+6F22
            (6, 8, 8),    // inside U+1F642
            (8, 10, 8),   // upper bound inside U+1F642
        ]

        for testCase in cases {
            XCTAssertThrowsError(
                try snap.nativeRange(for: byteRange(testCase.lower, testCase.upper))
            ) { error in
                XCTAssertEqual(
                    error as? CoordinateError,
                    .notScalarAligned(offset: testCase.offset, encoding: .utf8),
                    "bytes [\(testCase.lower), \(testCase.upper))"
                )
            }
        }
    }

    func testNativeRangeSplittingASurrogatePairIsRejected() throws {
        // Two astral scalars: 8 UTF-8 bytes, 4 UTF-16 code units. Valid UTF-16
        // boundaries are 0, 2 and 4, so offsets 1 and 3 sit inside a pair.
        let snap = try snapshot("\u{1F642}\u{1F642}")
        XCTAssertEqual(snap.utf8Count, 8)
        XCTAssertEqual(snap.utf16Count, 4)

        // A range that starts inside a pair is rejected at its start offset.
        XCTAssertThrowsError(try snap.byteRange(for: nativeRange(1, 1))) { error in
            XCTAssertEqual(error as? CoordinateError, .notScalarAligned(offset: 1, encoding: .utf16))
        }
        XCTAssertThrowsError(try snap.byteRange(for: nativeRange(3, 1))) { error in
            XCTAssertEqual(error as? CoordinateError, .notScalarAligned(offset: 3, encoding: .utf16))
        }
        // A range that ends inside a pair is rejected at its end offset.
        XCTAssertThrowsError(try snap.byteRange(for: nativeRange(0, 1))) { error in
            XCTAssertEqual(error as? CoordinateError, .notScalarAligned(offset: 1, encoding: .utf16))
        }
        XCTAssertThrowsError(try snap.byteRange(for: nativeRange(2, 1))) { error in
            XCTAssertEqual(error as? CoordinateError, .notScalarAligned(offset: 3, encoding: .utf16))
        }

        // Whole scalars convert cleanly.
        XCTAssertEqual(try snap.byteRange(for: nativeRange(0, 2)), try byteRange(0, 4))
        XCTAssertEqual(try snap.byteRange(for: nativeRange(2, 2)), try byteRange(4, 8))
        XCTAssertEqual(try snap.byteRange(for: nativeRange(0, 4)), try byteRange(0, 8))
    }

    func testSplitSurrogateInsideASCIIContextIsRejected() throws {
        // "a" + astral scalar + "b": valid UTF-16 boundaries are 0, 1, 3, 4.
        let snap = try snapshot("a\u{1F642}b")
        XCTAssertEqual(snap.utf8Count, 6)
        XCTAssertEqual(snap.utf16Count, 4)

        XCTAssertThrowsError(try snap.byteRange(for: nativeRange(1, 1))) { error in
            XCTAssertEqual(error as? CoordinateError, .notScalarAligned(offset: 2, encoding: .utf16))
        }
        XCTAssertEqual(try snap.byteRange(for: nativeRange(1, 2)), try byteRange(1, 5))
    }

    func testOutOfBoundsIsReportedWithTheLimit() throws {
        let snap = try snapshot("hello")   // 5 bytes, 5 UTF-16 units

        XCTAssertThrowsError(try snap.nativeRange(for: byteRange(3, 6))) { error in
            XCTAssertEqual(error as? CoordinateError, .outOfBounds(limit: 5, requested: 6))
        }
        XCTAssertThrowsError(try snap.byteRange(for: nativeRange(3, 4))) { error in
            XCTAssertEqual(error as? CoordinateError, .outOfBounds(limit: 5, requested: 7))
        }
        // The exact limit is valid; one past it is not.
        XCTAssertNoThrow(try snap.nativeRange(for: byteRange(5, 5)))
        XCTAssertNoThrow(try snap.byteRange(for: nativeRange(5, 0)))
        XCTAssertThrowsError(try snap.nativeRange(for: byteRange(6, 6)))
        XCTAssertThrowsError(try snap.byteRange(for: nativeRange(6, 0)))
    }

    // MARK: - Exhaustive round trip

    func testEveryScalarBoundaryRoundTripsInBothDirections() throws {
        let samples = [
            "",
            "plain ascii",
            mixedScalars,
            "e\u{0301}",
            zwjGrapheme,
            "line1\r\nline2\n\u{2028}end",
            "\u{645}\u{631}\u{62D}\u{628}\u{627} \u{6F22}\u{5B57} \u{1F389}",
            "\u{0000}\u{007F}\u{0080}\u{07FF}\u{0800}\u{FFFF}\u{10000}\u{10FFFF}",
        ]

        for sample in samples {
            let snap = try snapshot(sample)

            // Walk every scalar boundary using the snapshot's own scalar data.
            var boundaries: [Int] = [0]
            var utf8Offset = 0
            for scalar in snap.string.unicodeScalars {
                utf8Offset += SourceSnapshot.utf8Length(of: scalar)
                boundaries.append(utf8Offset)
            }
            XCTAssertEqual(boundaries.count, snap.scalarCount + 1)
            XCTAssertEqual(boundaries.last, snap.utf8Count)

            for lower in boundaries {
                for upper in boundaries where upper >= lower {
                    let bytes = try byteRange(lower, upper)
                    let native = try snap.nativeRange(for: bytes)
                    XCTAssertEqual(
                        try snap.byteRange(for: native),
                        bytes,
                        "round trip for \(sample.debugDescription) bytes [\(lower), \(upper))"
                    )
                }
            }
        }
    }

    func testConversionCoveringEntireDocumentMatchesReportedLengths() throws {
        for sample in ["", "abc", mixedScalars, zwjGrapheme, "\u{645}\u{631}\u{62D}\u{628}\u{627}"] {
            let snap = try snapshot(sample)
            let whole = try snap.nativeRange(for: byteRange(0, snap.utf8Count))
            XCTAssertEqual(whole, try nativeRange(0, snap.utf16Count), sample)
            XCTAssertEqual(try snap.byteRange(for: whole), try byteRange(0, snap.utf8Count), sample)
        }
    }

    // MARK: - Error descriptions

    func testTypedErrorsCarryUserSafeDescriptions() throws {
        XCTAssertNotNil(CoordinateError.notScalarAligned(offset: 2, encoding: .utf8).errorDescription)
        XCTAssertNotNil(CoordinateError.outOfBounds(limit: 5, requested: 6).errorDescription)
        XCTAssertNotNil(SourceSnapshotError.invalidUTF8(byteOffset: 3).errorDescription)
        XCTAssertTrue(
            try CoordinateError.outOfBounds(limit: 5, requested: 9)
                .errorDescription!.contains("9")
        )
    }
}
