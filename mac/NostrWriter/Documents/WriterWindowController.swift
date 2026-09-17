import AppKit
import SwiftUI

@MainActor
final class WriterWindowController: NSWindowController, NSToolbarDelegate, NSTextViewDelegate {
    let writerDocument: WriterDocument
    let editor = NSTextView(usingTextLayoutManager: true)
    private let split = NSSplitView()
    private let sidebar = NSHostingView(rootView: ShellSidebar())
    private let wordCount = NSTextField(labelWithString: "0 words")
    private let history = NSTextField(labelWithString: "Recording off")
    private let consent = RecordingConsent()
    private let placeholder = NSTextField(labelWithString: "Write what you think.")

    init(writerDocument: WriterDocument) {
        self.writerDocument = writerDocument
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 760),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Untitled"
        window.tabbingMode = .preferred
        super.init(window: window)
        setupContent(window)
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

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        #if DEBUG
        // NSDocument's first presentation may restore/cascade the frame. Apply
        // the isolated UI test's requested geometry after that native work.
        if ProcessInfo.processInfo.environment["NW_TEST_WINDOW_SIZE"] == "narrow", let window {
            window.setFrame(NSRect(origin: window.frame.origin, size: NSSize(width: 760, height: 520)), display: true)
        }
        #endif
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
        let status = NSStackView(views: [wordCount, NSView(), history])
        status.orientation = .horizontal; status.spacing = 16; status.translatesAutoresizingMaskIntoConstraints = false
        wordCount.font = .systemFont(ofSize: 12); wordCount.textColor = .secondaryLabelColor
        history.font = .systemFont(ofSize: 12); history.textColor = .secondaryLabelColor
        root.addSubview(status)
        NSLayoutConstraint.activate([
            split.leadingAnchor.constraint(equalTo: root.leadingAnchor), split.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            split.topAnchor.constraint(equalTo: root.topAnchor), split.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -8),
            status.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            status.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            status.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -8), status.heightAnchor.constraint(equalToConstant: 20),
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

    private func refreshStatus() {
        let words = editor.string.split(whereSeparator: \.isWhitespace).count
        wordCount.stringValue = "\(words) \(words == 1 ? "word" : "words") · \(writerDocument.isDocumentEdited ? "Unsaved" : "Scratch document")"
        history.stringValue = consent.choice == .off ? "Recording off" : "Recording requested · unavailable in this shell"
        placeholder.isHidden = !editor.string.isEmpty
    }

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

private struct ShellSidebar: View {
    var body: some View {
        List {
            Section("Open") { Label("Current document", systemImage: "doc.text") }
            Section("Recent") { Text("Opened documents will appear here.").foregroundStyle(.secondary).font(.callout) }
        }.listStyle(.sidebar).frame(minWidth: 180, idealWidth: 232)
    }
}
