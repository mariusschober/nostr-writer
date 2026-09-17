import Foundation
import WriterFoundation

public enum SourceAccessError: Error, Sendable, Equatable {
    case invalidBookmark, staleBookmark, permissionDenied, unavailable
}

/// A panel/explicitly selected URL already carries the caller's grant. A saved
/// bookmark must separately resolve and acquire its grant, without displaying UI.
public enum SourceLocation: Sendable {
    case selectedURL(URL)
    case bookmark(Data)
}
public struct ResolvedSourceBookmark: Sendable {
    public let url: URL
    public let isStale: Bool
    public init(url: URL, isStale: Bool) { self.url = url; self.isStale = isStale }
}
public protocol SourceBookmarkProviding: Sendable {
    func create(for selectedURL: URL) throws -> Data
    func resolve(_ bookmark: Data) throws -> ResolvedSourceBookmark
    func start(_ url: URL) -> Bool
    func stop(_ url: URL)
}
public struct NativeSourceBookmarks: SourceBookmarkProviding {
    public init() {}
    public func create(for selectedURL: URL) throws -> Data {
        do { return try selectedURL.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) }
        catch { throw SourceAccessError.unavailable }
    }
    public func resolve(_ bookmark: Data) throws -> ResolvedSourceBookmark {
        var stale = false
        do {
            let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale)
            return ResolvedSourceBookmark(url: url, isStale: stale)
        } catch { throw SourceAccessError.invalidBookmark }
    }
    public func start(_ url: URL) -> Bool { url.startAccessingSecurityScopedResource() }
    public func stop(_ url: URL) { url.stopAccessingSecurityScopedResource() }
}

/// Owns access only for the duration of each separate file operation. A stale
/// bookmark requires a new explicit selection; resolving it never auto-renews
/// or overwrites stored metadata. Raw bookmark bytes should remain app-private.
public actor ScopedSourceFiles {
    public static let maximumBookmarkBytes = 1024 * 1024
    private let bookmarks: any SourceBookmarkProviding
    private let files: CoordinatedSourceFiles
    public init(bookmarks: any SourceBookmarkProviding = NativeSourceBookmarks(), files: CoordinatedSourceFiles = CoordinatedSourceFiles()) {
        self.bookmarks = bookmarks; self.files = files
    }
    public func bookmarkForExplicitSelection(_ url: URL) throws -> Data {
        try Self.validate(url); try Task.checkCancellation()
        let acquired = bookmarks.start(url); defer { if acquired { bookmarks.stop(url) } }
        let data = try bookmarks.create(for: url)
        guard !data.isEmpty, data.count <= Self.maximumBookmarkBytes else { throw SourceAccessError.invalidBookmark }
        return data
    }
    public func read(_ location: SourceLocation) async throws -> SourceFileRead {
        let access = try acquire(location); defer { if access.started { bookmarks.stop(access.url) } }
        return try await files.read(access.url)
    }
    public func create(_ source: SourceSnapshot, at location: SourceLocation) async throws -> SourceFileWrite {
        let access = try acquire(location); defer { if access.started { bookmarks.stop(access.url) } }
        return try await files.create(source, at: access.url)
    }
    public func replace(_ source: SourceSnapshot, at location: SourceLocation, expecting previous: SourceFileRead) async throws -> SourceFileWrite {
        let access = try acquire(location); defer { if access.started { bookmarks.stop(access.url) } }
        // If a bookmark resolves to a moved location, the caller first re-reads and
        // reconciles identity there. An old-path observation is not a write grant.
        return try await files.replace(source, at: access.url, expecting: previous)
    }
    private func acquire(_ location: SourceLocation) throws -> (url: URL, started: Bool) {
        try Task.checkCancellation()
        switch location {
        case .selectedURL(let url):
            try Self.validate(url)
            // Open/Save panels already grant access; a false return may also mean
            // this file is within the app container. Let actual I/O check access.
            return (url, bookmarks.start(url))
        case .bookmark(let data):
            guard !data.isEmpty, data.count <= Self.maximumBookmarkBytes else { throw SourceAccessError.invalidBookmark }
            let result = try bookmarks.resolve(data); try Self.validate(result.url)
            guard !result.isStale else { throw SourceAccessError.staleBookmark }
            guard bookmarks.start(result.url) else { throw SourceAccessError.permissionDenied }
            return (result.url, true)
        }
    }
    private static func validate(_ url: URL) throws {
        guard url.isFileURL, url.path.hasPrefix("/"), !url.path.utf8.contains(0), url.host == nil || url.host == "" || url.host == "localhost" else { throw SourceFileError.invalidLocation }
    }
}
