import XCTest
@testable import WriterFoundation

/// Voluntary-focus reducer contract from FOCUS.md: normal versus locked mode,
/// persisted-intent acknowledgement, uninterrupted foreground time, clamped word
/// progress from authoritative lineage input, restriction gating, and exit paths
/// that always restore whatever the adapter saved.
final class FocusStateTests: XCTestCase {

    private let documentID = DocumentID(
        rawValue: UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!
    )
    private let sessionA = FocusSessionID(
        rawValue: UUID(uuidString: "AAAAAAAA-0000-4000-8000-00000000000A")!
    )
    private let sessionB = FocusSessionID(
        rawValue: UUID(uuidString: "BBBBBBBB-0000-4000-8000-00000000000B")!
    )

    private var testPresentation: FocusPresentation {
        FocusPresentation(priorOptionsToken: "prior-options")
    }

    @discardableResult
    private func begin(_ reducer: inout FocusReducer,
                       sessionID: FocusSessionID,
                       mode: FocusMode = .locked,
                       goal: FocusGoal? = nil,
                       restrictions: FocusRestrictions = FocusRestrictions(),
                       baselineWordCount: Int? = nil,
                       preflight: FocusPreflight = FocusPreflight(),
                       presentation: FocusPresentation? = nil,
                       acknowledge: Bool = true) -> [FocusEffect] {
        let effects = reducer.send(.begin(
            sessionID: sessionID,
            mode: mode,
            documentID: documentID,
            goal: goal,
            restrictions: restrictions,
            baselineWordCount: baselineWordCount,
            preflight: preflight,
            presentation: presentation ?? testPresentation,
            recordedAtEpochSeconds: 1_700_000_000
        ))
        if acknowledge, case .persistSessionIntent(let intent)? = effects.first {
            _ = reducer.send(.intentPersisted(intent.sessionID))
        }
        return effects
    }

    /// A locked session already through its persistence acknowledgement.
    private func locked(_ goal: FocusGoal,
                        restrictions: FocusRestrictions = FocusRestrictions(),
                        baselineWordCount: Int? = nil) -> FocusReducer {
        var reducer = FocusReducer()
        begin(&reducer, sessionID: sessionA, goal: goal, restrictions: restrictions,
              baselineWordCount: baselineWordCount)
        return reducer
    }

    // MARK: - Mode and preflight

    func testLockedBeginValidatesGoalsPreflightAndBaseline() {
        func effects(goal: FocusGoal?,
                     preflight: FocusPreflight = FocusPreflight(),
                     baseline: Int? = nil) -> [FocusEffect] {
            var reducer = FocusReducer()
            return begin(&reducer, sessionID: sessionA, mode: .locked, goal: goal,
                         baselineWordCount: baseline, preflight: preflight, acknowledge: false)
        }

        XCTAssertEqual(effects(goal: .time(minutes: 0)), [.rejected(.invalidTimeGoal(0))])
        XCTAssertEqual(effects(goal: .time(minutes: 241)), [.rejected(.invalidTimeGoal(241))])
        XCTAssertEqual(effects(goal: .words(target: 49)), [.rejected(.invalidWordGoal(49))])
        XCTAssertEqual(
            effects(goal: .words(target: 20_001)),
            [.rejected(.invalidWordGoal(20_001))]
        )
        XCTAssertEqual(effects(goal: nil), [.rejected(.missingLockedGoal)])
        XCTAssertEqual(
            effects(goal: .time(minutes: 25),
                    preflight: FocusPreflight(hasUnresolvedFileConflict: true)),
            [.rejected(.unresolvedFileConflict)]
        )
        XCTAssertEqual(
            effects(goal: .time(minutes: 25),
                    preflight: FocusPreflight(hasUnsavedDiskFailure: true)),
            [.rejected(.unsavedDiskFailure)]
        )
        XCTAssertEqual(
            effects(goal: .words(target: 500)),
            [.rejected(.missingWordBaseline)]
        )
        XCTAssertEqual(
            effects(goal: .words(target: 500), baseline: -1),
            [.rejected(.invalidBaseline(-1))]
        )

        // Range endpoints are inclusive.
        XCTAssertNotNil(effects(goal: .time(minutes: 1)).first)
        XCTAssertNotNil(effects(goal: .time(minutes: 240)).first)
        XCTAssertNotNil(effects(goal: .words(target: 50), baseline: 0).first)
        XCTAssertNotNil(effects(goal: .words(target: 20_000), baseline: 0).first)
    }

    func testNormalModeIsPresentationOnlyAndExitsImmediately() {
        var reducer = FocusReducer()
        begin(&reducer, sessionID: sessionA, mode: .normal, goal: nil)

        XCTAssertEqual(reducer.state.phase, .active)
        XCTAssertEqual(reducer.state.mode, .normal)
        XCTAssertFalse(reducer.state.isLocked)
        // No goal, so no hidden timer can end normal presentation.
        XCTAssertFalse(reducer.state.isGoalMet)
        XCTAssertFalse(reducer.state.shouldComplete)

        // Nothing is denied in a presentation-only session.
        for command in FocusCommand.allCases {
            XCTAssertTrue(reducer.state.allows(command), "\(command) in normal mode")
        }

        _ = reducer.send(.tick(monotonic: 0, isForegroundAwake: true))
        _ = reducer.send(.tick(monotonic: 100_000, isForegroundAwake: true))
        XCTAssertEqual(reducer.state.phase, .active, "normal focus must not self-complete")

        let effects = reducer.send(.requestEnd)
        XCTAssertEqual(reducer.state.phase, .ended)
        XCTAssertFalse(reducer.state.endedEarly)
        XCTAssertTrue(effects.contains(.finalizeRecovery(.normalEnd)))
        XCTAssertFalse(effects.contains(.beginExitCountdown(seconds: 10)))
    }

    func testNormalModeRejectsAGoal() {
        var reducer = FocusReducer()
        XCTAssertEqual(
            begin(&reducer, sessionID: sessionA, mode: .normal, goal: .time(minutes: 25),
                  acknowledge: false),
            [.rejected(.goalNotAllowedInNormalMode)]
        )
        XCTAssertEqual(reducer.state.phase, .idle)
    }

    func testBeginRejectedWhileASessionIsRunning() {
        var reducer = locked(.time(minutes: 25))
        XCTAssertEqual(
            begin(&reducer, sessionID: sessionB, goal: .time(minutes: 5), acknowledge: false),
            [.rejected(.sessionAlreadyActive(.active))]
        )
        XCTAssertEqual(reducer.state.goal, .time(minutes: 25))
        XCTAssertEqual(reducer.state.sessionID, sessionA)
    }

    // MARK: - Persisted intent gates activation

    func testSessionIsNotActiveUntilTheIntentIsAcknowledged() {
        var reducer = FocusReducer()
        let effects = begin(&reducer, sessionID: sessionA, goal: .time(minutes: 25),
                            acknowledge: false)
        guard case .persistSessionIntent(let intent)? = effects.first else {
            return XCTFail("begin must persist the session intent first")
        }
        XCTAssertEqual(intent.sessionID, sessionA)
        XCTAssertEqual(reducer.state.phase, .preparing)
        // Nothing is locked before the acknowledgement, so no command is denied.
        XCTAssertFalse(reducer.state.isLocked)
        XCTAssertTrue(reducer.state.allows(.close))

        // Time before the acknowledgement is never credited.
        _ = reducer.send(.tick(monotonic: 0, isForegroundAwake: true))
        _ = reducer.send(.tick(monotonic: 60, isForegroundAwake: true))
        XCTAssertEqual(reducer.state.accumulatedActiveSeconds, 0)

        XCTAssertEqual(
            reducer.send(.intentPersisted(sessionB)),
            [.rejected(.sessionMismatch)]
        )
        XCTAssertEqual(reducer.state.phase, .preparing)

        XCTAssertEqual(
            reducer.send(.intentPersisted(sessionA)),
            [.applyPresentation(testPresentation)]
        )
        XCTAssertEqual(reducer.state.phase, .active)
        XCTAssertTrue(reducer.state.isLocked)
    }

    func testIntentAcknowledgementStartsSoundOnlyWhenEnabled() {
        var reducer = FocusReducer()
        let sounding = FocusPresentation(priorOptionsToken: "prior", soundEnabled: true)
        begin(&reducer, sessionID: sessionA, goal: .time(minutes: 25),
              presentation: sounding, acknowledge: false)
        XCTAssertEqual(
            reducer.send(.intentPersisted(sessionA)),
            [.applyPresentation(sounding), .startSound]
        )
    }

    // MARK: - Interruption

    func testInterruptionRestoresFullPresentationAndReleasesShields() {
        var reducer = locked(.time(minutes: 25))
        XCTAssertEqual(
            reducer.send(.interruption(.sleep)),
            [.restorePresentation(testPresentation), .releaseShields, .stopSound]
        )
        XCTAssertEqual(reducer.state.phase, .interrupted)
        XCTAssertEqual(reducer.state.interruption, .sleep)
        // Protection was released, so no presentation restriction remains, but
        // the session is still a commitment: escapes stay denied until it ends.
        XCTAssertTrue(reducer.state.isLocked)
        XCTAssertFalse(reducer.state.allows(.close))
    }

    func testInterruptedBeforeAcknowledgementResumesToPreparing() {
        var reducer = FocusReducer()
        begin(&reducer, sessionID: sessionA, goal: .time(minutes: 25), acknowledge: false)
        XCTAssertEqual(reducer.state.phase, .preparing)

        _ = reducer.send(.interruption(.screenLock))
        XCTAssertEqual(reducer.state.phase, .interrupted)

        // Resuming must not activate a session whose intent was never persisted.
        XCTAssertEqual(reducer.send(.resume), [])
        XCTAssertEqual(reducer.state.phase, .preparing)

        XCTAssertEqual(
            reducer.send(.intentPersisted(sessionA)),
            [.applyPresentation(testPresentation)]
        )
        XCTAssertEqual(reducer.state.phase, .active)
    }

    func testInterruptedAfterAcknowledgementResumesAndReappliesProtection() {
        var reducer = locked(.time(minutes: 25))
        _ = reducer.send(.interruption(.appDeactivation))
        XCTAssertEqual(reducer.send(.resume), [.applyPresentation(testPresentation)])
        XCTAssertEqual(reducer.state.phase, .active)
        XCTAssertNil(reducer.state.interruption)
        XCTAssertTrue(reducer.state.isLocked)
    }

    func testInterruptionResetsTheTimeAnchor() {
        var reducer = locked(.time(minutes: 240))
        _ = reducer.send(.tick(monotonic: 0, isForegroundAwake: true))
        _ = reducer.send(.tick(monotonic: 10, isForegroundAwake: true))
        XCTAssertEqual(reducer.state.accumulatedActiveSeconds, 10)

        _ = reducer.send(.interruption(.screenLock))
        _ = reducer.send(.resume)

        // The elapsed gap while paused is never credited.
        _ = reducer.send(.tick(monotonic: 100, isForegroundAwake: true))
        _ = reducer.send(.tick(monotonic: 110, isForegroundAwake: true))
        XCTAssertEqual(reducer.state.accumulatedActiveSeconds, 20)
    }

    // MARK: - Time accounting

    func testOnlyContinuousForegroundTimeIsCredited() {
        var reducer = locked(.time(minutes: 240))
        _ = reducer.send(.tick(monotonic: 0, isForegroundAwake: true))
        _ = reducer.send(.tick(monotonic: 30, isForegroundAwake: true))
        // A suspended stretch contributes nothing.
        _ = reducer.send(.tick(monotonic: 60, isForegroundAwake: false))
        _ = reducer.send(.tick(monotonic: 600, isForegroundAwake: true))
        XCTAssertEqual(reducer.state.accumulatedActiveSeconds, 30)

        // Foreground time resumes only after the re-anchoring tick.
        _ = reducer.send(.tick(monotonic: 620, isForegroundAwake: true))
        XCTAssertEqual(reducer.state.accumulatedActiveSeconds, 50)
    }

    func testAWakeTickAfterASuspendedTickDoesNotCountTheGap() {
        var reducer = locked(.time(minutes: 240))
        // Anchor while suspended, then return to the foreground.
        _ = reducer.send(.tick(monotonic: 0, isForegroundAwake: false))
        _ = reducer.send(.tick(monotonic: 100, isForegroundAwake: true))
        XCTAssertEqual(reducer.state.accumulatedActiveSeconds, 0)
    }

    func testBackwardClockInterruptsWithoutCreditingOrRollingBack() {
        var reducer = locked(.time(minutes: 240))
        _ = reducer.send(.tick(monotonic: 100, isForegroundAwake: true))
        _ = reducer.send(.tick(monotonic: 150, isForegroundAwake: true))
        XCTAssertEqual(reducer.state.accumulatedActiveSeconds, 50)

        let effects = reducer.send(.tick(monotonic: 120, isForegroundAwake: true))
        XCTAssertEqual(reducer.state.phase, .interrupted)
        XCTAssertEqual(reducer.state.interruption, .clockMovedBackward)
        XCTAssertEqual(reducer.state.accumulatedActiveSeconds, 50)
        XCTAssertEqual(
            effects,
            [.restorePresentation(testPresentation), .releaseShields, .stopSound]
        )
    }

    func testNonFiniteClockReadingIsRejected() {
        var reducer = locked(.time(minutes: 240))
        for reading in [Double.nan, .infinity, -.infinity] {
            XCTAssertEqual(
                reducer.send(.tick(monotonic: reading, isForegroundAwake: true)),
                [.rejected(.invalidClockReading)]
            )
        }
        XCTAssertEqual(reducer.state.phase, .active)
        XCTAssertEqual(reducer.state.accumulatedActiveSeconds, 0)
        XCTAssertNil(reducer.state.lastTickMonotonic)
    }

    // MARK: - Goal completion

    func testTimerGoalCompletesReleasesTheLockAndNeverRelocks() {
        var reducer = locked(.time(minutes: 1))
        _ = reducer.send(.tick(monotonic: 0, isForegroundAwake: true))
        let effects = reducer.send(.tick(monotonic: 60, isForegroundAwake: true))

        XCTAssertEqual(reducer.state.phase, .completed)
        XCTAssertTrue(effects.contains(.restorePresentation(testPresentation)))
        XCTAssertTrue(effects.contains(.finalizeRecovery(.goalReached)))
        XCTAssertFalse(reducer.state.isLocked)
        XCTAssertFalse(reducer.state.allowsRelock)

        _ = reducer.send(.tick(monotonic: 600, isForegroundAwake: true))
        _ = reducer.send(.tick(monotonic: 9_000, isForegroundAwake: true))
        XCTAssertEqual(reducer.state.phase, .completed)
        XCTAssertFalse(reducer.state.isLocked)
    }

    func testContinueWritingNeverCompletesAgain() {
        var reducer = locked(.time(minutes: 1))
        _ = reducer.send(.tick(monotonic: 0, isForegroundAwake: true))
        _ = reducer.send(.tick(monotonic: 60, isForegroundAwake: true))
        XCTAssertEqual(reducer.state.phase, .completed)
        // The 60 s that satisfied the timer stays recorded.
        let accruedAtCompletion = reducer.state.accumulatedActiveSeconds
        XCTAssertEqual(accruedAtCompletion, 60)

        XCTAssertEqual(
            reducer.send(.completeAfterGoal(.continueWriting, newSessionID: sessionB)),
            []
        )
        XCTAssertEqual(reducer.state.phase, .active)
        XCTAssertFalse(reducer.state.isLocked)
        XCTAssertFalse(reducer.state.shouldComplete)

        // Further runtime neither completes, re-locks, nor announces a goal again.
        for reading in [100.0, 200.0, 400.0] {
            let effects = reducer.send(.tick(monotonic: reading, isForegroundAwake: true))
            XCTAssertEqual(effects, [], "tick at \(reading) must be inert")
        }
        XCTAssertEqual(reducer.state.phase, .active)
        XCTAssertFalse(reducer.state.isLocked)
        XCTAssertEqual(
            reducer.state.accumulatedActiveSeconds, accruedAtCompletion,
            "an unlocked continuation accrues no further goal progress"
        )
    }

    // MARK: - Word progress

    func testWordProgressIsClampedAndRelativeToTheFixedBaseline() {
        var reducer = locked(.words(target: 500), baselineWordCount: 1_000)

        _ = reducer.send(.updateWordProgress(currentWordCount: 1_050, eligibleNewWordCount: 40))
        XCTAssertEqual(reducer.state.wordProgress, 40)

        _ = reducer.send(.updateWordProgress(currentWordCount: 1_050, eligibleNewWordCount: 500))
        XCTAssertEqual(reducer.state.wordProgress, 50)

        _ = reducer.send(.updateWordProgress(currentWordCount: 900, eligibleNewWordCount: 500))
        XCTAssertEqual(reducer.state.wordProgress, 0)

        _ = reducer.send(.updateWordProgress(currentWordCount: 1_200, eligibleNewWordCount: 0))
        XCTAssertEqual(reducer.state.wordProgress, 0)
    }

    func testNegativeWordInputsAreRejected() {
        var reducer = locked(.words(target: 500), baselineWordCount: 10)
        XCTAssertEqual(
            reducer.send(.updateWordProgress(currentWordCount: -1, eligibleNewWordCount: 10)),
            [.rejected(.invalidWordInput(currentWordCount: -1, eligibleNewWordCount: 10))]
        )
        XCTAssertEqual(
            reducer.send(.updateWordProgress(currentWordCount: 10, eligibleNewWordCount: -5)),
            [.rejected(.invalidWordInput(currentWordCount: 10, eligibleNewWordCount: -5))]
        )
        XCTAssertEqual(reducer.state.wordProgress, 0)
    }

    func testExtremeWordCountsDoNotOverflow() {
        // 0 - Int.max is representable, so the clamped progress is simply zero.
        var reducer = locked(.words(target: 50), baselineWordCount: Int.max)
        XCTAssertEqual(
            reducer.send(.updateWordProgress(currentWordCount: 0, eligibleNewWordCount: Int.max)),
            []
        )
        XCTAssertEqual(reducer.state.wordProgress, 0)
    }

    func testWordGoalCompletesAtTarget() {
        var reducer = locked(.words(target: 50), baselineWordCount: 100)
        let effects = reducer.send(
            .updateWordProgress(currentWordCount: 150, eligibleNewWordCount: 50)
        )
        XCTAssertEqual(reducer.state.phase, .completed)
        XCTAssertTrue(effects.contains(.finalizeRecovery(.goalReached)))
        XCTAssertEqual(reducer.state.wordProgress, 50)
    }

    func testWordProgressIsIgnoredForTimerAndNormalSessions() {
        var timer = locked(.time(minutes: 25))
        _ = timer.send(.updateWordProgress(currentWordCount: 5_000, eligibleNewWordCount: 5_000))
        XCTAssertEqual(timer.state.wordProgress, 0)

        var normal = FocusReducer()
        begin(&normal, sessionID: sessionA, mode: .normal, goal: nil)
        _ = normal.send(.updateWordProgress(currentWordCount: 5_000, eligibleNewWordCount: 5_000))
        XCTAssertEqual(normal.state.wordProgress, 0)
        XCTAssertEqual(normal.state.phase, .active)
    }

    // MARK: - Restriction gating

    func testWordGoalAlwaysBlocksExternalTextRegardlessOfClipboardPolicy() {
        let reducer = locked(.words(target: 500), baselineWordCount: 0)
        XCTAssertFalse(reducer.state.allows(.externalInsertion))
        XCTAssertFalse(reducer.state.allows(.dictation))
        XCTAssertFalse(reducer.state.allows(.completion))
        XCTAssertFalse(reducer.state.allows(.crossDocumentImport))
        XCTAssertTrue(reducer.state.allows(.typing))
        XCTAssertTrue(reducer.state.allows(.undo))
    }

    func testClipboardPoliciesGateExternalTextAndCopyCutSeparately() {
        let unrestricted = locked(.time(minutes: 25))
        XCTAssertTrue(unrestricted.state.allows(.externalInsertion))
        XCTAssertTrue(unrestricted.state.allows(.copy))
        XCTAssertTrue(unrestricted.state.allows(.cut))

        let insertionBlocked = locked(
            .time(minutes: 25),
            restrictions: FocusRestrictions(clipboard: .blockExternalInsertion)
        )
        XCTAssertFalse(insertionBlocked.state.allows(.externalInsertion))
        XCTAssertFalse(insertionBlocked.state.allows(.dictation))
        XCTAssertTrue(insertionBlocked.state.allows(.copy))
        XCTAssertTrue(insertionBlocked.state.allows(.cut))

        let fullyBlocked = locked(
            .time(minutes: 25),
            restrictions: FocusRestrictions(clipboard: .blockCopyCutAndPaste)
        )
        XCTAssertFalse(fullyBlocked.state.allows(.externalInsertion))
        XCTAssertFalse(fullyBlocked.state.allows(.copy))
        XCTAssertFalse(fullyBlocked.state.allows(.cut))
        XCTAssertFalse(fullyBlocked.state.allows(.exportShare))
    }

    func testLockedSessionsDenyEscapesButNeverSaveUndoNavigationOrExit() {
        for reducer in [locked(.time(minutes: 25)),
                        locked(.words(target: 500), baselineWordCount: 0)] {
            XCTAssertTrue(reducer.state.isLocked)
            for command: FocusCommand in [.localSave, .undo, .typing, .scrolling,
                                          .find, .textAccessibility, .emergencyExit] {
                XCTAssertTrue(reducer.state.allows(command), "\(command) must never be denied")
            }
            for command: FocusCommand in [.close, .newDocument, .openDocument,
                                          .publish, .quickPost, .settingsChange] {
                XCTAssertFalse(reducer.state.allows(command), "\(command) escapes the session")
            }
        }
    }

    func testEndedSessionAllowsEveryCommand() {
        var reducer = locked(.time(minutes: 25))
        _ = reducer.send(.recoverStaleSession)
        XCTAssertEqual(reducer.state.phase, .ended)
        for command in FocusCommand.allCases {
            XCTAssertTrue(reducer.state.allows(command), "\(command) in an ended session")
        }
    }

    // MARK: - Exit paths

    func testPreparingExitIsImmediateWithNoCountdown() {
        var reducer = FocusReducer()
        begin(&reducer, sessionID: sessionA, goal: .time(minutes: 25), acknowledge: false)
        XCTAssertEqual(reducer.state.phase, .preparing)

        let effects = reducer.send(.requestEnd)
        XCTAssertEqual(reducer.state.phase, .ended)
        XCTAssertFalse(reducer.state.endedEarly)
        XCTAssertTrue(effects.contains(.finalizeRecovery(.normalEnd)))
        XCTAssertFalse(effects.contains(.beginExitCountdown(seconds: 10)))
    }

    func testLockedExitRequiresTheDeliberateCountdownAndCanBeCancelled() {
        var reducer = locked(.time(minutes: 25))
        XCTAssertEqual(
            reducer.send(.requestEnd),
            [.beginExitCountdown(seconds: FocusReducer.emergencyExitSeconds)]
        )
        XCTAssertEqual(reducer.state.phase, .exiting)
        XCTAssertEqual(reducer.state.exitCountdownRemaining, 10)

        // Nine of the ten seconds is not enough.
        _ = reducer.send(.tick(monotonic: 100, isForegroundAwake: true))
        _ = reducer.send(.tick(monotonic: 109, isForegroundAwake: true))
        XCTAssertEqual(reducer.state.phase, .exiting)
        XCTAssertEqual(reducer.state.exitCountdownRemaining, 1)

        XCTAssertEqual(reducer.send(.cancelPendingExit), [.applyPresentation(testPresentation)])
        XCTAssertEqual(reducer.state.phase, .active)
        XCTAssertNil(reducer.state.exitCountdownRemaining)
        XCTAssertTrue(reducer.state.isLocked)
    }

    func testCancellingAnExitFromAPausedSessionDoesNotRestoreProtection() {
        var reducer = locked(.time(minutes: 25))
        _ = reducer.send(.interruption(.appDeactivation))
        XCTAssertEqual(reducer.state.phase, .interrupted)

        // A paused session can still end, and cancelling returns to paused.
        XCTAssertEqual(
            reducer.send(.requestEnd),
            [.beginExitCountdown(seconds: FocusReducer.emergencyExitSeconds)]
        )
        XCTAssertEqual(reducer.state.phase, .exiting)
        XCTAssertEqual(reducer.send(.cancelPendingExit), [])
        XCTAssertEqual(reducer.state.phase, .interrupted)
        // Cancelling returned to the paused phase without re-protecting: the
        // session still gates escapes, but no presentation was re-applied.
        XCTAssertTrue(reducer.state.isLocked)
        XCTAssertEqual(reducer.state.interruption, .appDeactivation)
    }

    func testExitCountdownElapsesToEndedEarly() {
        var reducer = locked(.time(minutes: 25))
        _ = reducer.send(.requestEnd)
        _ = reducer.send(.tick(monotonic: 200, isForegroundAwake: true))
        let done = reducer.send(.tick(monotonic: 211, isForegroundAwake: true))
        XCTAssertEqual(reducer.state.phase, .ended)
        XCTAssertTrue(reducer.state.endedEarly)
        XCTAssertTrue(done.contains(.restorePresentation(testPresentation)))
        XCTAssertTrue(done.contains(.finalizeRecovery(.emergencyExit)))
    }

    func testUnlockedExitIsImmediate() {
        var reducer = locked(.time(minutes: 1))
        _ = reducer.send(.tick(monotonic: 0, isForegroundAwake: true))
        _ = reducer.send(.tick(monotonic: 60, isForegroundAwake: true))
        _ = reducer.send(.completeAfterGoal(.continueWriting, newSessionID: sessionB))
        XCTAssertFalse(reducer.state.isLocked)

        let effects = reducer.send(.requestEnd)
        XCTAssertEqual(reducer.state.phase, .ended)
        XCTAssertFalse(reducer.state.endedEarly)
        XCTAssertTrue(effects.contains(.finalizeRecovery(.normalEnd)))
        XCTAssertFalse(effects.contains(.beginExitCountdown(seconds: 10)))
    }

    // MARK: - Post-completion actions

    func testAddTenMinutesPersistsAFreshIntentAndWaitsForItsAcknowledgement() {
        var reducer = locked(.time(minutes: 1))
        _ = reducer.send(.tick(monotonic: 0, isForegroundAwake: true))
        _ = reducer.send(.tick(monotonic: 60, isForegroundAwake: true))
        XCTAssertEqual(reducer.state.phase, .completed)
        // Reaching the goal never extends it by itself.
        XCTAssertEqual(reducer.state.goal, .time(minutes: 1))

        let effects = reducer.send(.completeAfterGoal(.addTenMinutes, newSessionID: sessionB))
        guard case .persistSessionIntent(let intent)? = effects.first else {
            return XCTFail("addTenMinutes must persist a fresh intent")
        }
        XCTAssertEqual(intent.sessionID, sessionB)
        XCTAssertEqual(intent.mode, .locked)
        XCTAssertEqual(intent.goal, .time(minutes: 10))
        XCTAssertEqual(reducer.state.sessionID, sessionB)
        XCTAssertEqual(reducer.state.phase, .preparing)
        XCTAssertFalse(reducer.state.intentPersisted)
        XCTAssertFalse(reducer.state.isLocked)
        XCTAssertEqual(reducer.state.accumulatedActiveSeconds, 0)

        // No time accrues before the new intent is acknowledged.
        _ = reducer.send(.tick(monotonic: 1_000, isForegroundAwake: true))
        _ = reducer.send(.tick(monotonic: 1_100, isForegroundAwake: true))
        XCTAssertEqual(reducer.state.accumulatedActiveSeconds, 0)
        XCTAssertEqual(
            reducer.send(.intentPersisted(sessionA)),
            [.rejected(.sessionMismatch)]
        )

        XCTAssertEqual(
            reducer.send(.intentPersisted(sessionB)),
            [.applyPresentation(testPresentation)]
        )
        XCTAssertEqual(reducer.state.phase, .active)
        XCTAssertTrue(reducer.state.isLocked)
        XCTAssertEqual(reducer.state.goal, .time(minutes: 10))
    }

    func testAddTenMinutesIsRejectedForWordSessions() {
        var reducer = locked(.words(target: 50), baselineWordCount: 0)
        _ = reducer.send(.updateWordProgress(currentWordCount: 50, eligibleNewWordCount: 50))
        XCTAssertEqual(reducer.state.phase, .completed)
        XCTAssertEqual(
            reducer.send(.completeAfterGoal(.addTenMinutes, newSessionID: sessionB)),
            [.rejected(.addTimeRequiresTimerGoal)]
        )
    }

    func testPostCompletionActionsAreRejectedBeforeCompletion() {
        var reducer = locked(.time(minutes: 25))
        XCTAssertEqual(
            reducer.send(.completeAfterGoal(.continueWriting, newSessionID: sessionB)),
            [.rejected(.actionNotPermitted(.active))]
        )
    }

    // MARK: - Recovery

    func testStaleLockRecoveryEndsTheSessionAndNeverRelocks() {
        var reducer = locked(.time(minutes: 25))
        _ = reducer.send(.tick(monotonic: 0, isForegroundAwake: true))
        _ = reducer.send(.tick(monotonic: 5, isForegroundAwake: true))

        let effects = reducer.send(.recoverStaleSession)
        XCTAssertEqual(reducer.state.phase, .ended)
        XCTAssertTrue(reducer.state.endedEarly)
        XCTAssertFalse(reducer.state.isLocked)
        XCTAssertTrue(effects.contains(.restorePresentation(testPresentation)))
        XCTAssertTrue(effects.contains(.finalizeRecovery(.staleLockRecovered)))

        XCTAssertEqual(reducer.send(.recoverStaleSession), [])
        XCTAssertEqual(reducer.state.phase, .ended)
    }

    func testRecoveringAnIdleReducerDoesNothing() {
        var reducer = FocusReducer()
        XCTAssertEqual(reducer.send(.recoverStaleSession), [])
        XCTAssertEqual(reducer.state.phase, .idle)
    }

    func testInterruptionDuringEmergencyExitReleasesProtectionAndNeverRelocks() {
        var reducer = locked(.time(minutes: 25))
        _ = reducer.send(.requestEnd)
        let effects = reducer.send(.interruption(.screenLock))
        XCTAssertEqual(reducer.state.phase, .ended)
        XCTAssertFalse(reducer.state.allowsRelock)
        XCTAssertTrue(effects.contains(.restorePresentation(testPresentation)))
        XCTAssertTrue(effects.contains(.releaseShields))
        XCTAssertTrue(effects.contains(.finalizeRecovery(.emergencyExit)))
        XCTAssertEqual(reducer.send(.tick(monotonic: 1000, isForegroundAwake: true)), [])
    }

    func testInvalidClockBreaksContinuityAndFreshGoalRejectsReusedIdentity() {
        var reducer = locked(.time(minutes: 1))
        _ = reducer.send(.tick(monotonic: 0, isForegroundAwake: true))
        _ = reducer.send(.tick(monotonic: .nan, isForegroundAwake: true))
        _ = reducer.send(.tick(monotonic: 100, isForegroundAwake: true))
        XCTAssertEqual(reducer.state.accumulatedActiveSeconds, 0)
        _ = reducer.send(.tick(monotonic: 160, isForegroundAwake: true))
        XCTAssertEqual(reducer.state.phase, .completed)
        XCTAssertEqual(reducer.send(.completeAfterGoal(.addTenMinutes, newSessionID: sessionA)), [.rejected(.sessionMismatch)])
        XCTAssertEqual(reducer.state.phase, .completed)
    }
}
