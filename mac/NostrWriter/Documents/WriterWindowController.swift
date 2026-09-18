import AppKit
import SwiftUI

@MainActor
final class WriterWindowController: NSWindowController, NSToolbarDelegate, NSTextViewDelegate, NSWindowDelegate {
    let writerDocument: WriterDocument
    let editor = NSTextView(usingTextLayoutManager: true)
    private let split = NSSplitView()
    private let sidebar: NSHostingView<WriterLibrarySidebar>
    private let wordCount = NSTextField(labelWithString: "0 words")
    private let recoveryWarning = NSTextField(labelWithString: "")
    private let retryRecovery = NSButton(title: "Retry Recovery", target: nil, action: nil)
    private let reviewChanges = NSButton(title: "Review Changes", target: nil, action: nil)
    private let history = NSTextField(labelWithString: "Recording off")
    private let consent = RecordingConsent()
    private let placeholder = NSTextField(labelWithString: "Write what you think.")

    init(writerDocument: WriterDocument) {
        self.writerDocument = writerDocument
        let library = (NSApp.delegate as? AppDelegate)?.libraryModel
            ?? WriterLibraryModel(recovery: writerDocument.recoveryLibrary ?? RecoveryLibrary())
        self.sidebar = NSHostingView(rootView: WriterLibrarySidebar(model: library))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 760),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Untitled"
        window.tabbingMode = .preferred
        super.init(window: window)
        window.delegate = self
        setupContent(window)
        for name in [Notification.Name.NSUndoManagerDidUndoChange, Notification.Name.NSUndoManagerDidRedoChange] {
            NotificationCenter.default.addObserver(self, selector: #selector(nativeUndoCompleted(_:)), name: name, object: writerDocument.undoManager)
        }
        // AppKit chooses the initial key view when ordering the window. Setting
        // only firstResponder in showWindow can be overwritten by that step.
        window.initialFirstResponder = editor
        let toolbar = NSToolbar(identifier: "WriterToolbar")
        toolbar.delegate = self; toolbar.displayMode = .iconOnly
        window.toolbar = toolbar; window.toolbarStyle = .unified
        window.center()
        window.contentView?.layoutSubtreeIfNeeded()
        // AppKit ignores minSize with Auto Layout. Constrain the content to the
        // required outer frame after accounting for the actual native toolbar.
        let chromeHeight = window.frame.height - window.contentLayoutRect.height
        if let content = window.contentView {
            NSLayoutConstraint.activate([
                content.widthAnchor.constraint(greaterThanOrEqualToConstant: 760),
                content.heightAnchor.constraint(greaterThanOrEqualToConstant: 520 - chromeHeight)
            ])
        }
        window.setFrame(NSRect(origin: window.frame.origin, size: NSSize(width: 1120, height: 760)), display: false)
    }
    required init?(coder: NSCoder) { nil }
    deinit { NotificationCenter.default.removeObserver(self) }

    func windowDidResignKey(_ notification: Notification) { writerDocument.checkpointForInterruption(.interruption) }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeFirstResponder(editor)
        if !consent.hasChosen { showRecordingConsent() }
    }

    private func setupContent(_ window: NSWindow) {
        let root = NSView(); window.contentView = root
        split.isVertical = true; split.dividerStyle = .thin
        split.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(split)
        sidebar.setAccessibilityLabel("Document sidebar")
        sidebar.frame = NSRect(x: 0, y: 0, width: 232, height: 700)
        split.addArrangedSubview(sidebar)
        let writing = NSView(); writing.setContentHuggingPriority(.defaultLow, for: .horizontal)
        split.addArrangedSubview(writing)
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.drawsBackground = false; scroll.translatesAutoresizingMaskIntoConstraints = false
        editor.isRichText = false; editor.importsGraphics = false
        editor.allowsUndo = true; editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]; editor.minSize = NSSize(width: 0, height: 0)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: 720, height: CGFloat.greatestFiniteMagnitude)
        editor.font = .monospacedSystemFont(ofSize: 18, weight: .regular)
        editor.textColor = .textColor; editor.backgroundColor = .textBackgroundColor
        editor.textContainerInset = NSSize(width: 40, height: 32)
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 9
        editor.defaultParagraphStyle = paragraph
        editor.isContinuousSpellCheckingEnabled = true
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextCompletionEnabled = false
        if #available(macOS 15.0, *) { editor.writingToolsBehavior = .none }
        editor.usesFindBar = true
        editor.setAccessibilityLabel("Markdown editor")
        editor.setAccessibilityIdentifier("markdown-editor")
        // Bytes were validated on import. The decoding initializer preserves an
        // initial U+FEFF rather than treating the UTF-8 BOM as a removable marker.
        editor.string = String(decoding: writerDocument.sourceBytes, as: UTF8.self)
        editor.delegate = self
        scroll.documentView = editor; writing.addSubview(scroll)
        placeholder.font = .monospacedSystemFont(ofSize: 18, weight: .regular)
        placeholder.textColor = .placeholderTextColor
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        placeholder.setAccessibilityElement(false)
        writing.addSubview(placeholder)
        retryRecovery.target = writerDocument; retryRecovery.action = #selector(WriterDocument.retryRecovery(_:))
        retryRecovery.bezelStyle = .inline; retryRecovery.isHidden = true
        reviewChanges.target = self; reviewChanges.action = #selector(reviewExternalChanges(_:))
        reviewChanges.bezelStyle = .inline; reviewChanges.isHidden = true
        let status = NSStackView(views: [wordCount, NSView(), reviewChanges, retryRecovery, history])
        status.orientation = .horizontal; status.spacing = 16; status.translatesAutoresizingMaskIntoConstraints = false
        wordCount.font = .systemFont(ofSize: 12); wordCount.textColor = .secondaryLabelColor
        history.font = .systemFont(ofSize: 12); history.textColor = .secondaryLabelColor
        root.addSubview(status)
        recoveryWarning.translatesAutoresizingMaskIntoConstraints = false
        recoveryWarning.font = .systemFont(ofSize: 11)
        recoveryWarning.textColor = .secondaryLabelColor
        recoveryWarning.setAccessibilityIdentifier("recovery-warning")
        root.addSubview(recoveryWarning)
        NSLayoutConstraint.activate([
            split.leadingAnchor.constraint(equalTo: root.leadingAnchor), split.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            split.topAnchor.constraint(equalTo: root.topAnchor), split.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -8),
            status.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            status.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            status.bottomAnchor.constraint(equalTo: recoveryWarning.topAnchor, constant: -2), status.heightAnchor.constraint(equalToConstant: 20),
            recoveryWarning.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            recoveryWarning.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            recoveryWarning.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -6),
            sidebar.widthAnchor.constraint(greaterThanOrEqualToConstant: 180), sidebar.widthAnchor.constraint(lessThanOrEqualToConstant: 300),
            scroll.leadingAnchor.constraint(equalTo: writing.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: writing.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: writing.topAnchor), scroll.bottomAnchor.constraint(equalTo: writing.bottomAnchor),
            placeholder.leadingAnchor.constraint(equalTo: writing.leadingAnchor, constant: 45),
            placeholder.topAnchor.constraint(equalTo: writing.topAnchor, constant: 32)
        ])
        split.setPosition(232, ofDividerAt: 0)
        let preferredSidebar = sidebar.widthAnchor.constraint(equalToConstant: 232)
        preferredSidebar.priority = .defaultHigh
        preferredSidebar.isActive = true
        refreshStatus()
    }

    @objc private func nativeUndoCompleted(_ notification: Notification) {
        // Direct UndoManager invocations can update NSTextView without its
        // textDidChange callback. Admit the resulting exact bytes once; the
        // usual callback is harmless because identical bytes do not mutate.
        do { try writerDocument.acceptScratchEdit(editor.string) }
        catch { window?.presentError(error) }
        refreshStatus()
    }

    func undoManager(for view: NSTextView) -> UndoManager? { writerDocument.undoManager }

    func textDidChange(_ notification: Notification) {
        do { try writerDocument.acceptScratchEdit(editor.string) }
        catch { window?.presentError(error) }
        refreshStatus()
    }

    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
        guard writerDocument.session?.snapshot.revision.next != nil else { return false }
        guard let replacementString, let range = Range(affectedCharRange, in: textView.string) else { return replacementString == nil }
        let candidate = textView.string.replacingCharacters(in: range, with: replacementString)
        return candidate.utf8.count <= 8 * 1024 * 1024 && candidate.unicodeScalars.count <= 1_000_000
    }

    func reloadSource() {
        let selection = editor.selectedRange()
        editor.string = String(decoding: writerDocument.sourceBytes, as: UTF8.self)
        editor.setSelectedRange(NSRange(location: min(selection.location, editor.string.utf16.count), length: 0))
        refreshStatus()
    }

    func refreshStatus() {
        let words = editor.string.split(whereSeparator: \.isWhitespace).count
        let fileState: String
        if writerDocument.fileLifecycle.conflict != nil { fileState = "External changes need review" }
        else if writerDocument.isSavingSource { fileState = "Saving…" }
        else if writerDocument.saveFailed { fileState = "Save failed" }
        else if let saved = writerDocument.savedFile, saved.source == writerDocument.session?.snapshot {
            fileState = "Saved to \(saved.url.deletingLastPathComponent().lastPathComponent)"
        } else { fileState = "Unsaved" }
        wordCount.stringValue = "\(words) \(words == 1 ? "word" : "words") · \(fileState)"
        wordCount.toolTip = writerDocument.recovery?.message
        let recoveryFailed = writerDocument.recovery?.hasFailure == true || writerDocument.recoveryPreparationError != nil
        retryRecovery.isHidden = !recoveryFailed
        reviewChanges.isHidden = writerDocument.fileLifecycle.conflict == nil
        retryRecovery.toolTip = writerDocument.recovery?.message
        recoveryWarning.stringValue = writerDocument.fileLifecycle.issue ?? (recoveryFailed
            ? "Recovery unavailable. Save your document to a file; your text is still editable." : "")
        recoveryWarning.toolTip = writerDocument.recovery?.message
        history.stringValue = consent.choice == .off ? "Recording off" : "Recording requested · unavailable in this shell"
        placeholder.isHidden = !editor.string.isEmpty
    }

    @objc private func reviewExternalChanges(_ sender: Any?) { writerDocument.fileLifecycle.presentReview() }

    private func showRecordingConsent() {
        guard let window, window.attachedSheet == nil else { return }
        let alert = NSAlert()
        alert.messageText = "Store writing history on this Mac?"
        alert.informativeText = "History includes revisions, timing and deleted text. It stays on this Mac unless you explicitly export it. Recording is optional and does not prove authorship.\n\nThis development shell saves your choice; history recording becomes available with the storage stage."
        alert.addButton(withTitle: "Start Writing with Recording")
        alert.addButton(withTitle: "Write Without Recording")
        alert.addButton(withTitle: "Learn About Proof")
        // No default choice: Return must not silently authorize sensitive history.
        for button in alert.buttons { button.keyEquivalent = "" }
        alert.buttons[1].keyEquivalent = "\u{1b}"
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            if response == .alertThirdButtonReturn {
                (NSApp.delegate as? AppDelegate)?.showWriterHelp(nil)
                self.showRecordingConsent()
                return
            }
            self.consent.choose(response == .alertFirstButtonReturn ? .requested : .off)
            self.refreshStatus()
            self.window?.makeFirstResponder(self.editor)
        }
    }

    @objc func toggleSidebar(_ sender: Any?) { sidebar.isHidden.toggle(); split.adjustSubviews() }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.init("sidebar"), .flexibleSpace, .init("focus"), .init("preview"), .init("publish")]
    }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarAllowedItemIdentifiers(toolbar) }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: identifier)
        let details: (String, String)
        switch identifier.rawValue {
        case "sidebar": details = ("Toggle Sidebar", "sidebar.left"); item.target = self; item.action = #selector(toggleSidebar(_:))
        case "focus": details = ("Focus", "circle.dotted"); item.isEnabled = false
        case "preview": details = ("Preview and Export", "doc.richtext"); item.isEnabled = false
        case "publish":
            details = ("Publish", "paperplane"); item.isEnabled = false
            let button = NSButton(title: "Publish", image: NSImage(systemSymbolName: "paperplane", accessibilityDescription: "Publish")!, target: nil, action: nil)
            button.bezelStyle = .rounded; button.imagePosition = .imageLeading; button.isEnabled = false
            button.setAccessibilityLabel("Publish")
            item.view = button
        default: return nil
        }
        item.label = details.0; item.paletteLabel = details.0; item.toolTip = details.0
        item.image = NSImage(systemSymbolName: details.1, accessibilityDescription: details.0)
        return item
    }
}
