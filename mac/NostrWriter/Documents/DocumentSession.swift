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
        let receipt = try command.applying(to: snapshot, completeness: completeness)
        snapshot = receipt.post
        lastMutation = receipt
    }

    func finalizeObservation(reason: ObservationBoundary) async throws -> CapturedRecordHandle? {
        if recordingState == .off { return nil }
        throw ContractError.unsupported("Native observation finalization is not available until Stage 03.")
    }

    func acceptsCompletion(for source: SourceSnapshot) -> Bool { source == snapshot }
}
