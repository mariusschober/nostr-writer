import Foundation

public struct LibraryFileEntry: Sendable, Equatable, Identifiable {
    public let url: URL
    public let relativePath: String
    public var id: URL { url }
}

public struct LibraryFolderListing: Sendable {
    public let root: URL
    public let entries: [LibraryFileEntry]
    public let limited: Bool
    public let unreadableCount: Int
}

/// An explicitly selected folder only; no disk-wide discovery, Spotlight index,
/// persistent plaintext bodies or symlink traversal. Each operation owns its grant.
public actor LibraryFolders {
    private let bookmarks: any SourceBookmarkProviding
    private let files = CoordinatedSourceFiles()
    public init(bookmarks: any SourceBookmarkProviding = NativeSourceBookmarks()) { self.bookmarks = bookmarks }

    public func list(_ location: SourceLocation, query: String = "") async throws -> LibraryFolderListing {
        guard query.utf8.count <= 4096 else { throw SourceFileError.sourceTooLarge }
        let access = try acquire(location)
        defer { if access.started { bookmarks.stop(access.root) } }
        let root = access.root.standardizedFileURL.resolvingSymlinksInPath()
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
            .fileSizeKey, .fileAllocatedSizeKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        guard try root.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw SourceFileError.notRegularFile }
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { throw SourceFileError.permissionDenied }
        var entries: [LibraryFileEntry] = [], visited = 0, searchedBytes = 0, unreadable = 0, limited = false
        while let enumerated = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            // DirectoryEnumerator can expose /private/var while the selected
            // root uses /var. Compare and display the same standardized form.
            let candidate = enumerated.standardizedFileURL
            visited += 1
            if visited > 4096 { limited = true; break }
            let values: URLResourceValues
            do { values = try candidate.resourceValues(forKeys: Set(keys)) }
            catch { unreadable += 1; continue }
            // skipDescendants on a non-directory can skip a later sibling's
            // subtree. The enumerator does not traverse symbolic links.
            guard values.isSymbolicLink != true else { continue }
            guard Self.contains(candidate, in: root) else {
                if values.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            let relative = candidate.pathComponents.dropFirst(root.pathComponents.count).joined(separator: "/")
            if relative.split(separator: "/").count > 8 { enumerator.skipDescendants(); limited = true; continue }
            guard values.isRegularFile == true, ["md", "txt"].contains(candidate.pathExtension.lowercased()) else { continue }
            let entry = LibraryFileEntry(url: candidate, relativePath: relative)
            if query.isEmpty || relative.localizedCaseInsensitiveContains(query) { entries.append(entry); continue }
            // Search materialized current files only. Opening unavailable remote
            // content is a separate native Open operation with provider progress.
            if values.isUbiquitousItem == true,
               ![URLUbiquitousItemDownloadingStatus.current, .downloaded].contains(values.ubiquitousItemDownloadingStatus ?? .notDownloaded) {
                unreadable += 1; continue
            }
            let size = values.fileSize ?? 0
            if size > 0 && values.fileAllocatedSize == 0 { unreadable += 1; continue }
            guard size <= CoordinatedSourceFiles.maximumBytes, size <= 64 * 1024 * 1024 - searchedBytes else { limited = true; continue }
            do {
                let current = try await files.read(candidate)
                // A path may move while a provider materializes it. Never use a
                // returned source outside the selected root for library search.
                guard Self.contains(current.url, in: root) else { unreadable += 1; continue }
                guard current.bytes.count <= 64 * 1024 * 1024 - searchedBytes else { limited = true; continue }
                searchedBytes += current.bytes.count
                if String(decoding: current.bytes, as: UTF8.self).localizedCaseInsensitiveContains(query) { entries.append(entry) }
            } catch is CancellationError { throw CancellationError() }
            catch { unreadable += 1 }
        }
        entries.sort { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
        return LibraryFolderListing(root: root, entries: entries, limited: limited, unreadableCount: unreadable)
    }

    public nonisolated static func contains(_ candidate: URL, in root: URL) -> Bool {
        let base = root.standardizedFileURL.resolvingSymlinksInPath().path
        let selected = candidate.standardizedFileURL
        let canonical = selected.resolvingSymlinksInPath()
        // Reject symlinks even when they happen to point back inside the grant.
        guard selected.path == canonical.path else { return false }
        return canonical.path.hasPrefix(base == "/" ? "/" : base + "/") && canonical.path != base
    }

    private func acquire(_ location: SourceLocation) throws -> (root: URL, started: Bool) {
        let root: URL, requiresAccess: Bool
        switch location {
        case .selectedURL(let url): root = url; requiresAccess = false
        case .bookmark(let data):
            guard !data.isEmpty, data.count <= ScopedSourceFiles.maximumBookmarkBytes else { throw SourceAccessError.invalidBookmark }
            let resolved = try bookmarks.resolve(data)
            guard !resolved.isStale else { throw SourceAccessError.staleBookmark }
            root = resolved.url; requiresAccess = true
        }
        guard root.isFileURL, root.host == nil || root.host == "" || root.host == "localhost" else { throw SourceFileError.invalidLocation }
        let started = bookmarks.start(root)
        guard started || !requiresAccess else { throw SourceAccessError.permissionDenied }
        return (root, started)
    }
}
