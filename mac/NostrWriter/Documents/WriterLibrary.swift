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
    struct OpenDocument: Identifiable {
        let document: WriterDocument
        let title: String
        var id: ObjectIdentifier { ObjectIdentifier(document) }
    }
    struct Folder: Identifiable {
        var record: DocumentCatalogRecord
        var entries: [LibraryFileEntry] = []
        var notice: String?
        var id: UUID { record.id }
    }
    struct FolderMatch: Identifiable {
        let folderID: UUID
        let entry: LibraryFileEntry
        var id: String { folderID.uuidString + entry.url.absoluteString }
    }
    @Published var recent: [URL] = []
    @Published var pinned: [URL] = []
    @Published var folders: [Folder] = []
    @Published var folderMatches: [FolderMatch] = []
    @Published var libraryNotice: String?
    @Published var recovered: [DocumentCatalogRecord] = []
    @Published var results: [DocumentCatalogRecord] = []
    @Published var query = "" { didSet { search() } }
    @Published var recoveryUnavailable = false
    private let recovery: RecoveryLibrary
    private var catalog: [DocumentCatalogRecord] = []
    private var searchTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var folderTasks: [UUID: Task<Void, Never>] = [:]
    private var hiddenLocations: Set<String> = []
    private let folderAccess = LibraryFolders()

    // Snapshot presentation values so SwiftUI can see a title change even when
    // NSDocument keeps the same object identity through Save As or a move.
    var openDocuments: [OpenDocument] {
        NSDocumentController.shared.documents.compactMap { document in
            guard let document = document as? WriterDocument else { return nil }
            return OpenDocument(document: document, title: document.displayName ?? "Untitled")
        }
    }

    init(recovery: RecoveryLibrary) { self.recovery = recovery }

    func noteRecent(_ url: URL) {
        hiddenLocations.remove(Self.location(url))
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        recent = uniqueRecent([url] + recent)
    }

    func refresh() {
        let nativeRecent = NSDocumentController.shared.recentDocumentURLs
        recent = uniqueRecent(recent + nativeRecent)
        refreshTask?.cancel()
        refreshTask = Task { [weak self, recovery] in
            do {
                let entries = try await recovery.recoveredEntries()
                let catalog = try await recovery.catalogEntries(includeHidden: true)
                guard let self, !Task.isCancelled else { return }
                self.catalog = catalog
                self.hiddenLocations = Set(catalog.filter { !$0.isVisible }.compactMap(\.location))
                let savedURLs = catalog.filter { $0.isVisible && $0.isFolder != true }.compactMap { $0.location.flatMap(URL.init(string:)) }
                self.recent = self.uniqueRecent(self.recent + savedURLs)
                self.pinned = catalog.filter { $0.isVisible && $0.isPinned == true && $0.isFolder != true }.compactMap { $0.location.flatMap(URL.init(string:)) }
                for record in catalog where record.isFolder == true && record.isVisible { self.loadFolder(record) }
                self.recovered = entries; self.recoveryUnavailable = false
            } catch {
                guard !Task.isCancelled else { return }
                self?.recoveryUnavailable = true
            }
        }
    }

    private func search() {
        searchTask?.cancel(); results = []; folderMatches = []
        let searchText = query
        guard !searchText.isEmpty else { return }
        searchTask = Task { [weak self, recovery] in
            do {
                try await Task.sleep(for: .milliseconds(180))
                let matches = (try? await recovery.searchCurrentText(searchText)) ?? []
                guard !Task.isCancelled, self?.query == searchText else { return }
                self?.results = matches
                guard let self else { return }
                let records = self.folders.map(\.record)
                for record in records {
                    try Task.checkCancellation()
                    guard let bookmark = record.bookmark else { continue }
                    do {
                        let listing = try await self.folderAccess.list(.bookmark(bookmark), query: searchText)
                        guard !Task.isCancelled, self.query == searchText else { return }
                        self.folderMatches += listing.entries.map { FolderMatch(folderID: record.id, entry: $0) }
                        if listing.limited || listing.unreadableCount > 0 {
                            self.libraryNotice = "Some files were unavailable or exceeded the search limit. Open a file to download it, or narrow your search."
                        }
                    } catch is CancellationError { return }
                    catch { self.libraryNotice = "A library folder is unavailable. Use Locate Folder to restore access." }
                }
            } catch { /* Keep native filename matches available when recovery is unavailable. */ }
        }
    }

    func openRecent(_ url: URL) {
        let location = url.standardizedFileURL.resolvingSymlinksInPath().absoluteString
        if let record = catalog.first(where: { $0.location == location }) { open(record); return }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if error != nil { self.offerLocate(url) }
        }
    }

    func removeRecent(_ url: URL) {
        hiddenLocations.insert(Self.location(url)); recent.removeAll { Self.location($0) == Self.location(url) }
        pinned.removeAll { Self.location($0) == Self.location(url) }
        Task {
            do { try await recovery.hideReference(at: url); refresh() }
            catch { libraryNotice = "Removed for this session. Recovery must be available to remember this change." }
        }
    }

    func pin(_ url: URL, value: Bool) {
        Task {
            do { try await recovery.pinReference(at: url, pinned: value); libraryNotice = nil; refresh() }
            catch { libraryNotice = "This reference could not be saved. Recovery must be available to remember pinned documents." }
        }
    }

    func locate(_ url: URL) {
        let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.title = "Locate Document"; panel.message = "Open the document at its current location. Its existing recovery is kept separately."
        panel.begin { [weak self] response in
            guard response == .OK, let selected = panel.url, let self else { return }
            NSDocumentController.shared.openDocument(withContentsOf: selected, display: true) { _, _, error in
                if let error { NSApp.presentError(error) }
                else {
                    if Self.location(url) != Self.location(selected) { self.removeRecent(url) }
                    self.noteRecent(selected)
                }
            }
        }
    }

    private func offerLocate(_ url: URL) {
        let alert = NSAlert(); alert.messageText = "This document is unavailable"
        alert.informativeText = "Locate the file to grant access again, or remove this reference. Removing it does not delete the file or private recovery."
        alert.addButton(withTitle: "Locate…"); alert.addButton(withTitle: "Remove Reference"); alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: locate(url)
        case .alertSecondButtonReturn: removeRecent(url)
        default: break
        }
    }

    func chooseFolder(replacing oldID: UUID? = nil) {
        guard oldID != nil || folders.count < 16 else { libraryNotice = "The library supports up to 16 selected folders."; return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.title = oldID == nil ? "Add Library Folder" : "Locate Library Folder"
        panel.message = "List Markdown and text files in this folder. Search reads current locally available text; private writing history is not indexed."
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            Task {
                do {
                    let bookmark = try await ScopedSourceFiles().bookmarkForExplicitSelection(url)
                    let existing = self.folders.first { $0.record.location == Self.location(url) }
                    var record = DocumentCatalogRecord(documentID: DocumentID(rawValue: oldID ?? existing?.id ?? UUID()),
                        title: url.lastPathComponent, location: Self.location(url), bookmark: bookmark)
                    record.isFolder = true; record.isOpen = false
                    do { try await self.recovery.rememberFolder(record) }
                    catch { self.libraryNotice = "Folder added for this session. Recovery must be available to remember it after quitting." }
                    self.loadFolder(record)
                } catch { self.libraryNotice = "The selected folder could not be opened. Its files were not changed." }
            }
        }
    }

    private func loadFolder(_ record: DocumentCatalogRecord) {
        guard let bookmark = record.bookmark else { return }
        if let index = folders.firstIndex(where: { $0.id == record.id }) { folders[index].record = record }
        else if folders.count < 16 { folders.append(Folder(record: record)) }
        else { return }
        folderTasks[record.id]?.cancel()
        folderTasks[record.id] = Task { [weak self, folderAccess] in
            do {
                let listing = try await folderAccess.list(.bookmark(bookmark))
                guard let self, !Task.isCancelled, let index = self.folders.firstIndex(where: { $0.id == record.id }) else { return }
                self.folders[index].entries = listing.entries
                self.folders[index].notice = listing.limited ? "Folder listing is limited. Select a smaller folder to see more." : nil
            } catch {
                guard let self, !Task.isCancelled, let index = self.folders.firstIndex(where: { $0.id == record.id }) else { return }
                self.folders[index].notice = "Unavailable — locate this folder to restore access."
            }
            self?.folderTasks[record.id] = nil
        }
    }

    func removeFolder(_ folder: Folder) {
        folderTasks[folder.id]?.cancel(); folderTasks[folder.id] = nil
        folders.removeAll { $0.id == folder.id }
        if let location = folder.record.location, let url = URL(string: location) {
            Task { do { try await recovery.hideReference(at: url) } catch { libraryNotice = "Removed for this session; private metadata is unavailable." } }
        }
    }

    func openFolderEntry(_ entry: LibraryFileEntry, folderID: UUID) {
        guard let folder = folders.first(where: { $0.id == folderID }), let bookmark = folder.record.bookmark else { return }
        do {
            let resolved = try NativeSourceBookmarks().resolve(bookmark)
            guard !resolved.isStale, LibraryFolders.contains(entry.url, in: resolved.url),
                  resolved.url.startAccessingSecurityScopedResource() else { throw SourceAccessError.permissionDenied }
            let lease = SelectedSourceLease(acquired: resolved.url)
            NSDocumentController.shared.openDocument(withContentsOf: entry.url, display: true) { document, _, error in
                if let document = document as? WriterDocument { document.retainSelectedScope(lease) }
                if let error { NSApp.presentError(error) }
            }
        } catch { libraryNotice = "Folder access changed. Locate the folder again; the file was not opened." }
    }

    private func uniqueRecent(_ urls: [URL]) -> [URL] {
        var seen = hiddenLocations
        var result: [URL] = []
        for url in urls where seen.insert(Self.location(url)).inserted {
            result.append(url)
            if result.count == 40 { break }
        }
        return result
    }

    private static func location(_ url: URL) -> String { url.standardizedFileURL.resolvingSymlinksInPath().absoluteString }

    func open(_ record: DocumentCatalogRecord, recovering: Bool = false) {
        if record.location != nil && !recovering {
            do {
                guard let bookmark = record.bookmark else { throw SourceAccessError.invalidBookmark }
                let resolved = try NativeSourceBookmarks().resolve(bookmark)
                guard !resolved.isStale else { throw SourceAccessError.staleBookmark }
                guard resolved.url.startAccessingSecurityScopedResource() else { throw SourceAccessError.permissionDenied }
                let lease = SelectedSourceLease(acquired: resolved.url)
                Task {
                    do { try await recovery.relocateReference(record.documentID, to: resolved.url) }
                    catch { libraryNotice = "Private metadata could not follow the file. The source file remains available." }
                    NSDocumentController.shared.openDocument(withContentsOf: resolved.url, display: true) { document, _, error in
                        if let document = document as? WriterDocument { document.retainSelectedScope(lease) }
                        if error != nil { self.offerLocate(resolved.url) }
                    }
                }
            } catch {
                if let location = record.location, let url = URL(string: location) { offerLocate(url) }
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
                Button { model.chooseFolder() } label: { Image(systemName: "folder.badge.plus") }
                    .help("Add Library Folder").accessibilityLabel("Add Library Folder")
            }.buttonStyle(.borderless).padding(12)
            TextField("Search documents", text: $model.query).textFieldStyle(.roundedBorder)
                .padding(.horizontal, 12).padding(.bottom, 8)
                .help("Search recent filenames and current locally stored text. Private writing history is not searched.")
            List {
                if model.query.isEmpty, !model.openDocuments.isEmpty {
                    Section("Open") {
                        ForEach(model.openDocuments) { entry in
                            Button { entry.document.showWindows() } label: { Label(entry.title, systemImage: "doc.text") }
                        }
                    }
                }
                if !model.query.isEmpty {
                    Section("Results") {
                        ForEach(model.results) { entry in
                            Button { model.open(entry, recovering: model.recovered.contains { $0.id == entry.id }) } label: { Label(entry.title, systemImage: "doc.text") }
                        }
                        ForEach(model.folderMatches) { match in
                            Button { model.openFolderEntry(match.entry, folderID: match.folderID) } label: { Label(match.entry.relativePath, systemImage: "doc.text") }
                        }
                    }
                }
                if !model.pinned.isEmpty && model.query.isEmpty {
                    Section("Pinned") {
                        ForEach(model.pinned, id: \.self) { url in
                            Button { model.openRecent(url) } label: { Label(url.lastPathComponent, systemImage: "pin") }
                                .contextMenu {
                                    Button("Unpin") { model.pin(url, value: false) }
                                    Button("Locate…") { model.locate(url) }
                                }
                        }
                    }
                }
                if model.query.isEmpty {
                    ForEach(model.folders) { folder in
                        Section {
                            ForEach(folder.entries) { entry in
                                Button { model.openFolderEntry(entry, folderID: folder.id) } label: { Label(entry.relativePath, systemImage: "doc.text") }
                            }
                            if let notice = folder.notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
                            HStack {
                                Button("Locate…") { model.chooseFolder(replacing: folder.id) }
                                Button("Remove") { model.removeFolder(folder) }
                            }.font(.caption)
                        } header: { Label(folder.record.title, systemImage: "folder") }
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
                            .contextMenu {
                                Button(model.pinned.contains(url) ? "Unpin" : "Pin") { model.pin(url, value: !model.pinned.contains(url)) }
                                Button("Locate…") { model.locate(url) }
                                Button("Remove Reference") { model.removeRecent(url) }
                            }
                    }
                    if model.recent.isEmpty { Text("Open a document to add it here.").foregroundStyle(.secondary).font(.callout) }
                }
                if model.recoveryUnavailable {
                    Text("Recovery unavailable").font(.caption).foregroundStyle(.secondary)
                }
                if let notice = model.libraryNotice { Text(notice).font(.caption).foregroundStyle(.secondary) }
            }.listStyle(.sidebar).buttonStyle(.plain)
            Button("Refresh") { model.refresh() }.buttonStyle(.borderless).padding(8)
        }.frame(minWidth: 180, idealWidth: 232).onAppear { model.refresh() }
    }
}
