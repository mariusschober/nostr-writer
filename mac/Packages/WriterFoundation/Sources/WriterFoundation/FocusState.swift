import Foundation

// Pure voluntary-focus reducer for FOCUS.md. No AppKit or sound engine: adapters
// own presentation and apply the returned effects. Word counts arrive from the
// editor's authoritative lineage input, so nothing here tokenizes text or
// invents ancestry. A focus session is a motivation measure only, never HWP.
//
// Safety invariants encoded here:
//   * Normal Focus is presentation only: no lock, no restrictions, immediate exit.
//   * A session is not active until its persisted intent is acknowledged, and an
//     interruption can never bypass that acknowledgement.
//   * Interruption restores the full prior presentation state, so nothing that
//     restricts process switching is left active.
//   * Cancelling an exit returns to the phase the countdown came from, so a
//     paused session is never silently re-protected.
//   * Only uninterrupted foreground time is credited, and only while locked.

public struct FocusSessionID: Hashable, Sendable {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
    public init() { self.rawValue = UUID() }
}

/// Normal Focus is presentation only; a Locked Session adds a goal, command
/// restrictions and the deliberate exit countdown.
public enum FocusMode: String, Hashable, Sendable {
    case normal, locked
}

public enum FocusGoal: Hashable, Sendable {
    case time(minutes: Int)
    case words(target: Int)

    public static let timeRange = 1...240
    public static let wordRange = 50...20_000

    public var isTimer: Bool {
        if case .time = self { return true }
        return false
    }
}

public enum ClipboardPolicy: String, Hashable, Sendable {
    case off, blockExternalInsertion, blockCopyCutAndPaste
}

public struct FocusRestrictions: Hashable, Sendable {
    public let clipboard: ClipboardPolicy
    public init(clipboard: ClipboardPolicy = .off) { self.clipboard = clipboard }
}

/// Opaque adapter-owned presentation state. `priorOptionsToken` is whatever the
/// adapter recorded as the prior options value, returned untouched on restore so
/// the app never overwrites options owned by something else.
public struct FocusPresentation: Hashable, Sendable {
    public let priorOptionsToken: String
    public let shieldsOtherDisplays: Bool
    public let soundEnabled: Bool

    public init(priorOptionsToken: String,
                shieldsOtherDisplays: Bool = false,
                soundEnabled: Bool = false) {
        self.priorOptionsToken = priorOptionsToken
        self.shieldsOtherDisplays = shieldsOtherDisplays
        self.soundEnabled = soundEnabled
    }
}

public struct FocusIntent: Hashable, Sendable {
    public let sessionID: FocusSessionID
    public let documentID: DocumentID
    public let mode: FocusMode
    public let goal: FocusGoal?
    public let restrictions: FocusRestrictions
    /// Display only; goal arithmetic uses monotonic time.
    public let recordedAtEpochSeconds: Double

    public init(sessionID: FocusSessionID, documentID: DocumentID, mode: FocusMode,
                goal: FocusGoal?, restrictions: FocusRestrictions,
                recordedAtEpochSeconds: Double) {
        self.sessionID = sessionID
        self.documentID = documentID
        self.mode = mode
        self.goal = goal
        self.restrictions = restrictions
        self.recordedAtEpochSeconds = recordedAtEpochSeconds
    }
}

public struct FocusPreflight: Hashable, Sendable {
    public let hasUnresolvedFileConflict: Bool
    public let hasUnsavedDiskFailure: Bool

    public init(hasUnresolvedFileConflict: Bool = false,
                hasUnsavedDiskFailure: Bool = false) {
        self.hasUnresolvedFileConflict = hasUnresolvedFileConflict
        self.hasUnsavedDiskFailure = hasUnsavedDiskFailure
    }
}

public enum FocusPhase: String, Hashable, Sendable, CaseIterable {
    case idle, preparing, active, interrupted, exiting, completed, ended

    /// `completed` deliberately does not own presentation: the goal is met.
    public var isRunning: Bool {
        switch self {
        case .preparing, .active, .interrupted, .exiting: return true
        case .idle, .completed, .ended: return false
        }
    }
}

public enum FocusInterruptionReason: String, Hashable, Sendable {
    case sleep, screenLock, appDeactivation, protectedEnvironment
    case clockMovedBackward, presentationOwnershipLost
}

public enum FocusRecoveryReason: String, Hashable, Sendable {
    case normalEnd, emergencyExit, goalReached, staleLockRecovered
}

public enum FocusError: Error, Equatable, Sendable {
    case invalidTimeGoal(Int)
    case invalidWordGoal(Int)
    case missingWordBaseline
    case invalidBaseline(Int)
    case invalidWordInput(currentWordCount: Int, eligibleNewWordCount: Int)
    /// Carries no value: a NaN payload would make `Equatable` unsound.
    case invalidClockReading
    case goalNotAllowedInNormalMode
    case missingLockedGoal
    case sessionAlreadyActive(FocusPhase)
    case unresolvedFileConflict
    case unsavedDiskFailure
    case sessionMismatch
    case noSession
    case interruptionNotPermitted(FocusPhase)
    case actionNotPermitted(FocusPhase)
    case addTimeRequiresTimerGoal
}

public enum FocusCommand: String, Hashable, Sendable, CaseIterable {
    case typing, undo, scrolling, find, textAccessibility, localSave, emergencyExit
    case close, newDocument, openDocument, publish, quickPost, settingsChange
    case externalInsertion, dictation, completion, crossDocumentImport
    case copy, cut, exportShare
}

public enum PostCompletionAction: Hashable, Sendable {
    case continueWriting, endSession, addTenMinutes
}

public enum FocusEffect: Equatable, Sendable {
    /// Persist and acknowledge before the session becomes active.
    case persistSessionIntent(FocusIntent)
    case applyPresentation(FocusPresentation)
    case releaseShields
    case restorePresentation(FocusPresentation)
    case startSound
    case stopSound
    case beginExitCountdown(seconds: Double)
    case finalizeRecovery(FocusRecoveryReason)
    case rejected(FocusError)
}

public struct FocusState: Hashable, Sendable {
    public var mode: FocusMode = .normal
    public var phase: FocusPhase = .idle
    public var sessionID: FocusSessionID?
    public var intentPersisted = false
    public var documentID: DocumentID?
    public var goal: FocusGoal?
    public var restrictions = FocusRestrictions()
    public var presentation: FocusPresentation?
    public var baselineWordCount: Int?
    public var wordProgress = 0
    public var accumulatedActiveSeconds: Double = 0
    public var lastTickMonotonic: Double?
    public var wasForegroundAwake = false
    public var interruption: FocusInterruptionReason?
    public var phaseBeforeInterruption: FocusPhase?
    public var exitCountdownRemaining: Double?
    public var phaseBeforeExit: FocusPhase?
    public var recordedAtEpochSeconds: Double = 0
    public var endedEarly = false
    /// Set by Continue Writing so a reached goal can never re-lock.
    public var isUnlockedContinuation = false

    public init() {}

    /// A lock exists only after the adapter has persisted and acknowledged the
    /// intent, so a preparing session holds no restrictions.
    public var isLocked: Bool {
        mode == .locked && goal != nil && intentPersisted
            && !isUnlockedContinuation && phase.isRunning
    }

    public var isGoalMet: Bool {
        guard let goal else { return false }
        switch goal {
        case .time(let minutes): return FocusGoal.timeRange.contains(minutes) && accumulatedActiveSeconds >= Double(minutes) * 60
        case .words(let target): return wordProgress >= target
        }
    }

    public var isTimerGoal: Bool { goal?.isTimer ?? false }

    /// Completion is only possible while genuinely locked and active, so a
    /// finished session never re-completes and an unlocked continuation never
    /// announces a goal again.
    public var shouldComplete: Bool { phase == .active && isLocked && isGoalMet }

    public var allowsRelock: Bool { phase == .active && isLocked && !isGoalMet }

    /// Save, undo, navigation and the emergency exit are never denied.
    public func allows(_ command: FocusCommand) -> Bool {
        switch command {
        case .typing, .undo, .scrolling, .find, .textAccessibility,
             .localSave, .emergencyExit:
            return true
        default:
            break
        }
        guard isLocked else { return true }

        switch command {
        case .close, .newDocument, .openDocument, .publish, .quickPost, .settingsChange:
            return false
        case .externalInsertion, .dictation, .completion, .crossDocumentImport:
            if case .words = goal { return false }
            return restrictions.clipboard == .off
        case .copy, .cut, .exportShare:
            return restrictions.clipboard != .blockCopyCutAndPaste
        default:
            return true
        }
    }
}

public enum FocusEvent: Sendable {
    // Session identifiers are supplied by the caller so production can use
    // system randomness and tests can inject deterministic values.
    case begin(sessionID: FocusSessionID, mode: FocusMode, documentID: DocumentID,
               goal: FocusGoal?, restrictions: FocusRestrictions,
               baselineWordCount: Int?, preflight: FocusPreflight,
               presentation: FocusPresentation, recordedAtEpochSeconds: Double)
    case intentPersisted(FocusSessionID)
    case tick(monotonic: Double, isForegroundAwake: Bool)
    case interruption(FocusInterruptionReason)
    case resume
    case updateWordProgress(currentWordCount: Int, eligibleNewWordCount: Int)
    case requestEnd
    case cancelPendingExit
    case completeAfterGoal(PostCompletionAction, newSessionID: FocusSessionID)
    case recoverStaleSession
}

public struct FocusReducer: Sendable {

    /// The deliberate emergency countdown, keyboard-accessible with Cancel.
    public static let emergencyExitSeconds: Double = 10
    public static let addedMinutes = 10

    public private(set) var state: FocusState

    public init(state: FocusState = FocusState()) { self.state = state }

    @discardableResult
    public mutating func send(_ event: FocusEvent) -> [FocusEffect] {
        switch event {
        case .begin(let sessionID, let mode, let documentID, let goal, let restrictions,
                    let baseline, let preflight, let presentation, let epoch):
            return begin(sessionID: sessionID, mode: mode, documentID: documentID, goal: goal,
                         restrictions: restrictions, baselineWordCount: baseline,
                         preflight: preflight, presentation: presentation,
                         recordedAtEpochSeconds: epoch)
        case .intentPersisted(let sessionID):
            return intentPersisted(sessionID)
        case .tick(let monotonic, let isForegroundAwake):
            return tick(monotonic: monotonic, isForegroundAwake: isForegroundAwake)
        case .interruption(let reason):
            return interruption(reason)
        case .resume:
            return resume()
        case .updateWordProgress(let current, let eligible):
            return updateWordProgress(currentWordCount: current, eligibleNewWordCount: eligible)
        case .requestEnd:
            return requestEnd()
        case .cancelPendingExit:
            return cancelPendingExit()
        case .completeAfterGoal(let action, let newSessionID):
            return completeAfterGoal(action, newSessionID: newSessionID)
        case .recoverStaleSession:
            return recoverStaleSession()
        }
    }

    // MARK: - Transitions

    private mutating func begin(sessionID: FocusSessionID, mode: FocusMode,
                                documentID: DocumentID, goal: FocusGoal?,
                                restrictions: FocusRestrictions, baselineWordCount: Int?,
                                preflight: FocusPreflight, presentation: FocusPresentation,
                                recordedAtEpochSeconds: Double) -> [FocusEffect] {
        guard !state.phase.isRunning else {
            return [.rejected(.sessionAlreadyActive(state.phase))]
        }
        switch mode {
        case .normal:
            // Presentation only: no goal, and restrictions are never enforced.
            guard goal == nil else { return [.rejected(.goalNotAllowedInNormalMode)] }
        case .locked:
            guard let goal else { return [.rejected(.missingLockedGoal)] }
            switch goal {
            case .time(let minutes) where !FocusGoal.timeRange.contains(minutes):
                return [.rejected(.invalidTimeGoal(minutes))]
            case .words(let target) where !FocusGoal.wordRange.contains(target):
                return [.rejected(.invalidWordGoal(target))]
            default:
                break
            }
            if preflight.hasUnresolvedFileConflict { return [.rejected(.unresolvedFileConflict)] }
            if preflight.hasUnsavedDiskFailure { return [.rejected(.unsavedDiskFailure)] }
            if case .words = goal {
                guard let baselineWordCount else { return [.rejected(.missingWordBaseline)] }
                guard baselineWordCount >= 0 else {
                    return [.rejected(.invalidBaseline(baselineWordCount))]
                }
            }
        }

        state = FocusState()
        state.sessionID = sessionID
        state.mode = mode
        state.phase = .preparing
        state.documentID = documentID
        state.goal = goal
        state.restrictions = restrictions
        state.presentation = presentation
        state.baselineWordCount = baselineWordCount
        state.recordedAtEpochSeconds = recordedAtEpochSeconds

        guard let intent = intentForCurrentState() else { return [.rejected(.noSession)] }
        return [.persistSessionIntent(intent)]
    }

    private mutating func intentPersisted(_ sessionID: FocusSessionID) -> [FocusEffect] {
        guard state.phase == .preparing, state.sessionID == sessionID else {
            return [.rejected(.sessionMismatch)]
        }
        state.intentPersisted = true
        state.phase = .active
        state.lastTickMonotonic = nil
        state.wasForegroundAwake = false
        guard let presentation = state.presentation else { return [] }
        var effects: [FocusEffect] = [.applyPresentation(presentation)]
        if presentation.soundEnabled { effects.append(.startSound) }
        return effects
    }

    private mutating func tick(monotonic: Double, isForegroundAwake: Bool) -> [FocusEffect] {
        // Completed or ended sessions can never be re-locked by later ticks.
        guard state.phase.isRunning else { return [] }
        guard monotonic.isFinite else {
            state.lastTickMonotonic = nil
            state.wasForegroundAwake = false
            return [.rejected(.invalidClockReading)]
        }
        guard let last = state.lastTickMonotonic else {
            state.lastTickMonotonic = monotonic
            state.wasForegroundAwake = isForegroundAwake
            return []
        }
        let delta = monotonic - last
        if !delta.isFinite || delta < 0 {
            return interruption(.clockMovedBackward)
        }
        let previouslyAwake = state.wasForegroundAwake
        state.lastTickMonotonic = monotonic
        state.wasForegroundAwake = isForegroundAwake
        // Only continuous foreground time counts: a gap between a suspended tick
        // and the next awake tick is never credited.
        guard previouslyAwake, isForegroundAwake else { return [] }

        switch state.phase {
        case .active:
            // Only a goal in force accrues progress: an unlocked continuation
            // (and a goal-less Normal session) tracks nothing.
            guard state.isLocked else { return [] }
            state.accumulatedActiveSeconds += delta
            return state.shouldComplete ? completeByReachingGoal() : []
        case .exiting:
            let remaining = max(0, (state.exitCountdownRemaining ?? 0) - delta)
            state.exitCountdownRemaining = remaining
            return remaining > 0 ? [] : finish(endedEarly: true, reason: .emergencyExit)
        default:
            return []
        }
    }

    private mutating func interruption(_ reason: FocusInterruptionReason) -> [FocusEffect] {
        // An interruption during Emergency Exit must release protection too. End
        // early safely rather than cancel the escape or leave stale restrictions.
        if state.phase == .exiting {
            return finish(endedEarly: true, reason: .emergencyExit) + [.releaseShields]
        }
        guard state.phase == .active || state.phase == .preparing else {
            return [.rejected(.interruptionNotPermitted(state.phase))]
        }
        state.phaseBeforeInterruption = state.phase
        state.interruption = reason
        state.phase = .interrupted
        state.lastTickMonotonic = nil
        state.wasForegroundAwake = false
        state.exitCountdownRemaining = nil
        // Full restore: a paused session must not leave process-switch or other
        // presentation restrictions active.
        var effects: [FocusEffect] = []
        if let presentation = state.presentation {
            effects.append(.restorePresentation(presentation))
        }
        effects.append(.releaseShields)
        effects.append(.stopSound)
        return effects
    }

    private mutating func resume() -> [FocusEffect] {
        guard state.phase == .interrupted else {
            return [.rejected(.interruptionNotPermitted(state.phase))]
        }
        // An interrupted session that never acknowledged its intent returns to
        // preparing; it can never become active through the interruption.
        let interruptedFromActive = state.phaseBeforeInterruption == .active
        state.phaseBeforeInterruption = nil
        state.interruption = nil
        state.lastTickMonotonic = nil
        state.wasForegroundAwake = false
        state.phase = (interruptedFromActive && state.intentPersisted) ? .active : .preparing
        if state.shouldComplete { return completeByReachingGoal() }
        guard state.phase == .active, let presentation = state.presentation else { return [] }
        return [.applyPresentation(presentation)]
    }

    private mutating func updateWordProgress(currentWordCount: Int,
                                             eligibleNewWordCount: Int) -> [FocusEffect] {
        guard currentWordCount >= 0, eligibleNewWordCount >= 0 else {
            return [.rejected(.invalidWordInput(currentWordCount: currentWordCount,
                                                eligibleNewWordCount: eligibleNewWordCount))]
        }
        guard state.isLocked, let goal = state.goal,
              case .words(let target) = goal else {
            return []
        }
        let baseline = state.baselineWordCount ?? 0
        let (net, overflow) = currentWordCount.subtractingReportingOverflow(baseline)
        guard !overflow else {
            return [.rejected(.invalidWordInput(currentWordCount: currentWordCount,
                                                eligibleNewWordCount: eligibleNewWordCount))]
        }
        state.wordProgress = min(max(0, net), eligibleNewWordCount)
        // A paused session shows progress but cannot complete.
        guard state.phase == .active, state.wordProgress >= target else { return [] }
        return completeByReachingGoal()
    }

    private mutating func requestEnd() -> [FocusEffect] {
        switch state.phase {
        case .idle, .ended:
            return [.rejected(.noSession)]
        case .exiting:
            return []
        case .completed:
            return finish(endedEarly: false, reason: .normalEnd)
        case .preparing:
            // No lock has been acquired yet, so leaving is immediate.
            return finish(endedEarly: false, reason: .normalEnd)
        default:
            break
        }
        // Unlocked exits are immediate; only a genuine lock takes the countdown.
        guard state.isLocked else { return finish(endedEarly: false, reason: .normalEnd) }
        state.phaseBeforeExit = state.phase
        state.phase = .exiting
        state.exitCountdownRemaining = Self.emergencyExitSeconds
        state.lastTickMonotonic = nil
        state.wasForegroundAwake = false
        return [.beginExitCountdown(seconds: Self.emergencyExitSeconds)]
    }

    private mutating func cancelPendingExit() -> [FocusEffect] {
        guard state.phase == .exiting else {
            return [.rejected(.actionNotPermitted(state.phase))]
        }
        let origin = state.phaseBeforeExit ?? .active
        state.phaseBeforeExit = nil
        state.exitCountdownRemaining = nil
        state.lastTickMonotonic = nil
        state.wasForegroundAwake = false
        // Return to the phase the countdown came from: cancelling an exit from a
        // paused session must not silently re-apply protection.
        state.phase = (origin == .active && state.intentPersisted) ? .active : origin
        guard state.phase == .active, let presentation = state.presentation else { return [] }
        return [.applyPresentation(presentation)]
    }

    private mutating func completeAfterGoal(_ action: PostCompletionAction,
                                            newSessionID: FocusSessionID) -> [FocusEffect] {
        guard state.phase == .completed else {
            return [.rejected(.actionNotPermitted(state.phase))]
        }
        switch action {
        case .continueWriting:
            state.phase = .active
            state.isUnlockedContinuation = true
            state.lastTickMonotonic = nil
            state.wasForegroundAwake = false
            return []
        case .endSession:
            return finish(endedEarly: false, reason: .normalEnd)
        case .addTenMinutes:
            guard state.isTimerGoal else { return [.rejected(.addTimeRequiresTimerGoal)] }
            guard state.documentID != nil else { return [.rejected(.noSession)] }
            guard newSessionID != state.sessionID else { return [.rejected(.sessionMismatch)] }
            // A fresh explicit goal: a new session that must persist and
            // acknowledge its own intent before it becomes active again.
            state.sessionID = newSessionID
            state.goal = .time(minutes: Self.addedMinutes)
            state.intentPersisted = false
            state.accumulatedActiveSeconds = 0
            state.wordProgress = 0
            state.lastTickMonotonic = nil
            state.wasForegroundAwake = false
            state.isUnlockedContinuation = false
            state.phase = .preparing
            guard let intent = intentForCurrentState() else { return [.rejected(.noSession)] }
            return [.persistSessionIntent(intent)]
        }
    }

    private mutating func recoverStaleSession() -> [FocusEffect] {
        guard state.phase.isRunning || state.phase == .completed else { return [] }
        // A lock left by a crash or force quit is ended, never resumed.
        state.phase = .ended
        state.endedEarly = true
        state.exitCountdownRemaining = nil
        state.lastTickMonotonic = nil
        state.wasForegroundAwake = false
        state.phaseBeforeInterruption = nil
        state.phaseBeforeExit = nil
        return restoreEffects() + [.finalizeRecovery(.staleLockRecovered)]
    }

    // MARK: - Helpers

    private mutating func completeByReachingGoal() -> [FocusEffect] {
        state.phase = .completed
        state.exitCountdownRemaining = nil
        state.lastTickMonotonic = nil
        state.wasForegroundAwake = false
        // The lock is released the moment the goal is met, so it cannot relock.
        return restoreEffects() + [.finalizeRecovery(.goalReached)]
    }

    private mutating func finish(endedEarly: Bool,
                                 reason: FocusRecoveryReason) -> [FocusEffect] {
        state.phase = .ended
        state.endedEarly = endedEarly
        state.exitCountdownRemaining = nil
        state.lastTickMonotonic = nil
        state.wasForegroundAwake = false
        state.phaseBeforeInterruption = nil
        state.phaseBeforeExit = nil
        return restoreEffects() + [.finalizeRecovery(reason)]
    }

    private func intentForCurrentState() -> FocusIntent? {
        guard let sessionID = state.sessionID, let documentID = state.documentID else { return nil }
        return FocusIntent(sessionID: sessionID,
                    documentID: documentID,
                    mode: state.mode,
                    goal: state.goal,
                    restrictions: state.restrictions,
                    recordedAtEpochSeconds: state.recordedAtEpochSeconds)
    }

    private func restoreEffects() -> [FocusEffect] {
        guard let presentation = state.presentation else { return [.stopSound] }
        return [.restorePresentation(presentation), .stopSound]
    }
}
