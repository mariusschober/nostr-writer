import AppKit
import WriterFoundation
import WriterStorage

enum DocumentConflictError: LocalizedError, Sendable {
    case needsReview, changedAgain, unavailable, cancelled
    var errorDescription: String? {
        switch self {
        case .needsReview: "This file has external changes. Review both versions before saving over it, or use Save As to keep a separate copy."
        case .changedAgain: "The file changed again. Your writing remains open; review the new external version before replacing it."
        case .unavailable: "Both versions could not be preserved safely. Your writing remains open. Save As can keep a separate source copy."
        case .cancelled: "The operation was cancelled. Both versions remain unchanged."
        }
    }
}

@MainActor
final class DocumentFileLifecycle {
    struct Conflict {
        let external: SourceFileRead
        let observedAt: Date
    }
    enum Resolution { case keepBoth, keepLocal, openExternalCopy }

    private weak var document: WriterDocument?
    private let files = CoordinatedSourceFiles()
    private var checkTask: Task<Void, Never>?
    private var needsCheck = false
    private var stopped = false
    private(set) var conflict: Conflict?
    private(set) var issue: String?
    private(set) var isResolving = false
    private(set) var authorizedSave: SourceFileRead?

    init(document: WriterDocument) { self.document = document }

    func didSaveAs() {
        // The new source file has its own identity; an old-location conflict
        // remains preserved there and must not block saves of this new file.
        conflict = nil; issue = nil
    }

    func scheduleCheck() {
        guard !stopped else { return }
        needsCheck = true
        guard checkTask == nil, !isResolving else { return }
        checkTask = Task { [weak self] in
            guard let self else { return }
            while self.needsCheck, !Task.isCancelled, !self.stopped {
                guard self.document?.isLifecycleTransitionActive != true else { break }
                self.needsCheck = false
                do { try await self.checkForChanges() }
                catch { self.issue = Self.message(for: error); self.document?.refreshWindows() }
            }
            self.checkTask = nil
        }
    }

    func resumeAfterTransition() { if needsCheck { scheduleCheck() } }

    func checkForChanges() async throws {
        guard let document, !stopped, !isResolving else { return }
        await document.awaitSourceSaves()
        guard !document.isLifecycleTransitionActive else { needsCheck = true; return }
        guard let url = document.fileURL else { return }
        let external = try await files.read(url, excluding: document)
        guard !stopped, document.fileURL == url, let current = document.session?.snapshot else { return }
        guard !document.isLifecycleTransitionActive else { needsCheck = true; return }
        issue = nil
        // Byte comparison, not notification timing or Unicode string equality:
        // providers may deliver our own notification after a later local edit.
        if external.bytes == document.savedFile?.source.utf8 {
            conflict = nil; document.refreshWindows(); return
        }
        if conflict == nil, document.savedFile?.source == current,
           document.session?.recordingState == .off, !document.isDocumentEdited,
           let library = document.recoveryLibrary {
            do {
                try await RecoveryDeadline.run { try await library.preserveCopy(current, title: "Before External Change — \(document.displayName ?? "Untitled")") }
                if document.session?.snapshot == current, !document.isSavingSource, !document.isLifecycleTransitionActive, !stopped {
                    try document.applyExternalSource(external)
                    document.refreshWindows(); return
                }
            } catch { issue = "External changes need review. Recovery could not preserve the previous version." }
        }
        conflict = Conflict(external: external, observedAt: Date())
        document.refreshWindows()
    }

    /// The caller's explicit choice applies to the displayed external bytes.
    /// Editing is paused only during this bounded preservation/transition.
    @discardableResult
    func resolve(_ choice: Resolution, copyURL: URL? = nil, displayCopies: Bool = true) async throws -> WriterDocument? {
        guard let document, let conflict, let url = document.fileURL,
              let library = document.recoveryLibrary, !isResolving, !document.isSavingSource, !document.isLifecycleTransitionActive,
              let local = document.session?.snapshot else { throw DocumentConflictError.unavailable }
        if choice == .keepBoth, copyURL == nil { throw DocumentConflictError.cancelled }
        isResolving = true; document.setLifecycleBusy(true)
        defer {
            authorizedSave = nil; isResolving = false; document.setLifecycleBusy(false)
            document.refreshWindows()
            if needsCheck { scheduleCheck() }
        }
        let latest = try await files.read(url, excluding: document)
        guard latest.bytes == conflict.external.bytes else {
            self.conflict = Conflict(external: latest, observedAt: Date())
            throw DocumentConflictError.changedAgain
        }
        let imported = try SourceSnapshot(documentID: DocumentID(), revision: Revision(0), utf8: latest.bytes)
        try await RecoveryDeadline.run {
            try await library.preserveCopy(local, title: "Local Conflict — \(document.displayName ?? "Untitled")")
            try await library.preserveCopy(imported, title: "External Conflict — \(document.displayName ?? "Untitled")")
        }
        guard document.session?.snapshot == local else { throw DocumentConflictError.changedAgain }
        switch choice {
        case .keepBoth:
            guard let copyURL else { throw DocumentConflictError.cancelled }
            let copy = try makeCopy(local, title: datedCopyName(), document: document)
            // A new destination is mandatory; this never overwrites a file.
            _ = try await files.create(local, at: copyURL)
            copy.fileURL = copyURL
            copy.updateChangeCount(.changeCleared)
            try document.applyExternalSource(latest)
            self.conflict = nil; issue = nil
            register(copy, display: displayCopies)
            return copy
        case .keepLocal:
            authorizedSave = latest
            document.fileModificationDate = latest.modificationDate
            // NSDocument still owns coordination and atomic replacement. The
            // write accessor compares these exact bytes again inside its lock.
            try await document.save(to: url, ofType: document.fileType ?? "net.daringfireball.markdown", for: .saveOperation)
            self.conflict = nil; issue = nil
            return nil
        case .openExternalCopy:
            let copy = try makeCopy(imported, title: "External — \(document.displayName ?? "Untitled")", document: document)
            register(copy, display: displayCopies)
            // The original stays dirty and still requires a replacement choice.
            return copy
        }
    }

    private func makeCopy(_ source: SourceSnapshot, title: String, document: WriterDocument) throws -> WriterDocument {
        let copy = WriterDocument(); copy.fileType = document.fileType ?? "net.daringfireball.markdown"
        copy.recoveryLibrary = document.recoveryLibrary
        try copy.restoreRecoveredSource(source, title: title, asCopy: true)
        return copy
    }

    private func register(_ copy: WriterDocument, display: Bool) {
        NSDocumentController.shared.addDocument(copy)
        NSFileCoordinator.addFilePresenter(copy)
        copy.makeWindowControllers()
        if display { copy.showWindows() }
        (NSApp.delegate as? AppDelegate)?.libraryModel.refresh()
    }

    func presentReview() {
        guard let document, let conflict, let window = document.windowControllers.first?.window,
              window.attachedSheet == nil, !isResolving else { return }
        let alert = NSAlert()
        alert.messageText = "External changes need review"
        alert.informativeText = "The file changed outside Nostr Writer. Both exact versions will be kept in local recovery before your choice is applied. Keep Both saves your writing as a separate file and leaves the external file in place.\n\nExternal version observed \(conflict.observedAt.formatted(date: .abbreviated, time: .standard)). Times do not determine which version wins."
        alert.accessoryView = comparison(local: document.sourceBytes, external: conflict.external.bytes)
        alert.addButton(withTitle: "Keep Both…")
        alert.addButton(withTitle: "Keep Local")
        alert.addButton(withTitle: "Open External Copy")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[3].keyEquivalent = "\u{1b}"
        alert.beginSheetModal(for: window) { [weak self] result in
            guard let self else { return }
            switch result {
            case .alertFirstButtonReturn: self.chooseCopyDestination()
            case .alertSecondButtonReturn: self.perform(.keepLocal)
            case .alertThirdButtonReturn: self.perform(.openExternalCopy)
            default: break
            }
        }
    }

    private func chooseCopyDestination() {
        guard let document, let window = document.windowControllers.first?.window else { return }
        let panel = NSSavePanel(); panel.title = "Keep Both Versions"
        panel.nameFieldStringValue = datedCopyName()
        panel.message = "Choose a new file for your local writing. The externally changed file stays in place."
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.chooseCopyFolder(for: url)
        }
    }

    private func chooseCopyFolder(for destination: URL) {
        // Our no-overwrite atomic copy creates a temporary sibling before
        // installing the new file. A Save-panel grant covers the selected file,
        // not arbitrary siblings in a sandboxed File Provider folder.
        let folder = destination.deletingLastPathComponent()
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false; panel.directoryURL = folder
        panel.title = "Allow Conflict Copy in Folder"
        panel.message = "Select the destination folder to safely create “\(destination.lastPathComponent)”. Both existing versions remain unchanged if you cancel."
        panel.begin { [weak self] response in
            guard response == .OK, let selected = panel.url, let self else { return }
            guard selected.standardizedFileURL.resolvingSymlinksInPath().path == folder.standardizedFileURL.resolvingSymlinksInPath().path else {
                NSApp.presentError(SourceFileError.permissionDenied); return
            }
            let lease = selected.startAccessingSecurityScopedResource() ? SelectedSourceLease(acquired: selected) : nil
            self.perform(.keepBoth, copyURL: destination, destinationLease: lease)
        }
    }

    private func perform(_ choice: Resolution, copyURL: URL? = nil, destinationLease: SelectedSourceLease? = nil) {
        Task {
            do {
                let copy = try await resolve(choice, copyURL: copyURL)
                // Keep the explicit grant through asynchronous bookmark setup
                // and the resulting document session; its close releases it.
                if let destinationLease { copy?.retainSelectedScope(destinationLease) }
            }
            catch {
                let alert = NSAlert(); alert.messageText = "Your writing was kept open"
                alert.informativeText = (error as? DocumentConflictError)?.errorDescription ?? Self.message(for: error)
                alert.addButton(withTitle: "Back to Writing"); alert.runModal()
            }
        }
    }

    private func datedCopyName() -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        let url = document?.fileURL
        return "\(url?.deletingPathExtension().lastPathComponent ?? "Untitled") (Conflict \(formatter.string(from: Date()))).\(url?.pathExtension ?? "md")"
    }

    private func comparison(local: Data, external: Data) -> NSView {
        let stack = NSStackView(); stack.orientation = .horizontal; stack.spacing = 12
        for (title, bytes) in [("Your current writing", local), ("External file", external)] {
            let label = NSTextField(labelWithString: "\(title) · \(bytes.count) bytes")
            let text = NSTextView(usingTextLayoutManager: true); text.isEditable = false; text.isSelectable = true
            text.frame = NSRect(x: 0, y: 0, width: 260, height: 180)
            text.minSize = NSSize(width: 0, height: 180)
            text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            text.isRichText = false; text.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            // Bounded visual comparison only; stored/resolved sources stay exact.
            let preview = String(String(decoding: bytes, as: UTF8.self).prefix(24_000))
            text.string = preview + (preview.utf8.count < bytes.count ? "\n[Preview truncated; the complete source is preserved.]" : "")
            text.setAccessibilityLabel(title)
            let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.documentView = text
            text.isVerticallyResizable = true; text.autoresizingMask = [.width]
            text.textContainer?.widthTracksTextView = true
            let column = NSStackView(views: [label, scroll]); column.orientation = .vertical; column.alignment = .leading
            stack.addArrangedSubview(column)
            scroll.widthAnchor.constraint(equalToConstant: 260).isActive = true
            scroll.heightAnchor.constraint(equalToConstant: 180).isActive = true
        }
        return stack
    }

    private static func message(for error: Error) -> String {
        switch error as? SourceFileError {
        case .missing: "The source file is unavailable. Locate it or save a separate copy; your writing remains open."
        case .permissionDenied: "Access to the source file was denied. Open it again to grant access or save a separate copy."
        case .invalidUTF8, .sourceTooLarge, .notRegularFile: "The external file cannot be opened as supported UTF-8 source. Your writing remains unchanged."
        default: "The file or encrypted recovery is unavailable. Both versions were left in place. Save As can keep your writing in a separate file."
        }
    }

    func stop() { stopped = true; checkTask?.cancel(); checkTask = nil }
}
