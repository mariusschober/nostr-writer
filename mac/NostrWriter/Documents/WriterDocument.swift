import AppKit
import WriterFoundation
import WriterStorage
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
    private var openingRevision = Revision(0)
    private var selectedScope: SelectedSourceLease?
    private(set) var derivedFrom: SourceSnapshot?
    var textImport: TextImportReceipt?
    private(set) var session: DocumentSession?
    private(set) var recovery: DocumentRecovery?
    var recoveryLibrary: RecoveryLibrary?
    private var recoveryAttachment: Task<Void, Never>?
    private var pendingPreparation: (RecoveryLibrary.Prepared, SourceSnapshot)?
    private(set) var recoveryPreparationError: String?
    private(set) var savedFile: SavedFileRevision?
    private(set) var isSavingSource = false
    private(set) var saveFailed = false
    private var writeSnapshot: SourceSnapshot?
    private var saveChangeToken: Any?
    private nonisolated let writingBytes = OSAllocatedUnfairLock<SourceSnapshot?>(initialState: nil)
    private nonisolated let expectedDiskBytes = OSAllocatedUnfairLock<(URL, Data)?>(initialState: nil)
    lazy var fileLifecycle = DocumentFileLifecycle(document: self)
    lazy var assets = DocumentAssets(document: self)
    private var preparedAssets: DocumentAssets.PreparedSave?
    private var savePausedEditing = false
    private var programmaticOrigin: EditOrigin?
    private struct QueuedSave {
        let url: URL
        let type: String
        let operation: NSDocument.SaveOperationType
        var completions: [(Error?) -> Void]
    }
    private var queuedSaves: [QueuedSave] = []
    private var saveWaiters: [CheckedContinuation<Void, Never>] = []
    private var lifecycleBusy = false
    private var lifecycleWaiters: [CheckedContinuation<Void, Never>] = []
    var isLifecycleTransitionActive: Bool { lifecycleBusy }
    private var preservedRevertSource: SourceSnapshot?
    private var interruptionFlush: Task<Void, Never>?
    var sourceBytes: Data { session?.snapshot.utf8 ?? loadedBytes.withLock { $0 } }
    override class var autosavesInPlace: Bool { false }
    override class var autosavesDrafts: Bool { false }
    nonisolated override var autosavingFileType: String? { nil } // Private drafts use encrypted recovery only.

    override func makeWindowControllers() {
        do {
            if session == nil {
                session = DocumentSession(snapshot: try SourceSnapshot(documentID: documentID, revision: openingRevision, utf8: loadedBytes.withLock { $0 }))
            }
        } catch { presentError(error); return }
        let controller = WriterWindowController(writerDocument: self)
        addWindowController(controller)
        recoveryLibrary = recoveryLibrary ?? (NSApp.delegate as? AppDelegate)?.recoveryLibrary
        attachRecovery()
        if let source = session?.snapshot, let fileURL {
            savedFile = SavedFileRevision(source: source, url: fileURL)
            (NSApp.delegate as? AppDelegate)?.libraryModel.noteRecent(fileURL)
        }
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
        guard !lifecycleBusy || fileLifecycle.isResolving else { completionHandler(CocoaError(.userCancelled)); return }
        if saveOperation == .saveOperation, fileLifecycle.conflict != nil, !fileLifecycle.isResolving {
            completionHandler(DocumentConflictError.needsReview); return
        }
        guard !isSavingSource else {
            // One physical writer, with the newest live revision captured when
            // its turn starts. Distinct destinations retain their order.
            if let last = queuedSaves.indices.last, queuedSaves[last].url == url,
               queuedSaves[last].type == typeName, queuedSaves[last].operation == saveOperation,
               queuedSaves[last].completions.count < 64 {
                queuedSaves[last].completions.append(completionHandler)
            } else if queuedSaves.count < 8 {
                queuedSaves.append(QueuedSave(url: url, type: typeName, operation: saveOperation, completions: [completionHandler]))
            } else { completionHandler(CocoaError(.userCancelled)) }
            return
        }
        isSavingSource = true; saveFailed = false
        writeSnapshot = session?.snapshot
        saveChangeToken = super.changeCountToken(for: saveOperation)
        let sourceToWrite = writeSnapshot
        let relocatesAssets = !assets.records.isEmpty && (saveOperation == .saveAsOperation || fileURL == nil)
        if relocatesAssets { savePausedEditing = true; setLifecycleBusy(true) }
        writingBytes.withLock { $0 = sourceToWrite }
        let expected: Data?
        if let authorized = fileLifecycle.authorizedSave, authorized.url.standardizedFileURL == url.standardizedFileURL {
            expected = authorized.bytes
        } else if let savedFile, savedFile.url.standardizedFileURL == url.standardizedFileURL {
            expected = savedFile.source.utf8
        } else { expected = nil }
        expectedDiskBytes.withLock { $0 = expected.map { (url.standardizedFileURL, $0) } }
        refreshWindows()
        Task { [self] in
            if relocatesAssets, let sourceToWrite {
                do { preparedAssets = try await assets.prepareDestination(url, source: sourceToWrite) }
                catch {
                    finishSaveState(error: error)
                    completionHandler(error); startNextSave(); return
                }
            }
            // Recovery failure must never prevent an emergency ordinary source
            // save. The recovery warning remains separate from file status.
            do { try await flushRecovery(at: .save) } catch { }
            performNativeSave(to: url, ofType: typeName, for: saveOperation, completionHandler: completionHandler)
        }
    }

    nonisolated override func writeSafely(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType) throws {
        if let (_, expected) = expectedDiskBytes.withLock({ $0 }) {
            guard try CoordinatedSourceFiles.readInsideNativeAccessor(url) == expected else { throw DocumentConflictError.changedAgain }
        }
        try super.writeSafely(to: url, ofType: typeName, for: saveOperation)
    }

    nonisolated override func presentedItemDidChange() {
        // Do not let AppKit reload directly into the live editor. Reconcile on
        // the main actor after leaving the presenter callback/coordination.
        Task { @MainActor [weak self] in self?.fileLifecycle.scheduleCheck() }
    }

    override func move(to url: URL, completionHandler: ((Error?) -> Void)?) {
        guard fileURL != nil else { super.move(to: url, completionHandler: completionHandler); return }
        Task {
            do { try await movePreservingSource(to: url); completionHandler?(nil) }
            catch { completionHandler?(error) }
        }
    }

    func movePreservingSource(to destination: URL, grantedAssetFolder: URL? = nil) async throws {
        guard !lifecycleBusy, !isSavingSource, let oldURL = fileURL else { throw CocoaError(.userCancelled) }
        if oldURL.standardizedFileURL.path == destination.standardizedFileURL.path { return }
        setLifecycleBusy(true)
        defer { setLifecycleBusy(false); refreshWindows() }
        try await flushRecovery(at: .save)
        guard fileURL == oldURL, let current = session?.snapshot, let saved = savedFile,
              fileLifecycle.conflict == nil else { throw DocumentConflictError.needsReview }
        let files = CoordinatedSourceFiles()
        let observed = try await files.read(oldURL, excluding: self)
        guard observed.bytes == saved.source.utf8 else { throw DocumentConflictError.changedAgain }
        let copiedAssets = try await assets.prepareDestination(destination, source: current,
            additionalSources: [saved.source], grantedFolder: grantedAssetFolder)
        let moved = try await files.move(observed, to: destination, excluding: self)
        // The physical move has completed. Adopt its location even when later
        // metadata/directory durability fails; never claim the old path remains.
        fileURL = moved.file.url; fileModificationDate = moved.file.modificationDate
        savedFile = SavedFileRevision(source: saved.source, url: moved.file.url)
        assets.apply(copiedAssets)
        if let savedFile {
            recovery?.acknowledgeSave(savedFile, parent: derivedFrom, assets: assets.records, assetFolderBookmark: assets.folderBookmark)
        }
        do { try await flushRecovery(at: .save) }
        catch { recoveryPreparationError = "The file moved, but its private recovery location could not be updated. Keep this document open and retry recovery." }
        if !moved.durabilityConfirmed {
            recoveryPreparationError = "The file moved, but the destination could not confirm durable storage. Keep this document open and save another copy."
        }
        if let model = (NSApp.delegate as? AppDelegate)?.libraryModel {
            model.removeRecent(oldURL); model.noteRecent(moved.file.url); model.refresh()
        }
    }

    nonisolated override func presentedItemDidMove(to newURL: URL) {
        super.presentedItemDidMove(to: newURL)
        Task { @MainActor [weak self] in
            guard let self, let saved = self.savedFile, self.fileURL == newURL else { return }
            self.savedFile = SavedFileRevision(source: saved.source, url: newURL)
            self.recovery?.acknowledgeSave(self.savedFile!, parent: self.derivedFrom,
                assets: self.assets.records, assetFolderBookmark: self.assets.folderBookmark)
            self.fileLifecycle.scheduleCheck(); self.refreshWindows()
        }
    }

    @objc func moveSourceToTrash(_ sender: Any?) {
        guard fileURL != nil, !lifecycleBusy, !isSavingSource else { return }
        let alert = NSAlert(); alert.messageText = "Move this document to Trash?"
        alert.informativeText = "Your current writing, including unsaved changes, will first be preserved in Recovered drafts. Image files and private history will remain where they are."
        alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Move to Trash")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        Task {
            do { _ = try await trashPreservingRecovery() }
            catch {
                let failure = NSAlert(); failure.messageText = "The document was kept open"
                failure.informativeText = "The file or its recovery could not be safely moved to Trash. Review external changes or save a separate copy, then try again."
                failure.addButton(withTitle: "Back to Writing"); failure.runModal()
            }
        }
    }

    @discardableResult
    func trashPreservingRecovery() async throws -> URL? {
        guard !lifecycleBusy, !isSavingSource, let originalURL = fileURL, let library = recoveryLibrary else { throw SourceAccessError.unavailable }
        setLifecycleBusy(true)
        defer { setLifecycleBusy(false) }
        try await flushRecovery(at: .close)
        guard fileURL == originalURL, let source = session?.snapshot, let saved = savedFile,
              fileLifecycle.conflict == nil else { throw DocumentConflictError.needsReview }
        let files = CoordinatedSourceFiles()
        let observed = try await files.read(originalURL, excluding: self)
        guard observed.bytes == saved.source.utf8 else { throw DocumentConflictError.changedAgain }
        try await RecoveryDeadline.run { try await library.preserveCopy(source, title: "Before Trash — \(self.displayName ?? "Untitled")") }
        let trashed = try await files.trash(observed, excluding: self)
        fileURL = nil; savedFile = nil
        do {
            try await library.recordTrashed(source.documentID)
            updateChangeCount(.changeCleared)
            if let model = (NSApp.delegate as? AppDelegate)?.libraryModel { model.removeRecent(originalURL); model.refresh() }
            close()
        } catch {
            // Trash already succeeded; leave an editable unsaved document when
            // catalog updates fail, and never report the physical move as undone.
            updateChangeCount(.changeDone)
            recoveryPreparationError = "The source file is in Trash. Your writing is still open because its private library entry could not be updated."
            refreshWindows()
        }
        return trashed
    }

    private func performNativeSave(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
                                   completionHandler: @escaping (Error?) -> Void) {
        super.save(to: url, ofType: typeName, for: saveOperation) { [self] error in
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
                        self.recoveryAttachment?.cancel()
                        self.pendingPreparation = nil
                        if let library = self.recoveryLibrary {
                            self.recovery = DocumentRecovery(source: replacement, library: library)
                            self.recovery?.didChange = { [weak self] in self?.refreshWindows() }
                        }
                    } catch {
                        self.finishSaveState(error: error)
                        completionHandler(error); self.startNextSave(); return
                    }
                }
                if let preparedAssets = self.preparedAssets { self.assets.apply(preparedAssets) }
                let saved = SavedFileRevision(source: savedSource, url: url)
                self.savedFile = saved
                if saveOperation == .saveAsOperation { self.fileLifecycle.didSaveAs() }
                (NSApp.delegate as? AppDelegate)?.libraryModel.noteRecent(url)
                self.recovery?.acknowledgeSave(saved, parent: self.derivedFrom, assets: self.assets.records, assetFolderBookmark: self.assets.folderBookmark)
            }
            self.finishSaveState(error: error)
            completionHandler(error)
            self.startNextSave()
            if error != nil { self.fileLifecycle.scheduleCheck() }
        }
    }

    private func finishSaveState(error: Error?) {
        isSavingSource = false; saveFailed = error != nil; writeSnapshot = nil; saveChangeToken = nil
        writingBytes.withLock { $0 = nil }; expectedDiskBytes.withLock { $0 = nil }
        preparedAssets = nil
        if savePausedEditing { savePausedEditing = false; setLifecycleBusy(false) }
        applyPreparedRecovery(); refreshWindows()
    }

    private func startNextSave() {
        guard !isSavingSource else { return }
        if !queuedSaves.isEmpty {
            let next = queuedSaves.removeFirst()
            save(to: next.url, ofType: next.type, for: next.operation) { error in
                for completion in next.completions { completion(error) }
            }
        } else {
            let waiters = saveWaiters; saveWaiters.removeAll()
            for waiter in waiters { waiter.resume() }
        }
    }

    func awaitSourceSaves() async {
        guard isSavingSource || !queuedSaves.isEmpty else { return }
        await withCheckedContinuation { saveWaiters.append($0) }
    }

    override func revert(toContentsOf url: URL, ofType typeName: String) throws {
        guard let source = session?.snapshot, source == preservedRevertSource else {
            throw RecoveryKeyError.unavailable("Preserve the current writing before reverting. Use File → Revert to Saved.")
        }
        preservedRevertSource = nil
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
        fileLifecycle.scheduleCheck()
    }

    func revertPreservingRecovery(to url: URL, ofType typeName: String) async throws {
        guard !lifecycleBusy, !isSavingSource, let source = session?.snapshot, let library = recoveryLibrary else {
            throw RecoveryKeyError.unavailable("Revert is unavailable. Keep this document open or save a separate copy first.")
        }
        setLifecycleBusy(true)
        defer { preservedRevertSource = nil; setLifecycleBusy(false) }
        try await RecoveryDeadline.run {
            try await library.preserveCopy(source, title: "Before Revert — \(self.displayName ?? "Untitled")")
        }
        guard session?.snapshot == source else { throw CocoaError(.userCancelled) }
        preservedRevertSource = source
        try revert(toContentsOf: url, ofType: typeName)
        (NSApp.delegate as? AppDelegate)?.libraryModel.refresh()
    }

    @objc func revertPreservingChanges(_ sender: Any?) {
        guard let fileURL, let fileType, !lifecycleBusy, !isSavingSource else { return }
        let alert = NSAlert()
        alert.messageText = "Revert to the saved file?"
        alert.informativeText = "Your current writing will be kept in Recovered drafts before the saved file replaces it."
        alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Revert")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        Task {
            do { try await revertPreservingRecovery(to: fileURL, ofType: fileType) }
            catch {
                let failure = NSAlert(); failure.messageText = "Your writing was kept open"
                failure.informativeText = "Recovery could not safely preserve your current writing. Save a separate copy before trying Revert again."
                failure.addButton(withTitle: "Back to Writing"); failure.runModal()
            }
        }
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if [Selector(("renameDocument:")), Selector(("moveDocument:")), #selector(moveSourceToTrash(_:))].contains(item.action) {
            return fileURL != nil && !lifecycleBusy && !isSavingSource
        }
        if item.action == #selector(revertPreservingChanges(_:)) { return fileURL != nil && !lifecycleBusy && !isSavingSource }
        if item.action == #selector(insertImage(_:)) { return fileURL != nil && !lifecycleBusy && !isSavingSource }
        if item.action == #selector(revealInFinder(_:)) { return fileURL != nil }
        return super.validateUserInterfaceItem(item)
    }

    @objc func insertImage(_ sender: Any?) { assets.chooseImage() }

    @objc func revealInFinder(_ sender: Any?) {
        if let fileURL { NSWorkspace.shared.activateFileViewerSelecting([fileURL]) }
    }

    func setLifecycleBusy(_ busy: Bool) {
        lifecycleBusy = busy
        for controller in windowControllers.compactMap({ $0 as? WriterWindowController }) { controller.editor.isEditable = !busy }
        if !busy {
            fileLifecycle.resumeAfterTransition()
            let waiters = lifecycleWaiters; lifecycleWaiters.removeAll()
            for waiter in waiters { waiter.resume() }
        }
    }

    func flushRecovery(at boundary: ObservationBoundary) async throws {
        try await RecoveryDeadline.run { [self] in
            await awaitRecoveryAttachment()
            guard let recovery, let source = session?.snapshot else {
                throw RecoveryKeyError.unavailable("Recovery is unavailable. Save your writing to a file.")
            }
            try await recovery.flush(source, boundary: boundary)
        }
    }

    func checkpointForInterruption(_ boundary: ObservationBoundary) {
        guard interruptionFlush == nil else { return }
        interruptionFlush = Task { [weak self] in
            guard let self else { return }
            defer { self.interruptionFlush = nil }
            do { try await self.flushRecovery(at: boundary) } catch { }
        }
    }

    override func canClose(withDelegate delegate: Any, shouldClose shouldCloseSelector: Selector?, contextInfo: UnsafeMutableRawPointer?) {
        // This path also participates in NSDocumentController's ordinary quit
        // negotiation. Keep AppKit's Save/Discard/Cancel decision intact.
        Task { [self] in
            if lifecycleBusy { await withCheckedContinuation { lifecycleWaiters.append($0) } }
            await awaitSourceSaves()
            setLifecycleBusy(true)
            do { try await flushRecovery(at: .close) } catch { }
            setLifecycleBusy(false)
            continueNativeClose(withDelegate: delegate, shouldClose: shouldCloseSelector, contextInfo: contextInfo)
        }
    }

    private func continueNativeClose(withDelegate delegate: Any, shouldClose selector: Selector?, contextInfo: UnsafeMutableRawPointer?) {
        super.canClose(withDelegate: delegate, shouldClose: selector, contextInfo: contextInfo)
    }

    override func close() {
        fileLifecycle.stop()
        interruptionFlush?.cancel(); recovery?.stop(); recoveryAttachment?.cancel()
        if let id = session?.snapshot.documentID, let library = recoveryLibrary {
            Task { try? await library.markClosed(id) }
        }
        super.close()
    }

    override func duplicate() throws -> NSDocument {
        let copy = WriterDocument()
        copy.fileType = fileType
        try copy.read(from: sourceBytes, ofType: fileType ?? "net.daringfireball.markdown")
        copy.derivedFrom = session?.snapshot
        copy.recoveryLibrary = recoveryLibrary
        copy.assets.inherit(from: assets)
        copy.updateChangeCount(.changeDone)
        NSDocumentController.shared.addDocument(copy)
        NSFileCoordinator.addFilePresenter(copy)
        return copy
    }

    func restoreRecoveredSource(_ source: SourceSnapshot, title: String, asCopy: Bool = false) throws {
        let restored: SourceSnapshot
        if asCopy {
            restored = try SourceSnapshot(documentID: DocumentID(), revision: Revision(0), utf8: source.utf8)
            derivedFrom = source
        } else { restored = source }
        documentID = restored.documentID; openingRevision = restored.revision
        let bytes = restored.utf8; loadedBytes.withLock { $0 = bytes }
        displayName = title; updateChangeCount(.changeDone)
    }

    func retainSelectedScope(_ lease: SelectedSourceLease) { selectedScope = lease }

    func applyExternalSource(_ external: SourceFileRead) throws {
        guard let session else { throw CocoaError(.fileReadUnknown) }
        try session.apply(EditCommand(id: UUID(), expectedRevision: session.snapshot.revision,
            range: try ByteRange(lowerBound: 0, upperBound: session.snapshot.byteCount),
            replacement: external.bytes, origin: .externalReload, undoGroup: UUID()))
        let bytes = external.bytes; loadedBytes.withLock { $0 = bytes }
        savedFile = SavedFileRevision(source: session.snapshot, url: external.url)
        fileModificationDate = external.modificationDate
        updateChangeCount(.changeCleared)
        undoManager?.removeAllActions()
        recovery?.observe(session.snapshot)
        if let savedFile { recovery?.acknowledgeSave(savedFile, parent: derivedFrom, assets: assets.records, assetFolderBookmark: assets.folderBookmark) }
        for controller in windowControllers.compactMap({ $0 as? WriterWindowController }) { controller.reloadSource() }
        refreshWindows()
    }

    func refreshWindows() {
        for controller in windowControllers.compactMap({ $0 as? WriterWindowController }) { controller.refreshStatus() }
    }

    @objc func retryRecovery(_ sender: Any?) {
        recoveryPreparationError = nil
        if let recovery {
            recovery.retry()
            if let savedFile {
                recovery.acknowledgeSave(savedFile, parent: derivedFrom, assets: assets.records, assetFolderBookmark: assets.folderBookmark)
            }
        } else { attachRecovery(retry: true) }
    }

    func awaitRecoveryAttachment() async { await recoveryAttachment?.value }

    private func attachRecovery(retry: Bool = false) {
        guard let initial = session?.snapshot, let library = recoveryLibrary else { return }
        recoveryAttachment?.cancel()
        recoveryPreparationError = nil
        let url = fileURL, parent = derivedFrom, textImport = textImport, title = displayName
        let initialAssets = assets.records.isEmpty ? nil : assets.records, initialAssetBookmark = assets.folderBookmark
        recoveryAttachment = Task { [weak self] in
            do {
                if retry { _ = try await library.store(retry: true) }
                let prepared = try await library.prepare(initial, url: url, parent: parent, textImport: textImport, title: title, assets: initialAssets, assetFolderBookmark: initialAssetBookmark)
                guard let self, !Task.isCancelled else { return }
                self.pendingPreparation = (prepared, initial)
                self.applyPreparedRecovery()
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.recoveryPreparationError = "Recovery is unavailable. Save your document to a file; your text remains editable."
                self.refreshWindows()
            }
        }
    }

    private func applyPreparedRecovery() {
        guard !isSavingSource, let (prepared, initial) = pendingPreparation,
              let current = session?.snapshot, current.documentID == initial.documentID,
              let library = recoveryLibrary else { return }
        pendingPreparation = nil
        do {
            let delta = current.revision.rawValue - initial.revision.rawValue
            let (revision, overflow) = prepared.source.revision.rawValue.addingReportingOverflow(delta)
            guard !overflow else { throw ContractError.unsupported("The document revision limit was reached.") }
            let rebound = try SourceSnapshot(documentID: prepared.source.documentID, revision: Revision(revision), utf8: current.utf8)
            // Only identity/revision changes here; the editor and its undo history
            // retain all edits that arrived while the private store was opening.
            documentID = rebound.documentID
            session = DocumentSession(snapshot: rebound)
            if let saved = savedFile, saved.source.documentID == initial.documentID,
               saved.source.revision >= initial.revision {
                let savedDelta = saved.source.revision.rawValue - initial.revision.rawValue
                let (savedRevision, savedOverflow) = prepared.source.revision.rawValue.addingReportingOverflow(savedDelta)
                guard !savedOverflow else { throw ContractError.unsupported("The document revision limit was reached.") }
                savedFile = SavedFileRevision(source: try SourceSnapshot(documentID: documentID,
                    revision: Revision(savedRevision), utf8: saved.source.utf8), url: saved.url)
            }
            assets.restore(prepared.record)
            recovery = DocumentRecovery(source: rebound, library: library)
            recovery?.didChange = { [weak self] in self?.refreshWindows() }
            if let savedFile { recovery?.acknowledgeSave(savedFile, parent: derivedFrom, assets: assets.records, assetFolderBookmark: assets.folderBookmark) }
            recoveryPreparationError = nil
        } catch { recoveryPreparationError = "Recovery could not attach safely. Save your document to a file." }
        refreshWindows()
    }


    nonisolated override func read(from data: Data, ofType typeName: String) throws {
        guard data.count <= 8 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
        guard SourceSnapshot.firstInvalidUTF8Offset(in: data) == nil else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadInapplicableStringEncodingError,
                userInfo: [NSLocalizedDescriptionKey: "This file is not valid UTF-8.",
                           NSLocalizedRecoverySuggestionErrorKey: "Use File → Import Text Copy… to choose its encoding and review a new copy. The original file will stay unchanged."])
        }
        guard String(decoding: data, as: UTF8.self).unicodeScalars.count <= 1_000_000 else { throw CocoaError(.fileReadTooLarge) }
        loadedBytes.withLock { $0 = data }
    }

    func insertManagedImageLink(_ link: String, at selection: NSRange, expecting source: SourceSnapshot) throws {
        guard !lifecycleBusy, session?.snapshot == source,
              let editor = (windowControllers.first as? WriterWindowController)?.editor else { throw CocoaError(.userCancelled) }
        _ = try source.byteRange(for: NativeRange(location: selection.location, length: selection.length))
        editor.breakUndoCoalescing()
        programmaticOrigin = .formatting
        defer { programmaticOrigin = nil; editor.breakUndoCoalescing() }
        editor.insertText(link, replacementRange: selection)
        guard session?.snapshot != source else { throw CocoaError(.userCancelled) }
    }

    func acceptScratchEdit(_ text: String) throws {
        guard !lifecycleBusy else { throw CocoaError(.userCancelled) }
        // This stage-local scratch adapter is replaced by the attributed gateway in Stage 03.
        let next = Data(text.utf8)
        guard next != sourceBytes else { return }
        guard let session else { throw ContractError.unsupported("The document session has not opened.") }
        let command = EditCommand(id: UUID(), expectedRevision: session.snapshot.revision,
                                  range: try ByteRange(lowerBound: 0, upperBound: session.snapshot.byteCount),
                                  replacement: next, origin: programmaticOrigin ?? .unknown, undoGroup: UUID())
        try session.apply(command)
        loadedBytes.withLock { $0 = next }
        updateChangeCount(.changeDone)
        recovery?.observe(session.snapshot)
    }
}
