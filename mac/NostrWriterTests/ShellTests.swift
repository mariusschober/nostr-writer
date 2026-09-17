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
}
