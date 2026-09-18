import Foundation
import XCTest
import WriterFoundation
@testable import WriterStorage

@MainActor
final class TextImportTests: XCTestCase {
    func testExplicitImportPreservesOriginalAndRejectsMalformedText() async throws {
        let workspace = try TempWorkspace(); defer { workspace.remove() }
        let raw = Data([0x43,0x61,0x66,0xe9,0x0d,0x0a]), file = workspace.url("legacy.txt")
        try raw.write(to: file)
        let files = CoordinatedSourceFiles()
        do { _ = try await files.read(file); XCTFail("Ordinary Open silently accepted non-UTF-8") }
        catch { XCTAssertEqual(error as? SourceFileError, .invalidUTF8) }
        let selected = try await files.readForTextImport(file)
        XCTAssertEqual(selected, raw)
        XCTAssertThrowsError(try TextImport.convert(selected, encoding: .utf8))
        let imported = try TextImport.convert(selected, encoding: .latin1)
        XCTAssertEqual(imported.bytes, Data("Café\r\n".utf8))
        XCTAssertEqual(try Data(contentsOf: file), raw, "Import must not rewrite the selected original")
        XCTAssertEqual(imported.receipt.originalDigest, SourceSnapshot.sha256(raw))
        XCTAssertEqual(imported.receipt.convertedDigest, SourceSnapshot.sha256(imported.bytes))
        let exact = Data([0xef,0xbb,0xbf]) + Data("Cafe\u{301}\r\n  \n".utf8)
        XCTAssertEqual(try TextImport.convert(exact, encoding: .utf8).bytes, exact)
        let text = "Cafe\u{301} 😀\r\n"
        for (encoding, native, bom) in [(TextImportEncoding.utf16LittleEndian, String.Encoding.utf16LittleEndian, Data([0xff,0xfe])),
                                         (.utf16BigEndian, .utf16BigEndian, Data([0xfe,0xff]))] {
            let input = bom + (try XCTUnwrap(text.data(using: native)))
            XCTAssertEqual(try TextImport.convert(input, encoding: encoding).bytes, Data(text.utf8))
        }
        for malformed in [Data([0x00,0xd8]), Data([0x00,0xdc]), Data([0x00])] {
            XCTAssertThrowsError(try TextImport.convert(malformed, encoding: .utf16LittleEndian))
        }
        XCTAssertEqual(try TextImport.convert(Data([0x80]), encoding: .windows1252).bytes, Data("€".utf8))
        XCTAssertThrowsError(try TextImport.convert(Data(repeating: 65, count: CoordinatedSourceFiles.maximumBytes+1), encoding: .latin1))
        let store = try makeStore(workspace)
        var record = DocumentCatalogRecord(documentID: DocumentID(), title: "Imported copy")
        record.textImport = imported.receipt
        try await store.saveCatalogRecord(record)
        let restored = try await store.catalogRecord(for: record.documentID)
        XCTAssertEqual(restored?.textImport, imported.receipt)
        try await store.close()
    }
}
