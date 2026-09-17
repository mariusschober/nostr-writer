import XCTest
import AppKit
import WriterFoundation
import WriterStorage
import CryptoKit

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
        let store = try DocumentStore(configuration: .init(databaseURL: root.appendingPathComponent("recovery.sqlite")), keyProvider: SyntheticNativeRecoveryKey())
        let document = WriterDocument()
        document.recoveryLibrary = RecoveryLibrary(store: store)
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
        let beforeRevert = try XCTUnwrap(document.session?.snapshot)
        XCTAssertThrowsError(try document.revert(toContentsOf: first, ofType: "net.daringfireball.markdown"))
        try await document.revertPreservingRecovery(to: first, ofType: "net.daringfireball.markdown")
        let preserved = try await XCTUnwrap(document.recoveryLibrary).recoveredEntries()
        let preservedEntry = try XCTUnwrap(preserved.first(where: { $0.parentDigest == beforeRevert.digest }))
        guard case .complete(let restored) = try await store.recover(preservedEntry.documentID) else { return XCTFail("Revert lost previous source") }
        XCTAssertEqual(restored.source.utf8, beforeRevert.utf8)
        XCTAssertEqual(document.sourceBytes, bytes)
        XCTAssertEqual(Data((document.windowControllers[0] as! WriterWindowController).editor.string.utf8), bytes)
        XCTAssertEqual(document.session?.snapshot.documentID, id)
        let copy = try XCTUnwrap(try document.duplicate() as? WriterDocument)
        copy.makeWindowControllers()
        XCTAssertNotEqual(copy.session?.snapshot.documentID, id)
        XCTAssertEqual(copy.sourceBytes, bytes)
        XCTAssertEqual(copy.derivedFrom, document.session?.snapshot)
        XCTAssertNil(copy.fileURL)
        await copy.awaitRecoveryAttachment()
        try await copy.flushRecovery(at: .close)
        copy.close()
        let second = root.appendingPathComponent("second.md")
        try await document.save(to: second, ofType: "net.daringfireball.markdown", for: .saveAsOperation)
        XCTAssertNotEqual(document.session?.snapshot.documentID, id)
        XCTAssertEqual(document.derivedFrom?.documentID, id)
        XCTAssertEqual(try Data(contentsOf: second), bytes)
        XCTAssertEqual(document.savedFile?.source, document.session?.snapshot)
        try await document.flushRecovery(at: .close)
        document.close()
        try await store.close()
    }

    func testQueuedSavesAndCloseBoundaryPreserveLatestRevision() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("writer-save-queue-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try DocumentStore(configuration: .init(databaseURL: root.appendingPathComponent("recovery.sqlite")), keyProvider: SyntheticNativeRecoveryKey())
        let document = WriterDocument(); document.recoveryLibrary = RecoveryLibrary(store: store)
        document.fileType = "net.daringfireball.markdown"
        try document.read(from: Data("first".utf8), ofType: document.fileType!)
        document.makeWindowControllers(); await document.awaitRecoveryAttachment()
        let url = root.appendingPathComponent("queued.md")
        var completed = 0
        let completion: (Error?) -> Void = { error in XCTAssertNil(error); completed += 1 }
        document.save(to: url, ofType: document.fileType!, for: .saveOperation, completionHandler: completion)
        try document.acceptScratchEdit("second\r\n")
        document.save(to: url, ofType: document.fileType!, for: .saveOperation, completionHandler: completion)
        try document.acceptScratchEdit("latest Cafe\u{301}\r\n")
        document.save(to: url, ofType: document.fileType!, for: .saveOperation, completionHandler: completion)
        await document.awaitSourceSaves()
        XCTAssertEqual(completed, 3)
        XCTAssertEqual(try Data(contentsOf: url), document.sourceBytes)
        XCTAssertEqual(document.savedFile?.source, document.session?.snapshot)
        XCTAssertFalse(document.isDocumentEdited)
        let probe = NativeCloseProbe()
        let allowed = await withCheckedContinuation { continuation in
            probe.completion = { continuation.resume(returning: $0) }
            document.canClose(withDelegate: probe, shouldClose: #selector(NativeCloseProbe.document(_:shouldClose:contextInfo:)), contextInfo: nil)
        }
        XCTAssertTrue(allowed)
        let id = try XCTUnwrap(document.session?.snapshot.documentID)
        guard case .complete(let durable) = try await store.recover(id) else { return XCTFail("Close boundary did not persist") }
        XCTAssertEqual(durable.source, document.session?.snapshot)
        document.close(); try await store.close()
    }

    func testPersistentIdentityReopenPreservesDifferentUnsavedRecovery() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("writer-reopen-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("source.md")
        let initial = Data("Original\r\n".utf8)
        try initial.write(to: url)
        let store = try DocumentStore(configuration: .init(databaseURL: root.appendingPathComponent("recovery.sqlite")),
                                      keyProvider: SyntheticNativeRecoveryKey())
        let library = RecoveryLibrary(store: store)
        let first = WriterDocument(); first.fileType = "net.daringfireball.markdown"; first.fileURL = url
        first.recoveryLibrary = library
        try first.read(from: initial, ofType: first.fileType!)
        first.makeWindowControllers(); await first.awaitRecoveryAttachment()
        XCTAssertNil(first.recoveryPreparationError)
        let firstID = try XCTUnwrap(first.session?.snapshot.documentID)
        try first.acceptScratchEdit("Unsaved exact revision\r\n")
        let unsaved = try XCTUnwrap(first.session?.snapshot)
        try await XCTUnwrap(first.recovery).flush(unsaved, boundary: .close)
        first.recovery?.stop(); first.close()
        let reopened = WriterDocument(); reopened.fileType = "net.daringfireball.markdown"; reopened.fileURL = url
        reopened.recoveryLibrary = library
        try reopened.read(from: initial, ofType: reopened.fileType!)
        reopened.makeWindowControllers(); await reopened.awaitRecoveryAttachment()
        XCTAssertNil(reopened.recoveryPreparationError)
        XCTAssertEqual(reopened.session?.snapshot.documentID, firstID)
        XCTAssertEqual(reopened.sourceBytes, initial)
        XCTAssertGreaterThan(try XCTUnwrap(reopened.session?.snapshot.revision), unsaved.revision)
        let recoveredEntries = try await library.recoveredEntries()
        let savedRecovery = try XCTUnwrap(recoveredEntries.first(where: { $0.parentID == firstID.rawValue }))
        guard case .complete(let recovered) = try await store.recover(savedRecovery.documentID) else { return XCTFail("Unsaved recovery was lost") }
        XCTAssertEqual(recovered.source.utf8, unsaved.utf8)
        reopened.recovery?.stop(); reopened.close(); try await store.close()
    }

}


private struct SyntheticNativeRecoveryKey: RecoveryKeyProviding {
    func loadRecoveryKey() async throws -> SymmetricKey { SymmetricKey(data: Data(repeating: 0x37, count: 32)) }
}

@MainActor
private final class NativeCloseProbe: NSObject {
    var completion: ((Bool) -> Void)?
    @objc func document(_ document: NSDocument, shouldClose: Bool, contextInfo: UnsafeMutableRawPointer?) {
        completion?(shouldClose)
    }
}
