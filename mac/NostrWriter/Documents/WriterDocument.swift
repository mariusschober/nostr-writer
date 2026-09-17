import AppKit
import WriterFoundation
import os

@MainActor
final class WriterDocument: NSDocument {
    // Also declare the concrete source types on the document class so native
    // file operations remain defined when hosted without the application plist.
    nonisolated override class var readableTypes: [String] { ["net.daringfireball.markdown", "public.plain-text"] }
    nonisolated override class var writableTypes: [String] { readableTypes }
    nonisolated override class func isNativeType(_ type: String) -> Bool { readableTypes.contains(type) }

    // NSDocument may call read on its loading executor. This buffer only transfers
    // decoded source into the main-actor live editor; no UI or capture state lives here.
    private nonisolated let loadedBytes = OSAllocatedUnfairLock(initialState: Data())
    private var documentID = DocumentID()
    private(set) var derivedFrom: SourceSnapshot?
    private(set) var session: DocumentSession?
    private(set) var recovery: DocumentRecovery?
    private(set) var savedFile: SavedFileRevision?
    private(set) var isSavingSource = false
    private(set) var saveFailed = false
    private var writeSnapshot: SourceSnapshot?
    private var saveChangeToken: Any?
    private nonisolated let writingBytes = OSAllocatedUnfairLock<SourceSnapshot?>(initialState: nil)
    var sourceBytes: Data { session?.snapshot.utf8 ?? loadedBytes.withLock { $0 } }
    override class var autosavesInPlace: Bool { false }
    override class var autosavesDrafts: Bool { false }
    nonisolated override var autosavingFileType: String? { nil } // Private drafts use encrypted recovery only.

    override func makeWindowControllers() {
        do {
            session = DocumentSession(snapshot: try SourceSnapshot(documentID: documentID, revision: Revision(0), utf8: loadedBytes.withLock { $0 }))
        } catch { presentError(error); return }
        let controller = WriterWindowController(writerDocument: self)
        addWindowController(controller)
        if let source = session?.snapshot, let library = (NSApp.delegate as? AppDelegate)?.recoveryLibrary {
            recovery = DocumentRecovery(source: source, library: library)
            recovery?.didChange = { [weak self] in self?.refreshWindows() }
        }
        if let source = session?.snapshot, let fileURL { savedFile = SavedFileRevision(source: source, url: fileURL) }
        refreshWindows()
    }

    nonisolated override func data(ofType typeName: String) throws -> Data {
        // AppKit invokes this from its file-writing queue. Never cross back to
        // editor state or synthesize a newer snapshot during this save.
        writingBytes.withLock { $0?.utf8 } ?? loadedBytes.withLock { $0 }
    }

    override func changeCountToken(for saveOperation: NSDocument.SaveOperationType) -> Any {
        saveChangeToken ?? super.changeCountToken(for: saveOperation)
    }

    override func canAsynchronouslyWrite(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType) -> Bool { true }

    override func save(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
                       completionHandler: @escaping (Error?) -> Void) {
        guard !isSavingSource else {
            completionHandler(CocoaError(.userCancelled)); return
        }
        isSavingSource = true; saveFailed = false
        writeSnapshot = session?.snapshot
        saveChangeToken = super.changeCountToken(for: saveOperation)
        let sourceToWrite = writeSnapshot
        writingBytes.withLock { $0 = sourceToWrite }
        refreshWindows()
        super.save(to: url, ofType: typeName, for: saveOperation) { [weak self] error in
            guard let self else { completionHandler(error); return }
            if error == nil, let source = self.writeSnapshot {
                var savedSource = source
                if saveOperation == .saveAsOperation, let current = self.session?.snapshot {
                    do {
                        self.derivedFrom = source
                        self.documentID = DocumentID()
                        let replacement = try SourceSnapshot(documentID: self.documentID, revision: current.revision, utf8: current.utf8)
                        self.session = DocumentSession(snapshot: replacement)
                        savedSource = try SourceSnapshot(documentID: self.documentID, revision: source.revision, utf8: source.utf8)
                        self.recovery?.stop()
                        if let library = (NSApp.delegate as? AppDelegate)?.recoveryLibrary {
                            self.recovery = DocumentRecovery(source: replacement, library: library)
                            self.recovery?.didChange = { [weak self] in self?.refreshWindows() }
                        }
                    } catch {
                        self.isSavingSource = false; self.saveFailed = true; self.writeSnapshot = nil; self.saveChangeToken = nil
                        self.writingBytes.withLock { $0 = nil }
                        self.refreshWindows(); completionHandler(error); return
                    }
                }
                let saved = SavedFileRevision(source: savedSource, url: url)
                self.savedFile = saved
                self.recovery?.acknowledgeSave(saved)
            }
            self.isSavingSource = false; self.saveFailed = error != nil; self.writeSnapshot = nil; self.saveChangeToken = nil
            self.writingBytes.withLock { $0 = nil }
            self.refreshWindows(); completionHandler(error)
        }
    }

    override func revert(toContentsOf url: URL, ofType typeName: String) throws {
        try super.revert(toContentsOf: url, ofType: typeName)
        guard let session else { return }
        let bytes = loadedBytes.withLock { $0 }
        if bytes != session.snapshot.utf8 {
            try session.apply(EditCommand(id: UUID(), expectedRevision: session.snapshot.revision,
                range: try ByteRange(lowerBound: 0, upperBound: session.snapshot.byteCount),
                replacement: bytes, origin: .unknown, undoGroup: UUID()))
        }
        savedFile = SavedFileRevision(source: session.snapshot, url: url)
        recovery?.observe(session.snapshot)
        for controller in windowControllers.compactMap({ $0 as? WriterWindowController }) { controller.reloadSource() }
        refreshWindows()
    }

    override func duplicate() throws -> NSDocument {
        let copy = WriterDocument()
        copy.fileType = fileType
        try copy.read(from: sourceBytes, ofType: fileType ?? "net.daringfireball.markdown")
        copy.derivedFrom = session?.snapshot
        copy.updateChangeCount(.changeDone)
        NSDocumentController.shared.addDocument(copy)
        NSFileCoordinator.addFilePresenter(copy)
        return copy
    }

    func refreshWindows() {
        for controller in windowControllers.compactMap({ $0 as? WriterWindowController }) { controller.refreshStatus() }
    }

    @objc func retryRecovery(_ sender: Any?) { recovery?.retry() }


    nonisolated override func read(from data: Data, ofType typeName: String) throws {
        guard let text = String(data: data, encoding: .utf8), data.count <= 8 * 1024 * 1024,
              text.unicodeScalars.count <= 1_000_000 else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        loadedBytes.withLock { $0 = data }
    }

    func acceptScratchEdit(_ text: String) throws {
        // This stage-local scratch adapter is replaced by the attributed gateway in Stage 03.
        let next = Data(text.utf8)
        guard next != sourceBytes else { return }
        guard let session else { throw ContractError.unsupported("The document session has not opened.") }
        let command = EditCommand(id: UUID(), expectedRevision: session.snapshot.revision,
                                  range: try ByteRange(lowerBound: 0, upperBound: session.snapshot.byteCount),
                                  replacement: next, origin: .unknown, undoGroup: UUID())
        try session.apply(command)
        loadedBytes.withLock { $0 = next }
        updateChangeCount(.changeDone)
        recovery?.observe(session.snapshot)
    }
}
