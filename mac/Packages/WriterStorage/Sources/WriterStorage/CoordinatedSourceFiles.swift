import Foundation
import Darwin
import WriterFoundation

/// Safe, actionable categories only: underlying paths, contents and provider
/// error descriptions must not leak into logs or UI diagnostics.
public enum SourceFileError: Error, Equatable, Sendable {
    case invalidLocation, missing, permissionDenied, unavailable, notRegularFile
    case sourceTooLarge, invalidUTF8, changedDuringRead, externalChange
    case alreadyExists, diskFull, cancelled, ioFailure, durabilityUnavailable
    /// Replacement completed but final directory synchronization failed. The
    /// caller must reread/reconcile; it must not retry with an old expected source.
    case replacementDurabilityUncertain
}

public struct SourceFileRead: Sendable, Equatable {
    public let url: URL
    public let bytes: Data
    public let digest: Data
    /// Presentation metadata only, never an ordering/conflict decision.
    public let modificationDate: Date?
    public var byteCount: Int { bytes.count }
    init(url: URL, bytes: Data) {
        self.url = url; self.bytes = bytes; self.digest = SourceSnapshot.sha256(bytes)
        self.modificationDate = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}

public struct SourceFileWrite: Sendable {
    public let saved: SavedFileRevision
    /// Local coordinated replacement only, never remote upload confirmation.
    public let localVersion: SourceFileRead
}

public enum SourceFileFaultPoint: Sendable { case beforeWrite, beforeSync, beforeReplace, afterReplace }
public protocol SourceFileFaultInjecting: Sendable { func checkpoint(_ point: SourceFileFaultPoint) throws }
public struct NoSourceFileFault: SourceFileFaultInjecting {
    public init() {}
    public func checkpoint(_ point: SourceFileFaultPoint) throws {}
}

/// NSFileCoordinator.h explicitly permits cancel() from any thread and returns
/// immediately. Only this operation-local cancellation handle crosses executors;
/// the coordinator's configuration/accessor work stays on its owning actor.
private final class FileCoordinationCancellation: @unchecked Sendable {
    let coordinator: NSFileCoordinator
    init(presenter: (any NSFilePresenter & Sendable)? = nil) { coordinator = NSFileCoordinator(filePresenter: presenter) }
    func cancel() { coordinator.cancel() }
}

/// Coordinated operations for separate copies/imports and other files not already
/// managed by an NSDocument accessor. NEVER nest these calls inside NSDocument's
/// read/write callbacks: NSDocument owns that coordination itself. This actor
/// performs bounded source I/O away from the editor/main actor, with no networking.
/// A caller must hold the selected URL's security-scoped grant for each operation.
public actor CoordinatedSourceFiles {
    public static let maximumBytes = 8 * 1024 * 1024
    public static let maximumScalars = 1_000_000
    private let faults: any SourceFileFaultInjecting
    public init(faults: any SourceFileFaultInjecting = NoSourceFileFault()) { self.faults = faults }

    public func read(_ url: URL, excluding presenter: (any NSFilePresenter & Sendable)? = nil) async throws -> SourceFileRead {
        try Self.validate(url)
        try Task.checkCancellation(); try Self.preflight(url, mustBeNew: false)
        let cancellation = FileCoordinationCancellation(presenter: presenter)
        let coordinator = cancellation.coordinator
        return try await withTaskCancellationHandler {
            try coordinatedRead(url, coordinator: coordinator)
        } onCancel: { cancellation.cancel() }
    }

    /// Explicit import reads bounded original bytes before the person selects
    /// their encoding. Ordinary source reads still require strict UTF-8.
    public func readForTextImport(_ url: URL) async throws -> Data {
        try await readBinaryInput(url, maximumBytes: Self.maximumBytes)
    }

    public func readBinaryInput(_ url: URL, maximumBytes readLimit: Int) async throws -> Data {
        guard readLimit > 0, readLimit <= 20 * 1024 * 1024 else { throw SourceFileError.sourceTooLarge }
        try Self.validate(url); try Self.preflight(url, mustBeNew: false, readLimit: readLimit)
        let cancellation = FileCoordinationCancellation()
        return try await withTaskCancellationHandler {
            var coordinationError: NSError?, result: Result<Data, Error>?
            cancellation.coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { target in
                result = Result { try Self.readExact(target, requireUTF8: false, readLimit: readLimit) }
            }
            if let coordinationError { throw Self.safe(coordinationError) }
            guard let result else { throw SourceFileError.unavailable }
            return try result.get()
        } onCancel: { cancellation.cancel() }
    }

    /// New, validated image bytes only. Never replaces an existing path.
    public func createAssetBytes(_ bytes: Data, at url: URL) throws {
        guard bytes.count <= 20 * 1024 * 1024 else { throw SourceFileError.sourceTooLarge }
        try Self.validate(url); try Self.preflight(url, mustBeNew: true)
        var coordinationError: NSError?, result: Result<Void, Error>?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: [], error: &coordinationError) { target in
            result = Result { try Self.atomicWrite(bytes, at: target, expected: nil, faults: self.faults) }
        }
        if let coordinationError { throw Self.safe(coordinationError) }
        guard let result else { throw SourceFileError.unavailable }; try result.get()
    }

    /// Only for a native document writer already inside its coordinated file
    /// accessor. Adding another coordinator there would risk recursive access.
    public nonisolated static func readInsideNativeAccessor(_ url: URL) throws -> Data {
        try validate(url)
        return try readExact(url)
    }

    private func coordinatedRead(_ url: URL, coordinator: NSFileCoordinator) throws -> SourceFileRead {
        try Task.checkCancellation()
        var coordinatorError: NSError?, value: Result<SourceFileRead, Error>?
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinatorError) { coordinated in
            value = Result { SourceFileRead(url: coordinated, bytes: try Self.readExact(coordinated)) }
        }
        if let coordinatorError { throw Self.safe(coordinatorError) }
        guard let value else { throw SourceFileError.unavailable }
        return try value.get()
    }

    /// A new user-selected source/copy. Refuses every existing destination,
    /// including symlinks. A failed operation never replaces a nearby file.
    public func create(_ source: SourceSnapshot, at url: URL) async throws -> SourceFileWrite {
        try await write(source, to: url, expected: nil)
    }

    /// Compare exact source again inside the writer coordination. This protects
    /// against cooperating provider writers after the UI last observed the file.
    /// Other processes which deliberately bypass coordination can still race it;
    /// callers must retain recovery and reconcile subsequent presenter events.
    public func replace(_ source: SourceSnapshot, at url: URL, expecting previous: SourceFileRead) async throws -> SourceFileWrite {
        guard previous.url.standardizedFileURL == url.standardizedFileURL else { throw SourceFileError.invalidLocation }
        return try await write(source, to: url, expected: previous.bytes)
    }

    private func write(_ source: SourceSnapshot, to url: URL, expected: Data?) async throws -> SourceFileWrite {
        try Self.validate(url); try Self.validateSource(source.utf8)
        try Task.checkCancellation(); try Self.preflight(url, mustBeNew: expected == nil)
        let cancellation = FileCoordinationCancellation()
        let coordinator = cancellation.coordinator
        return try await withTaskCancellationHandler {
            try coordinatedWrite(source, to: url, expected: expected, coordinator: coordinator)
        } onCancel: { cancellation.cancel() }
    }

    private func coordinatedWrite(_ source: SourceSnapshot, to url: URL, expected: Data?, coordinator: NSFileCoordinator) throws -> SourceFileWrite {
        try Task.checkCancellation()
        var coordinatorError: NSError?, value: Result<SourceFileWrite, Error>?
        coordinator.coordinate(writingItemAt: url, options: expected == nil ? [] : .forReplacing, error: &coordinatorError) { coordinated in
            value = Result {
                try Self.atomicWrite(source.utf8, at: coordinated, expected: expected, faults: faults)
                return SourceFileWrite(saved: SavedFileRevision(source: source, url: coordinated), localVersion: SourceFileRead(url: coordinated, bytes: source.utf8))
            }
        }
        if let coordinatorError { throw Self.safe(coordinatorError) }
        guard let value else { throw SourceFileError.unavailable }
        return try value.get()
    }

    private static func validate(_ url: URL) throws {
        guard url.isFileURL, url.host == nil || url.host == "" || url.host == "localhost",
              !url.path.isEmpty, url.path.hasPrefix("/"), !url.path.utf8.contains(0),
              !["", ".", "..", "/"].contains(url.lastPathComponent) else { throw SourceFileError.invalidLocation }
    }
    /// NSFileCoordinator may open the item itself before invoking our accessor;
    /// reject FIFOs/devices/symlinks here so that its open cannot block on them.
    /// Missing paths are left to coordination (providers may materialize them).
    /// Accessor checks remain mandatory for changes after this advisory preflight.
    private static func preflight(_ url: URL, mustBeNew: Bool, readLimit: Int = maximumBytes) throws {
        var info = stat()
        if lstat(url.path, &info) == 0 {
            if mustBeNew { throw SourceFileError.alreadyExists }
            try regular(info, readLimit: readLimit)
        } else if errno != ENOENT { throw posix() }
    }

    private static func validateSource(_ bytes: Data) throws {
        guard bytes.count <= maximumBytes else { throw SourceFileError.sourceTooLarge }
        guard SourceSnapshot.firstInvalidUTF8Offset(in: bytes) == nil else { throw SourceFileError.invalidUTF8 }
        guard String(decoding: bytes, as: UTF8.self).unicodeScalars.count <= maximumScalars else { throw SourceFileError.sourceTooLarge }
    }
    private static func safe(_ error: NSError) -> SourceFileError {
        if error.domain == NSPOSIXErrorDomain { return posix(Int32(error.code)) }
        if error.domain == NSCocoaErrorDomain {
            switch error.code {
            case NSFileReadNoSuchFileError, NSFileNoSuchFileError: return .missing
            case NSFileReadNoPermissionError, NSFileWriteNoPermissionError: return .permissionDenied
            case NSFileWriteOutOfSpaceError: return .diskFull
            case NSUserCancelledError: return .cancelled
            default: break
            }
        }
        return .unavailable
    }
    private static func posix(_ code: Int32 = errno) -> SourceFileError {
        switch code {
        case ENOENT: return .missing
        case EACCES, EPERM, EROFS: return .permissionDenied
        case EEXIST: return .alreadyExists
        case ENOSPC, EDQUOT: return .diskFull
        case ELOOP, EISDIR, ENOTDIR: return .notRegularFile
        case ENXIO, ENODEV, ETIMEDOUT: return .unavailable
        default: return .ioFailure
        }
    }
    private static func regular(_ stat: stat, readLimit: Int = maximumBytes) throws {
        guard stat.st_mode & S_IFMT == S_IFREG else { throw SourceFileError.notRegularFile }
        guard stat.st_size >= 0, stat.st_size <= readLimit else { throw SourceFileError.sourceTooLarge }
    }
    private static func sameVersion(_ a: stat, _ b: stat) -> Bool {
        a.st_dev == b.st_dev && a.st_ino == b.st_ino && a.st_size == b.st_size &&
        a.st_mtimespec.tv_sec == b.st_mtimespec.tv_sec && a.st_mtimespec.tv_nsec == b.st_mtimespec.tv_nsec &&
        a.st_ctimespec.tv_sec == b.st_ctimespec.tv_sec && a.st_ctimespec.tv_nsec == b.st_ctimespec.tv_nsec
    }
    private static func readExact(_ url: URL, requireUTF8: Bool = true, readLimit: Int = maximumBytes) throws -> Data {
        let fd = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw posix() }; defer { Darwin.close(fd) }
        var before = stat(); guard fstat(fd, &before) == 0 else { throw posix() }; try regular(before, readLimit: readLimit)
        var bytes = Data(), buffer = [UInt8](repeating: 0, count: 65536)
        bytes.reserveCapacity(Int(before.st_size))
        while true {
            try Task.checkCancellation()
            let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
            if count == 0 { break }
            if count < 0 { if errno == EINTR { continue }; throw posix() }
            guard count <= readLimit - bytes.count else { throw SourceFileError.sourceTooLarge }
            bytes.append(contentsOf: buffer.prefix(count))
        }
        var after = stat(), pathNow = stat()
        guard fstat(fd, &after) == 0, lstat(url.path, &pathNow) == 0 else { throw posix() }
        guard sameVersion(before, after), sameVersion(after, pathNow), bytes.count == Int(after.st_size) else { throw SourceFileError.changedDuringRead }
        if requireUTF8 { try validateSource(bytes) }
        return bytes
    }
    private static func syncFile(_ fd: Int32) throws {
        guard fsync(fd) == 0, fcntl(fd, F_FULLFSYNC) == 0 else { throw SourceFileError.durabilityUnavailable }
    }
    private static func atomicWrite(_ bytes: Data, at url: URL, expected: Data?, faults: any SourceFileFaultInjecting) throws {
        // Replacing a symlink, directory or stale source is never implicit consent.
        var originalMode: mode_t = 0o600
        if let expected {
            guard try readExact(url) == expected else { throw SourceFileError.externalChange }
            var info = stat(); guard lstat(url.path, &info) == 0 else { throw posix() }; try regular(info)
            originalMode = info.st_mode & 0o777
        } else {
            var info = stat()
            if lstat(url.path, &info) == 0 { throw SourceFileError.alreadyExists }
            guard errno == ENOENT else { throw posix() }
        }
        try Task.checkCancellation(); try faults.checkpoint(.beforeWrite)
        let parent = url.deletingLastPathComponent()
        let temporary = parent.appendingPathComponent(".nostr-writer-\(UUID().uuidString).tmp")
        let fd = Darwin.open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw posix() }
        var installed = false
        defer { Darwin.close(fd); if !installed { _ = unlink(temporary.path) } }
        try bytes.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                try Task.checkCancellation()
                let count = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), min(65536, buffer.count-offset))
                if count < 0 { if errno == EINTR { continue }; throw posix() }
                guard count > 0 else { throw SourceFileError.ioFailure }; offset += count
            }
        }
        if expected != nil {
            let original = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
            guard original >= 0 else { throw posix() }; defer { Darwin.close(original) }
            var info = stat(); guard fstat(original, &info) == 0 else { throw posix() }; try regular(info)
            // Retain ACLs and extended attributes (including Finder tags), not just
            // source bytes. Metadata failure occurs before atomic replacement.
            guard fcopyfile(original, fd, nil, copyfile_flags_t(COPYFILE_METADATA)) == 0 else { throw posix() }
        }
        guard fchmod(fd, originalMode) == 0 else { throw posix() }
        try faults.checkpoint(.beforeSync); try syncFile(fd)
        try Task.checkCancellation(); try faults.checkpoint(.beforeReplace); try Task.checkCancellation()
        // A fault/callback may have delivered new bytes since the first read.
        if let expected { guard try readExact(url) == expected else { throw SourceFileError.externalChange } }
        let result = expected == nil
            ? renamex_np(temporary.path, url.path, UInt32(RENAME_EXCL))
            : rename(temporary.path, url.path)
        guard result == 0 else { throw posix() }; installed = true
        // There is no cancellation boundary after replacement: report the actual
        // committed local outcome instead of pretending it never happened.
        do {
            try faults.checkpoint(.afterReplace)
            let directory = Darwin.open(parent.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
            guard directory >= 0 else { throw posix() }; defer { Darwin.close(directory) }
            guard fsync(directory) == 0 else { throw SourceFileError.durabilityUnavailable }
        } catch { throw SourceFileError.replacementDurabilityUncertain }
    }
}
