import Foundation
import WriterFoundation

/// Main-actor revision owner. Native capture/storage are attached in their stages;
/// a scratch mutation is never labelled independent HWP observation.
@MainActor
final class DocumentSession: DocumentEditing {
    private(set) var snapshot: SourceSnapshot
    private(set) var lastMutation: MutationReceipt?
    var recordingState: RecordingState = .off
    init(snapshot: SourceSnapshot) { self.snapshot = snapshot }

    func apply(_ command: EditCommand) throws {
        let completeness: CaptureCompleteness = recordingState == .off ? .recordingOff : .descriptiveOnly
        try apply(command, completeness: completeness)
    }

    /// Applies one command with an explicitly observed completeness. The
    /// caller declares what it actually saw; the session never re-derives a
    /// cause from the resulting text.
    @discardableResult
    func apply(_ command: EditCommand, completeness: CaptureCompleteness) throws -> MutationReceipt {
        let receipt = try command.applying(to: snapshot, completeness: completeness)
        snapshot = receipt.post
        lastMutation = receipt
        return receipt
    }

    /// Closes the descriptive lifecycle at a real boundary. Recording off
    /// yields no handle; recording on yields a handle bound to the exact
    /// current source. The handle is a local descriptive record, never an HWP
    /// approval.
    func finalizeObservation(reason: ObservationBoundary) async throws -> CapturedRecordHandle? {
        if recordingState == .off { return nil }
        switch recordingState {
        case .off:
            return nil
        case .paused, .pausedLimit, .gap:
            // A boundary during a gap is honest: no continuous handle exists.
            return nil
        case .observing:
            return CapturedRecordHandle(id: UUID(), source: snapshot)
        }
    }

    func acceptsCompletion(for source: SourceSnapshot) -> Bool { source == snapshot }
}
