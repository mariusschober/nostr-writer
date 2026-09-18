import AppKit
import SwiftUI
import WriterFoundation

@MainActor
final class WriterWindowController: NSWindowController, NSToolbarDelegate, NSTextViewDelegate, NSWindowDelegate {
    let writerDocument: WriterDocument
    let editor = MarkdownTextView(usingTextLayoutManager: true)
    let gateway: EditorMutationGateway
    private let split = NSSplitView()
    private let sidebar: NSHostingView<WriterLibrarySidebar>
    private let inspectorHosting: NSHostingView<EditorInspectorView>
    private let inspectorModel = EditorInspectorModel()
    private let wordCount = NSTextField(labelWithString: "0 words")
    private let recoveryWarning = NSTextField(labelWithString: "")
    private let retryRecovery = NSButton(title: "Retry Recovery", target: nil, action: nil)
    private let reviewChanges = NSButton(title: "Review Changes", target: nil, action: nil)
    private let history = NSTextField(labelWithString: "Recording off")
    private let placeholder = NSTextField(labelWithString: "Write what you think.")
    private let preferences = WritePreferences()
    private var inspectorVisible = false
    private var isChromeHidden = false
    private weak var outlineMenu: NSMenu?
    private lazy var dictation = DictationController(editor: editor, gateway: gateway)
    /// Cached product word count. The whole document is counted only on the
    /// coalesced presentation pass, never inside a keystroke.
    private var cachedWordCount = 0
    /// Coalesces expensive, purely presentational work (Markdown emphasis,
    /// outline parse, focus highlight, word count) so a keystroke in a long
    /// document never blocks on a full-document scan.
    private var presentationWork: DispatchWorkItem?

    init(writerDocument: WriterDocument) {
        self.writerDocument = writerDocument
        self.gateway = EditorMutationGateway(document: writerDocument)
        let library = (NSApp.delegate as? AppDelegate)?.libraryModel
            ?? WriterLibraryModel(recovery: writerDocument.recoveryLibrary ?? RecoveryLibrary())
        self.sidebar = NSHostingView(rootView: WriterLibrarySidebar(model: library))
        self.inspectorHosting = NSHostingView(rootView: EditorInspectorView(model: inspectorModel))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 760),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Untitled"
        window.tabbingMode = .preferred
        super.init(window: window)
        window.delegate = self
        setupContent(window)
        gateway.attach(editor)
        configureInspector()
        for name in [Notification.Name.NSUndoManagerDidUndoChange, Notification.Name.NSUndoManagerDidRedoChange] {
            NotificationCenter.default.addObserver(self, selector: #selector(nativeUndoCompleted(_:)), name: name, object: writerDocument.undoManager)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(preferencesChanged(_:)),
                                               name: WritePreferences.didChangeNotification, object: preferences)
        NotificationCenter.default.addObserver(self, selector: #selector(recordingStateChanged(_:)),
                                               name: WriterDocument.recordingStateDidChange, object: writerDocument)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(systemWillSleep(_:)),
                                                          name: NSWorkspace.willSleepNotification, object: nil)
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
        applyPreferences()
        writerDocument.startRecordingIfConsented()
    }
    required init?(coder: NSCoder) { nil }
    deinit { NotificationCenter.default.removeObserver(self) }

    func windowDidResignKey(_ notification: Notification) { writerDocument.checkpointForInterruption(.interruption) }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeFirstResponder(editor)
        if !writerDocument.consent.hasChosen { showRecordingConsent() }
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
        inspectorHosting.setAccessibilityLabel("Passage inspector")
        inspectorHosting.isHidden = true
        split.addArrangedSubview(inspectorHosting)
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
        editor.onEscape = { [weak self] in self?.exitFocusIfNeeded() ?? false }
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
            inspectorHosting.widthAnchor.constraint(greaterThanOrEqualToConstant: 240),
            inspectorHosting.widthAnchor.constraint(lessThanOrEqualToConstant: 420),
            scroll.leadingAnchor.constraint(equalTo: writing.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: writing.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: writing.topAnchor), scroll.bottomAnchor.constraint(equalTo: writing.bottomAnchor),
            placeholder.leadingAnchor.constraint(equalTo: writing.leadingAnchor, constant: 45),
            placeholder.topAnchor.constraint(equalTo: writing.topAnchor, constant: 32)
        ])
        split.setPosition(232, ofDividerAt: 0)
        let preferredSidebar = sidebar.widthAnchor.constraint(equalToConstant: 232)
        preferredSidebar.priority = .defaultHigh
        preferredSidebar.isActive = true
        // One synchronous pass so the first paint has emphasis, outline and a
        // word count; later edits coalesce through `schedulePresentationRefresh`.
        runPresentationRefresh()
    }

    private func configureInspector() {
        inspectorModel.onDeleteHistory = { [weak self] in
            self?.confirmDeleteLocalHistory()
        }
        inspectorModel.onTogglePause = { [weak self] in
            guard let self else { return }
            if case .paused = self.writerDocument.recordingState { self.writerDocument.resumeRecording() }
            else { self.writerDocument.stopRecording(pausing: true) }
            self.refreshStatus()
        }
        inspectorModel.onRemoveAnnotation = { [weak self] id in
            self?.writerDocument.removeAnnotation(id); self?.refreshStatus()
        }
        inspectorModel.onToggleDictation = { [weak self] in self?.toggleDictation(nil) }
        inspectorModel.onMarkSource = { [weak self] kind, description, url in
            self?.markExternalSource(kind: kind, description: description, url: url)
        }
    }

    /// Destruction stays honest: the owner sees exactly what is and is not
    /// removed before any history is deleted. Deletion is never one-click.
    private func confirmDeleteLocalHistory() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete this document's detailed writing history?"
        alert.informativeText = """
        This permanently removes the recorded detailed history for this document, \
        including deleted text and timing.

        Your document and its encrypted recovery are not deleted. Deleting history \
        cannot revoke an already exported proof or erase backups.
        """
        alert.addButton(withTitle: "Delete History")
        alert.addButton(withTitle: "Cancel")
        guard let window else { return }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            Task { await self.writerDocument.deleteLocalHistory(); self.refreshStatus() }
        }
    }

    // MARK: - Gateways and delegates

    @objc private func nativeUndoCompleted(_ notification: Notification) {
        // Direct UndoManager invocations can update NSTextView without its
        // textDidChange callback. Admit the resulting exact bytes once; the
        // usual callback is harmless because identical bytes do not mutate.
        let origin: EditOrigin = notification.name == .NSUndoManagerDidRedoChange ? .redo(UUID()) : .undo(UUID())
        gateway.commitWholeDocument(origin: origin)
        refreshStatus()
    }

    func undoManager(for view: NSTextView) -> UndoManager? { writerDocument.undoManager }

    func textDidChange(_ notification: Notification) {
        gateway.didChange()
        refreshStatus()
        schedulePresentationRefresh()
    }

    // MARK: - Presentation

    private func applyPreferences() {
        editor.font = preferences.fontChoice.font(ofSize: CGFloat(preferences.fontSize))
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = CGFloat(preferences.fontSize) * 0.5
        editor.defaultParagraphStyle = paragraph
        placeholder.font = editor.font
        applyMeasure()
        applyFocusHighlight()
    }

    /// Centers the preferred character measure while preserving a generous
    /// horizontal margin. It adapts as side panels consume space and never
    /// forces clipping at the minimum window size.
    private func applyMeasure() {
        guard let scroll = editor.enclosingScrollView else { return }
        let available = max(240, scroll.contentSize.width)
        let characterWidth = editor.font?.maximumAdvancement.width ?? 10
        let desired = CGFloat(preferences.measure) * characterWidth + editor.textContainerInset.width * 2
        let width = min(max(desired, available - 56), available)
        editor.textContainer?.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainer?.lineFragmentPadding = 0
    }

    private func applyFocusHighlight() {
        EditorPresentation.applyFocusHighlight(to: editor, mode: preferences.focusMode)
    }

    @discardableResult
    private func exitFocusIfNeeded() -> Bool {
        guard preferences.focusMode != .off || isChromeHidden else { return false }
        preferences.focusMode = .off
        setChromeHidden(false)
        refreshStatus()
        return true
    }

    private func setChromeHidden(_ hidden: Bool) {
        isChromeHidden = hidden
        window?.toolbar?.isVisible = !hidden
        sidebar.isHidden = hidden
        split.adjustSubviews()
    }

    /// Focus mode uses a background highlight on the active sentence or
    /// paragraph; it never dims text below accessibility contrast.
    private func typewriterScroll() {
        guard let scroll = editor.enclosingScrollView else { return }
        let screenRect = editor.firstRect(forCharacterRange: editor.selectedRange(), actualRange: nil)
        guard screenRect.origin.y.isFinite else { return }
        let windowRect = window?.convertFromScreen(screenRect) ?? screenRect
        let viewRect = editor.convert(windowRect, from: nil)
        let visible = scroll.contentView.bounds
        // Reduce Motion: keep the caret visible with the smallest jump instead
        // of continuously recentering the page. The text position is identical;
        // only the amount of on-screen motion changes.
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let padding = editor.font?.boundingRectForFont.height ?? 20
            if viewRect.minY < visible.minY + padding * 0.5 {
                scroll.contentView.scroll(to: NSPoint(x: visible.minX, y: max(0, viewRect.minY - padding)))
                scroll.reflectScrolledClipView(scroll.contentView)
            } else if viewRect.maxY > visible.maxY - padding * 0.5 {
                scroll.contentView.scroll(to: NSPoint(x: visible.minX, y: viewRect.maxY - visible.height + padding))
                scroll.reflectScrolledClipView(scroll.contentView)
            }
            return
        }
        let delta = viewRect.origin.y - (visible.minY + visible.height * 0.45)
        guard abs(delta) > 8 else { return }
        var origin = visible.origin
        origin.y = max(0, visible.minY + delta)
        scroll.contentView.scroll(to: origin)
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    func refreshStatus() {
        let words = cachedWordCount
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
        let willPopulate = recordingStatusText
        history.stringValue = willPopulate
        placeholder.isHidden = !editor.string.isEmpty
        refreshInspector()
    }

    private var recordingStatusText: String {
        switch writerDocument.recordingState {
        case .off:
            return writerDocument.consent.choice == .requested ? "Recording on — starting" : "Recording off"
        case .observing:
            return "Recording on"
        case .paused:
            return "Recording paused"
        case .pausedLimit:
            return "Recording paused — history limit reached"
        case .gap(let reason):
            return "Recording gap — \(reason)"
        }
    }

    private func refreshInspector() {
        switch writerDocument.recordingState {
        case .off:
            inspectorModel.recording = "Recording off"
            inspectorModel.recordingDetail = "No detailed revisions or deleted text are stored."
        case .observing:
            inspectorModel.recording = "Recording on"
            inspectorModel.recordingDetail = "Detailed revisions are stored encrypted on this Mac until you delete them."
        case .paused:
            inspectorModel.recording = "Recording paused"
            inspectorModel.recordingDetail = "Earlier history is preserved; new detail is not recorded."
        case .pausedLimit:
            inspectorModel.recording = "Recording paused"
            inspectorModel.recordingDetail = "Detailed history reached its limit. Your writing and recovery are unaffected."
        case .gap(let reason):
            inspectorModel.recording = "Recording gap"
            inspectorModel.recordingDetail = "Detail is not continuous (\(reason)). Your writing is unchanged."
        }
        inspectorModel.notice = writerDocument.historyError ?? ""
        inspectorModel.dictation = dictationStatusText
        inspectorModel.annotations = writerDocument.annotations.map { annotation in
            let kind = annotation.kind.rawValue.capitalized
            let detail = "\(kind) · bytes \(annotation.range.lowerBound)–\(annotation.range.upperBound)"
            return EditorInspectorModel.AnnotationRow(id: annotation.id, title: annotation.description,
                                                      detail: detail, isStale: annotation.isStale)
        }
        updateInspectorSelection()
    }

    private func updateInspectorSelection() {
        let selection = editor.selectedRange()
        let text = editor.string as NSString
        let hasSelection = selection.length > 0 && NSMaxRange(selection) <= text.length
        inspectorModel.selectedText = hasSelection ? text.substring(with: selection) : ""
        inspectorModel.canAnnotate = hasSelection && writerDocument.sessionSnapshot != nil
    }

    private var dictationStatusText: String {
        switch dictation.state {
        case .idle: "Off"
        case .listening: "Listening — speak now"
        case .unavailable(let reason): reason
        case .denied(let reason): reason
        }
    }

    // MARK: - Commands

    @objc func toggleSidebar(_ sender: Any?) { sidebar.isHidden.toggle(); split.adjustSubviews() }

    @objc func toggleInspector(_ sender: Any?) {
        inspectorVisible.toggle()
        inspectorHosting.isHidden = !inspectorVisible
        split.adjustSubviews()
        if inspectorVisible { window?.makeFirstResponder(editor) }
        refreshStatus()
    }

    @objc func toggleFocusWriting(_ sender: Any?) {
        let hiding = !isChromeHidden
        setChromeHidden(hiding)
        if hiding { preferences.focusMode = preferences.focusMode == .off ? .paragraph : preferences.focusMode }
        refreshStatus()
    }

    @objc func toggleTypewriterScrolling(_ sender: Any?) { preferences.typewriterScrolling.toggle() }

    @objc func toggleRecording(_ sender: Any?) {
        switch writerDocument.recordingState {
        case .off, .gap: writerDocument.startRecordingIfConsented()
        case .observing: writerDocument.stopRecording(pausing: true)
        case .paused, .pausedLimit: writerDocument.resumeRecording()
        }
        refreshStatus()
    }

    @objc func toggleDictation(_ sender: Any?) {
        dictation.onStateChange = { [weak self] _ in self?.refreshStatus() }
        dictation.toggle()
        refreshStatus()
    }

    @objc func showPassageInspector(_ sender: Any?) {
        inspectorVisible = true
        inspectorHosting.isHidden = false
        split.adjustSubviews()
        inspectorModel.notice = "Select a passage, choose a category, describe the source, then mark it."
        refreshStatus()
    }

    private func markExternalSource(kind: AnnotationKind, description: String, url: String?) {
        let selection = editor.selectedRange()
        let text = editor.string as NSString
        guard selection.length > 0, NSMaxRange(selection) <= text.length,
              let snapshot = writerDocument.sessionSnapshot,
              let range = try? snapshot.byteRange(for: NativeRange(location: selection.location, length: selection.length)) else {
            inspectorModel.notice = "Select a passage first."
            return
        }
        writerDocument.addAnnotation(kind: kind, range: range, description: description, url: url)
        inspectorModel.annotationDescription = ""
        inspectorModel.annotationURL = ""
        inspectorModel.notice = "Marked the selected passage as \(kind.rawValue)."
        refreshStatus()
    }

    @objc func applyFormatting(_ sender: Any?) {
        guard let item = sender as? NSMenuItem,
              let raw = item.representedObject as? String,
              let formatting = EditorCommands.Formatting(rawValue: raw) else { return }
        EditorCommands.apply(formatting, to: editor, gateway: gateway)
        refreshStatus()
    }

    @objc private func reviewExternalChanges(_ sender: Any?) { writerDocument.fileLifecycle.presentReview() }

    private func showRecordingConsent() {
        guard let window, window.attachedSheet == nil else { return }
        let alert = NSAlert()
        alert.messageText = "Store writing history on this Mac?"
        alert.informativeText = "History includes revisions, timing and deleted text. It stays encrypted on this Mac unless you explicitly export it. Recording is optional and does not prove authorship."
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
            let choseRecording = response == .alertFirstButtonReturn
            self.writerDocument.consent.choose(choseRecording ? .requested : .off)
            if choseRecording { self.writerDocument.resumeRecording() }
            else { self.writerDocument.stopRecording(pausing: false) }
            self.refreshStatus()
            self.window?.makeFirstResponder(self.editor)
        }
    }

    // MARK: - Toolbar

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.init("sidebar"), .init("outline"), .flexibleSpace, .init("formatting"), .init("dictation"),
         .init("focus"), .init("inspector"), .init("preview"), .init("publish")]
    }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.init("sidebar"), .init("outline"), .flexibleSpace, .init("formatting"), .init("dictation"),
         .init("focus"), .init("inspector"), .init("preview"), .init("publish")]
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: identifier)
        let details: (String, String)
        switch identifier.rawValue {
        case "sidebar": details = ("Toggle Sidebar", "sidebar.left"); item.target = self; item.action = #selector(toggleSidebar(_:))
        case "inspector": details = ("Toggle Inspector", "sidebar.right"); item.target = self; item.action = #selector(toggleInspector(_:))
        case "focus": details = ("Focus", "circle.dotted"); item.target = self; item.action = #selector(toggleFocusWriting(_:))
        case "dictation":
            details = ("Dictate On This Mac", "mic")
            let button = NSButton(title: "Dictate", image: NSImage(systemSymbolName: "mic", accessibilityDescription: "Dictate")!, target: self, action: #selector(toggleDictation(_:)))
            button.bezelStyle = .rounded; button.imagePosition = .imageLeading
            button.setAccessibilityLabel("Dictate on this Mac")
            item.view = button
        case "formatting":
            details = ("Formatting", "textformat")
            let button = NSPopUpButton(frame: .zero, pullsDown: true)
            button.bezelStyle = .texturedRounded
            let header = NSMenuItem(title: "Formatting", action: nil, keyEquivalent: "")
            header.image = NSImage(systemSymbolName: "textformat", accessibilityDescription: "Formatting")
            button.menu?.addItem(header)
            for formatting in EditorCommands.Formatting.allCases {
                let entry = NSMenuItem(title: formatting.title, action: #selector(applyFormatting(_:)), keyEquivalent: "")
                entry.representedObject = formatting.rawValue; entry.target = self
                button.menu?.addItem(entry)
            }
            item.view = button
        case "outline":
            details = ("Headings", "list.bullet.indent")
            let button = NSPopUpButton(frame: .zero, pullsDown: true)
            button.bezelStyle = .texturedRounded
            let header = NSMenuItem(title: "Headings", action: nil, keyEquivalent: "")
            header.image = NSImage(systemSymbolName: "list.bullet.indent", accessibilityDescription: "Headings")
            button.menu?.addItem(header)
            outlineMenu = button.menu
            rebuildOutlineMenu()
            item.view = button
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

    // MARK: - Outline

    /// Revision-bound outline. A heading click moves the caret; it never edits
    /// source and never reuses a stale parse of an older revision.
    func rebuildOutlineMenu() {
        guard let menu = outlineMenu, let snapshot = writerDocument.sessionSnapshot else { return }
        while menu.items.count > 1 { menu.removeItem(at: menu.items.count - 1) }
        let items = EditorOutline.items(in: snapshot)
        if items.isEmpty {
            let empty = NSMenuItem(title: "No headings", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }
        for item in items {
            let title = String(repeating: "  ", count: max(0, item.level - 1)) + item.title
            let entry = NSMenuItem(title: title.isEmpty ? "Heading" : title, action: #selector(navigateToHeading(_:)), keyEquivalent: "")
            entry.representedObject = item.byteRange.lowerBound
            entry.target = self
            menu.addItem(entry)
        }
    }

    @objc private func navigateToHeading(_ sender: Any?) {
        guard let item = sender as? NSMenuItem, let offset = item.representedObject as? Int,
              let snapshot = writerDocument.sessionSnapshot else { return }
        guard let range = try? ByteRange(lowerBound: offset, upperBound: offset),
              let native = try? snapshot.nativeRange(for: range) else { return }
        editor.setSelectedRange(NSRange(location: native.location, length: 0))
        editor.scrollRangeToVisible(editor.selectedRange())
        window?.makeFirstResponder(editor)
    }

    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
        guard writerDocument.session?.snapshot.revision.next != nil else { return false }
        guard let replacementString, let range = Range(affectedCharRange, in: textView.string) else {
            return replacementString == nil
        }
        let candidate = textView.string.replacingCharacters(in: range, with: replacementString)
        guard candidate.utf8.count <= 8 * 1024 * 1024 && candidate.unicodeScalars.count <= 1_000_000 else { return false }
        return gateway.shouldChange(in: affectedCharRange, replacement: replacementString)
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        if preferences.typewriterScrolling, editor.window?.firstResponder == editor { typewriterScroll() }
        updateInspectorSelection()
    }

    /// Runs the expensive presentation work once, shortly after the last change.
    private func schedulePresentationRefresh() {
        presentationWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.runPresentationRefresh() }
        presentationWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    private func runPresentationRefresh() {
        cachedWordCount = editor.string.split(whereSeparator: \.isWhitespace).count
        EditorPresentation.applySyntaxEmphasis(to: editor)
        applyFocusHighlight()
        rebuildOutlineMenu()
        refreshStatus()
    }

    func windowWillClose(_ notification: Notification) {
        // A closing document invalidates any in-flight dictation callbacks so a
        // late transcript can never land in another document.
        dictation.stop()
        presentationWork?.cancel()
        NSWorkspace.shared.notificationCenter.removeObserver(self, name: NSWorkspace.willSleepNotification,
                                                            object: nil)
    }

    /// Sleep invalidates late dictation callbacks rather than continuing to
    /// capture audio. This is wired from `showWindow`, not from key changes,
    /// because a system permission prompt also resigns key.
    @objc private func systemWillSleep(_ notification: Notification) {
        if dictation.state.isListening { dictation.stop() }
    }

    @objc private func preferencesChanged(_ notification: Notification) { applyPreferences() }

    @objc private func recordingStateChanged(_ notification: Notification) { refreshStatus() }

    func reloadSource() {
        let selection = editor.selectedRange()
        editor.string = String(decoding: writerDocument.sourceBytes, as: UTF8.self)
        editor.setSelectedRange(NSRange(location: min(selection.location, editor.string.utf16.count), length: 0))
        runPresentationRefresh()
    }
}
