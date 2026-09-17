import Dispatch
import Foundation
import WriterFoundation

// MARK: - Injected monotonic scheduling seam

/// A monotonic instant in nanoseconds from an unspecified origin.
///
/// Only differences between two instants are meaningful, and the value never
/// moves backwards. It is deliberately not epoch time: recovery scheduling must
/// not depend on the wall clock, which can jump.
public struct MonotonicInstant: Hashable, Comparable, Sendable, CustomStringConvertible {

    /// Nanoseconds from the scheduler's origin.
    public let ticks: UInt64

    public init(ticks: UInt64) { self.ticks = ticks }

    public static func < (lhs: MonotonicInstant, rhs: MonotonicInstant) -> Bool {
        lhs.ticks < rhs.ticks
    }

    public var description: String { String(ticks) }

    /// Saturating addition, so an oversized interval cannot wrap a deadline into
    /// the past and silently defeat the checkpoint bound.
    public func advanced(by delta: UInt64) -> MonotonicInstant {
        let (sum, overflow) = ticks.addingReportingOverflow(delta)
        return MonotonicInstant(ticks: overflow ? UInt64.max : sum)
    }
}

/// The injected, controllable timing seam.
///
/// Production installs ``SystemMonotonicScheduler``. A test substitutes a
/// virtual scheduler it advances by hand, so no test depends on real sleeps.
public protocol MonotonicScheduling: Sendable {
    /// The current monotonic instant. Never decreases.
    func now() -> MonotonicInstant
    /// Suspends until the clock reaches `deadline`.
    ///
    /// Throws `CancellationError` if the surrounding task is cancelled, so the
    /// coordinator can abandon a timer cooperatively.
    func sleep(until deadline: MonotonicInstant) async throws
}

/// Production scheduler over the process uptime clock. This is the only place a
/// real sleep happens, and it is never entered on the editor's hot path.
public struct SystemMonotonicScheduler: MonotonicScheduling {

    public init() {}

    public func now() -> MonotonicInstant {
        MonotonicInstant(ticks: DispatchTime.now().uptimeNanoseconds)
    }

    public func sleep(until deadline: MonotonicInstant) async throws {
        let current = now()
        guard current < deadline else { return }
        let remaining = deadline.ticks - current.ticks
        try await Task.sleep(for: .nanoseconds(Int64(clamping: remaining)))
    }
}

// MARK: - Typed, privacy-safe failures

/// Typed failures of recovery scheduling.
///
/// Every case is an outcome a caller can act on. No case ever carries source
/// text, a file path or key material: an error path must not disclose private
/// writing. Messages describe the state and the required decision only.
public enum RecoveryCoordinatorError: Error, Equatable, Sendable {
    /// The coordinator is closing or closed and no longer accepts new work.
    case closed
    /// Another caller is already closing this coordinator. Closing is a single
    /// owner operation: a second concurrent close is refused rather than allowed
    /// to race the first one's durability target.
    case closeAlreadyInProgress
    /// The supplied snapshot belongs to a different document than this
    /// coordinator's binding. Identifiers are UUIDs, never document text.
    case foreignDocument(expected: UUID, received: UUID)
    /// The supplied revision is older than the newest revision already known.
    case nonMonotonicRevision(latest: UInt64, offered: UInt64)
    /// The revision is already known with different bytes, so it cannot be the
    /// same revision. The stored snapshot is kept.
    case conflictingRevision(revision: UInt64)
    /// The caller referenced a revision the coordinator never produced.
    case unknownRevision(latest: UInt64, offered: UInt64)
    /// An attempted durable commit returned a snapshot that is not the offered
    /// one. The durable state is not advanced.
    case durableMismatch(revision: UInt64)
    /// More callers are waiting on durability than the configured bound.
    case tooManyWaiters(limit: Int)
    /// The offered source exceeds the product's hard editor input bound, so it was
    /// not retained for recovery. Counts only: never source text.
    case sourceBeyondInputBound(
        byteCount: Int,
        scalarCount: Int,
        maximumBytes: Int,
        maximumScalars: Int
    )
    /// The injected persistence layer failed with a typed storage failure.
    case persistence(StorageError)
    /// The injected persistence layer failed without a typed storage failure.
    /// The message is deliberately generic and never derived from the raw error.
    case persistenceFailure(String)
    /// The injected scheduler could not complete a wait, so no further scheduled
    /// checkpoint can be promised. The newest text is preserved and an explicit
    /// ``RecoveryCoordinator/retry()`` or a new edit resumes work.
    case schedulingFailed
}

extension RecoveryCoordinatorError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .closed:
            return "The recovery coordinator is closed; no further recovery work was accepted."
        case .closeAlreadyInProgress:
            return "This document is already being closed, so the second close request was refused."
        case .foreignDocument:
            return "This recovery coordinator is bound to a different document, so the supplied snapshot was not used."
        case .nonMonotonicRevision(let latest, let offered):
            return "Revision \(offered) is older than the newest known revision \(latest), so it was not used for recovery."
        case .conflictingRevision(let revision):
            return "Revision \(revision) is already known with different content, so the stored snapshot was kept."
        case .unknownRevision(let latest, let offered):
            return "Revision \(offered) was never produced in this session (the newest known revision is \(latest))."
        case .durableMismatch(let revision):
            return "The recovery store returned an unexpected snapshot for revision \(revision), so it was not treated as durable."
        case .tooManyWaiters(let limit):
            return "Too many callers are already waiting for recovery durability (limit \(limit)). No recovery work was dropped."
        case .sourceBeyondInputBound(let byteCount, let scalarCount, let maximumBytes, let maximumScalars):
            return "This source (\(byteCount) bytes, \(scalarCount) scalars) is beyond the editor input bound of \(maximumBytes) bytes and \(maximumScalars) scalars, so it was not retained for recovery."
        case .persistence(let error):
            return error.errorDescription
        case .persistenceFailure:
            return "The recovery store could not complete a durable checkpoint. Your work was not changed."
        case .schedulingFailed:
            return "The recovery checkpoint timer could not complete, so scheduled recovery paused. Your work was not changed."
        }
    }
}

// MARK: - Observable state

/// The durable recovery acknowledgement for one revision. A commit identity is
/// not evidence about human composition, and this type makes no such claim.
public struct RecoveryDurableState: Sendable, Equatable {
    public let revision: Revision
    public let digest: Data
    public let recoveryCommit: UUID
}

/// The exact snapshot acknowledged as written to the document's saved file.
public struct RecoverySavedFileState: Sendable, Equatable {
    public let revision: Revision
    public let digest: Data
    public let url: URL
}

/// A point-in-time view of the separate states one document has.
///
/// `memory` is the newest observed editor revision, `durable` is the newest
/// revision acknowledged by the recovery store, and `savedFile` is the exact
/// snapshot known to be on disk. They advance independently, which is the whole
/// point: a save finishing for one revision can never mark a newer revision
/// saved, and a recovery commit is never a save.
public struct RecoveryCoordinatorState: Sendable, Equatable {
    public let documentID: DocumentID
    public let memoryRevision: Revision?
    public let memoryDigest: Data?
    public let durable: RecoveryDurableState?
    public let savedFile: RecoverySavedFileState?
    public let lastFailure: RecoveryCoordinatorError?
    public let lastBoundary: ObservationBoundary?
    public let hasOutstandingChanges: Bool
    /// True when the oldest outstanding unsaved edit has waited longer than the
    /// checkpoint interval without a covering durable commit.
    ///
    /// This is an honest lag report. While it is true the product must not claim
    /// the outstanding work is durable, whatever the scheduler has attempted.
    public let isCheckpointOverdue: Bool
    /// True when a failed checkpoint stopped scheduling and only an explicit
    /// ``RecoveryCoordinator/retry()`` or a new edit resumes it.
    public let isPausedForRetry: Bool
    /// True between the start of ``RecoveryCoordinator/close()`` and either its
    /// completion or its failure. New observations and boundary flushes are
    /// refused while it is set; a failed close clears it again.
    public let isClosing: Bool
    /// True once the newest observed revision is durable and the coordinator has
    /// stopped accepting new work.
    public let isClosed: Bool

    /// True when the newest observed revision is exactly the durable recovery
    /// revision. It is not a saved-file claim.
    public var isDurablyRecovered: Bool {
        guard let memoryRevision, let durable else { return false }
        return durable.revision == memoryRevision
    }

    /// True when the newest observed revision is exactly the snapshot recorded as
    /// on disk. Set from the completion order of real file writes, never from a
    /// revision comparison.
    public var isSaved: Bool {
        guard let memoryRevision, let memoryDigest, let savedFile else { return false }
        return savedFile.revision == memoryRevision && savedFile.digest == memoryDigest
    }
}

/// What a saved-file acknowledgement means for the document's saved state.
public struct SavedFileAcknowledgement: Sendable, Equatable {
    /// The revision now believed to be physically on disk.
    public let savedRevision: Revision
    /// True when the newest observed revision is exactly the snapshot on disk.
    public let isCurrent: Bool
    /// True when this acknowledgement completed after a newer one.
    ///
    /// Physical writes are not ordered by revision, so an older save landing last
    /// leaves an older file. The app must re-save or re-check rather than let a UI
    /// still show the newer revision as saved.
    public let completedOutOfOrder: Bool
}

// MARK: - Recovery coordinator

/// Schedules bounded, encrypted source recovery for exactly one document.
///
/// The coordinator owns no file, no key and no database. It observes immutable
/// ``SourceSnapshot`` values and hands them to an injected ``DocumentPersistence``
/// (in production, ``DocumentStore``), which does the sealing and the durable
/// commit. Nothing here claims capture evidence, HWP authority or a saved file:
/// the acknowledgment is only that a recovery checkpoint committed.
///
/// Guarantees:
/// - **Immediate first checkpoint.** The first observation of a document that has
///   never been checkpointed is written without waiting for the interval, so a
///   brand-new unsaved document is recoverable immediately.
/// - **One interval, anchored to the oldest outstanding edit.** The deadline is
///   measured from the first unsaved edit and keeps running while an earlier
///   checkpoint is still in flight. Later edits in the batch never push it back,
///   so continuous typing cannot starve recovery. There is no debounce.
/// - **Disposable coalescing only.** Only superseded source checkpoints are
///   coalesced away. The newest observed revision is always eventually written.
/// - **Serialized writes.** At most one commit is in flight. An older completion
///   can never mark a newer revision durable, because the durable revision only
///   advances from the snapshot the store actually committed, and an
///   acknowledgement that is not the offered snapshot is refused.
/// - **Bounded state.** One observed snapshot, one pending snapshot, one
///   in-flight snapshot, one durable acknowledgment, one saved-file
///   acknowledgment, one timer task, one write task and a bounded waiter list.
///   No mutation receipts are buffered: recovery carries source only.
/// - **Honest failure and lag.** A failed checkpoint keeps the newest observed
///   text, exposes a typed failure, pauses scheduling and stops. Recovery then
///   requires an explicit ``retry()`` or a new ``observe(_:)``; there is no
///   unattended retry loop. ``RecoveryCoordinatorState/isCheckpointOverdue``
///   reports lag instead of implying the work is durable.
/// - **Orderly shutdown.** ``close()`` stops new observations, cancels the timer
///   cooperatively, lets any in-flight commit finish, then flushes the newest
///   observed revision and throws if that cannot be made durable. The newest text
///   stays readable and an explicit ``retry()`` stays available, so a failed
///   close cannot strand it.
public actor RecoveryCoordinator {

    /// The single document this coordinator is bound to.
    public nonisolated let documentID: DocumentID

    /// The longest checkpoint interval this coordinator will honour. The product
    /// contract is one second; a shorter interval is allowed, a longer one is
    /// clamped rather than silently accepted.
    public static let maximumCheckpointIntervalTicks: UInt64 = 1_000_000_000

    private let persistence: any DocumentPersistence
    private let scheduler: any MonotonicScheduling
    private let checkpointIntervalTicks: UInt64
    private let maximumWaiters: Int
    private let maximumSourceBytes: Int
    private let maximumSourceScalars: Int

    // The three separate states, plus the newest failure.
    private var latestObserved: SourceSnapshot?
    private var durableRecovery: DurableRevision?
    private var savedFile: SavedFileRevision?
    private var lastFailure: RecoveryCoordinatorError?
    private var lastBoundary: ObservationBoundary?

    // Scheduling and the single outstanding batch.
    private var pending: SourceSnapshot?
    private var inFlight: SourceSnapshot?
    private var outstandingSince: MonotonicInstant?
    private var pendingSince: MonotonicInstant?
    private var deadline: MonotonicInstant?
    private var forceDue = false
    private var hasAttemptedWrite = false
    private var isPausedForRetry = false
    private var timerTask: Task<Void, Never>?
    private var timerToken: UUID?
    private var driverTask: Task<Void, Never>?

    private var isClosing = false
    private var isClosed = false

    private var waiters: [Waiter] = []

    /// Binds a coordinator to one document and one persistence path.
    ///
    /// - Parameters:
    ///   - documentID: The document this coordinator serves. Any other identity
    ///     is rejected rather than silently mixed.
    ///   - persistence: The only durable sink. The coordinator never writes a
    ///     file, creates a key or reads a document itself.
    ///   - scheduler: The injected monotonic timing seam.
    ///   - checkpointInterval: Maximum time a checkpoint may trail the *oldest*
    ///     outstanding unsaved edit. Defaults to one second and is clamped to at
    ///     most ``maximumCheckpointIntervalTicks``; a shorter interval is
    ///     honoured.
    ///   - recoveredDurable: The durable revision already recovered from the
    ///     store when reopening a session. It seeds the durable state so a
    ///     resumed session is compared against the right revision; it is never a
    ///     save claim.
    ///   - maximumWaiters: Hard bound on concurrent durability waiters. Values
    ///     below one are raised to one.
    ///   - maximumSourceBytes: Hard bound on one retained source, defaulting to
    ///     the product's 8 MiB editor input bound.
    ///   - maximumSourceScalars: Hard bound on one retained source in Unicode
    ///     scalars, defaulting to the product's 1,000,000 scalar bound.
    ///
    /// Throws ``RecoveryCoordinatorError/foreignDocument(expected:received:)`` when
    /// a recovered durable revision belongs to a different document, and
    /// ``StorageError/invariantViolation(_:)`` for an unusable bound. A supplied
    /// seed is never silently ignored.
    public init(
        documentID: DocumentID,
        persistence: any DocumentPersistence,
        scheduler: any MonotonicScheduling = SystemMonotonicScheduler(),
        checkpointInterval: Duration = .seconds(1),
        recoveredDurable: DurableRevision? = nil,
        maximumWaiters: Int = 32,
        maximumSourceBytes: Int = 8 * 1024 * 1024,
        maximumSourceScalars: Int = 1_000_000
    ) throws {
        guard (1...(8 * 1024 * 1024)).contains(maximumSourceBytes),
              (1...1_000_000).contains(maximumSourceScalars) else {
            throw StorageError.invariantViolation(
                "Recovery input bounds must be positive and within the product limits."
            )
        }
        if let recoveredDurable, recoveredDurable.source.documentID != documentID {
            throw RecoveryCoordinatorError.foreignDocument(
                expected: documentID.rawValue,
                received: recoveredDurable.source.documentID.rawValue
            )
        }
        self.documentID = documentID
        self.persistence = persistence
        self.scheduler = scheduler
        self.checkpointIntervalTicks = Self.intervalTicks(from: checkpointInterval)
        self.maximumWaiters = max(1, maximumWaiters)
        self.maximumSourceBytes = maximumSourceBytes
        self.maximumSourceScalars = maximumSourceScalars
        self.durableRecovery = recoveredDurable
    }

    // MARK: - Observation

    /// Offers the current editor snapshot as the newest recoverable source.
    ///
    /// Coalesces with any not-yet-written snapshot: only the newest is kept. A
    /// stale revision, a same-revision-different-bytes offer and a snapshot for a
    /// different document are rejected with a typed failure, and the stored
    /// state is left untouched. New observations are refused once closing starts.
    public func observe(_ snapshot: SourceSnapshot) throws {
        try admit(snapshot)
    }

    /// A point-in-time view of the separate memory, durable and saved states.
    public func state() -> RecoveryCoordinatorState {
        RecoveryCoordinatorState(
            documentID: documentID,
            memoryRevision: latestObserved?.revision,
            memoryDigest: latestObserved?.digest,
            durable: durableRecovery.map {
                RecoveryDurableState(
                    revision: $0.source.revision,
                    digest: $0.source.digest,
                    recoveryCommit: $0.recoveryCommit
                )
            },
            savedFile: savedFile.map {
                RecoverySavedFileState(
                    revision: $0.source.revision,
                    digest: $0.source.digest,
                    url: $0.url
                )
            },
            lastFailure: lastFailure,
            lastBoundary: lastBoundary,
            hasOutstandingChanges: hasOutstandingChanges,
            isCheckpointOverdue: isCheckpointOverdue,
            isPausedForRetry: isPausedForRetry,
            isClosing: isClosing,
            isClosed: isClosed
        )
    }

    /// True while an observed revision is still newer than the durable one, or
    /// while a checkpoint is pending or in flight.
    public var hasOutstandingChanges: Bool {
        if pending != nil || inFlight != nil { return true }
        guard let latest = latestObserved else { return false }
        return !isDurable(latest.revision)
    }

    /// True when the oldest outstanding unsaved edit has exceeded the interval
    /// without a covering durable commit. A slow store therefore surfaces as lag
    /// rather than as an implied durable revision.
    public var isCheckpointOverdue: Bool {
        guard hasOutstandingChanges, let since = outstandingSince else { return false }
        return scheduler.now() >= since.advanced(by: checkpointIntervalTicks)
    }

    // MARK: - Lifecycle boundaries

    /// Waits until the given snapshot, or a newer one, is durably recoverable.
    ///
    /// Used at save, sleep and resign boundaries. It force-schedules a checkpoint
    /// for exactly this snapshot even if the interval has not elapsed, then
    /// suspends until a durable revision at least as new as the target exists, the
    /// checkpoint fails, or the waiter is cancelled.
    ///
    /// Cancelling the awaiting task removes only this waiter. A store write that
    /// is already committing continues to completion.
    ///
    /// The supplied snapshot must be the caller's current one: a boundary that
    /// flushes a stale revision is a caller error and is rejected.
    @discardableResult
    public func flush(
        _ snapshot: SourceSnapshot,
        atBoundary boundary: ObservationBoundary
    ) async throws -> DurableRevision {
        try admit(snapshot)
        lastBoundary = boundary
        return try await awaitDurability(of: snapshot)
    }

    /// Re-attempts the outstanding checkpoint after an exposed failure.
    ///
    /// This is the explicit owner action that replaces unattended retries. It is
    /// available while closing or closed so a failed shutdown cannot strand the
    /// newest observed text. It re-offers that revision through
    /// ``DocumentPersistence``, which is idempotent: a commit that was durable but
    /// reported as failed is returned with its original commit identity instead of
    /// being written twice.
    public func retry() {
        guard let target = pending ?? latestObserved else { return }
        if isDurable(target.revision) { return }
        pending = target
        stageImmediateWrite()
        kick()
    }

    /// Acknowledges that an exact snapshot finished being written to the
    /// document's file, and reports what that means for the saved state.
    ///
    /// The acknowledgement is recorded in *completion* order, because that is
    /// what determines the bytes physically on disk. The ack carries the exact
    /// bytes and URL, so a save finishing for revision `n` records `n` and never
    /// marks a newer revision saved. If a newer save already completed, this ack
    /// moves the saved state back to the older revision and reports
    /// ``SavedFileAcknowledgement/completedOutOfOrder`` rather than leaving the
    /// current revision displayed as saved.
    ///
    /// An acknowledgement for the current revision is refused unless its bytes
    /// match the observed memory snapshot, so a mismatched payload can never be
    /// reported as saved. Serialising native saves so two physical writes never
    /// overlap is an ownership rule of the file layer; this type reports the
    /// completion order it is told about and never assumes it.
    @discardableResult
    public func acknowledgeSavedFile(_ saved: SavedFileRevision) throws -> SavedFileAcknowledgement {
        guard !isClosing, !isClosed else { throw RecoveryCoordinatorError.closed }
        guard saved.source.documentID == documentID else {
            throw RecoveryCoordinatorError.foreignDocument(
                expected: documentID.rawValue,
                received: saved.source.documentID.rawValue
            )
        }
        guard let memory = latestObserved else {
            throw RecoveryCoordinatorError.unknownRevision(
                latest: 0,
                offered: saved.source.revision.rawValue
            )
        }
        guard saved.source.revision <= memory.revision else {
            throw RecoveryCoordinatorError.unknownRevision(
                latest: memory.revision.rawValue,
                offered: saved.source.revision.rawValue
            )
        }
        // The saved indicator is only ever set by this value, so the bytes of the
        // current revision must be exactly the bytes the editor produced.
        if saved.source.revision == memory.revision, saved.source.digest != memory.digest {
            throw RecoveryCoordinatorError.conflictingRevision(revision: saved.source.revision.rawValue)
        }
        if let current = savedFile,
           saved.source.revision == current.source.revision,
           saved.source.digest != current.source.digest {
            throw RecoveryCoordinatorError.conflictingRevision(revision: saved.source.revision.rawValue)
        }
        let completedOutOfOrder = (savedFile?.source.revision ?? Revision(0)) > saved.source.revision
        savedFile = saved
        return SavedFileAcknowledgement(
            savedRevision: saved.source.revision,
            isCurrent: saved.source.revision == memory.revision && saved.source.digest == memory.digest,
            completedOutOfOrder: completedOutOfOrder
        )
    }

    /// Stops new observations, finishes the in-flight commit and flushes the
    /// newest observed revision.
    ///
    /// Throws when the newest revision cannot be made durable. The coordinator
    /// then stays readable, keeps the newest text available and accepts an
    /// explicit ``retry()``; it is fully closed only once the newest revision is
    /// durable.
    public func close() async throws {
        if isClosed { return }
        // A second concurrent close is refused. Otherwise one caller's
        // cancellation could clear `isClosing` while the other is still waiting
        // for an older durability target, letting a newer edit slip in and the
        // coordinator close over unsaved text.
        guard !isClosing else {
            throw RecoveryCoordinatorError.closeAlreadyInProgress
        }
        isClosing = true
        cancelTimer()
        do {
            // Force the newest revision and wait on a cancellable waiter. An
            // already-committing store write is left alone; only this waiter is
            // removed if the close is cancelled.
            if let latest = latestObserved {
                _ = try await awaitDurability(of: latest)
            }
            isClosed = true
            isClosing = false
            failWaiters(RecoveryCoordinatorError.closed)
        } catch {
            // Cancelling a close must not be reported as a storage failure, and
            // must not discard the pending request: only its waiter is removed.
            // Clearing `isClosing` lets the document keep writing and lets an
            // emergency source save be acknowledged again.
            isClosing = false
            throw error
        }
    }

    /// Suspends until no timer is armed and no write is in flight.
    ///
    /// Under the injected virtual scheduler this is fully deterministic, which
    /// is why it exists: a test can drive the clock by hand and then observe the
    /// settled state without any real sleep.
    public func awaitQuiescence() async {
        while true {
            if let timer = timerTask {
                await timer.value
                continue
            }
            if let driver = driverTask {
                await driver.value
                continue
            }
            return
        }
    }

    // MARK: - Admission

    private func admit(_ snapshot: SourceSnapshot) throws {
        guard !isClosing, !isClosed else { throw RecoveryCoordinatorError.closed }
        guard snapshot.documentID == documentID else {
            throw RecoveryCoordinatorError.foreignDocument(
                expected: documentID.rawValue,
                received: snapshot.documentID.rawValue
            )
        }
        // The product's hard editor input bound is enforced before anything is
        // retained, so an oversized source is refused rather than memorised.
        guard snapshot.byteCount <= maximumSourceBytes,
              snapshot.scalarCount <= maximumSourceScalars else {
            throw RecoveryCoordinatorError.sourceBeyondInputBound(
                byteCount: snapshot.byteCount,
                scalarCount: snapshot.scalarCount,
                maximumBytes: maximumSourceBytes,
                maximumScalars: maximumSourceScalars
            )
        }
        if let highest = highestKnownRevision, snapshot.revision < highest {
            throw RecoveryCoordinatorError.nonMonotonicRevision(
                latest: highest.rawValue,
                offered: snapshot.revision.rawValue
            )
        }
        if let known = knownSnapshot(for: snapshot.revision), known.digest != snapshot.digest {
            throw RecoveryCoordinatorError.conflictingRevision(revision: snapshot.revision.rawValue)
        }
        if let observed = latestObserved {
            if observed.revision < snapshot.revision {
                latestObserved = snapshot
            } else if observed.digest != snapshot.digest {
                throw RecoveryCoordinatorError.conflictingRevision(revision: snapshot.revision.rawValue)
            }
        } else {
            latestObserved = snapshot
        }

        // The lag clock starts at the first edit that is not yet covered by a
        // durable commit, and keeps running while a checkpoint is in flight.
        if !isDurable(snapshot.revision), outstandingSince == nil {
            outstandingSince = scheduler.now()
        }

        guard !isDurable(snapshot.revision) else { return }
        registerPending(snapshot)
    }

    /// True only when a durable commit exists at or beyond `revision`. A missing
    /// durable revision is never treated as revision zero.
    private func isDurable(_ revision: Revision) -> Bool {
        guard let durable = durableRecovery else { return false }
        return durable.source.revision >= revision
    }

    private var highestKnownRevision: Revision? {
        switch (latestObserved, durableRecovery) {
        case let (observed?, durable?):
            return max(observed.revision, durable.source.revision)
        case let (observed?, nil):
            return observed.revision
        case let (nil, durable?):
            return durable.source.revision
        case (nil, nil):
            return nil
        }
    }

    private func knownSnapshot(for revision: Revision) -> SourceSnapshot? {
        if let durable = durableRecovery, durable.source.revision == revision {
            return durable.source
        }
        if let observed = latestObserved, observed.revision == revision {
            return observed
        }
        return nil
    }

    // MARK: - Scheduling

    /// Keeps only the newest disposable checkpoint and anchors the interval to
    /// the first change of this batch.
    private func registerPending(_ snapshot: SourceSnapshot) {
        if isBeingWritten(snapshot) { return }
        pending = snapshot
        isPausedForRetry = false
        // The timer anchor is the arrival time of the oldest edit in this batch.
        // A non-nil anchor is preserved (so later edits cannot push the deadline
        // back, and a forced write keeps the anchor for lag accounting), while a
        // cleared anchor is restored here. It is cleared after a failure or a
        // scheduler failure, where a new edit must restart the interval.
        if pendingSince == nil { pendingSince = scheduler.now() }

        // A document that has never been checkpointed is recoverable now, not
        // one interval from now. This applies once; after a failed first attempt
        // the caller must retry or edit again.
        if !hasAttemptedWrite, durableRecovery == nil {
            stageImmediateWrite()
            kick()
            return
        }
        // A write is already forced due; when the driver is free it takes this
        // newest snapshot without any further arming.
        if forceDue { return }
        // A deadline already anchored to an earlier change in this batch is
        // never pushed back, so continuous edits cannot starve recovery.
        if deadline == nil, let anchor = pendingSince {
            let due = anchor.advanced(by: checkpointIntervalTicks)
            deadline = due
            armTimer(due)
        }
    }

    private func stageImmediateWrite() {
        forceDue = true
        isPausedForRetry = false
        deadline = nil
        cancelTimer()
    }

    private func isBeingWritten(_ snapshot: SourceSnapshot) -> Bool {
        guard let inFlight else { return false }
        return inFlight.revision == snapshot.revision && inFlight.digest == snapshot.digest
    }

    private func armTimer(_ due: MonotonicInstant) {
        cancelTimer()
        let token = UUID()
        timerToken = token
        let scheduler = self.scheduler
        timerTask = Task { [weak self] in
            do {
                try await scheduler.sleep(until: due)
            } catch {
                // Cancellation is cooperative and expected. Any other scheduler
                // failure must still clear the armed timer and surface a paused
                // failure, or `awaitQuiescence` would wait on a finished task
                // forever and the checkpoint would never be promised.
                await self?.timerUnavailable(token: token, cancelled: error is CancellationError)
                return
            }
            if Task.isCancelled {
                await self?.timerUnavailable(token: token, cancelled: true)
                return
            }
            await self?.timerFired(token: token)
        }
    }

    private func cancelTimer() {
        timerTask?.cancel()
        timerTask = nil
        timerToken = nil
    }

    private func timerFired(token: UUID) {
        guard token == timerToken else { return }
        timerToken = nil
        timerTask = nil
        guard pending != nil else { return }
        stageImmediateWrite()
        kick()
    }

    /// Clears the armed timer after its wait ended without firing.
    ///
    /// A cancelled wait is not a failure: the timer task simply finishes and the
    /// reference is dropped. Any other scheduler failure pauses scheduling and is
    /// reported, because no further checkpoint can be promised in time. The
    /// newest text is preserved in both cases.
    private func timerUnavailable(token: UUID, cancelled: Bool) {
        guard token == timerToken else { return }
        timerToken = nil
        timerTask = nil
        guard !cancelled, !isPausedForRetry else { return }
        lastFailure = .schedulingFailed
        guard !forceDue else { return }
        guard let latest = latestObserved, !isDurable(latest.revision) else { return }
        pending = latest
        isPausedForRetry = true
        pendingSince = nil
        deadline = nil
    }

    // MARK: - Serialized writing

    private func kick() {
        guard driverTask == nil else { return }
        driverTask = Task { await self.driveLoop() }
    }

    private func driveLoop() async {
        while true {
            guard let next = takeDuePending() else {
                driverTask = nil
                return
            }
            // Marked in flight before the await, so no actor interleaving can
            // observe a snapshot as neither pending nor in flight.
            inFlight = next
            await persistOne(next)
            inFlight = nil
        }
    }

    private func takeDuePending() -> SourceSnapshot? {
        guard let candidate = pending else { return nil }
        // A failed checkpoint parks the newest text until an explicit retry or a
        // new edit. Without this a nil deadline would look immediately due and
        // the loop would retry forever.
        guard !isPausedForRetry else { return nil }
        if !forceDue {
            guard let deadline else {
                // No deadline and not paused means an immediate checkpoint was
                // staged and no deadline has been anchored yet.
                pending = nil
                pendingSince = nil
                return candidate
            }
            guard scheduler.now() >= deadline else { return nil }
        }
        pending = nil
        pendingSince = nil
        deadline = nil
        forceDue = false
        cancelTimer()
        return candidate
    }

    private func persistOne(_ snapshot: SourceSnapshot) async {
        hasAttemptedWrite = true
        do {
            // Recovery carries source only. No mutation receipt backlog is kept,
            // and a recovery acknowledgement is never capture evidence.
            let durable = try await persistence.persist(
                RecoveryBatch(source: snapshot, receipts: [])
            )
            handle(durable: durable, offered: snapshot)
        } catch {
            handle(failure: error, offered: snapshot)
        }
    }

    private func handle(durable: DurableRevision, offered: SourceSnapshot) {
        guard durable.source.documentID == documentID else {
            handle(
                failure: RecoveryCoordinatorError.foreignDocument(
                    expected: documentID.rawValue,
                    received: durable.source.documentID.rawValue
                ),
                offered: offered
            )
            return
        }
        // The acknowledgement must be the exact snapshot that was offered. A
        // revision-only match would let a different payload be recorded as
        // durable.
        guard durable.source.revision == offered.revision,
              durable.source.digest == offered.digest,
              durable.source.utf8 == offered.utf8 else {
            handle(
                failure: RecoveryCoordinatorError.durableMismatch(revision: offered.revision.rawValue),
                offered: offered
            )
            return
        }
        // The durable revision only ever advances from the snapshot the store
        // actually committed, so a slow older completion cannot mark a newer
        // revision durable. Revision zero is a real revision and is recorded even
        // when nothing was durable before.
        if durableRecovery == nil || durableRecovery!.source.revision < durable.source.revision {
            durableRecovery = durable
        }
        // A pending batch the commit already covers needs no further write.
        if let queued = pending, isDurable(queued.revision) {
            pending = nil
            pendingSince = nil
            deadline = nil
            forceDue = false
        }
        if let latest = latestObserved, isDurable(latest.revision) {
            outstandingSince = nil
        } else if pending != nil, let anchor = pendingSince {
            // The committed revision is no longer outstanding, so the lag clock
            // now measures the first edit that is still pending. Without this an
            // already-durable revision's timestamp would report false lag forever.
            outstandingSince = anchor
        }
        lastFailure = nil
        settleWaiters()
    }

    private func handle(failure: any Error, offered: SourceSnapshot) {
        let typed = Self.typedFailure(failure)
        lastFailure = typed
        restorePendingAfterFailure()
        failWaiters(typed)
    }

    /// Keeps the newest observed text available for an explicit retry, and pauses
    /// scheduling: a failure must not start an unattended retry loop. The lag
    /// clock keeps running, so the failure is reported as overdue rather than
    /// quietly resolved.
    private func restorePendingAfterFailure() {
        if let latest = latestObserved, !isDurable(latest.revision) {
            pending = latest
            isPausedForRetry = true
        } else {
            pending = nil
            isPausedForRetry = false
            outstandingSince = nil
        }
        pendingSince = nil
        deadline = nil
        forceDue = false
        cancelTimer()
    }

    /// Maps an arbitrary thrown error to a typed, privacy-safe failure. The raw
    /// error is never stringified into the result.
    private static func typedFailure(_ error: any Error) -> RecoveryCoordinatorError {
        if let typed = error as? RecoveryCoordinatorError { return typed }
        if let storage = error as? StorageError { return .persistence(storage) }
        return .persistenceFailure("unclassified")
    }

    // MARK: - Durability waiting

    /// Forces a checkpoint for `snapshot` and suspends until a durable revision at
    /// least as new as it exists, the checkpoint fails, or the caller cancels.
    private func awaitDurability(of snapshot: SourceSnapshot) async throws -> DurableRevision {
        if let durable = durableRecovery, durable.source.revision >= snapshot.revision {
            return durable
        }
        if !isBeingWritten(snapshot) {
            pending = snapshot
            stageImmediateWrite()
        }
        kick()

        // The span above is synchronous, so the driver cannot commit in between:
        // either the commit is already done, or a waiter is settled by it.
        if let durable = durableRecovery, durable.source.revision >= snapshot.revision {
            return durable
        }
        guard waiters.count < maximumWaiters else {
            throw RecoveryCoordinatorError.tooManyWaiters(limit: maximumWaiters)
        }
        let token = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<DurableRevision, any Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.waiters.append(
                    Waiter(token: token, targetRevision: snapshot.revision, continuation: continuation)
                )
                self.settleWaiters()
            }
        } onCancel: {
            Task { await self.cancelWaiter(token: token) }
        }
    }

    // MARK: - Waiters

    private func settleWaiters() {
        guard !waiters.isEmpty else { return }
        var remaining: [Waiter] = []
        remaining.reserveCapacity(waiters.count)
        for waiter in waiters {
            if let durable = durableRecovery, durable.source.revision >= waiter.targetRevision {
                waiter.continuation.resume(returning: durable)
            } else {
                remaining.append(waiter)
            }
        }
        waiters = remaining
    }

    private func failWaiters(_ error: RecoveryCoordinatorError) {
        guard !waiters.isEmpty else { return }
        let outstanding = waiters
        waiters = []
        for waiter in outstanding {
            waiter.continuation.resume(throwing: error)
        }
    }

    /// Removes one waiting caller. The store write it was waiting on is untouched
    /// and continues to completion.
    private func cancelWaiter(token: UUID) {
        guard let index = waiters.firstIndex(where: { $0.token == token }) else { return }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
    }

    // MARK: - Helpers

    /// Nanosecond ticks for an interval, clamped to the product's one-second
    /// maximum. Attoseconds are scaled to nanoseconds rather than added directly.
    static func intervalTicks(from duration: Duration) -> UInt64 {
        let components = duration.components
        guard components.seconds > 0 || components.attoseconds > 0 else { return 0 }
        let seconds = UInt64(clamping: components.seconds)
        let (secondTicks, secondsOverflow) = seconds.multipliedReportingOverflow(by: 1_000_000_000)
        let attosecondTicks = UInt64(clamping: components.attoseconds) / 1_000_000_000
        let (total, sumOverflow) = secondTicks.addingReportingOverflow(attosecondTicks)
        let ticks = (secondsOverflow || sumOverflow) ? UInt64.max : total
        return min(ticks, maximumCheckpointIntervalTicks)
    }

    private struct Waiter {
        let token: UUID
        let targetRevision: Revision
        let continuation: CheckedContinuation<DurableRevision, any Error>
    }
}
