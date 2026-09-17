import AppKit
import SwiftUI
import WriterFoundation
import WriterStorage

final class SelectedSourceLease: Sendable {
    let url: URL
    init(acquired url: URL) { self.url = url }
    deinit { url.stopAccessingSecurityScopedResource() }
}

@MainActor
final class WriterLibraryModel: ObservableObject {
    @Published var recent: [URL] = []
    @Published var recovered: [DocumentCatalogRecord] = []
    @Published var results: [DocumentCatalogRecord] = []
    @Published var query = "" { didSet { search() } }
    @Published var recoveryUnavailable = false
    private let recovery: RecoveryLibrary
    private var catalog: [DocumentCatalogRecord] = []
    private var searchTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?

    init(recovery: RecoveryLibrary) { self.recovery = recovery }

    func noteRecent(_ url: URL) {
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        recent = Array(([url] + recent.filter { $0 != url }).prefix(40))
    }

    func refresh() {
        let nativeRecent = NSDocumentController.shared.recentDocumentURLs
        recent = Array((recent + nativeRecent.filter { !recent.contains($0) }).prefix(40))
        refreshTask?.cancel()
        refreshTask = Task { [weak self, recovery] in
            do {
                let entries = try await recovery.recoveredEntries()
                let catalog = try await recovery.catalogEntries()
                guard let self, !Task.isCancelled else { return }
                self.catalog = catalog
                let savedURLs = catalog.compactMap { $0.location.flatMap(URL.init(string:)) }
                self.recent = Array((self.recent + savedURLs.filter { !self.recent.contains($0) }).prefix(40))
                self.recovered = entries; self.recoveryUnavailable = false
            } catch {
                guard !Task.isCancelled else { return }
                self?.recoveryUnavailable = true
            }
        }
    }

    private func search() {
        searchTask?.cancel(); results = []
        let searchText = query
        guard !searchText.isEmpty else { return }
        searchTask = Task { [weak self, recovery] in
            do {
                try await Task.sleep(for: .milliseconds(180))
                let matches = try await recovery.searchCurrentText(searchText)
                guard !Task.isCancelled, self?.query == searchText else { return }
                self?.results = matches
            } catch { /* Keep native filename matches available when recovery is unavailable. */ }
        }
    }

    func openRecent(_ url: URL) {
        let location = url.standardizedFileURL.resolvingSymlinksInPath().absoluteString
        if let record = catalog.first(where: { $0.location == location }) { open(record); return }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error { NSApp.presentError(error) }
        }
    }

    func open(_ record: DocumentCatalogRecord, recovering: Bool = false) {
        if record.location != nil && !recovering && !recovered.contains(where: { $0.id == record.id }) {
            do {
                guard let bookmark = record.bookmark else { throw SourceAccessError.invalidBookmark }
                let resolved = try NativeSourceBookmarks().resolve(bookmark)
                guard !resolved.isStale else { throw SourceAccessError.staleBookmark }
                guard resolved.url.startAccessingSecurityScopedResource() else { throw SourceAccessError.permissionDenied }
                let lease = SelectedSourceLease(acquired: resolved.url)
                NSDocumentController.shared.openDocument(withContentsOf: resolved.url, display: true) { document, _, error in
                    if let document = document as? WriterDocument { document.retainSelectedScope(lease) }
                    if let error { NSApp.presentError(error) }
                }
            } catch {
                let alert = NSAlert()
                alert.messageText = "Locate this document"
                alert.informativeText = "Its saved file permission is unavailable or expired. Open the file again to grant access. The original file and recovery were preserved."
                alert.addButton(withTitle: "Open…"); alert.addButton(withTitle: "Cancel")
                if alert.runModal() == .alertFirstButtonReturn { NSDocumentController.shared.openDocument(nil) }
            }
        } else {
            Task { [recovery] in
                do {
                    let source = try await recovery.recoveredSource(record.documentID)
                    if let open = NSDocumentController.shared.documents.compactMap({ $0 as? WriterDocument })
                        .first(where: { $0.session?.snapshot.documentID == source.documentID }) {
                        open.showWindows(); return
                    }
                    let document = WriterDocument()
                    document.fileType = "net.daringfireball.markdown"; document.recoveryLibrary = recovery
                    try document.restoreRecoveredSource(source, title: record.title, asCopy: record.location != nil)
                    NSDocumentController.shared.addDocument(document)
                    NSFileCoordinator.addFilePresenter(document)
                    document.makeWindowControllers(); document.showWindows()
                } catch {
                    let alert = NSAlert(); alert.messageText = "Recovery is unavailable"
                    alert.informativeText = "This saved recovery could not be opened safely. It has not been changed or removed."
                    alert.addButton(withTitle: "OK"); alert.runModal()
                }
            }
        }
    }
}

struct WriterLibrarySidebar: View {
    @ObservedObject var model: WriterLibraryModel
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { NSDocumentController.shared.newDocument(nil) } label: { Label("New", systemImage: "square.and.pencil") }
                Button { NSDocumentController.shared.openDocument(nil) } label: { Label("Open", systemImage: "folder") }
            }.buttonStyle(.borderless).padding(12)
            TextField("Search documents", text: $model.query).textFieldStyle(.roundedBorder)
                .padding(.horizontal, 12).padding(.bottom, 8)
                .help("Search recent filenames and current locally stored text. Private writing history is not searched.")
            List {
                if !model.query.isEmpty {
                    Section("Results") {
                        ForEach(model.results) { entry in
                            Button { model.open(entry) } label: { Label(entry.title, systemImage: "doc.text") }
                        }
                    }
                }
                if !model.recovered.isEmpty && model.query.isEmpty {
                    Section("Recovered drafts") {
                        ForEach(model.recovered) { entry in
                            Button { model.open(entry, recovering: true) } label: { Label(entry.title, systemImage: "arrow.counterclockwise") }
                        }
                    }
                }
                Section("Recent") {
                    ForEach(model.recent.filter { model.query.isEmpty || $0.lastPathComponent.localizedCaseInsensitiveContains(model.query) }, id: \.self) { url in
                        Button { model.openRecent(url) } label: { Label(url.lastPathComponent, systemImage: "doc.text") }
                    }
                    if model.recent.isEmpty { Text("Open a document to add it here.").foregroundStyle(.secondary).font(.callout) }
                }
                if model.recoveryUnavailable {
                    Text("Recovery unavailable").font(.caption).foregroundStyle(.secondary)
                }
            }.listStyle(.sidebar).buttonStyle(.plain)
            Button("Refresh") { model.refresh() }.buttonStyle(.borderless).padding(8)
        }.frame(minWidth: 180, idealWidth: 232).onAppear { model.refresh() }
    }
}
