import AVFoundation
import AppKit
import Speech
import WriterFoundation

/// Pure, source-bound decision for one dictation update.
///
/// It never touches AppKit or audio, so the anchor/cancellation rules — the
/// part that must never overwrite later typing — are verified deterministically
/// without a microphone or a private transcript.
struct DictationAnchor: Equatable, Sendable {
    enum Decision: Equatable, Sendable {
        /// Insert the transcript at the anchor (nothing dictated yet).
        case insert(NSRange)
        /// Replace only this session's still-valid dictated range.
        case replace(NSRange)
        /// The anchor no longer holds what this session put there; cancel.
        case cancel
    }

    /// Exact UTF-16 location where dictation began.
    let location: Int
    /// Identity of the dictation session that owns this anchor.
    let session: UUID
    /// Text this session has actually committed at the anchor.
    private(set) var inserted = ""

    init(location: Int, session: UUID = UUID()) {
        self.location = location
        self.session = session
    }

    /// Applies the session's own replacement rule for the next transcript.
    ///
    /// If a later, unrelated edit replaced the dictated range, the live text no
    /// longer equals `inserted` and the session cancels rather than clobbering
    /// newer writing.
    mutating func plan(for transcript: String, liveText: NSString) -> Decision {
        let existing = NSRange(location: location, length: (inserted as NSString).length)
        guard NSMaxRange(existing) <= liveText.length else { return .cancel }
        if inserted.isEmpty {
            inserted = transcript
            return .insert(NSRange(location: location, length: 0))
        }
        guard liveText.substring(with: existing) == inserted else { return .cancel }
        inserted = transcript
        return .replace(existing)
    }
}

/// Monotonic session identity. A recognition callback carries the token of the
/// session that started it, and a token is never reused, so anything older than
/// `current` belongs to a session that has already stopped or finished.
struct DictationGeneration: Equatable, Sendable {
    private(set) var current = 0

    /// Opens a new session and returns its token.
    mutating func begin() -> Int {
        current += 1
        return current
    }

    /// Ends the open session, invalidating every token issued so far.
    mutating func invalidate() { current += 1 }

    func isCurrent(_ token: Int) -> Bool { token == current }
}

/// The two capability questions dictation asks, separated so the unsupported,
/// denied and granted paths can be decided without answering a privacy prompt
/// on the owner's behalf. The live gate is the only one that touches TCC.
@MainActor
struct DictationGate {
    var isSupported: (Locale) -> Bool
    var requestSpeech: () async -> Bool
    var requestMicrophone: () async -> Bool

    static let live = DictationGate(
        isSupported: { locale in
            guard let recognizer = SFSpeechRecognizer(locale: locale) else { return false }
            return recognizer.isAvailable && recognizer.supportsOnDeviceRecognition
        },
        requestSpeech: DictationController.requestSpeechPermission,
        requestMicrophone: DictationController.requestMicrophonePermission)
}

/// Optional, explicit, on-device dictation.
///
/// It requests microphone and speech permission only at invocation, refuses
/// recognition that would require the network, anchors its insertion to a
/// source-bound range, and invalidates late callbacks with a generation token.
/// It never silently falls back to cloud recognition and never overwrites text
/// typed after dictation started.
@MainActor
final class DictationController {
    enum State: Equatable {
        case idle
        case listening
        case unavailable(String)
        case denied(String)

        var isListening: Bool { self == .listening }
    }

    private(set) var state: State = .idle
    var onStateChange: ((State) -> Void)?

    private weak var editor: MarkdownTextView?
    private let gateway: EditorMutationGateway
    private let locale: Locale
    private let gate: DictationGate

    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var generation = DictationGeneration()
    /// Source-bound anchor and the exact text this session has inserted there.
    private var anchor: DictationAnchor?
    private var insertionOrigin: EditOrigin = .knownAssistance(.dictation)

    init(editor: MarkdownTextView, gateway: EditorMutationGateway, locale: Locale = .current,
         gate: DictationGate = .live) {
        self.editor = editor
        self.gateway = gateway
        self.locale = locale
        self.gate = gate
    }

    var isSupported: Bool { gate.isSupported(locale) }

    func toggle() {
        if state.isListening { stop() } else { start() }
    }

    func start() {
        guard state.isListening == false else { return }
        guard let editor else {
            update(.unavailable("Dictation needs an open document window."))
            return
        }
        guard isSupported else {
            update(.unavailable("On-device dictation is not available for this language or system."))
            return
        }
        // Anchor to the exact caret at invocation, before any permission prompt
        // can move it, and open the session now so a callback from a previous
        // session is already stale. Later unrelated edits are detected before
        // any transcript is applied.
        let token = beginSession(at: editor.selectedRange().location)
        Task { [weak self] in
            guard let self, self.generation.isCurrent(token) else { return }
            let speechAllowed = await self.gate.requestSpeech()
            guard self.generation.isCurrent(token) else { return }
            guard speechAllowed else {
                self.update(.denied("Speech recognition permission was not granted."))
                return
            }
            let micAllowed = await self.gate.requestMicrophone()
            guard self.generation.isCurrent(token) else { return }
            guard micAllowed else {
                self.update(.denied("Microphone permission was not granted."))
                return
            }
            self.beginRecognition(token: token)
        }
    }

    /// Opens a dictation session at an exact source location and returns the
    /// token that any callback for it must carry.
    ///
    /// `start()` is the production caller; this is separate so the session and
    /// coalescing rules can be driven without a microphone or a private
    /// transcript.
    @discardableResult
    func beginSession(at location: Int) -> Int {
        let token = generation.begin()
        anchor = DictationAnchor(location: location)
        return token
    }

    func stop() {
        generation.invalidate()
        // Dropping the anchor means a late callback that slips past the
        // generation guard still cannot claim a valid range.
        anchor = nil
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
        update(.idle)
    }

    // MARK: - Recognition

    private func beginRecognition(token: Int) {
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.supportsOnDeviceRecognition else {
            update(.unavailable("On-device recognition became unavailable."))
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // The product only records locally; never fall back to a server.
        request.requiresOnDeviceRecognition = true
        self.request = request

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            update(.unavailable("No audio input device is available."))
            return
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
        engine.prepare()
        do { try engine.start() } catch {
            input.removeTap(onBus: 0)
            update(.unavailable("The microphone could not be started."))
            return
        }
        audioEngine = engine

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self, self.generation.isCurrent(token) else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.deliver(transcript: text, token: token)
                        self.stop()
                    } else {
                        self.deliver(transcript: text, token: token)
                    }
                } else if error != nil {
                    self.stop()
                    self.update(.unavailable("Dictation stopped before producing text."))
                }
            }
        }
        update(.listening)
    }

    /// Applies one recognition hypothesis for `token`.
    ///
    /// A token other than the current one belongs to a session that has already
    /// stopped, finished or been superseded, so the hypothesis is dropped here -
    /// before the anchor is consulted - and can neither move the caret nor
    /// publish a revision.
    func deliver(transcript: String, token: Int) {
        guard generation.isCurrent(token) else { return }
        applyTranscript(transcript)
    }

    /// Replaces only this session's still-valid dictated range. If newer,
    /// unrelated text occupies it, the session cancels rather than overwrite.
    private func applyTranscript(_ text: String) {
        guard let editor, var anchor else { return }
        let current = editor.string as NSString
        let decision = anchor.plan(for: text, liveText: current)
        self.anchor = anchor
        let range: NSRange
        switch decision {
        case .insert(let insertRange): range = insertRange
        case .replace(let replaceRange): range = replaceRange
        case .cancel:
            // Someone else changed the anchored range; never overwrite it.
            stop()
            update(.unavailable("Dictation stopped because the anchored text changed."))
            return
        }
        gateway.performProgrammatic(origin: insertionOrigin) {
            editor.insertText(text, replacementRange: range)
        }
    }

    // MARK: - Permissions

    static func requestSpeechPermission() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .denied, .restricted: return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        @unknown default: return false
        }
    }

    static func requestMicrophonePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .denied, .restricted: return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default: return false
        }
    }

    private func update(_ state: State) {
        self.state = state
        onStateChange?(state)
    }
}
