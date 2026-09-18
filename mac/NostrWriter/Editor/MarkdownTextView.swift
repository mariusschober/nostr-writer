import AppKit
import WriterFoundation

/// The single live TextKit 2 editor view.
///
/// It exists to observe *actual native delivery* — typed input, input-method
/// composition and commit, pasteboard operations, drag/drop and native
/// assistance — without guessing from the resulting text. It never owns
/// revisions, never records history and never invents physical-typing
/// certainty: it only reports the cause of the next mutation to the gateway,
/// which commits exactly one receipt.
@MainActor
final class MarkdownTextView: NSTextView {

    /// The observed cause of the next text mutation.
    enum Delivery: Equatable {
        case typed
        case imeComposition
        case imeCommit
        case spellingCorrection
        case pasteInternalCopy
        case pasteInternalMove
        case pasteExternal
        case cut
        case drop
        /// A mutation whose cause the app declares explicitly (formatting,
        /// find/replace, image insertion, dictation).
        case programmatic
        /// No observed cause: the gateway treats this as an honest gap.
        case unknown
    }

    /// Cause of the next programmatic mutation, when one is declared.
    var programmaticOrigin: EditOrigin?
    /// Returns true when Escape was handled (for example leaving focus mode).
    var onEscape: (() -> Bool)?
    private(set) var pendingDelivery: Delivery = .unknown
    /// Exact bytes captured by an in-app copy/cut, used to prove an internal
    /// paste carries a real source payload rather than merely identical text.
    private var internalClipboard: AncestryToken?
    /// The id of the internal ancestry token validated for the most recent
    /// paste. Nil when the paste did not carry a real in-app source operation.
    private(set) var lastAncestryID: UUID?
    /// Latches an accepted marked-text composition so the *commit* that follows
    /// is classified as an IME commit even if AppKit clears the marked range
    /// before delivering the final insertion.
    private var heldComposition = false

    /// Private pasteboard type marking app-internal lineage; never leaves the app.
    static let ancestryPasteboardType = NSPasteboard.PasteboardType("com.mariusschober.nostrwriter.ancestry")

    /// Consumes and clears the pending cause, so it cannot be reused twice.
    func consumeDelivery() -> Delivery {
        defer { pendingDelivery = .unknown; programmaticOrigin = nil; lastAncestryID = nil }
        return pendingDelivery
    }

    /// Declares the cause of a programmatic mutation (formatting, find/replace…).
    func setProgrammaticDelivery(_ origin: EditOrigin) {
        pendingDelivery = .programmatic
        programmaticOrigin = origin
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        if hasMarkedText() || heldComposition {
            pendingDelivery = .imeCommit
        } else if pendingDelivery == .unknown {
            // A pure native insertion at the caret is direct native input. An
            // existing programmatic cause (formatting, dictation) is preserved.
            pendingDelivery = .typed
        }
        heldComposition = false
        super.insertText(string, replacementRange: replacementRange)
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        heldComposition = true
        pendingDelivery = .imeComposition
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
    }

    override func unmarkText() {
        heldComposition = false
        pendingDelivery = .imeCommit
        super.unmarkText()
    }

    override func cancelOperation(_ sender: Any?) {
        if onEscape?() == true { return }
        super.cancelOperation(sender)
    }

    /// Accepting a spelling correction is known assistance, not fresh typing.
    override func changeSpelling(_ sender: Any?) {
        pendingDelivery = .programmatic
        programmaticOrigin = .knownAssistance(.spelling)
        super.changeSpelling(sender)
    }

    /// Replace/Replace All from the native find bar are declared as
    /// find/replace, never as direct typing.
    override func performFindPanelAction(_ sender: Any?) {
        if let item = sender as? NSValidatedUserInterfaceItem,
           let action = NSTextFinder.Action(rawValue: item.tag),
           action == .replace || action == .replaceAll {
            pendingDelivery = .programmatic
            programmaticOrigin = .findReplace
        }
        super.performFindPanelAction(sender)
    }

    override func copy(_ sender: Any?) {
        captureInternalPayload(kind: .internalCopy)
        super.copy(sender)
    }

    override func cut(_ sender: Any?) {
        captureInternalPayload(kind: .internalMove)
        pendingDelivery = .cut
        super.cut(sender)
    }

    override func paste(_ sender: Any?) {
        if let token = internalClipboard,
           let pasted = NSPasteboard.general.string(forType: .string),
           token.matches(payload: Data(pasted.utf8)) {
            pendingDelivery = token.originCategory == .internalMove ? .pasteInternalMove : .pasteInternalCopy
            // Carry the real copy/cut operation identity forward instead of
            // inventing a fresh one per delivery.
            lastAncestryID = token.sourceRecordID
        } else {
            pendingDelivery = .pasteExternal
            lastAncestryID = nil
        }
        internalClipboard = nil
        super.paste(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        // A drop is an observed cause. The private lineage marker only decides
        // whether it also carries real in-document ancestry, never the text.
        pendingDelivery = .drop
        return super.performDragOperation(sender)
    }

    private func captureInternalPayload(kind: EditOriginCategory) {
        let range = selectedRange()
        guard range.length > 0, let swiftRange = Range(range, in: string) else { return }
        let payload = Data(string[swiftRange].utf8)
        let token = AncestryToken(originCategory: kind, sourceRecordID: UUID(),
                                  payloadDigest: SourceSnapshot.sha256(payload))
        internalClipboard = token
        // Advertise the private marker so an in-app drag can be recognised.
        let pasteboard = NSPasteboard.general
        pasteboard.setData(Data(token.id.uuidString.utf8), forType: Self.ancestryPasteboardType)
    }
}
