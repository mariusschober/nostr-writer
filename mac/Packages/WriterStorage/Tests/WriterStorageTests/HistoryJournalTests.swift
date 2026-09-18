import XCTest
import CryptoKit
@testable import WriterStorage
import WriterFoundation

final class HistoryJournalTests: XCTestCase {
    private func makeJournal(_ workspace: TempWorkspace, key: SymmetricKey = testKey(),
                             capacity: HistoryCapacity = .standard) throws -> HistoryJournal {
        try HistoryJournal(configuration: configuration(workspace),
                           keyProvider: InMemoryKeyProvider(key: key),
                           capacity: capacity,
                           clock: MonotonicClock(),
                           uuidGenerator: CountingUUIDGenerator(),
                           nonceGenerator: CountingNonceGenerator())
    }

    private func insertRecord(epoch: CaptureEpoch, source: SourceSnapshot, text: String,
                              origin: EditOrigin = .directNativeInput) throws -> LocalEditRecord {
        let range = try ByteRange(lowerBound: source.byteCount, upperBound: source.byteCount)
        let command = try EditCommand(id: UUID(), expectedRevision: source.revision, range: range,
                                      replacement: Data(text.utf8), origin: origin, undoGroup: UUID())
        let receipt = try command.applying(to: source, completeness: .descriptiveOnly)
        return LocalEditRecord(epochID: epoch.id, receipt: receipt, recordedAtEpochSeconds: 1)
    }

    func testJournalRoundTripsEncryptsReplaysAndDeletes() async throws {
        let workspace = try TempWorkspace(); defer { workspace.remove() }
        let id = DocumentID()
        let journal = try makeJournal(workspace)
        let initial = try makeSnapshot(id, 0, "ordinary opening line")
        let epoch = try await journal.beginEpoch(documentID: id, atRevision: initial.revision,
                                                 priorTextCompleteness: .descriptiveOnly)
        try await journal.append([try insertRecord(epoch: epoch, source: initial, text: " SECRETTOKEN")])
        let annotation = SourceAnnotation(kind: .quotation,
                                          range: try ByteRange(lowerBound: 0, upperBound: 8),
                                          description: "PRIVATENOTE", url: "https://example.test/a",
                                          revision: initial.revision)
        try await journal.saveAnnotation(annotation, documentID: id)

        let rows = try await journal.records(documentID: id)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].record.inserted, Data(" SECRETTOKEN".utf8))
        XCTAssertEqual(rows[0].record.originCategory, .directNativeInput)
        let replayed = try LocalReplay.replay(from: initial, records: rows.map(\.record))
        XCTAssertEqual(replayed.utf8, initial.utf8 + Data(" SECRETTOKEN".utf8))

        let annotations = try await journal.annotations(documentID: id)
        XCTAssertEqual(annotations.count, 1)
        XCTAssertEqual(annotations[0].description, "PRIVATENOTE")
        XCTAssertEqual(annotations[0].url, "https://example.test/a")

        let summary = try await journal.summary(documentID: id)
        XCTAssertEqual(summary.recordCount, 1)
        XCTAssertEqual(summary.annotationCount, 1)
        XCTAssertNotNil(summary.openEpochID)
        XCTAssertEqual(summary.retention, .healthy)

        // Encryption at rest: no plaintext writing reaches the database or WAL.
        let raw = storeFiles(workspace.databaseURL).compactMap { try? Data(contentsOf: $0) }.reduce(Data(), +)
        XCTAssertNil(raw.range(of: Data("SECRETTOKEN".utf8)), "inserted text must be sealed before SQLite")
        XCTAssertNil(raw.range(of: Data("PRIVATENOTE".utf8)), "annotation text must be sealed before SQLite")

        try await journal.deleteLocalHistory(documentID: id)
        let afterDelete = try await journal.records(documentID: id)
        let annotationsAfterDelete = try await journal.annotations(documentID: id)
        XCTAssertTrue(afterDelete.isEmpty)
        XCTAssertTrue(annotationsAfterDelete.isEmpty)
        await journal.close()
    }

    func testRecordingEpochsAndGapsAreHonest() async throws {
        let workspace = try TempWorkspace(); defer { workspace.remove() }
        let id = DocumentID()
        let journal = try makeJournal(workspace)
        let initial = try makeSnapshot(id, 0, "text")

        // Appending into an epoch that was never opened is refused, not invented.
        let orphan = CaptureEpoch(documentID: id, recordingUUID: UUID(), beganAtRevision: Revision(0),
                                  beganAtEpochSeconds: 0, priorTextCompleteness: .descriptiveOnly)
        do { try await journal.append([try insertRecord(epoch: orphan, source: initial, text: "x")])
             XCTFail("An unopened epoch must not accept records") }
        catch let error as HistoryError { XCTAssertEqual(error, .epochUnknown) }

        let epoch = try await journal.beginEpoch(documentID: id, atRevision: initial.revision,
                                                 priorTextCompleteness: .descriptiveOnly)
        let reopened = try await journal.resumeOrOpenEpoch(documentID: id, atRevision: Revision(1),
                                                           priorTextCompleteness: .descriptiveOnly)
        XCTAssertEqual(reopened.id, epoch.id, "An open epoch is reused, not duplicated")
        try await journal.appendGap(CaptureGap(reason: .userPaused, revision: Revision(1), recordedAtEpochSeconds: 5),
                                    documentID: id, epochID: epoch.id)
        try await journal.endEpoch(epoch.id)
        let resumed = try await journal.resumeOrOpenEpoch(documentID: id, atRevision: Revision(1),
                                                          priorTextCompleteness: .descriptiveOnly)
        XCTAssertNotEqual(resumed.id, epoch.id, "A new epoch follows a pause")
        let gaps = try await journal.gaps(documentID: id)
        XCTAssertEqual(gaps.map(\.reason), [.userPaused, .resumed])
        await journal.close()
    }

    func testCapacityPausesDetailedHistoryWithoutStoppingWriting() async throws {
        let workspace = try TempWorkspace(); defer { workspace.remove() }
        let id = DocumentID()
        let journal = try makeJournal(workspace, capacity: HistoryCapacity(warnBytes: 200, pauseBytes: 400))
        let initial = try makeSnapshot(id, 0, "body")
        let epoch = try await journal.beginEpoch(documentID: id, atRevision: initial.revision,
                                                 priorTextCompleteness: .descriptiveOnly)
        var appended = 0
        for index in 0..<60 {
            if !(try await journal.retentionState()).acceptsNewRecords { break }
            try await journal.append([try insertRecord(epoch: epoch, source: initial,
                                                       text: "passage-\(index)-abcdefghij")])
            appended += 1
        }
        let state = try await journal.retentionState()
        XCTAssertFalse(state.acceptsNewRecords, "Capacity must eventually pause detailed recording")
        if case .pausedLimit = state {} else { XCTFail("Expected pausedLimit, got \(state)") }
        let countBefore = try await journal.records(documentID: id).count
        XCTAssertEqual(countBefore, appended)
        try await journal.append([try insertRecord(epoch: epoch, source: initial, text: "nope")])
        let countAfter = try await journal.records(documentID: id).count
        XCTAssertEqual(countAfter, countBefore, "A paused journal is a no-op, never an error")
        XCTAssertGreaterThan(appended, 0)
        await journal.close()
    }

    func testDeleteLocalHistoryLeavesRecoveryIntact() async throws {
        let workspace = try TempWorkspace(); defer { workspace.remove() }
        let store = try makeStore(workspace)
        let id = DocumentID()
        let saved = try makeSnapshot(id, 5, "recovered source text")
        _ = try await store.persist(batch(saved))
        guard case .complete(let durable) = try await store.recover(id) else {
            return XCTFail("Recovery must be present before history is deleted")
        }
        XCTAssertEqual(durable.source, saved)

        let journal = try makeJournal(workspace)
        let epoch = try await journal.beginEpoch(documentID: id, atRevision: saved.revision,
                                                 priorTextCompleteness: .descriptiveOnly)
        let older = try makeSnapshot(id, 4, "older")
        try await journal.append([try insertRecord(epoch: epoch, source: older, text: "history")])
        try await journal.deleteLocalHistory(documentID: id)
        let remaining = try await journal.records(documentID: id)
        XCTAssertTrue(remaining.isEmpty)
        await journal.close()

        guard case .complete(let stillThere) = try await store.recover(id) else {
            return XCTFail("Deleting history must not delete recovery")
        }
        XCTAssertEqual(stillThere.source, saved)
        try await store.close()
    }

    func testWrongKeyCannotReadRecords() async throws {
        let workspace = try TempWorkspace(); defer { workspace.remove() }
        let id = DocumentID()
        let journal = try makeJournal(workspace, key: testKey(0x11))
        let initial = try makeSnapshot(id, 0, "source")
        let epoch = try await journal.beginEpoch(documentID: id, atRevision: initial.revision,
                                                 priorTextCompleteness: .descriptiveOnly)
        try await journal.append([try insertRecord(epoch: epoch, source: initial, text: "private")])
        await journal.close()

        let other = try makeJournal(workspace, key: testKey(0x22))
        do {
            _ = try await other.records(documentID: id)
            XCTFail("A wrong key must not decrypt history")
        } catch let error as HistoryError {
            guard case .corrupt = error else { return XCTFail("Expected corrupt, got \(error)") }
        }
        await other.close()
    }
}
