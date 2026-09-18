import AppKit
import UniformTypeIdentifiers
import WriterFoundation
import WriterStorage
import WriterExport

@MainActor
final class DocumentAssets {
    struct PreparedSave {
        let records: [ManagedAsset]
        let folderBookmark: Data?
    }
    private weak var document: WriterDocument?
    private let files = ManagedAssets()
    private let bookmarks: any SourceBookmarkProviding
    private(set) var records: [ManagedAsset] = []
    private(set) var folderBookmark: Data?
    init(document: WriterDocument, bookmarks: any SourceBookmarkProviding = NativeSourceBookmarks()) {
        self.document = document; self.bookmarks = bookmarks
    }

    func restore(_ record: DocumentCatalogRecord) {
        guard records.isEmpty else { return }
        records = record.managedAssets ?? []; folderBookmark = record.assetFolderBookmark
    }
    func inherit(from parent: DocumentAssets) { records = parent.records; folderBookmark = parent.folderBookmark }
    func apply(_ prepared: PreparedSave) { records = prepared.records; folderBookmark = prepared.folderBookmark }

    func chooseImage() {
        guard let document, document.fileURL != nil, !document.isSavingSource, !document.isLifecycleTransitionActive else {
            showError("Save the document before inserting an image, so the image can be stored beside it."); return
        }
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg]; panel.title = "Insert Image"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            Task {
                do { try await self.insertImage(url) }
                catch is CancellationError { }
                catch let error as CocoaError where error.code == .userCancelled { }
                catch { self.showError("The image could not be safely inserted. Your source text is unchanged. Check folder access, local recovery and image limits (20 MiB per image, 100 MiB total, 50 megapixels).") }
            }
        }
    }

    func insertImage(_ selected: URL, grantedFolder: URL? = nil) async throws {
        guard let document, let sourceURL = document.fileURL, let library = document.recoveryLibrary,
              !document.isSavingSource, !document.isLifecycleTransitionActive else { throw SourceAccessError.unavailable }
        await document.awaitRecoveryAttachment()
        try await document.flushRecovery(at: .save)
        guard !document.isSavingSource, !document.isLifecycleTransitionActive, document.recovery != nil, let source = document.session?.snapshot,
              let controller = document.windowControllers.first as? WriterWindowController else { throw SourceAccessError.unavailable }
        let selection = controller.editor.selectedRange()
        let folder = try await folderGrant(for: sourceURL.deletingLastPathComponent(), explicit: grantedFolder)
        defer { if folder.started { bookmarks.stop(folder.url) } }
        // A separate start owns this operation; the transient value below does
        // not retain a second lease after stop. Existing document scope survives.
        let imageAccess = bookmarks.start(selected)
        defer { if imageAccess { bookmarks.stop(selected) } }
        guard document.session?.snapshot == source else { throw CocoaError(.userCancelled) }
        document.setLifecycleBusy(true)
        defer { document.setLifecycleBusy(false) }
        let asset = try await files.importImage(selected, documentName: sourceURL.lastPathComponent, into: folder.url, existing: records)
        let bookmark = try await ScopedSourceFiles(bookmarks: bookmarks).bookmarkForExplicitSelection(folder.url)
        try await library.recordAssets(source.documentID, assets: records + [asset], folderBookmark: bookmark)
        records.append(asset); folderBookmark = bookmark
        // The native text operation owns selection and undo; its explicit origin
        // is formatting/imported material, never a reconstructed key event.
        document.setLifecycleBusy(false)
        try document.insertManagedImageLink("![Image](\(asset.markdownPath))", at: selection, expecting: source)
    }

    func prepareDestination(_ url: URL, source: SourceSnapshot, grantedFolder: URL? = nil) async throws -> PreparedSave {
        guard !records.isEmpty else { return PreparedSave(records: [], folderBookmark: nil) }
        guard let folderBookmark else { throw SourceAccessError.invalidBookmark }
        let referenced = try await Task.detached { try MarkdownAssetReferences.relativeImagePaths(in: source) }.value
        let selected = records.filter { referenced.contains($0.relativePath) }
        guard !selected.isEmpty else { return PreparedSave(records: [], folderBookmark: nil) }
        let original = try bookmarks.resolve(folderBookmark)
        guard !original.isStale, bookmarks.start(original.url) else { throw SourceAccessError.permissionDenied }
        defer { bookmarks.stop(original.url) }
        let target = url.deletingLastPathComponent()
        if original.url.standardizedFileURL.resolvingSymlinksInPath().path == target.standardizedFileURL.resolvingSymlinksInPath().path {
            try await files.verify(selected, in: original.url)
            return PreparedSave(records: selected, folderBookmark: folderBookmark)
        }
        if grantedFolder == nil {
            let alert = NSAlert(); alert.messageText = "Copy linked images with this document?"
            alert.informativeText = "Copy the \(selected.count) managed images into the destination folder. Relative links and source text stay unchanged. The original images remain available to the original document."
            alert.addButton(withTitle: "Copy Images"); alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { throw CocoaError(.userCancelled) }
        }
        let folder = try await folderGrant(for: target, explicit: grantedFolder)
        defer { if folder.started { bookmarks.stop(folder.url) } }
        try await files.copy(selected, from: original.url, to: folder.url)
        return PreparedSave(records: selected, folderBookmark: try await ScopedSourceFiles(bookmarks: bookmarks).bookmarkForExplicitSelection(folder.url))
    }

    // A simple operation-owned grant. Do not use SelectedSourceLease here:
    // this method balances access explicitly before returning from its caller.
    private struct Grant { let url: URL; let started: Bool }
    private func folderGrant(for expected: URL, explicit: URL?) async throws -> Grant {
        let canonical = expected.standardizedFileURL.resolvingSymlinksInPath().path
        if explicit == nil, let folderBookmark,
           let resolved = try? bookmarks.resolve(folderBookmark), !resolved.isStale,
           resolved.url.standardizedFileURL.resolvingSymlinksInPath().path == canonical,
           bookmarks.start(resolved.url) {
            return Grant(url: resolved.url, started: true)
        }
        let selected: URL
        if let explicit { selected = explicit }
        else {
            let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
            panel.directoryURL = expected; panel.title = "Allow Access to Document Folder"
            panel.message = "Select this document's folder so Nostr Writer can store its managed images beside it."
            selected = try await withCheckedThrowingContinuation { continuation in
                panel.begin { response in
                    if response == .OK, let url = panel.url { continuation.resume(returning: url) }
                    else { continuation.resume(throwing: CocoaError(.userCancelled)) }
                }
            }
        }
        guard selected.standardizedFileURL.resolvingSymlinksInPath().path == canonical else { throw SourceAccessError.permissionDenied }
        let started = bookmarks.start(selected)
        return Grant(url: selected, started: started)
    }

    private func showError(_ message: String) {
        let alert = NSAlert(); alert.messageText = "Image unavailable"; alert.informativeText = message
        alert.addButton(withTitle: "Back to Writing"); alert.runModal()
    }
}
