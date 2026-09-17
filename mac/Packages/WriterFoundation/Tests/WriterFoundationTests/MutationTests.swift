import XCTest
@testable import WriterFoundation

final class MutationTests: XCTestCase {
    func testSlicedDataUsesDocumentRelativeByteOffsets() throws {
        let sliced = Data("prefixé!".utf8).dropFirst(6)
        XCTAssertEqual(sliced.startIndex, 6)
        let source = try SourceSnapshot(documentID: DocumentID(), revision: Revision(0), utf8: sliced)
        XCTAssertEqual(source.utf8.startIndex, 0)
        XCTAssertEqual(source.utf8, Data("é!".utf8))
        let command = EditCommand(id: UUID(), expectedRevision: source.revision,
            range: try ByteRange(lowerBound: 0, upperBound: 2), replacement: Data("e".utf8),
            origin: .unknown, undoGroup: UUID())
        let receipt = try command.applying(to: source, completeness: .recordingOff)
        XCTAssertEqual(receipt.deleted, Data("é".utf8))
        XCTAssertEqual(receipt.post.utf8, Data("e!".utf8))
    }
    func testMutationRejectsStaleRevisionAndPreservesExactDeletedBytes() throws {
        let original = try SourceSnapshot(documentID: DocumentID(), revision: Revision(8), utf8: Data("a e\u{301}\r\n".utf8))
        let command = EditCommand(id: UUID(), expectedRevision: original.revision,
                                  range: try ByteRange(lowerBound: 2, upperBound: 5), replacement: Data("é".utf8),
                                  origin: .knownAssistance(.spelling), undoGroup: UUID())
        let receipt = try command.applying(to: original, completeness: .descriptiveOnly)
        XCTAssertEqual(receipt.deleted, Data("e\u{301}".utf8))
        XCTAssertEqual(receipt.post.utf8, Data("a é\r\n".utf8))
        XCTAssertEqual(receipt.post.revision, Revision(9))
        XCTAssertEqual(receipt.command.origin, .knownAssistance(.spelling))
        XCTAssertThrowsError(try command.applying(to: receipt.post, completeness: .observed))
        XCTAssertEqual(original.utf8, Data("a e\u{301}\r\n".utf8))
    }
    func testInvalidReplacementAndExhaustedRevisionFailWithoutMutation() throws {
        let original = try SourceSnapshot(documentID: DocumentID(), revision: Revision(UInt64.max), utf8: Data())
        let command = EditCommand(id: UUID(), expectedRevision: original.revision,
                                  range: try ByteRange(lowerBound: 0, upperBound: 0), replacement: Data([0xff]),
                                  origin: .pasteExternal, undoGroup: UUID())
        XCTAssertThrowsError(try command.applying(to: original, completeness: .recordingOff))
        let other = try SourceSnapshot(documentID: original.documentID, revision: Revision(0), utf8: Data())
        let invalid = EditCommand(id: UUID(), expectedRevision: other.revision, range: command.range,
                                  replacement: command.replacement, origin: .unknown, undoGroup: UUID())
        XCTAssertThrowsError(try invalid.applying(to: other, completeness: .gap("unsupported")))
    }
}
