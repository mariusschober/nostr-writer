import Foundation
import WriterFoundation
@testable import WriterStorage
import XCTest

// MARK: - Controllable seams

/// A virtual monotonic clock and scheduler.
///
/// Tests advance it by hand, so every scheduling assertion is deterministic and
/// no test sleeps to advance time. The 200 microsecond coordination pause in
/// `awaitCondition` only lets other tasks run; it never advances this clock.
final class VirtualMonotonicScheduler: MonotonicScheduling, @unchecked Sendable {

    private struct Sleeper {
        let id: UInt64
        let deadline: UInt64
        let continuation: CheckedContinuation<Void, Error>
    }

    private let lock = NSLock()
    private var currentTicks: UInt64
    private var nextID: UInt64 = 0
    private var sleepers: [Sleeper] = []
    private var cancelledIDs: Set<UInt64> = []

    init(startingAt: UInt64 = 0) { currentTicks = startingAt }

    func now() -> MonotonicInstant {
        lock.lock(); defer { lock.unlock() }
        return MonotonicInstant(ticks: currentTicks)
    }

    func sleep(until deadline: MonotonicInstant) async throws {
        let id: UInt64 = lock.withLock {
            nextID += 1
            return nextID
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.lock()
                if Task.isCancelled || cancelledIDs.remove(id) != nil {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                if currentTicks >= deadline.ticks {
                    lock.unlock()
                    continuation.resume()
                    return
                }
                sleepers.append(Sleeper(id: id, deadline: deadline.ticks, continuation: continuation))
                lock.unlock()
            }
        } onCancel: {
            self.cancel(id: id)
        }
    }

    private func cancel(id: UInt64) {
        lock.lock()
        if let index = sleepers.firstIndex(where: { $0.id == id }) {
            let sleeper = sleepers.remove(at: index)
            lock.unlock()
            sleeper.continuation.resume(throwing: CancellationError())
            return
        }
        cancelledIDs.insert(id)
        lock.unlock()
    }

    /// Advances the virtual clock and resumes every sleeper that is now due.
    func advance(by delta: UInt64) {
        lock.lock()
        currentTicks += delta
        let reference = currentTicks
        var due: [Sleeper] = []
        sleepers.removeAll { sleeper in
            guard sleeper.deadline <= reference else { return false }
            due.append(sleeper)
            return true
        }
        lock.unlock()
        for sleeper in due { sleeper.continuation.resume() }
    }

    var sleeperCount: Int { lock.withLock { sleepers.count } }
}

/// A controllable ``DocumentPersistence`` that mirrors `DocumentStore`'s ordering
/// rules without any file, key or encryption. Used for scheduling and state
/// assertions; the real encrypted store is exercised separately.
actor ControllablePersistence: DocumentPersistence {

    struct Offer: Sendable, Equatable {
        let revision: Revision
        let digest: Data
        let receiptCount: Int
    }

    private(set) var offers: [Offer] = []
    private(set) var attemptCount = 0
    private var durable: [UUID: DurableRevision] = [:]
    private var scriptedFailures: [StorageError] = []
    private var persistentFailure: StorageError?
    private var gateRemaining = 0
    private var parked: [CheckedContinuation<Void, Never>] = []
    private var nextCommit: UInt64 = 0

    var parkedCount: Int { parked.count }

    func failNext(_ count: Int, with error: StorageError) {
        for _ in 0..<count { scriptedFailures.append(error) }
    }

    func setPersistentFailure(_ error: StorageError?) { persistentFailure = error }

    func gateNextAttempts(_ count: Int) { gateRemaining = count }

    func releaseParked() {
        let waiting = parked
        parked = []
        for continuation in waiting { continuation.resume() }
    }

    func persist(_ batch: RecoveryBatch) async throws -> DurableRevision {
        attemptCount += 1
        offers.append(
            Offer(
                revision: batch.source.revision,
                digest: batch.source.digest,
                receiptCount: batch.receipts.count
            )
        )
        if !scriptedFailures.isEmpty {
            throw scriptedFailures.removeFirst()
        }
        if let persistentFailure {
            throw persistentFailure
        }
        if gateRemaining > 0 {
            gateRemaining -= 1
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                parked.append(continuation)
            }
        }
        return try commit(batch.source)
    }

    func recover(_ id: DocumentID) async throws -> RecoveryState {
        guard let revision = durable[id.rawValue] else { return .absent }
        return .complete(revision)
    }

    private func commit(_ source: SourceSnapshot) throws -> DurableRevision {
        if let existing = durable[source.documentID.rawValue] {
            if source.revision < existing.source.revision {
                throw StorageError.staleRevision(
                    latest: existing.source.revision.rawValue,
                    attempted: source.revision.rawValue
                )
            }
            if source.revision == existing.source.revision {
                if source.digest == existing.source.digest { return existing }
                throw StorageError.conflictingRevision(revision: source.revision.rawValue)
            }
        }
        nextCommit += 1
        let identifier = UUID(
            uuidString: String(format: "00000000-0000-4000-8000-%012llX", nextCommit)
        )!
        let result = DurableRevision(source: source, recoveryCommit: identifier, savedFile: nil)
        durable[source.documentID.rawValue] = result
        return result
    }
}

/// Fails a storage fault point a bounded number of times, then stops injecting.
///
/// `ScriptedFaultInjector` in `TestSupport` never stops, so it cannot model an
/// `afterCommit` failure that a retry then recovers from.
final class OneShotFaultInjector: StorageFaultInjecting, @unchecked Sendable {

    private let lock = NSLock()
    private var remaining: [StorageFaultPoint: Int]

    init(_ counts: [StorageFaultPoint: Int]) { remaining = counts }

    func checkpoint(_ point: StorageFaultPoint) throws {
        let shouldThrow: Bool = lock.withLock {
            guard let count = remaining[point], count > 0 else { return false }
            remaining[point] = count - 1
            return true
        }
        if shouldThrow {
            throw StorageError.ioFailure("injected failure at \(point.rawValue)")
        }
    }
}

// MARK: - Helpers

/// Polls a condition with cooperative yields so other tasks can run.
private func awaitCondition(
    iterations: Int = 4_000,
    _ condition: @Sendable () async -> Bool
) async -> Bool {
    for index in 0..<iterations {
        if await condition() { return true }
        if index % 64 == 63 {
            try? await Task.sleep(nanoseconds: 200_000)
        } else {
            await Task.yield()
        }
    }
    return await condition()
}

private func makeSavedFile(
    _ documentID: DocumentID,
    _ revision: UInt64,
    _ bytes: Data,
    url: URL = URL(fileURLWithPath: "/tmp/document.md")
) throws -> SavedFileRevision {
    SavedFileRevision(
        source: try SourceSnapshot(documentID: documentID, revision: Revision(revision), utf8: bytes),
        url: url
    )
}

/// A coordinator whose only durable sink is the controllable double.
private func makeCoordinator(
    documentID: DocumentID,
    persistence: any DocumentPersistence,
    scheduler: VirtualMonotonicScheduler,
    checkpointInterval: Duration = .seconds(1),
    maximumWaiters: Int = 32
) throws -> RecoveryCoordinator {
    try RecoveryCoordinator(
        documentID: documentID,
        persistence: persistence,
        scheduler: scheduler,
        checkpointInterval: checkpointInterval,
        maximumWaiters: maximumWaiters
    )
}

private let oneSecond: UInt64 = 1_000_000_000

// MARK: - Tests

final class RecoveryCoordinatorTests: XCTestCase {

    // MARK: Immediate first checkpoint and revision zero

    func testFirstUnsavedSnapshotCheckpointsImmediately() async throws {
        let clock = VirtualMonotonicScheduler()
        let store = ControllablePersistence()
        let documentID = DocumentID()
        let coordinator = try makeCoordinator(documentID: documentID, persistence: store, scheduler: clock)

        try await coordinator.observe(try makeSnapshot(documentID, 1, "first words"))
        await coordinator.awaitQuiescence()

        let state = await coordinator.state()
        XCTAssertEqual(state.durable?.revision, Revision(1))
        XCTAssertTrue(state.isDurablyRecovered)
        XCTAssertFalse(state.isCheckpointOverdue)
        XCTAssertEqual(clock.now().ticks, 0, "The first checkpoint must not wait for the interval.")
        let attempts = await store.attemptCount
        XCTAssertEqual(attempts, 1)
    }

    /// Review regression: revision zero is a real revision. A nil durable
    /// acknowledgement must never be conflated with revision zero.
    func testRevisionZeroIsCheckpointedAndRecordedAsDurable() async throws {
        let clock = VirtualMonotonicScheduler()
        let store = ControllablePersistence()
        let documentID = DocumentID()
        let coordinator = try makeCoordinator(documentID: documentID, persistence: store, scheduler: clock)

        try await coordinator.observe(try makeSnapshot(documentID, 0, "zero"))
        await coordinator.awaitQuiescence()

        let state = await coordinator.state()
        XCTAssertEqual(state.memoryRevision, Revision(0))
        XCTAssertEqual(state.durable?.revision, Revision(0))
        XCTAssertTrue(state.isDurablyRecovered)
        XCTAssertFalse(state.hasOutstandingChanges)
    }

    func testRevisionZeroFailureStillRetainsTheNewestText() async throws {
        let clock = VirtualMonotonicScheduler()
        let store = ControllablePersistence()
        await store.setPersistentFailure(.keyLocked("vault locked"))
        let documentID = DocumentID()
        let coordinator = try makeCoordinator(documentID: documentID, persistence: store, scheduler: clock)

        try await coordinator.observe(try makeSnapshot(documentID, 0, "zero"))
        await coordinator.awaitQuiescence()

        let state = await coordinator.state()
        XCTAssertEqual(state.memoryRevision, Revision(0))
        XCTAssertNil(state.durable)
        XCTAssertTrue(state.hasOutstandingChanges)
        XCTAssertTrue(state.isPausedForRetry)
        XCTAssertEqual(state.lastFailure, .persistence(.keyLocked("vault locked")))
    }

    // MARK: Interval anchoring

    func testCheckpointHonoursASubsecondInterval() async throws {
        let clock = VirtualMonotonicScheduler()
        let store = ControllablePersistence()
        let documentID = DocumentID()
        let coordinator = try makeCoordinator(
            documentID: documentID,
            persistence: store,
            scheduler: clock,
            checkpointInterval: .milliseconds(250)
        )
        try await coordinator.observe(try makeSnapshot(documentID, 1, "AAAA"))
        await coordinator.awaitQuiescence()

        try await coordinator.observe(try makeSnapshot(documentID, 2, "BBBB"))
        clock.advance(by: 249_000_000)
        var state = await coordinator.state()
        XCTAssertEqual(state.durable?.revision, Revision(1), "The interval has not elapsed yet.")
        XCTAssertFalse(state.isCheckpointOverdue)

        clock.advance(by: 1_000_000)
        await coordinator.awaitQuiescence()
        state = await coordinator.state()
        XCTAssertEqual(state.durable?.revision, Revision(2))
        XCTAssertTrue(state.isDurablyRecovered)
    }

    /// Review regression: continuous typing must not push the deadline back.
    func testContinuousEditsKeepTheDeadlineAnchoredToTheOldestChange() async throws {
        let clock = VirtualMonotonicScheduler()
        let store = ControllablePersistence()
        let documentID = DocumentID()
        let coordinator = try makeCoordinator(documentID: documentID, persistence: store, scheduler: clock)
        try await coordinator.observe(try makeSnapshot(documentID, 1, "AAAA"))
        await coordinator.awaitQuiescence()

        try await coordinator.observe(try makeSnapshot(documentID, 2, "BBBB"))
        clock.advance(by: 400_000_000)
        try await coordinator.observe(try makeSnapshot(documentID, 3, "CCCC"))
        clock.advance(by: 599_000_000)

        var state = await coordinator.state()
        XCTAssertEqual(state.memoryRevision, Revision(3))
        XCTAssertEqual(
            state.durable?.revision,
            Revision(1),
            "A later edit must not push the anchored deadline back."
        )

        clock.advance(by: 1_000_000)
        await coordinator.awaitQuiescence()
        state = await coordinator.state()
        XCTAssertEqual(state.durable?.revision, Revision(3))
        let attempts = await store.attemptCount
        XCTAssertEqual(attempts, 2, "Both edits must be coalesced into a single checkpoint.")
    }

    func testIntermediateSnapshotsAreCoalescedToTheNewest() async throws {
        let clock = VirtualMonotonicScheduler()
        let store = ControllablePersistence()
        let documentID = DocumentID()
        let coordinator = try makeCoordinator(documentID: documentID, persistence: store, scheduler: clock)
        try await coordinator.observe(try makeSnapshot(documentID, 1, "AAAA"))
        await coordinator.awaitQuiescence()

        for (revision, text) in [(2, "BBBB"), (3, "CCCC"), (4, "DDDD"), (5, "EEEE")] {
            try await coordinator.observe(try makeSnapshot(documentID, UInt64(revision), text))
        }
        clock.advance(by: oneSecond)
        await coordinator.awaitQuiescence()

        let state = await coordinator.state()
        XCTAssertEqual(state.durable?.revision, Revision(5))
        XCTAssertEqual(state.durable?.digest, try makeSnapshot(documentID, 5, "EEEE").digest)
        let offers = await store.offers
        XCTAssertEqual(offers.count, 2, "Only the first snapshot and the newest coalesced batch are written.")
        XCTAssertEqual(offers.last?.revision, Revision(5))
    }

    // MARK: Serialized writes

    func testOlderCompletionCannotMarkANewerRevisionDurable() async throws {
        let clock = VirtualMonotonicScheduler()
        let store = ControllablePersistence()
        let documentID = DocumentID()
        let coordinator = try makeCoordinator(documentID: documentID, persistence: store, scheduler: clock)
        await store.gateNextAttempts(1)

        try await coordinator.observe(try makeSnapshot(documentID, 1, "AAAA"))
        let parked = await awaitCondition { await store.parkedCount == 1 }
        XCTAssertTrue(parked, "The first checkpoint must park in the store.")

        try await coordinator.observe(try makeSnapshot(documentID, 3, "CCCC"))
        var state = await coordinator.state()
        XCTAssertEqual(state.memoryRevision, Revision(3))
        XCTAssertNil(
            state.durable,
            "A newer observed revision must not be reported durable before it is written."
        )

        await store.releaseParked()
        let settled = await awaitCondition { await coordinator.state().durable?.revision == Revision(1) }
        XCTAssertTrue(settled)
        state = await coordinator.state()
        XCTAssertEqual(state.memoryRevision, Revision(3))
        XCTAssertEqual(
            state.durable?.revision,
            Revision(1),
            "The completed older write must not be recorded as the newer revision."
        )

        clock.advance(by: oneSecond)
        await coordinator.awaitQuiescence()
        state = await coordinator.state()
        XCTAssertEqual(state.durable?.revision, Revision(3))
        let attempts = await store.attemptCount
        XCTAssertEqual(attempts, 2)
    }

    /// Review regression: while a slower store is still catching up, the lag is
    /// reported instead of an implied durable revision.
    func testSlowStoreSurfacesCheckpointLag() async throws {
        let clock = VirtualMonotonicScheduler()
        let store = ControllablePersistence()
        let documentID = DocumentID()
        let coordinator = try makeCoordinator(documentID: documentID, persistence: store, scheduler: clock)
        try await coordinator.observe(try makeSnapshot(documentID, 1, "AAAA"))
        await coordinator.awaitQuiescence()

        await store.gateNextAttempts(1)
        let flushing = Task { try await coordinator.flush(try makeSnapshot(documentID, 2, "BBBB"), atBoundary: .save) }
        let parked = await awaitCondition { await store.parkedCount == 1 }
        XCTAssertTrue(parked)

        clock.advance(by: 600_000_000)
        try await coordinator.observe(try makeSnapshot(documentID, 3, "CCCC"))
        clock.advance(by: 500_000_000)

        let lagging = await coordinator.state()
        XCTAssertEqual(lagging.durable?.revision, Revision(1))
        XCTAssertTrue(
            lagging.isCheckpointOverdue,
            "An outstanding edit older than the interval must be reported as overdue."
        )

        await store.releaseParked()
        _ = try await flushing.value
        clock.advance(by: 500_000_000)
        await coordinator.awaitQuiescence()

        let settled = await coordinator.state()
        XCTAssertEqual(settled.durable?.revision, Revision(3))
        XCTAssertFalse(settled.isCheckpointOverdue)
        let attempts = await store.attemptCount
        XCTAssertEqual(attempts, 3, "Initial checkpoint plus exactly one write per batch.")
    }

    // MARK: Flush and waiter lifecycle

    func testConcurrentFlushesShareOneWriteAndOneCommit() async throws {
        let clock = VirtualMonotonicScheduler()
        let store = ControllablePersistence()
        let documentID = DocumentID()
        let coordinator = try makeCoordinator(documentID: documentID, persistence: store, scheduler: clock)
        try await coordinator.observe(try makeSnapshot(documentID, 1, "AAAA"))
        await coordinator.awaitQuiescence()

        let target = try makeSnapshot(documentID, 2, "BBBB")
        async let first = coordinator.flush(target, atBoundary: .save)
        async let second = coordinator.flush(target, atBoundary: .save)
        async let third = coordinator.flush(target, atBoundary: .close)
        let results = try await [first, second, third]

        XCTAssertEqual(Set(results.map(\.recoveryCommit)).count, 1, "One commit for three waiters.")
        XCTAssertEqual(Set(results.map(\.source.revision)), [Revision(2)])
        let attempts = await store.attemptCount
        XCTAssertEqual(attempts, 2, "The concurrent flushes must not write the revision twice.")
        let boundary = await coordinator.state().lastBoundary
        XCTAssertEqual(boundary, .close)
    }

    /// Review regression: cancelling a waiting caller must not cancel the store
    /// write it was waiting on.
    func testCancellingAFlushWaiterDoesNotCancelTheStoreWrite() async throws {
        let clock = VirtualMonotonicScheduler()
        let store = ControllablePersistence()
        let documentID = DocumentID()
        let coordinator = try makeCoordinator(documentID: documentID, persistence: store, scheduler: clock)
        try await coordinator.observe(try makeSnapshot(documentID, 1, "AAAA"))
        await coordinator.awaitQuiescence()

        await store.gateNextAttempts(1)
        let target = try makeSnapshot(documentID, 2, "BBBB")
        let flushing = Task { try await coordinator.flush(target, atBoundary: .save) }
        let parked = await awaitCondition { await store.parkedCount == 1 }
        XCTAssertTrue(parked)

        flushing.cancel()
        do {
            _ = try await flushing.value
            XCTFail("A cancelled waiter must not report durability.")
        } catch is CancellationError {
            // Expected: only this waiter was removed.
        }

        await store.releaseParked()
        let committed = await awaitCondition {
            await coordinator.state().durable?.revision == Revision(2)
        }
        XCTAssertTrue(
            committed,
            "The store write must complete even though its waiter was cancelled."
        )
    }

    func testWaiterCountIsBounded() async throws {
        let clock = VirtualMonotonicScheduler()
        let store = ControllablePersistence()
        let documentID = DocumentID()
        let coordinator = try makeCoordinator(
            documentID: documentID,
            persistence: store,
            scheduler: clock,
            maximumWaiters: 1
        )
        try await coordinator.observe(try makeSnapshot(documentID, 1, "AAAA"))
        await coordinator.awaitQuiescence()

        await store.gateNextAttempts(1)
        let target = try makeSnapshot(documentID, 2, "BBBB")
        let first = Task { try await coordinator.flush(target, atBoundary: .save) }
        let parked = await awaitCondition { await store.parkedCount == 1 }
        XCTAssertTrue(parked)

        do {
            _ = try await coordinator.flush(target, atBoundary: .save)
            XCTFail("The waiter bound must be enforced.")
        } catch let error as RecoveryCoordinatorError {
            XCTAssertEqual(error, .tooManyWaiters(limit: 1))
        }

        await store.releaseParked()
        _ = try await first.value
    }

    // MARK: Saved-file state

    func testSaveAcknowledgementCannotMarkANewerRevisionSaved() async throws {
        let clock = VirtualMonotonicScheduler()
        let store = ControllablePersistence()
        let documentID = DocumentID()
        let coordinator = try makeCoordinator(documentID: documentID, persistence: store, scheduler: clock)
        for (revision, text) in [(1, "AAAA"), (2, "BBBB"), (3, "CCCC")] {
            try await coordinator.observe(try makeSnapshot(documentID, UInt64(revision), text))
        }

        // A save that started at revision 1 finishes while the editor is at 3.
        let acknowledgement = try await coordinator.acknowledgeSavedFile(
            try makeSavedFile(documentID, 1, Data("AAAA".utf8))
        )
        XCTAssertEqual(acknowledgement.savedRevision, Revision(1))
        XCTAssertFalse(acknowledgement.isCurrent)

        let state = await coordinator.state()
        XCTAssertEqual(state.memoryRevision, Revision(3))
        XCTAssertEqual(state.savedFile?.revision, Revision(1))
        XCTAssertFalse(
            state.isSaved,
            "A save finishing at an older revision must never leave the current revision saved."
        )
    }

    /// Review regression: an older physical save landing last leaves an older
    /// file. The saved state must follow completion order, not revision order.
    func testAnOlderSaveLandingLastIsReportedAsOutOfOrder() async throws {
        let clock = VirtualMonotonicScheduler()
        let store = ControllablePersistence()
        let documentID = DocumentID()
        let coordinator = try makeCoordinator(documentID: documentID, persistence: store, scheduler: clock)
        for (revision, text) in [(1, "AAAA"), (2, "BBBB"), (3, "CCCC")] {
            try await coordinator.observe(try makeSnapshot(documentID, UInt64(revision), text))
        }

        let newest = try await coordinator.acknowledgeSavedFile(
            try makeSavedFile(documentID, 3, Data("CCCC".utf8))
        )
        XCTAssertTrue(newest.isCurrent)
        XCTAssertFalse(newest.completedOutOfOrder)
        let savedAtNewest = await coordinator.state().isSaved
        XCTAssertTrue(savedAtNewest)

        let late = try await coordinator.acknowledgeSavedFile(
            try makeSavedFile(documentID, 1, Data("AAAA".utf8))
        )
        XCTAssertFalse(late.isCurrent)
        XCTAssertTrue(late.completedOutOfOrder, "An older save completing later must be reported.")
        let stillSaved = await coordinator.state().isSaved
        XCTAssertFalse(
            stillSaved,
            "The document must not stay saved for a revision the file no longer holds."
        )
    }

    /// Review regression: a forged acknowledgement for the current revision with
    /// different bytes must never set the saved indicator.
    func testCurrentRevisionAcknowledgementWithWrongBytesIsRejected() async throws {
        let clock = VirtualMonotonicScheduler()
        let store = ControllablePersistence()
        let documentID = DocumentID()
        let coordinator = try makeCoordinator(documentID: documentID, persistence: store, scheduler: clock)
        try await coordinator.observe(try makeSnapshot(documentID, 2, "AAAA"))

        do {
            _ = try await coordinator.acknowledgeSavedFile(
                try makeSavedFile(documentID, 2, Data("FORGED".utf8))
            )
            XCTFail("Mismatched bytes for the current revision must be refused.")
        } catch let error as RecoveryCoordinatorError {
            XCTAssertEqual(error, .conflictingRevision(revision: 2))
        }
        let afterForgery = await coordinator.state()
        XCTAssertNil(afterForgery.savedFile)
        XCTAssertFalse(afterForgery.isSaved)
    }

    func testSaveAcknowledgementRejectsForeignAndUnknownRevisions() async throws {
        let clock = VirtualMonotonicScheduler()
        let store = ControllablePersistence()
        let documentID = DocumentID()
        let coordinator = try makeCoordinator(documentID: documentID, persistence: store, scheduler: clock)
        try await coordinator.observe(try makeSnapshot(documentID, 1, "AAAA"))

        let other = DocumentID()
        do {
            _ = try await coordinator.acknowledgeSavedFile(try makeSavedFile(other, 1, Data("AAAA".utf8)))
            XCTFail("A foreign document acknowledgement must be refused.")
        } catch let error as RecoveryCoordinatorError {
            XCTAssertEqual(
                error,
                .foreignDocument(expected: documentID.rawValue, received: other.rawValue)
            )
        }

        do {
            _ = try await coordinator.acknowledgeSavedFile(try makeSavedFile(documentID, 7, Data("ZZZZ".utf8)))
            XCTFail("An unknown revision acknowledgement must be refused.")
        } catch let error as RecoveryCoordinatorError {
            XCTAssertEqual(error, .unknownRevision(latest: 1, offered: 7))
        }
    }

    // MARK: Shutdown

    func testCloseFlushesTheNewestRevisionBeforeTheTimerFires() async throws {
        let clock = VirtualMonotonicScheduler()
        let store = ControllablePersistence()
        let documentID = DocumentID()
        let coordinator = try makeCoordinator(documentID: documentID, persistence: store, scheduler: clock)
        try await coordinator.observe(try makeSnapshot(documentID, 1, "AAAA"))
        await coordinator.awaitQuiescence()

        try await coordinator.observe(try makeSnapshot(documentID, 2, "BBBB"))
        XCTAssertEqual(clock.now().ticks, 0, "The interval timer is armed but not fired.")
        try await coordinator.close()

        let state = await coordinator.state()
        XCTAssertTrue(state.isClosed)
        XCTAssertEqual(state.durable?.revision, Revision(2))
        XCTAssertTrue(state.isDurablyRecovered)
        XCTAssertEqual(clock.now().ticks, 0, "Closing must not wait for the interval.")
    }

    func testCloseDuringWriteDoesNotAbandonTheAcknowledgedCommit() async throws {
        let clock = VirtualMonotonicScheduler()
        let store = ControllablePersistence()
        let documentID = DocumentID()
        let coordinator = try makeCoordinator(documentID: documentID, persistence: store, scheduler: clock)
        await store.gateNextAttempts(1)
        try await coordinator.observe(try makeSnapshot(documentID, 1, "AAAA"))
        let parked = await awaitCondition { await store.parkedCount == 1 }
        XCTAssertTrue(parked)

        let closing = Task { try await coordinator.close() }
        await Task.yield()
        await store.releaseParked()
        try await closing.value

        let state = await coordinator.state()
        XCTAssertTrue(state.isClosed)
        XCTAssertEqual(
            state.durable?.revision,
            Revision(1),
            "The commit that was already in the store must not be abandoned."
        )
    }

    /// Review regression: a failed close must keep the newest text readable and
    /// permit an explicit retry.
    func testFailedCloseKeepsNewestTextAndPermitsExplicitRetry() async throws {
        let clock = VirtualMonotonicScheduler()
        let store = ControllablePersistence()
        await store.setPersistentFailure(.keyLocked("vault locked"))
        let documentID = DocumentID()
        let coordinator = try makeCoordinator(documentID: documentID, persistence: store, scheduler: clock)
        try await coordinator.observe(try makeSnapshot(documentID, 1, "AAAA"))
        await coordinator.awaitQuiescence()

        do {
            try await coordinator.close()
            XCTFail("A close that cannot reach durability must fail.")
        } catch let error as RecoveryCoordinatorError {
            XCTAssertEqual(error, .persistence(.keyLocked("vault locked")))
        }

        var state = await coordinator.state()
        XCTAssertFalse(state.isClosed)
        XCTAssertFalse(state.isClosing, "A failed close must let the document keep writing.")
        XCTAssertEqual(state.memoryRevision, Revision(1))
        XCTAssertEqual(state.memoryDigest, try makeSnapshot(documentID, 1, "AAAA").digest)
        XCTAssertNil(state.durable)
        XCTAssertTrue(state.isPausedForRetry)

        await store.setPersistentFailure(nil)
        await coordinator.retry()
        await coordinator.awaitQuiescence()
        try await coordinator.close()

        state = await coordinator.state()
        XCTAssertTrue(state.isClosed)
        XCTAssertEqual(state.durable?.revision, Revision(1))
        XCTAssertTrue(state.isDurablyRecovered)
    }

    // MARK: Failure behaviour

    /// Review regression: a supplied recovered revision for another document is
    /// rejected outright, never silently dropped.
    func testInitialiserRejectsForeignRecoveredDurableAndUnusableBounds() async throws {
        let clock = VirtualMonotonicScheduler()
        let store = ControllablePersistence()
        let documentID = DocumentID()
        let other = DocumentID()
        let seed = DurableRevision(
            source: try makeSnapshot(other, 1, "OTHER"),
            recoveryCommit: UUID(),
            savedFile: nil
        )
        do {
            _ = try RecoveryCoordinator(
                documentID: documentID,
                persistence: store,
                scheduler: clock,
                recoveredDurable: seed
            )
            XCTFail("A recovered revision for another document must be refused.")
        } catch let error as RecoveryCoordinatorError {
            XCTAssertEqual(
                error,
                .foreignDocument(expected: documentID.rawValue, received: other.rawValue)
            )
        }

        do {
            _ = try RecoveryCoordinator(
                documentID: documentID,
                persistence: store,
                scheduler: clock,
                maximumSourceBytes: 0
            )
            XCTFail("An unusable input bound must be refused.")
        } catch let error as StorageError {
            XCTAssertEqual(
                error,
                .invariantViolation("Recovery input bounds must be positive and within the product limits.")
            )
        }
    }

    /// The editor input bound is enforced before a source is retained.
    func testAdmissionBoundIsEnforcedBeforeRetaining() async throws {
        let clock = VirtualMonotonicScheduler()
        let store = ControllablePersistence()
        let documentID = DocumentID()
        let coordinator = try RecoveryCoordinator(
            documentID: documentID,
            persistence: store,
            scheduler: clock,
            maximumSourceBytes: 100,
            maximumSourceScalars: 2
        )

        do {
            try await coordinator.observe(try makeSnapshot(documentID, 1, "abc"))
            XCTFail("A source beyond the scalar bound must be refused.")
        } catch let error as RecoveryCoordinatorError {
            XCTAssertEqual(
                error,
                .sourceBeyondInputBound(
                    byteCount: 3,
                    scalarCount: 3,
                    maximumBytes: 100,
                    maximumScalars: 2
                )
            )
        }

        let state = await coordinator.state()
        XCTAssertNil(state.memoryRevision, "An oversized source must not be retained.")
        XCTAssertFalse(state.hasOutstandingChanges)
        let attempts = await store.attemptCount
        XCTAssertEqual(attempts, 0, "An oversized source must never reach the store.")
    }

    /// Review regression: a blocked store must not make close uncancellable, and a
    /// cancelled close must reopen observation without discarding the write.
    func testCloseCanBeCancelledWhileTheStoreIsBlocked() async throws {
        let clock = VirtualMonotonicScheduler()
        let store = ControllablePersistence()
        let documentID = DocumentID()
        let coordinator = try makeCoordinator(documentID: documentID, persistence: store, scheduler: clock)
        await store.gateNextAttempts(1)
        try await coordinator.observe(try makeSnapshot(documentID, 1, "AAAA"))
        let parked = await awaitCondition { await store.parkedCount == 1 }
        XCTAssertTrue(parked)

        let closing = Task { try await coordinator.close() }
        let requested = await awaitCondition { await coordinator.state().isClosing }
        XCTAssertTrue(requested)

        closing.cancel()
        do {
            try await closing.value
            XCTFail("A cancelled close must not report success.")
        } catch is CancellationError {
            // Expected: only close's waiter was removed.
        }

        var state = await coordinator.state()
        XCTAssertFalse(state.isClosing, "Cancelling a close must let the document keep writing.")
        XCTAssertFalse(state.isClosed)
        XCTAssertEqual(state.memoryRevision, Revision(1))
        XCTAssertFalse(state.isDurablyRecovered)

        // The store write it was waiting on continues to completion.
        await store.releaseParked()
        let committed = await awaitCondition {
            await coordinator.state().durable?.revision == Revision(1)
        }
        XCTAssertTrue(committed, "Cancelling close must not cancel the committing store write.")

        // Observation is open again.
        try await coordinator.observe(try makeSnapshot(documentID, 2, "BBBB"))
        state = await coordinator.state()
        XCTAssertEqual(state.memoryRevision, Revision(2))
        XCTAssertTrue(state.hasOutstandingChanges)
    }

    /// Review regression: a second concurrent close must be refused rather than
    /// racing the first one's durability target.
    func testASecondConcurrentCloseIsRejected() async throws {
        let clock = VirtualMonotonicScheduler()
        let store = ControllablePersistence()
        let documentID = DocumentID()
        let coordinator = try makeCoordinator(documentID: documentID, persistence: store, scheduler: clock)
        await store.gateNextAttempts(1)
        try await coordinator.observe(try makeSnapshot(documentID, 1, "AAAA"))
        let parked = await awaitCondition { await store.parkedCount == 1 }
        XCTAssertTrue(parked)

        let first = Task { try await coordinator.close() }
        let requested = await awaitCondition { await coordinator.state().isClosing }
        XCTAssertTrue(requested)

        do {
            try await coordinator.close()
            XCTFail("Only one close may be in progress.")
        } catch let error as RecoveryCoordinatorError {
            XCTAssertEqual(error, .closeAlreadyInProgress)
        }

        await store.releaseParked()
        try await first.value
        let state = await coordinator.state()
        XCTAssertTrue(state.isClosed)
        XCTAssertEqual(state.durable?.revision, Revision(1))
    }

    /// Review regression: once an older in-flight revision becomes durable, the lag
    /// clock must advance to the first edit that is still pending instead of
    /// reporting the already-durable revision as overdue forever.
    func testLagAdvancesToTheNextPendingEditAfterAnOlderCommit() async throws {
        let clock = VirtualMonotonicScheduler()
        let store = ControllablePersistence()
        let documentID = DocumentID()
        let coordinator = try makeCoordinator(documentID: documentID, persistence: store, scheduler: clock)
        try await coordinator.observe(try makeSnapshot(documentID, 1, "AAAA"))
        await coordinator.awaitQuiescence()

        await store.gateNextAttempts(1)
        let flushing = Task {
            try await coordinator.flush(try makeSnapshot(documentID, 2, "BBBB"), atBoundary: .save)
        }
        let parked = await awaitCondition { await store.parkedCount == 1 }
        XCTAssertTrue(parked)

        clock.advance(by: 600_000_000)
        try await coordinator.observe(try makeSnapshot(documentID, 3, "CCCC"))
        clock.advance(by: 600_000_000)
        let lagging = await coordinator.state().isCheckpointOverdue
        XCTAssertTrue(lagging, "The slow store must surface as lag while revision 2 is in flight.")

        await store.releaseParked()
        _ = try await flushing.value
        let committed = await awaitCondition { await coordinator.state().durable?.revision == Revision(2) }
        XCTAssertTrue(committed)

        let advanced = await coordinator.state()
        XCTAssertEqual(advanced.memoryRevision, Revision(3))
        XCTAssertEqual(advanced.durable?.revision, Revision(2))
        XCTAssertFalse(
            advanced.isCheckpointOverdue,
            "Lag must be measured from the oldest still-pending edit, not the committed one."
        )

        clock.advance(by: 400_000_000)
        await coordinator.awaitQuiescence()
        let settled = await coordinator.state()
        XCTAssertEqual(settled.durable?.revision, Revision(3))
        XCTAssertFalse(settled.isCheckpointOverdue)
    }

    /// Review regression: a failed checkpoint must stop scheduling rather than
    /// retry forever, and one new edit may attempt exactly one more checkpoint.
    func testPermanentFailureAttemptsOnceAndPauses() async throws {
        let clock = VirtualMonotonicScheduler()
        let store = ControllablePersistence()
        await store.setPersistentFailure(.diskFull("no space"))
        let documentID = DocumentID()
        let coordinator = try makeCoordinator(documentID: documentID, persistence: store, scheduler: clock)

        try await coordinator.observe(try makeSnapshot(documentID, 1, "AAAA"))
        await coordinator.awaitQuiescence()
        var attempts = await store.attemptCount
        XCTAssertEqual(attempts, 1)

        clock.advance(by: 30 * oneSecond)
        await coordinator.awaitQuiescence()
        attempts = await store.attemptCount
        XCTAssertEqual(attempts, 1, "A failure must not start an unattended retry loop.")

        var state = await coordinator.state()
        XCTAssertTrue(state.isPausedForRetry)
        XCTAssertEqual(state.lastFailure, .persistence(.diskFull("no space")))
        XCTAssertEqual(state.memoryRevision, Revision(1), "The newest text must be preserved.")
        XCTAssertFalse(state.isDurablyRecovered)
        XCTAssertTrue(state.isCheckpointOverdue, "Thirty intervals of lag must be reported.")

        // A new edit resumes scheduling, and only once.
        try await coordinator.observe(try makeSnapshot(documentID, 2, "BBBB"))
        let resumed = await coordinator.state().isPausedForRetry
        XCTAssertFalse(resumed)
        clock.advance(by: oneSecond)
        await coordinator.awaitQuiescence()
        attempts = await store.attemptCount
        XCTAssertEqual(attempts, 2)

        clock.advance(by: 30 * oneSecond)
        await coordinator.awaitQuiescence()
        attempts = await store.attemptCount
        XCTAssertEqual(attempts, 2)
    }

    func testPersistenceFailureIsTypedAndPrivacySafe() async throws {
        let clock = VirtualMonotonicScheduler()
        let store = ControllablePersistence()
        await store.setPersistentFailure(.keyUnavailable("provider offline"))
        let documentID = DocumentID()
        let coordinator = try makeCoordinator(documentID: documentID, persistence: store, scheduler: clock)

        let marker = "private-draft-marker-ÄÖÜ-👋"
        try await coordinator.observe(try makeSnapshot(documentID, 1, marker))
        await coordinator.awaitQuiescence()

        let failure = await coordinator.state().lastFailure
        XCTAssertEqual(failure, .persistence(.keyUnavailable("provider offline")))
        let description = try XCTUnwrap(failure?.errorDescription)
        XCTAssertFalse(description.contains(marker), "An error path must not disclose source text.")
    }

    // MARK: Admission

    func testObservationRejectsStaleConflictingAndForeignSnapshots() async throws {
        let clock = VirtualMonotonicScheduler()
        let store = ControllablePersistence()
        let documentID = DocumentID()
        let coordinator = try makeCoordinator(documentID: documentID, persistence: store, scheduler: clock)
        try await coordinator.observe(try makeSnapshot(documentID, 2, "BBBB"))

        do {
            try await coordinator.observe(try makeSnapshot(documentID, 1, "AAAA"))
            XCTFail("A stale revision must be refused.")
        } catch let error as RecoveryCoordinatorError {
            XCTAssertEqual(error, .nonMonotonicRevision(latest: 2, offered: 1))
        }

        do {
            try await coordinator.observe(try makeSnapshot(documentID, 2, "ZZZZ"))
            XCTFail("A same-revision-different-bytes offer must be refused.")
        } catch let error as RecoveryCoordinatorError {
            XCTAssertEqual(error, .conflictingRevision(revision: 2))
        }

        let other = DocumentID()
        do {
            try await coordinator.observe(try makeSnapshot(other, 9, "OTHER"))
            XCTFail("A foreign snapshot must be refused.")
        } catch let error as RecoveryCoordinatorError {
            XCTAssertEqual(
                error,
                .foreignDocument(expected: documentID.rawValue, received: other.rawValue)
            )
        }

        let state = await coordinator.state()
        XCTAssertEqual(state.memoryRevision, Revision(2))
        XCTAssertEqual(state.memoryDigest, try makeSnapshot(documentID, 2, "BBBB").digest)
    }

    func testRevisionAtUInt64MaxIsDurableAndDoesNotOverflow() async throws {
        let clock = VirtualMonotonicScheduler()
        let store = ControllablePersistence()
        let documentID = DocumentID()
        let coordinator = try makeCoordinator(documentID: documentID, persistence: store, scheduler: clock)
        let lastRevision = Revision(UInt64.max)

        let snapshot = try SourceSnapshot(
            documentID: documentID,
            revision: lastRevision,
            utf8: Data("final".utf8)
        )
        try await coordinator.observe(snapshot)
        await coordinator.awaitQuiescence()

        var state = await coordinator.state()
        XCTAssertEqual(state.durable?.revision, lastRevision)
        XCTAssertTrue(state.isDurablyRecovered)

        // A repeated offer of the same revision and bytes is an idempotent no-op.
        try await coordinator.observe(snapshot)
        let durable = try await coordinator.flush(snapshot, atBoundary: .save)
        XCTAssertEqual(durable.source.revision, lastRevision)
        state = await coordinator.state()
        XCTAssertTrue(state.isClosed == false)
        let attempts = await store.attemptCount
        XCTAssertEqual(attempts, 1)
    }

    func testClosedCoordinatorRejectsNewWorkButKeepsStateReadable() async throws {
        let clock = VirtualMonotonicScheduler()
        let store = ControllablePersistence()
        let documentID = DocumentID()
        let coordinator = try makeCoordinator(documentID: documentID, persistence: store, scheduler: clock)
        try await coordinator.observe(try makeSnapshot(documentID, 1, "AAAA"))
        try await coordinator.close()

        do {
            try await coordinator.observe(try makeSnapshot(documentID, 2, "BBBB"))
            XCTFail("A closed coordinator must refuse new observations.")
        } catch let error as RecoveryCoordinatorError {
            XCTAssertEqual(error, .closed)
        }
        do {
            _ = try await coordinator.flush(try makeSnapshot(documentID, 1, "AAAA"), atBoundary: .save)
            XCTFail("A closed coordinator must refuse boundary flushes.")
        } catch let error as RecoveryCoordinatorError {
            XCTAssertEqual(error, .closed)
        }

        let state = await coordinator.state()
        XCTAssertTrue(state.isClosed)
        XCTAssertEqual(state.memoryRevision, Revision(1))
        XCTAssertEqual(state.durable?.revision, Revision(1))
    }

    // MARK: Receipts and interval arithmetic

    func testRecoveryCarriesNoMutationReceiptBacklog() async throws {
        let clock = VirtualMonotonicScheduler()
        let store = ControllablePersistence()
        let documentID = DocumentID()
        let coordinator = try makeCoordinator(documentID: documentID, persistence: store, scheduler: clock)
        for revision in 1...3 {
            try await coordinator.observe(try makeSnapshot(documentID, UInt64(revision), "text-\(revision)"))
        }
        clock.advance(by: oneSecond)
        await coordinator.awaitQuiescence()

        let offers = await store.offers
        XCTAssertFalse(offers.isEmpty)
        XCTAssertTrue(offers.allSatisfy { $0.receiptCount == 0 }, "Recovery must not buffer receipts.")
    }

    func testIntervalTicksScalesAttosecondsAndClampsToOneSecond() {
        XCTAssertEqual(RecoveryCoordinator.intervalTicks(from: .zero), 0)
        XCTAssertEqual(RecoveryCoordinator.intervalTicks(from: .seconds(-1)), 0)
        XCTAssertEqual(RecoveryCoordinator.intervalTicks(from: .milliseconds(250)), 250_000_000)
        XCTAssertEqual(RecoveryCoordinator.intervalTicks(from: .seconds(1)), oneSecond)
        XCTAssertEqual(
            RecoveryCoordinator.intervalTicks(from: .seconds(30)),
            oneSecond,
            "A longer interval is clamped to the product maximum."
        )
        XCTAssertEqual(RecoveryCoordinator.intervalTicks(from: .milliseconds(1500)), oneSecond)
    }

    func testMonotonicInstantSaturatesInsteadOfWrapping() {
        let saturated = MonotonicInstant(ticks: UInt64.max - 1).advanced(by: 1_000)
        XCTAssertEqual(saturated.ticks, UInt64.max)
        XCTAssertEqual(MonotonicInstant(ticks: 10).advanced(by: 5).ticks, 15)
    }

    // MARK: Real encrypted store integration

    func testAfterCommitFailureRetriesIdempotentlyWithDocumentStore() async throws {
        let workspace = try TempWorkspace()
        defer { workspace.remove() }
        let key = testKey()
        let documentID = DocumentID()
        let store = try makeStore(
            workspace,
            key: key,
            faultInjector: OneShotFaultInjector([.afterCommit: 1])
        )
        let clock = VirtualMonotonicScheduler()
        let coordinator = try makeCoordinator(documentID: documentID, persistence: store, scheduler: clock)
        let snapshot = try makeSnapshot(documentID, 1, "durable despite the reported failure")

        try await coordinator.observe(snapshot)
        await coordinator.awaitQuiescence()

        var state = await coordinator.state()
        XCTAssertNil(state.durable, "The reported failure must not be recorded as durable.")
        XCTAssertEqual(state.memoryRevision, Revision(1))
        XCTAssertTrue(state.isPausedForRetry)
        XCTAssertEqual(state.lastFailure, .persistence(.ioFailure("injected failure at afterCommit")))

        await coordinator.retry()
        await coordinator.awaitQuiescence()
        state = await coordinator.state()
        XCTAssertEqual(state.durable?.revision, Revision(1))
        XCTAssertNil(state.lastFailure)

        // The retry is idempotent: the store returns the commit it already made.
        guard case .complete(let durable) = try await store.recover(documentID) else {
            return XCTFail("The committed revision must be recoverable.")
        }
        XCTAssertEqual(durable.source.utf8, snapshot.utf8)
        XCTAssertEqual(durable.source.digest, snapshot.digest)
        XCTAssertEqual(durable.recoveryCommit, state.durable?.recoveryCommit)
        try await coordinator.close()
        try await store.close()
    }

    func testCloseAndReopenPreserveExactBomCrlfUnicodeBytes() async throws {
        let workspace = try TempWorkspace()
        defer { workspace.remove() }
        let key = testKey()
        let documentID = DocumentID()
        let store = try makeStore(workspace, key: key)
        let clock = VirtualMonotonicScheduler()
        let coordinator = try makeCoordinator(documentID: documentID, persistence: store, scheduler: clock)

        // A byte-order mark, CRLF line endings, a precomposed and a decomposed
        // form, an astral scalar and a noncharacter-free unassigned scalar.
        var bytes = Data([0xEF, 0xBB, 0xBF])
        bytes.append(Data("line-one\r\nline-two\r\n".utf8))
        bytes.append(Data("Grüße, ẑ, Å, 👋, \u{1F468}\u{200D}\u{1F4BB}\r\n".utf8))
        let snapshot = try SourceSnapshot(documentID: documentID, revision: Revision(1), utf8: bytes)

        try await coordinator.observe(snapshot)
        await coordinator.awaitQuiescence()
        try await coordinator.close()
        try await store.close()

        let reopened = try makeStore(workspace, key: key)
        guard case .complete(let durable) = try await reopened.recover(documentID) else {
            return XCTFail("The closed and reopened store must recover the snapshot.")
        }
        XCTAssertEqual(durable.source.utf8, bytes, "Exact source bytes must survive a reopen.")
        XCTAssertEqual(durable.source.digest, snapshot.digest)
        XCTAssertEqual(durable.source.byteCount, bytes.count)
        try await reopened.close()
    }

    func testCoordinatorNeverWritesPlaintextToDisk() async throws {
        let workspace = try TempWorkspace()
        defer { workspace.remove() }
        let documentID = DocumentID()
        let store = try makeStore(workspace)
        let clock = VirtualMonotonicScheduler()
        let coordinator = try makeCoordinator(documentID: documentID, persistence: store, scheduler: clock)
        let marker = "private-recovery-marker-ÄÖÜ-👋-do-not-leak"

        try await coordinator.observe(try makeSnapshot(documentID, 1, marker))
        await coordinator.awaitQuiescence()
        try await coordinator.close()
        try await store.close()

        let files = allFiles(in: workspace.root)
        XCTAssertFalse(files.isEmpty, "The store must have written files.")
        for needle in plaintextNeedles(marker) {
            XCTAssertTrue(
                filesContaining(needle, in: files).isEmpty,
                "No store file may carry plaintext writing."
            )
        }
    }
}
