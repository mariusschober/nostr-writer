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

    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var generation = 0
    /// Source-bound anchor and the exact text this session has inserted there.
    private var anchor: DictationAnchor?
    private var insertionOrigin: EditOrigin = .knownAssistance(.dictation)

    init(editor: MarkdownTextView, gateway: EditorMutationGateway, locale: Locale = .current) {
        self.editor = editor
        self.gateway = gateway
        self.locale = locale
    }

    var isSupported: Bool {
        guard let recognizer = SFSpeechRecognizer(locale: locale) else { return false }
        return recognizer.isAvailable && recognizer.supportsOnDeviceRecognition
    }

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
        generation += 1
        let token = generation
        // Anchor to the exact caret at invocation. Later unrelated edits are
        // detected before any transcript is applied.
        anchor = DictationAnchor(location: editor.selectedRange().location)
        Task { [weak self] in
            guard let self, self.generation == token else { return }
            let speechAllowed = await self.requestSpeechPermission()
            guard self.generation == token else { return }
            guard speechAllowed else {
                self.update(.denied("Speech recognition permission was not granted."))
                return
            }
            let micAllowed = await self.requestMicrophonePermission()
            guard self.generation == token else { return }
            guard micAllowed else {
                self.update(.denied("Microphone permission was not granted."))
                return
            }
            self.beginRecognition(token: token)
        }
    }

    func stop() {
        generation += 1
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
                guard let self, self.generation == token else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.applyTranscript(text)
                        self.stop()
                    } else {
                        self.applyTranscript(text)
                    }
                } else if error != nil {
                    self.stop()
                    self.update(.unavailable("Dictation stopped before producing text."))
                }
            }
        }
        update(.listening)
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

    private func requestSpeechPermission() async -> Bool {
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

    private func requestMicrophonePermission() async -> Bool {
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
