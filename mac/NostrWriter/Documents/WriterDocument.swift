import AppKit
import WriterFoundation
import os

@MainActor
final class WriterDocument: NSDocument {
    // NSDocument may call read on its loading executor. This buffer only transfers
    // decoded source into the main-actor live editor; no UI or capture state lives here.
    private nonisolated let loadedBytes = OSAllocatedUnfairLock(initialState: Data())
    private let documentID = DocumentID()
    private(set) var session: DocumentSession?
    var sourceBytes: Data { session?.snapshot.utf8 ?? loadedBytes.withLock { $0 } }
    override class var autosavesInPlace: Bool { false } // Stage 02 installs durable recovery before autosave.

    override func makeWindowControllers() {
        do {
            session = DocumentSession(snapshot: try SourceSnapshot(documentID: documentID, revision: Revision(0), utf8: loadedBytes.withLock { $0 }))
        } catch { presentError(error); return }
        let controller = WriterWindowController(writerDocument: self)
        addWindowController(controller)
    }

    override func data(ofType typeName: String) throws -> Data { sourceBytes }

    override func read(from data: Data, ofType typeName: String) throws {
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
    }
}
