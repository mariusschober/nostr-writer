import AppKit
import WriterFoundation

/// Stage 07 seam: a narrow, local policy for external (non-native-typing)
/// insertion. Stage 03 only *exposes* the seam and proves it can refuse an
/// external paste without enabling global input interception, Accessibility
/// permission or locked-session UI; the locked session itself is Stage 07.
struct WriteInputPolicy: Equatable {
    /// Native typing, IME, undo and in-app commands are always allowed. Only
    /// externally-sourced insertion (paste, drop, Services, accessibility) is
    /// governed here.
    var allowsExternalInsertion = true

    /// Whether this observed delivery is external insertion.
    static func isExternalInsertion(_ delivery: MarkdownTextView.Delivery) -> Bool {
        switch delivery {
        case .pasteExternal, .drop: true
        case .typed, .imeComposition, .imeCommit, .spellingCorrection,
             .pasteInternalCopy, .pasteInternalMove, .cut, .programmatic, .unknown: false
        }
    }
}

/// The one revision/cause gateway for the live editor.
///
/// Every text mutation reaches the document through this object. It commits at
/// most one receipt for each real mutation, attaches the observed delivery cause
/// and records an honest capture gap — never a fabricated physical-typing claim —
/// when the cause or range cannot be established. It never replays a mutation
/// into the same text storage.
@MainActor
final class EditorMutationGateway {
    private unowned let document: WriterDocument
    private weak var editor: MarkdownTextView?
    private var pending: Pending?
    /// Cause of an observed change whose range could not be mapped to the
    /// document revision (for example an input-method commit, where the marked
    /// composition offsets are editor-local). The cause is still real even when
    /// only a coarse whole-document range can be recorded.
    private var unmappedOrigin: EditOrigin?
    /// Stage 07 input-policy seam. Defaults to the ordinary writing policy.
    var inputPolicy = WriteInputPolicy()
    /// Set when the policy refused an external insertion, so the UI can explain
    /// an honest gap instead of silently dropping the paste.
    private(set) var lastRefusedExternalInsertion = false

    /// Clears the refusal flag once the UI has explained it (or a policy is
    /// disengaged), so a stale refusal is never reported twice.
    func clearExternalInsertionRefusal() { lastRefusedExternalInsertion = false }

    /// Cause declared by an app command (`performProgrammatic`) that the text
    /// view does not itself know.
    private var declaredOrigin: EditOrigin?
    private var isReconciling = false

    private struct Pending {
        let revision: Revision
        let range: ByteRange
        let replacement: Data
        let origin: EditOrigin
    }

    init(document: WriterDocument) { self.document = document }

    func attach(_ editor: MarkdownTextView) { self.editor = editor }

    /// Runs `body` with an explicit, declared cause so programmatic edits keep
    /// their real origin (formatting, find/replace, dictation) rather than
    /// looking typed.
    func performProgrammatic(origin: EditOrigin, _ body: () -> Void) {
        declaredOrigin = origin
        editor?.setProgrammaticDelivery(origin)
        defer { declaredOrigin = nil }
        body()
    }

    /// Records the observed cause before a text change.
    @discardableResult
    func shouldChange(in range: NSRange, replacement: String?) -> Bool {
        guard !isReconciling else { return true }
        guard let snapshot = document.sessionSnapshot else { pending = nil; return true }
        // Read the declared programmatic cause before consuming the delivery,
        // which clears both fields.
        let declaredProgrammatic = editor?.programmaticOrigin
        let ancestryID = editor?.lastAncestryID
        let delivery = editor?.consumeDelivery() ?? .unknown
        // Stage 07 seam: refuse an external insertion only when a policy is
        // actually engaged. The ordinary writing policy allows it, so normal
        // pasting and dropping are unchanged.
        if !inputPolicy.allowsExternalInsertion, WriteInputPolicy.isExternalInsertion(delivery) {
            lastRefusedExternalInsertion = true
            pending = nil
            return false
        }
        let origin = origin(for: delivery, declaredProgrammatic: declaredProgrammatic, ancestryID: ancestryID)
        guard let replacement else {
            // A represented-object replacement (e.g. a deleted attachment) has
            // no text payload; treat it as an observed deletion.
            pending = nil
            return true
        }
        guard let nativeRange = try? NativeRange(location: range.location, length: range.length),
              range.location + range.length <= snapshot.utf16Count,
              let byteRange = try? snapshot.byteRange(for: nativeRange) else {
            // The range is editor-local (input-method composition) or otherwise
            // not addressable in this revision. Keep the observed cause so the
            // resulting change is not mislabelled an unexplained gap.
            unmappedOrigin = origin
            pending = nil
            return true
        }
        pending = Pending(revision: snapshot.revision, range: byteRange,
                          replacement: Data(replacement.utf8), origin: origin)
        return true
    }

    /// Commits exactly one receipt for the mutation that just happened.
    func didChange() {
        guard !isReconciling, let editor, let snapshot = document.sessionSnapshot else { return }
        // Intermediate input-method composition is not a committed edit.
        if editor.hasMarkedText() { return }
        let live = Data(editor.string.utf8)
        if live == snapshot.utf8 { pending = nil; return }

        // A predicted range is only usable when applying it reproduces the live
        // editor byte-for-byte. During composition inside existing text a
        // numerically valid range can address different content, so an
        // unverified prediction is discarded rather than published as a
        // revision. The observed cause is still preserved for the fallback.
        if let pending, pending.revision == snapshot.revision,
           predictedPost(pending, snapshot: snapshot) == live {
            self.pending = nil
            self.unmappedOrigin = nil
            let command = EditCommand(id: UUID(), expectedRevision: pending.revision, range: pending.range,
                                      replacement: pending.replacement, origin: pending.origin, undoGroup: UUID())
            do {
                try document.applyObserved(command, capture: capture(for: pending.origin))
                return
            } catch {
                // A stale range is real evidence of concurrent change; fall through.
            }
        }
        self.pending = nil
        let fallback = unmappedOrigin ?? declaredOrigin
        unmappedOrigin = nil
        reconcileWithWholeDocument(live: live, snapshot: snapshot, cause: fallback)
    }

    /// The exact bytes a pending prediction would produce against the base
    /// revision, or nil when its range is not addressable there.
    private func predictedPost(_ pending: Pending, snapshot: SourceSnapshot) -> Data? {
        let bytes = snapshot.utf8
        guard pending.range.lowerBound >= 0,
              pending.range.upperBound <= bytes.count,
              pending.range.lowerBound <= pending.range.upperBound,
              (try? snapshot.nativeRange(for: pending.range)) != nil else { return nil }
        var next = bytes
        next.replaceSubrange(pending.range.lowerBound..<pending.range.upperBound, with: pending.replacement)
        return next
    }

    /// Reconciles the document with the live editor after an out-of-band change
    /// (native undo/redo without a delegate callback, external reload, recovery).
    func commitWholeDocument(origin: EditOrigin) {
        guard let editor, let snapshot = document.sessionSnapshot else { return }
        pending = nil
        unmappedOrigin = nil
        reconcileWithWholeDocument(live: Data(editor.string.utf8), snapshot: snapshot, cause: origin)
    }

    private func reconcileWithWholeDocument(live: Data, snapshot: SourceSnapshot, cause: EditOrigin?) {
        guard live != snapshot.utf8 else { return }
        guard let range = try? ByteRange(lowerBound: 0, upperBound: snapshot.byteCount) else { return }
        let origin = cause ?? .unknown
        do {
            let command = EditCommand(id: UUID(), expectedRevision: snapshot.revision, range: range,
                                      replacement: live, origin: origin, undoGroup: UUID())
            try document.applyObserved(command, capture: capture(for: origin))
        } catch {
            // The live editor no longer matches the session; reload the exact
            // source rather than persist an unverified buffer.
            isReconciling = true
            editor?.string = String(decoding: snapshot.utf8, as: UTF8.self)
            isReconciling = false
            document.refreshWindows()
        }
    }

    /// An explained cause is descriptive; anything else is an honest gap.
    private func capture(for origin: EditOrigin) -> CaptureCompleteness {
        origin.category.isExplained ? .descriptiveOnly : .gap(CaptureGapReason.opaqueInput.rawValue)
    }

    /// Maps an observed delivery to its honest cause. Internal so the
    /// classification table can be verified deterministically without driving
    /// every native input path through a real window.
    func origin(for delivery: MarkdownTextView.Delivery, declaredProgrammatic: EditOrigin?,
                ancestryID: UUID? = nil) -> EditOrigin {
        // Native undo/redo are observed from the actual undo manager state, so
        // a real undo is never recorded as an opaque mutation.
        if let undo = document.undoManager {
            if undo.isUndoing { return .undo(UUID()) }
            if undo.isRedoing { return .redo(UUID()) }
        }
        switch delivery {
        case .typed: return .directNativeInput
        case .imeComposition: return .nativeIMEUpdate
        case .imeCommit: return .nativeIMECommit
        case .spellingCorrection: return .knownAssistance(.spelling)
        case .pasteExternal: return .pasteExternal
        // Ancestry is only claimed with the token captured by the real in-app
        // copy/cut. Without it the change is an honest gap, never invented
        // lineage.
        case .pasteInternalCopy: return ancestryID.map { .internalCopy($0) } ?? .unknown
        case .pasteInternalMove: return ancestryID.map { .internalMove($0) } ?? .unknown
        case .cut: return .cut
        case .drop: return .drop
        case .programmatic: return declaredProgrammatic ?? declaredOrigin ?? .unknown
        case .unknown: return declaredOrigin ?? .unknown
        }
    }
}
