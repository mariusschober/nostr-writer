import AppKit
import WriterFoundation
import WriterStorage

@MainActor
final class TextImportController: NSWindowController, NSWindowDelegate {
    private let library: RecoveryLibrary
    private let completion: () -> Void
    private let encoding = NSPopUpButton()
    private let preview = NSTextView(usingTextLayoutManager: true)
    private let status = NSTextField(wrappingLabelWithString: "Choose the encoding used by the original file.")
    private let importButton = NSButton(title: "Import UTF-8 Copy", target: nil, action: nil)
    private var original = Data()
    private var converted: TextImportCopy?
    private var sourceName = "Imported text"
    private var generation = UUID()
    private var readTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var finished = false
    private var sourceLoaded = false

    init(library: RecoveryLibrary, completion: @escaping () -> Void) {
        self.library = library; self.completion = completion
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 680, height: 480),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Import Text Copy"; window.delegate = self
        window.minSize = NSSize(width: 520, height: 360)
        let explanation = NSTextField(wrappingLabelWithString: "Choose an encoding and review the text. Import creates an unsaved UTF-8 copy; the original file stays unchanged.")
        encoding.addItems(withTitles: TextImportEncoding.allCases.map(\.title))
        encoding.target = self; encoding.action = #selector(updatePreview(_:)); encoding.setAccessibilityLabel("Original text encoding")
        encoding.isEnabled = false
        preview.isEditable = false; preview.isSelectable = true; preview.isRichText = false
        preview.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        preview.frame = NSRect(x: 0, y: 0, width: 640, height: 240)
        preview.minSize = NSSize(width: 0, height: 160)
        preview.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        preview.textContainerInset = NSSize(width: 8, height: 8)
        preview.isVerticallyResizable = true; preview.autoresizingMask = [.width]
        preview.textContainer?.widthTracksTextView = true
        preview.setAccessibilityLabel("Imported text preview")
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder; scroll.documentView = preview
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelImport(_:))); cancel.keyEquivalent = "\u{1b}"
        importButton.target = self; importButton.action = #selector(importCopy(_:)); importButton.isEnabled = false
        let buttons = NSStackView(views: [cancel, importButton]); buttons.orientation = .horizontal
        let stack = NSStackView(views: [explanation, encoding, scroll, status, buttons])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView(); window.contentView = content; content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor), scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 160),
            explanation.widthAnchor.constraint(equalTo: stack.widthAnchor), status.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        window.center()
    }
    required init?(coder: NSCoder) { nil }

    func chooseSource() {
        let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.title = "Import Text Copy"
        panel.begin { [weak self] response in
            guard let self else { return }
            guard response == .OK, let url = panel.url else { self.finish(); return }
            self.sourceName = url.deletingPathExtension().lastPathComponent + " (Imported)"
            self.status.stringValue = "Reading the selected file…"; self.showWindow(nil)
            self.readTask = Task {
                let acquired = url.startAccessingSecurityScopedResource()
                defer { if acquired { url.stopAccessingSecurityScopedResource() } }
                do {
                    let bytes = try await CoordinatedSourceFiles().readForTextImport(url)
                    guard !Task.isCancelled, !self.finished else { return }
                    self.original = bytes; self.sourceLoaded = true; self.encoding.isEnabled = true; self.updatePreview(nil)
                } catch {
                    guard !Task.isCancelled else { return }
                    self.status.stringValue = "This file could not be read safely, or exceeds the 8 MiB import limit. The original was not changed."
                }
            }
        }
    }

    @objc private func updatePreview(_ sender: Any?) {
        guard sourceLoaded else { return }
        previewTask?.cancel(); converted = nil; importButton.isEnabled = false
        let selected = TextImportEncoding.allCases[encoding.indexOfSelectedItem]
        let bytes = original, stamp = UUID(); generation = stamp
        status.stringValue = "Preparing preview…"
        previewTask = Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) { try TextImport.convert(bytes, encoding: selected) }.value
                guard !Task.isCancelled, generation == stamp, !finished else { return }
                converted = result
                let text = String(decoding: result.bytes, as: UTF8.self)
                preview.string = String(text.prefix(32_000))
                status.stringValue = "\(bytes.count) original bytes → \(result.bytes.count) UTF-8 bytes." + (text.count > 32_000 ? " Preview shortened; the complete copy will be imported." : "")
                importButton.isEnabled = true
            } catch {
                guard !Task.isCancelled, generation == stamp, !finished else { return }
                preview.string = ""
                status.stringValue = "This encoding cannot decode the file without loss, or the copy exceeds document limits. Choose another encoding or cancel."
            }
        }
    }

    @objc private func importCopy(_ sender: Any?) {
        guard let converted else { return }
        do {
            let source = try SourceSnapshot(documentID: DocumentID(), revision: Revision(0), utf8: converted.bytes)
            let document = WriterDocument(); document.fileType = "net.daringfireball.markdown"
            document.recoveryLibrary = library; document.textImport = converted.receipt
            try document.restoreRecoveredSource(source, title: sourceName)
            NSDocumentController.shared.addDocument(document); NSFileCoordinator.addFilePresenter(document)
            document.makeWindowControllers(); document.showWindows()
            finish()
        } catch { status.stringValue = "The copy could not be opened. The original file was not changed." }
    }

    @objc private func cancelImport(_ sender: Any?) { finish() }
    func windowWillClose(_ notification: Notification) { finish() }
    private func finish() {
        guard !finished else { return }; finished = true
        readTask?.cancel(); previewTask?.cancel(); window?.close(); completion()
    }
}
