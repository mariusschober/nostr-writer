import XCTest
import AppKit
import WriterFoundation

@MainActor
final class ShellTests: XCTestCase {
    func testConsentIsOffUntilExplicitChoice() throws {
        let name = "com.mariusschober.nostrwriter.tests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let consent = RecordingConsent(defaults: defaults)
        XCTAssertFalse(consent.hasChosen)
        XCTAssertEqual(consent.choice, .off)
        consent.choose(.requested)
        XCTAssertTrue(consent.hasChosen)
        XCTAssertEqual(RecordingConsent(defaults: defaults).choice, .requested)
        consent.choose(.off)
        XCTAssertEqual(consent.choice, .off)
    }

    func testDocumentRoundTripsExactSourceBytes() throws {
        let document = WriterDocument()
        let bytes = Data([0xef, 0xbb, 0xbf]) + Data("# Cafe\u{301}\r\n\r\n  \n".utf8)
        try document.read(from: bytes, ofType: "net.daringfireball.markdown")
        XCTAssertEqual(try document.data(ofType: "net.daringfireball.markdown"), bytes)
        _ = NSApplication.shared
        document.makeWindowControllers()
        let controller = try XCTUnwrap(document.windowControllers.first as? WriterWindowController)
        XCTAssertEqual(Data(controller.editor.string.utf8), bytes)
        try document.acceptScratchEdit(controller.editor.string + "x")
        XCTAssertEqual(document.sourceBytes, bytes + Data("x".utf8))
        XCTAssertThrowsError(try document.read(from: Data([0xff]), ofType: "public.plain-text"))
        XCTAssertEqual(try document.data(ofType: "net.daringfireball.markdown"), bytes + Data("x".utf8))
    }

    func testScratchEditorUsesTextKitTwoAndNoAutomaticWordingChanges() {
        _ = NSApplication.shared
        let controller = WriterWindowController(writerDocument: WriterDocument())
        XCTAssertNotNil(controller.editor.textLayoutManager)
        XCTAssertFalse(controller.editor.isAutomaticTextReplacementEnabled)
        XCTAssertFalse(controller.editor.isAutomaticTextCompletionEnabled)
        let window = controller.window!
        window.setFrame(NSRect(origin: window.frame.origin, size: NSSize(width: 760, height: 520)), display: false)
        window.contentView!.layoutSubtreeIfNeeded()
        XCTAssertEqual(window.frame.size, NSSize(width: 760, height: 520))
        XCTAssertGreaterThan(controller.editor.enclosingScrollView!.contentSize.width, 400)
    }

    func testSessionRejectsStaleAsyncCompletion() throws {
        let old = try SourceSnapshot(documentID: DocumentID(), revision: Revision(0), utf8: Data("Old".utf8))
        let session = DocumentSession(snapshot: old)
        try session.apply(EditCommand(id: UUID(), expectedRevision: old.revision,
                                      range: try ByteRange(lowerBound: 0, upperBound: 3),
                                      replacement: Data("New".utf8), origin: .unknown, undoGroup: UUID()))
        XCTAssertFalse(session.acceptsCompletion(for: old))
        XCTAssertTrue(session.acceptsCompletion(for: session.snapshot))
        XCTAssertEqual(session.snapshot.utf8, Data("New".utf8))
    }
    func testNativeSaveRevertAndDuplicateKeepExactBytesAndIdentity() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("writer-native-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let document = WriterDocument()
        document.fileType = "net.daringfireball.markdown"
        let bytes = Data([0xef, 0xbb, 0xbf]) + Data("Cafe\u{301}\r\n  \n".utf8)
        try document.read(from: bytes, ofType: "net.daringfireball.markdown")
        document.makeWindowControllers()
        let id = try XCTUnwrap(document.session?.snapshot.documentID)
        let first = root.appendingPathComponent("first.md")
        try await document.save(to: first, ofType: "net.daringfireball.markdown", for: .saveOperation)
        XCTAssertEqual(try Data(contentsOf: first), bytes)
        XCTAssertEqual(document.savedFile?.source, document.session?.snapshot)
        try document.acceptScratchEdit(String(decoding: bytes, as: UTF8.self) + "new")
        XCTAssertNotEqual(document.savedFile?.source, document.session?.snapshot)
        try document.revert(toContentsOf: first, ofType: "net.daringfireball.markdown")
        XCTAssertEqual(document.sourceBytes, bytes)
        XCTAssertEqual(Data((document.windowControllers[0] as! WriterWindowController).editor.string.utf8), bytes)
        XCTAssertEqual(document.session?.snapshot.documentID, id)
        let copy = try XCTUnwrap(try document.duplicate() as? WriterDocument)
        copy.makeWindowControllers()
        XCTAssertNotEqual(copy.session?.snapshot.documentID, id)
        XCTAssertEqual(copy.sourceBytes, bytes)
        XCTAssertEqual(copy.derivedFrom, document.session?.snapshot)
        XCTAssertNil(copy.fileURL)
        copy.close()
        let second = root.appendingPathComponent("second.md")
        try await document.save(to: second, ofType: "net.daringfireball.markdown", for: .saveAsOperation)
        XCTAssertNotEqual(document.session?.snapshot.documentID, id)
        XCTAssertEqual(document.derivedFrom?.documentID, id)
        XCTAssertEqual(try Data(contentsOf: second), bytes)
        XCTAssertEqual(document.savedFile?.source, document.session?.snapshot)
        document.close()
    }

}
