import XCTest
import Foundation
import Darwin
@testable import WriterStorage
import WriterFoundation

@MainActor
final class CoordinatedSourceFilesTests: XCTestCase {
    private struct Fault: SourceFileFaultInjecting {
        let action: @Sendable (SourceFileFaultPoint) throws -> Void
        func checkpoint(_ point: SourceFileFaultPoint) throws { try action(point) }
    }
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("nw-file-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        return url
    }
    private func snapshot(_ bytes: Data, id: DocumentID = DocumentID(), revision: UInt64 = 0) throws -> SourceSnapshot {
        try .init(documentID: id, revision: Revision(revision), utf8: bytes)
    }
    private func reject(_ expected: SourceFileError, _ operation: () async throws -> Void) async {
        do { try await operation(); XCTFail("Expected \(expected)") }
        catch { XCTAssertEqual(error as? SourceFileError, expected) }
    }
    private func noTemporaryFiles(_ directory: URL) throws {
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: directory.path).contains { $0.hasPrefix(".nostr-writer-") })
    }

    func testExactCreateReopenReplaceAndMetadata() async throws {
        let folder = try directory(), url = folder.appendingPathComponent("source.md"), io = CoordinatedSourceFiles()
        let bytes = Data([0xef, 0xbb, 0xbf]) + Data("# Cafe\u{301}\r\n🇪🇸\t\n\n".utf8), source = try snapshot(bytes)
        let first = try await io.create(source, at: url)
        XCTAssertEqual(first.saved.source, source); XCTAssertEqual(first.localVersion.bytes, bytes)
        let read = try await io.read(url); XCTAssertEqual(read.bytes, bytes)
        XCTAssertEqual(chmod(url.path, 0o640), 0)
        let attribute = Data("fixture-tag".utf8)
        XCTAssertEqual(attribute.withUnsafeBytes { setxattr(url.path, "com.nostrwriter.test", $0.baseAddress, $0.count, 0, 0) }, 0)
        let next = try snapshot(bytes + Data("new".utf8), id: source.documentID, revision: 1)
        let saved = try await io.replace(next, at: url, expecting: read)
        XCTAssertEqual(saved.saved.source.revision, Revision(1))
        XCTAssertEqual(try Data(contentsOf: url), next.utf8)
        var info = stat(); XCTAssertEqual(lstat(url.path, &info), 0); XCTAssertEqual(info.st_mode & 0o777, 0o640)
        var value = [UInt8](repeating: 0, count: 64)
        let count = value.withUnsafeMutableBytes { getxattr(url.path, "com.nostrwriter.test", $0.baseAddress, $0.count, 0, 0) }
        XCTAssertEqual(Data(value.prefix(Int(max(count, 0)))), attribute)
        try noTemporaryFiles(folder)
    }

    func testMoveAcrossMountedVolumesPreservesExactBytesAndMetadata() async throws {
        guard let path = ProcessInfo.processInfo.environment["NW_CROSS_VOLUME_DIRECTORY"] else {
            throw XCTSkip("Set NW_CROSS_VOLUME_DIRECTORY to an explicitly mounted disposable test volume.")
        }
        let sourceFolder = try directory()
        let targetFolder = URL(fileURLWithPath: path, isDirectory: true)
            .appendingPathComponent("nw-cross-volume-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: targetFolder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: targetFolder) }
        var sourceInfo = stat(), targetInfo = stat()
        XCTAssertEqual(stat(sourceFolder.path, &sourceInfo), 0)
        XCTAssertEqual(stat(targetFolder.path, &targetInfo), 0)
        XCTAssertNotEqual(sourceInfo.st_dev, targetInfo.st_dev, "Must exercise the real cross-volume branch")
        let sourceURL = sourceFolder.appendingPathComponent("source.md")
        let targetURL = targetFolder.appendingPathComponent("moved.md")
        let bytes = Data([0xef, 0xbb, 0xbf]) + Data("Cross-volume Cafe\u{301} 🇪🇸\r\n\tExact source.\r\n".utf8)
        try bytes.write(to: sourceURL, options: .withoutOverwriting)
        XCTAssertEqual(chmod(sourceURL.path, 0o640), 0)
        let io = CoordinatedSourceFiles(), previous = try await io.read(sourceURL)
        let moved = try await io.move(previous, to: targetURL)
        XCTAssertTrue(moved.durabilityConfirmed)
        XCTAssertEqual(moved.file.bytes, bytes)
        XCTAssertEqual(try Data(contentsOf: targetURL), bytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertEqual(stat(targetURL.path, &targetInfo), 0)
        XCTAssertEqual(targetInfo.st_mode & 0o777, 0o640)
        try noTemporaryFiles(sourceFolder); try noTemporaryFiles(targetFolder)
    }

    func testExistingDestinationAndStaleReadPreserveBothInputs() async throws {
        let folder = try directory(), url = folder.appendingPathComponent("source.md"), io = CoordinatedSourceFiles()
        let local = try snapshot(Data("local".utf8))
        _ = try await io.create(local, at: url)
        await reject(.alreadyExists) { _ = try await io.create(try snapshot(Data("other".utf8)), at: url) }
        let old = try await io.read(url), external = Data("external\r\ne\u{301}".utf8)
        try external.write(to: url, options: .atomic)
        await reject(.externalChange) { _ = try await io.replace(local, at: url, expecting: old) }
        XCTAssertEqual(try Data(contentsOf: url), external); XCTAssertEqual(local.utf8, Data("local".utf8))
        let copy = folder.appendingPathComponent("source-conflict.md")
        _ = try await io.create(local, at: copy)
        XCTAssertEqual(try Data(contentsOf: copy), local.utf8)
        XCTAssertEqual(try Data(contentsOf: url), external)
        try noTemporaryFiles(folder)
    }

    func testExternalChangeDuringWriteIsRecheckedBeforeReplacement() async throws {
        let folder = try directory(), url = folder.appendingPathComponent("source.md"), ordinary = CoordinatedSourceFiles()
        let source = try snapshot(Data("first".utf8)); _ = try await ordinary.create(source, at: url)
        let old = try await ordinary.read(url), external = Data("concurrent other process".utf8)
        let io = CoordinatedSourceFiles(faults: Fault { point in
            if point == .beforeReplace { try external.write(to: url, options: .atomic) }
        })
        await reject(.externalChange) { _ = try await io.replace(try snapshot(Data("local changed".utf8)), at: url, expecting: old) }
        XCTAssertEqual(try Data(contentsOf: url), external); try noTemporaryFiles(folder)
    }

    func testNewCopyRaceCannotOverwriteTheOtherWritersFile() async throws {
        let folder = try directory(), url = folder.appendingPathComponent("new-copy.md"), winner = Data("other writer won".utf8)
        let source = try snapshot(Data("local copy".utf8))
        let io = CoordinatedSourceFiles(faults: Fault { point in
            if point == .beforeReplace { try winner.write(to: url, options: .withoutOverwriting) }
        })
        await reject(.alreadyExists) { _ = try await io.create(source, at: url) }
        XCTAssertEqual(try Data(contentsOf: url), winner); try noTemporaryFiles(folder)
    }

    func testFailuresBeforeAndAfterAtomicReplacementAreHonest() async throws {
        let folder = try directory(), original = Data("original".utf8), next = try snapshot(Data("next".utf8))
        for point in [SourceFileFaultPoint.beforeWrite, .beforeSync, .beforeReplace, .afterReplace] {
            let url = folder.appendingPathComponent(UUID().uuidString+".txt"); try original.write(to: url)
            let old = try await CoordinatedSourceFiles().read(url)
            let io = CoordinatedSourceFiles(faults: Fault { if $0 == point { throw SourceFileError.diskFull } })
            await reject(point == .afterReplace ? .replacementDurabilityUncertain : .diskFull) {
                _ = try await io.replace(next, at: url, expecting: old)
            }
            XCTAssertEqual(try Data(contentsOf: url), point == .afterReplace ? next.utf8 : original)
            try noTemporaryFiles(folder)
        }
    }

    func testHostileImportsNeverBecomeAnEmptyDocument() async throws {
        let started = ContinuousClock.now
        defer { XCTAssertLessThan(ContinuousClock.now - started, .seconds(5)) }
        let folder = try directory(), io = CoordinatedSourceFiles(), url = folder.appendingPathComponent("bad.md")
        try Data([0xc0,0xaf]).write(to: url)
        await reject(.invalidUTF8) { _ = try await io.read(url) }
        let missing = folder.appendingPathComponent("missing.md")
        await reject(.missing) { _ = try await io.read(missing) }
        await reject(.notRegularFile) { _ = try await io.read(folder) }
        let pipe = folder.appendingPathComponent("pipe"); XCTAssertEqual(mkfifo(pipe.path, 0o600), 0)
        await reject(.notRegularFile) { _ = try await io.read(pipe) }
        let link = folder.appendingPathComponent("link.md")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)
        await reject(.notRegularFile) { _ = try await io.read(link) }
        await reject(.invalidLocation) { _ = try await io.read(URL(string: "https://example.invalid/source.md")!) }
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(CoordinatedSourceFiles.maximumBytes + 1)); try handle.close()
        await reject(.sourceTooLarge) { _ = try await io.read(url) }
        try Data(repeating: 65, count: CoordinatedSourceFiles.maximumScalars+1).write(to: url)
        await reject(.sourceTooLarge) { _ = try await io.read(url) }
    }

    func testCancellationBeforeReplaceDoesNotCreateOrOverwrite() async throws {
        let folder = try directory(), url = folder.appendingPathComponent("cancelled.md"), source = try snapshot(Data("cancel me".utf8))
        let io = CoordinatedSourceFiles(faults: Fault { point in
            if point == .beforeReplace { withUnsafeCurrentTask { $0?.cancel() } }
        })
        let task = Task.detached { try await io.create(source, at: url) }
        do { _ = try await task.value; XCTFail("Cancelled write returned success") }
        catch is CancellationError {} catch { XCTFail("Unexpected cancellation error") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path)); try noTemporaryFiles(folder)
    }

    func testTwoCoordinatedWritersSerializeAndRejectTheStaleSave() async throws {
        let folder = try directory(), url = folder.appendingPathComponent("shared.md")
        let original = try snapshot(Data("baseline".utf8)), first = try snapshot(Data("writer one".utf8)), second = try snapshot(Data("writer two".utf8))
        let io = CoordinatedSourceFiles(); _ = try await io.create(original, at: url); let old = try await io.read(url)
        let results = await withTaskGroup(of: Result<SourceFileWrite, SourceFileError>.self) { group in
            for source in [first, second] {
                group.addTask {
                    do { return .success(try await CoordinatedSourceFiles().replace(source, at: url, expecting: old)) }
                    catch { return .failure(error as? SourceFileError ?? .ioFailure) }
                }
            }
            var values: [Result<SourceFileWrite, SourceFileError>] = []
            for await result in group { values.append(result) }; return values
        }
        var successes: [SourceFileWrite] = [], failures: [SourceFileError] = []
        for result in results { switch result { case .success(let value): successes.append(value); case .failure(let error): failures.append(error) } }
        XCTAssertEqual(successes.count, 1); XCTAssertEqual(failures, [.externalChange])
        XCTAssertEqual(try Data(contentsOf: url), try XCTUnwrap(successes.first).saved.source.utf8)
        try noTemporaryFiles(folder)
    }

    func testSecondCoordinatedProcessCannotBeOverwrittenFromAnOldRead() async throws {
        guard let binary = ProcessInfo.processInfo.environment["NW_COORDINATED_WRITER"] else { throw XCTSkip("compile Tools/coordinated_writer.swift and set NW_COORDINATED_WRITER") }
        let folder = try directory(), url = folder.appendingPathComponent("shared.md"), io = CoordinatedSourceFiles()
        let local = try snapshot(Data("first local source".utf8)), external = Data("second process\r\nCAFÉ\n".utf8)
        _ = try await io.create(local, at: url); let old = try await io.read(url)
        let process = Process(); process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = [url.path, external.base64EncodedString()]
        try process.run(); process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0)
        let imported = try await io.read(url); XCTAssertEqual(imported.bytes, external)
        await reject(.externalChange) { _ = try await io.replace(local, at: url, expecting: old) }
        XCTAssertEqual(try Data(contentsOf: url), external)
        let copy = folder.appendingPathComponent("kept-local.md"); _ = try await io.create(local, at: copy)
        XCTAssertEqual(try Data(contentsOf: copy), local.utf8)
    }
}
