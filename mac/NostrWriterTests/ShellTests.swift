import XCTest
import AppKit
import WriterFoundation
import WriterStorage
import CryptoKit
import WriterExport
import ImageIO
import UniformTypeIdentifiers

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

    func testExternalChangesPreserveBothSourcesAndRejectUnreviewedSave() async throws {
        _ = NSApplication.shared
        guard let writer = ProcessInfo.processInfo.environment["NW_COORDINATED_WRITER"] else {
            throw XCTSkip("Set NW_COORDINATED_WRITER to the compiled test-only coordinated_writer.swift helper.")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("writer-conflict-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("source.md")
        let original = Data("original\r\n".utf8)
        try original.write(to: url)
        let store = try DocumentStore(configuration: .init(databaseURL: root.appendingPathComponent("recovery.sqlite")), keyProvider: SyntheticNativeRecoveryKey())
        let library = RecoveryLibrary(store: store)
        let document = WriterDocument(); document.recoveryLibrary = library
        document.fileURL = url; document.fileType = "net.daringfireball.markdown"
        try document.read(from: original, ofType: document.fileType!)
        document.makeWindowControllers(); await document.awaitRecoveryAttachment()
        try document.acceptScratchEdit("local Cafe\u{301}\r\n")
        let local = try XCTUnwrap(document.session?.snapshot)
        let external = Data("external CAFÉ\r\n".utf8)
        try await Self.externalWrite(external, to: url, executable: writer)
        do {
            try await document.save(to: url, ofType: document.fileType!, for: .saveOperation)
            XCTFail("An unseen external file was overwritten")
        } catch { }
        XCTAssertEqual(try Data(contentsOf: url), external)
        XCTAssertEqual(document.sourceBytes, local.utf8)
        try await document.fileLifecycle.checkForChanges()
        XCTAssertNotNil(document.fileLifecycle.conflict)
        let externalCopyResult = try await document.fileLifecycle.resolve(.openExternalCopy, displayCopies: false)
        let externalCopy = try XCTUnwrap(externalCopyResult)
        XCTAssertEqual(externalCopy.sourceBytes, external)
        XCTAssertNil(externalCopy.fileURL)
        XCTAssertEqual(document.sourceBytes, local.utf8)
        await externalCopy.awaitRecoveryAttachment(); try await externalCopy.flushRecovery(at: .close); externalCopy.close()
        let copyURL = root.appendingPathComponent("source (Conflict).md")
        let localCopyResult = try await document.fileLifecycle.resolve(.keepBoth, copyURL: copyURL, displayCopies: false)
        let localCopy = try XCTUnwrap(localCopyResult)
        XCTAssertEqual(try Data(contentsOf: copyURL), local.utf8)
        XCTAssertEqual(try Data(contentsOf: url), external)
        XCTAssertEqual(document.sourceBytes, external)
        XCTAssertEqual(document.session?.lastMutation?.command.origin, .externalReload)
        XCTAssertEqual(localCopy.derivedFrom, local)
        XCTAssertNotEqual(localCopy.session?.snapshot.documentID, local.documentID)
        await localCopy.awaitRecoveryAttachment(); try await localCopy.flushRecovery(at: .close); localCopy.close()

        try document.acceptScratchEdit("chosen local\r\n")
        let chosen = document.sourceBytes
        let externalTwo = Data("external two\r\n".utf8)
        try await Self.externalWrite(externalTwo, to: url, executable: writer)
        try await document.fileLifecycle.checkForChanges()
        try await document.fileLifecycle.resolve(.keepLocal, displayCopies: false)
        XCTAssertEqual(try Data(contentsOf: url), chosen)
        XCTAssertNil(document.fileLifecycle.conflict)
        let records = try await library.recoveredEntries()
        var recoveredBodies: [Data] = []
        for record in records { recoveredBodies.append(try await library.recoveredSource(record.documentID).utf8) }
        XCTAssertTrue(recoveredBodies.contains(local.utf8))
        XCTAssertTrue(recoveredBodies.contains(external))
        XCTAssertTrue(recoveredBodies.contains(externalTwo))

        try document.acceptScratchEdit("dirty after own save")
        let dirty = document.sourceBytes
        try await document.fileLifecycle.checkForChanges()
        XCTAssertNil(document.fileLifecycle.conflict, "Own-save echoes must not conflict with later typing")
        XCTAssertEqual(document.sourceBytes, dirty)
        try await document.save(to: url, ofType: document.fileType!, for: .saveOperation)
        let cleanExternal = Data("external change to clean document\r\n".utf8)
        try await Self.externalWrite(cleanExternal, to: url, executable: writer)
        try await document.fileLifecycle.checkForChanges()
        XCTAssertEqual(document.sourceBytes, cleanExternal)
        XCTAssertNil(document.fileLifecycle.conflict)
        XCTAssertEqual(document.savedFile?.source, document.session?.snapshot)
        try await document.flushRecovery(at: .close)
        document.close(); try await store.close()
    }

    func testNativeUndoSynchronizesExactDocumentSource() throws {
        _ = NSApplication.shared
        let document = WriterDocument(), original = Data("Cafe\u{301} 😀\r\n".utf8)
        try document.read(from: original, ofType: "net.daringfireball.markdown")
        document.makeWindowControllers()
        let editor = try XCTUnwrap((document.windowControllers.first as? WriterWindowController)?.editor)
        let undo = try XCTUnwrap(editor.undoManager)
        let source = try XCTUnwrap(document.session?.snapshot)
        undo.beginUndoGrouping()
        try document.insertManagedImageLink("![image](owned.assets/a.png)", at: NSRange(location: editor.string.utf16.count, length: 0), expecting: source)
        undo.endUndoGrouping()
        let inserted = document.sourceBytes
        undo.undo()
        XCTAssertEqual(Data(editor.string.utf8), original); XCTAssertEqual(document.sourceBytes, original)
        undo.redo()
        XCTAssertEqual(Data(editor.string.utf8), inserted); XCTAssertEqual(document.sourceBytes, inserted)
        document.close()
    }

    func testManagedImageInsertionUndoDerivationAndReferencedCopy() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("writer-native-assets-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try DocumentStore(configuration: .init(databaseURL: root.appendingPathComponent("recovery.sqlite")), keyProvider: SyntheticNativeRecoveryKey())
        let document = WriterDocument(); document.recoveryLibrary = RecoveryLibrary(store: store)
        document.assets = DocumentAssets(document: document, bookmarks: SyntheticAssetBookmarks())
        document.fileType = "net.daringfireball.markdown"
        let original = Data("Cafe\u{301} 😀\r\n".utf8)
        try document.read(from: original, ofType: document.fileType!)
        document.makeWindowControllers()
        let first = root.appendingPathComponent("Original.md")
        try await document.save(to: first, ofType: document.fileType!, for: .saveOperation)
        let pixels = try XCTUnwrap(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let imageBytes = NSMutableData(), image = try XCTUnwrap(pixels.makeImage())
        let encoder = try XCTUnwrap(CGImageDestinationCreateWithData(imageBytes, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(encoder, image, nil); XCTAssertTrue(CGImageDestinationFinalize(encoder))
        let selected = root.appendingPathComponent("input.png"); try (imageBytes as Data).write(to: selected)
        let editor = try XCTUnwrap((document.windowControllers.first as? WriterWindowController)?.editor)
        editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
        let undo = try XCTUnwrap(editor.undoManager)
        undo.beginUndoGrouping()
        try await document.assets.insertImage(selected, grantedFolder: root)
        undo.endUndoGrouping()
        let asset = try XCTUnwrap(document.assets.records.first)
        let withImage = original + Data("![Image](\(asset.markdownPath))".utf8)
        XCTAssertEqual(document.sourceBytes, withImage)
        XCTAssertEqual(document.session?.lastMutation?.command.origin, .formatting)
        undo.undo(); XCTAssertEqual(Data(editor.string.utf8), original, "Native editor undo result")
        XCTAssertEqual(document.sourceBytes, original, "Document receives native undo notification")
        undo.redo(); XCTAssertEqual(document.sourceBytes, withImage)
        let id = try XCTUnwrap(document.session?.snapshot.documentID)
        let second = root.appendingPathComponent("Copy.md")
        try await document.save(to: second, ofType: document.fileType!, for: .saveAsOperation)
        try await document.flushRecovery(at: .save)
        let nextID = try XCTUnwrap(document.session?.snapshot.documentID)
        XCTAssertNotEqual(nextID, id); XCTAssertEqual(document.derivedFrom?.documentID, id)
        XCTAssertEqual(try Data(contentsOf: second), withImage)
        XCTAssertEqual(try Data(contentsOf: first), original)
        let record = try await store.catalogRecord(for: nextID)
        XCTAssertEqual(record?.managedAssets, [asset]); XCTAssertNotNil(record?.assetFolderBookmark)
        let copy = try XCTUnwrap(try document.duplicate() as? WriterDocument)
        copy.makeWindowControllers(); await copy.awaitRecoveryAttachment()
        XCTAssertEqual(copy.assets.records, [asset]); XCTAssertNil(copy.fileURL)
        let duplicateID = try XCTUnwrap(copy.session?.snapshot.documentID)
        let duplicateRecord = try await store.catalogRecord(for: duplicateID)
        XCTAssertEqual(duplicateRecord?.managedAssets, [asset])
        copy.close()
        let destination = root.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        let prepared = try await document.assets.prepareDestination(destination.appendingPathComponent("moved.md"),
            source: XCTUnwrap(document.session?.snapshot), grantedFolder: destination)
        XCTAssertEqual(prepared.records, [asset]); XCTAssertEqual(document.assets.folderBookmark, record?.assetFolderBookmark)
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent(asset.relativePath)), imageBytes as Data)
        let markdown = "![owned](\(asset.markdownPath))\n```\n![code](code.assets/x.png)\n```\n[link](link.assets/x.png)\n![remote](https://example.com/x.png)\n![escape](../x.png)"
        let source = try SourceSnapshot(documentID: DocumentID(), revision: Revision(0), utf8: Data(markdown.utf8))
        XCTAssertEqual(try MarkdownAssetReferences.relativeImagePaths(in: source), [asset.relativePath])
        document.close(); try await store.close()
    }

    private static func externalWrite(_ bytes: Data, to url: URL, executable: String) async throws {
        let status = try await Task.detached {
            let process = Process(); process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = [url.path, bytes.base64EncodedString()]
            try process.run(); process.waitUntilExit(); return process.terminationStatus
        }.value
        XCTAssertEqual(status, 0)
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

private struct SyntheticAssetBookmarks: SourceBookmarkProviding {
    func create(for url: URL) throws -> Data { Data(url.absoluteString.utf8) }
    func resolve(_ bookmark: Data) throws -> ResolvedSourceBookmark {
        guard let url = URL(string: String(decoding: bookmark, as: UTF8.self)) else { throw SourceAccessError.invalidBookmark }
        return ResolvedSourceBookmark(url: url, isStale: false)
    }
    func start(_ url: URL) -> Bool { true }
    func stop(_ url: URL) {}
}
