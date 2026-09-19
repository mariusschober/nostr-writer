import XCTest
import AppKit
import WriterFoundation

/// Stage 03 native editor, provenance and assistance checks (M14–M21).
///
/// These exercise the real gateway/document path where it can be driven
/// deterministically. Observations that require a physical input method,
/// microphone or human are recorded as BLOCKED in STAGE-03 evidence rather than
/// faked here.
@MainActor
final class Stage03EditorTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Keep preferences out of the owner's real defaults and prevent an
        // accidental Keychain journal from being requested during tests.
        setenv("NW_TEST_DEFAULTS", "com.mariusschober.nostrwriter.tests.stage03", 1)
        UserDefaults(suiteName: "com.mariusschober.nostrwriter.tests.stage03")?
            .removePersistentDomain(forName: "com.mariusschober.nostrwriter.tests.stage03")
    }

    override func tearDown() {
        UserDefaults(suiteName: "com.mariusschober.nostrwriter.tests.stage03")?
            .removePersistentDomain(forName: "com.mariusschober.nostrwriter.tests.stage03")
        unsetenv("NW_TEST_DEFAULTS")
        super.tearDown()
    }

    private func makeController(_ text: String) throws -> (WriterDocument, WriterWindowController) {
        _ = NSApplication.shared
        let document = WriterDocument()
        document.consent.choose(.off)
        try document.read(from: Data(text.utf8), ofType: "net.daringfireball.markdown")
        document.makeWindowControllers()
        let controller = try XCTUnwrap(document.windowControllers.first as? WriterWindowController)
        return (document, controller)
    }

    // MARK: - M17: one gateway, honest causes

    func testGatewayClassifiesObservedDeliveryWithoutGuessingFromText() throws {
        let document = WriterDocument()
        let gateway = EditorMutationGateway(document: document)

        XCTAssertEqual(gateway.origin(for: .typed, declaredProgrammatic: nil), .directNativeInput)
        XCTAssertEqual(gateway.origin(for: .imeComposition, declaredProgrammatic: nil), .nativeIMEUpdate)
        XCTAssertEqual(gateway.origin(for: .imeCommit, declaredProgrammatic: nil), .nativeIMECommit)
        XCTAssertEqual(gateway.origin(for: .spellingCorrection, declaredProgrammatic: nil), .knownAssistance(.spelling))
        XCTAssertEqual(gateway.origin(for: .pasteExternal, declaredProgrammatic: nil), .pasteExternal)
        XCTAssertEqual(gateway.origin(for: .cut, declaredProgrammatic: nil), .cut)
        XCTAssertEqual(gateway.origin(for: .drop, declaredProgrammatic: nil), .drop)
        XCTAssertEqual(gateway.origin(for: .programmatic, declaredProgrammatic: .findReplace), .findReplace)
        XCTAssertEqual(gateway.origin(for: .programmatic, declaredProgrammatic: .formatting), .formatting)
        // An unexplained programmatic or unknown delivery is an honest gap, not typing.
        XCTAssertEqual(gateway.origin(for: .programmatic, declaredProgrammatic: nil), .unknown)
        XCTAssertEqual(gateway.origin(for: .unknown, declaredProgrammatic: nil), .unknown)
        XCTAssertFalse(EditOrigin.unknown.category.isExplained)
        XCTAssertEqual(EditOrigin.cut.category, .cut)
    }

    func testOneTypedMutationProducesExactlyOneRevision() throws {
        let (document, controller) = try makeController("alpha beta\n")
        let before = try XCTUnwrap(document.session?.snapshot)
        let editor = controller.editor
        let end = NSRange(location: editor.string.utf16.count, length: 0)

        editor.insertText("x", replacementRange: end)

        let after = try XCTUnwrap(document.session?.snapshot)
        XCTAssertEqual(after.revision.rawValue, before.revision.rawValue + 1, "one mutation must advance the revision once")
        XCTAssertEqual(document.session?.lastMutation?.command.origin, .directNativeInput)
        XCTAssertEqual(document.sourceBytes, before.utf8 + Data("x".utf8))
        XCTAssertEqual(Data(editor.string.utf8), document.sourceBytes)

        // A repeated delegate callback with identical bytes must not publish
        // another revision or a duplicate receipt.
        controller.textDidChange(Notification(name: NSText.didChangeNotification, object: editor))
        let stable = try XCTUnwrap(document.session?.snapshot)
        XCTAssertEqual(stable.revision, after.revision)
        XCTAssertEqual(stable.utf8, after.utf8)
    }

    // MARK: - M15: formatting and find/replace stay exact and reversible

    func testFormattingAndFindReplaceUseTheirOwnCausesAndPreserveBytes() throws {
        let (document, controller) = try makeController("alpha beta gamma")
        let editor = controller.editor

        // Formatting inserts visible syntax through the gateway as formatting.
        editor.setSelectedRange(NSRange(location: 6, length: 4)) // "beta"
        EditorCommands.apply(.bold, to: editor, gateway: controller.gateway)
        XCTAssertEqual(document.sourceBytes, Data("alpha **beta** gamma".utf8))
        XCTAssertEqual(document.session?.lastMutation?.command.origin, .formatting)

        // Find/replace is declared as such, never as direct typing.
        let boldRange = NSRange(location: 6, length: 8) // "**beta**"
        editor.setProgrammaticDelivery(.findReplace)
        editor.insertText("**BETA**", replacementRange: boldRange)
        XCTAssertEqual(document.sourceBytes, Data("alpha **BETA** gamma".utf8))
        XCTAssertEqual(document.session?.lastMutation?.command.origin, .findReplace)

        // The whole document remains exactly what the editor shows.
        XCTAssertEqual(Data(editor.string.utf8), document.sourceBytes)
    }

    // MARK: - M16: input-method composition does not commit intermediate text

    func testMarkedTextIsNotCommittedAsARevision() throws {
        let (document, controller) = try makeController("")
        let editor = controller.editor
        let before = try XCTUnwrap(document.session?.snapshot)

        editor.setMarkedText("に", selectedRange: NSRange(location: 0, length: 1),
                             replacementRange: NSRange(location: 0, length: 0))
        guard editor.hasMarkedText() else {
            throw XCTSkip("Marked-text composition is unavailable in this headless test host; "
                          + "the real IME observation is BLOCKED and recorded in STAGE-03 evidence.")
        }

        // While text is marked, the live editor may show composition, but the
        // document publishes nothing: intermediate IME text is not a commit.
        controller.textDidChange(Notification(name: NSText.didChangeNotification, object: editor))
        XCTAssertEqual(document.session?.snapshot, before, "a marked-text change must not publish a revision")

        // A real commit replaces the marked range and is recorded as IME commit.
        editor.insertText("日本", replacementRange: editor.markedRange())
        controller.textDidChange(Notification(name: NSText.didChangeNotification, object: editor))
        XCTAssertFalse(editor.hasMarkedText())
        XCTAssertEqual(document.session?.lastMutation?.command.origin, .nativeIMECommit)
        XCTAssertEqual(document.sourceBytes, Data("日本".utf8))
    }

    // MARK: - M19: dictation anchor never overwrites later typing

    func testDictationAnchorCancelsRatherThanOverwritingLaterText() {
        var anchor = DictationAnchor(location: 3, session: UUID())

        // First hypothesis inserts at the anchor.
        XCTAssertEqual(anchor.plan(for: "hi", liveText: "abcdef" as NSString), .insert(NSRange(location: 3, length: 0)))
        // A refined hypothesis replaces only this session's own range.
        XCTAssertEqual(anchor.plan(for: "hello", liveText: "abchidef" as NSString), .replace(NSRange(location: 3, length: 2)))
        // An unrelated edit replaced the dictated range: cancel, do not clobber.
        XCTAssertEqual(anchor.plan(for: "hello there", liveText: "abcXYdef" as NSString), .cancel)
        // A truncated document also cancels rather than writing past the end.
        XCTAssertEqual(anchor.plan(for: "hello", liveText: "ab" as NSString), .cancel)
    }

    // MARK: - M14: typewriter scroll honours Reduce Motion

    func testTypewriterScrollPlanHonoursReduceMotionWithoutMovingText() throws {
        let visible = NSRect(x: 0, y: 0, width: 600, height: 400)
        let padding: CGFloat = 20

        // Caret comfortably inside the viewport: ordinary mode still recentres
        // to the 45% target, Reduce Motion leaves the page exactly where it is.
        let inside = NSRect(x: 0, y: 200, width: 2, height: 20)
        let centredInside = try XCTUnwrap(
            TypewriterScrollPlan.plan(caret: inside, visible: visible, reduceMotion: false, padding: padding).origin)
        XCTAssertEqual(centredInside.y, 200 - 400 * 0.45, accuracy: 0.001)
        XCTAssertNil(TypewriterScrollPlan.plan(caret: inside, visible: visible, reduceMotion: true, padding: padding).origin)

        // A small drift inside the dead zone is not worth a scroll either way.
        let deadZone = NSRect(x: 0, y: 185, width: 2, height: 20)
        XCTAssertNil(TypewriterScrollPlan.plan(caret: deadZone, visible: visible, reduceMotion: false, padding: padding).origin)

        // Caret just below the bottom edge: Reduce Motion scrolls the smallest
        // amount that shows the caret, ordinary mode centres the line.
        let below = NSRect(x: 0, y: 405, width: 2, height: 20)
        let reduced = try XCTUnwrap(
            TypewriterScrollPlan.plan(caret: below, visible: visible, reduceMotion: true, padding: padding).origin)
        let centred = try XCTUnwrap(
            TypewriterScrollPlan.plan(caret: below, visible: visible, reduceMotion: false, padding: padding).origin)
        XCTAssertEqual(reduced.y, below.maxY - visible.height + padding, accuracy: 0.001)
        XCTAssertEqual(centred.y, below.minY - visible.height * 0.45, accuracy: 0.001)
        XCTAssertLessThan(reduced.y, centred.y, "Reduce Motion must travel less than recentring")
        XCTAssertLessThanOrEqual(below.maxY, reduced.y + visible.height, "the caret must still be visible")

        // Caret near the top edge scrolls up by the font padding, not to zero.
        let scrolled = NSRect(x: 0, y: 100, width: 600, height: 400)
        let nearTop = NSRect(x: 0, y: 102, width: 2, height: 20)
        let topUp = try XCTUnwrap(
            TypewriterScrollPlan.plan(caret: nearTop, visible: scrolled, reduceMotion: true, padding: padding).origin)
        XCTAssertEqual(topUp.y, 82, accuracy: 0.001)
    }

    // MARK: - Stage 07 input-policy seam (no global interception)

    // MARK: - M19: the gate refuses before any prompt, and late callbacks are dropped

    /// A gate whose answers are fixed, so the unsupported, denied and granted
    /// paths can be decided without answering a real privacy prompt. Each call
    /// is counted so a test can assert a prompt was never even requested.
    private final class CountingGate {
        var supported = true
        var speech = true
        var microphone = true
        var speechRequests = 0
        var microphoneRequests = 0

        @MainActor func make() -> DictationGate {
            DictationGate(
                isSupported: { [self] _ in supported },
                requestSpeech: { [self] in speechRequests += 1; return speech },
                requestMicrophone: { [self] in microphoneRequests += 1; return microphone })
        }
    }

    func testDictationRefusesUnsupportedLanguageBeforeAskingForPermission() throws {
        let (document, controller) = try makeController("keep me")
        let counter = CountingGate()
        counter.supported = false
        let dictation = DictationController(editor: controller.editor, gateway: controller.gateway,
                                           locale: Locale(identifier: "en-US"), gate: counter.make())

        dictation.toggle()

        XCTAssertEqual(dictation.state, .unavailable("On-device dictation is not available for this language or system."))
        XCTAssertFalse(dictation.state.isListening)
        XCTAssertEqual(counter.speechRequests, 0, "an unsupported language must not prompt for speech permission")
        XCTAssertEqual(counter.microphoneRequests, 0, "an unsupported language must not prompt for the microphone")
        XCTAssertEqual(document.sourceBytes, Data("keep me".utf8))
    }

    func testDictationReportsDeniedSpeechAndMicrophoneWithoutListening() async throws {
        let (document, controller) = try makeController("keep me")
        let counter = CountingGate()
        counter.speech = false
        counter.microphone = false
        let dictation = DictationController(editor: controller.editor, gateway: controller.gateway,
                                           locale: Locale(identifier: "en-US"), gate: counter.make())

        let denied = XCTestExpectation(description: "denied state")
        dictation.onStateChange = { if case .denied = $0 { denied.fulfill() } }
        dictation.start()
        await fulfillment(of: [denied], timeout: 5)

        XCTAssertEqual(dictation.state, .denied("Speech recognition permission was not granted."))
        XCTAssertFalse(dictation.state.isListening)
        XCTAssertEqual(counter.speechRequests, 1)
        XCTAssertEqual(counter.microphoneRequests, 0,
                       "a refused speech grant must stop before the microphone prompt")
        XCTAssertEqual(document.sourceBytes, Data("keep me".utf8))
        XCTAssertNil(document.session?.lastMutation)
    }

    func testDictationReportsDeniedMicrophoneAfterAGrantedSpeechPrompt() async throws {
        let (document, controller) = try makeController("keep me")
        let counter = CountingGate()
        counter.speech = true
        counter.microphone = false
        let dictation = DictationController(editor: controller.editor, gateway: controller.gateway,
                                           locale: Locale(identifier: "en-US"), gate: counter.make())

        let denied = XCTestExpectation(description: "microphone denied")
        dictation.onStateChange = { if case .denied = $0 { denied.fulfill() } }
        dictation.start()
        await fulfillment(of: [denied], timeout: 5)

        XCTAssertEqual(dictation.state, .denied("Microphone permission was not granted."))
        XCTAssertEqual(counter.speechRequests, 1)
        XCTAssertEqual(counter.microphoneRequests, 1)
        XCTAssertEqual(document.sourceBytes, Data("keep me".utf8))
    }

    func testLateDictationCallbackAfterStopCannotTouchTheDocument() throws {
        let (document, controller) = try makeController("abcdef")
        let counter = CountingGate()
        let dictation = DictationController(editor: controller.editor, gateway: controller.gateway,
                                           locale: Locale(identifier: "en-US"), gate: counter.make())

        let token = dictation.beginSession(at: 3)
        // A hypothesis from this session would insert at the anchor.
        dictation.deliver(transcript: "hi", token: token)
        XCTAssertEqual(document.sourceBytes, Data("abchidef".utf8))

        dictation.stop()
        let afterStop = document.sourceBytes
        // The callback for the session that just ended is now stale.
        dictation.deliver(transcript: " too late ", token: token)
        XCTAssertEqual(document.sourceBytes, afterStop, "a late callback must not change the source")
        XCTAssertEqual(document.session?.snapshot.utf8, Data("abchidef".utf8),
                       "the published revision must still hold the pre-callback source")
        XCTAssertEqual(dictation.state, .idle)
    }

    func testTokenFromAnEarlierSessionCannotOverwriteANewerOne() throws {
        let (document, controller) = try makeController("abcdef")
        let counter = CountingGate()
        let dictation = DictationController(editor: controller.editor, gateway: controller.gateway,
                                           locale: Locale(identifier: "en-US"), gate: counter.make())

        let first = dictation.beginSession(at: 0)
        dictation.stop()
        let second = dictation.beginSession(at: 0)
        XCTAssertNotEqual(first, second, "a closed session's token must never be reused")

        // The superseded session's callback is dropped even though a session is
        // open again, so it cannot overwrite the newer one.
        dictation.deliver(transcript: "STALE", token: first)
        XCTAssertEqual(document.sourceBytes, Data("abcdef".utf8))

        // The current session still works and is attributed to assistance.
        dictation.deliver(transcript: "live", token: second)
        XCTAssertEqual(document.sourceBytes, Data("liveabcdef".utf8))
        XCTAssertEqual(document.session?.lastMutation?.command.origin, .knownAssistance(.dictation))
    }

    func testInputPolicyRefusesExternalInsertionLocally() throws {
        let (document, controller) = try makeController("keep me")
        let before = try XCTUnwrap(document.session?.snapshot)
        let gateway = controller.gateway
        gateway.inputPolicy.allowsExternalInsertion = false

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("EXTERNAL", forType: .string)
        controller.editor.setSelectedRange(NSRange(location: controller.editor.string.utf16.count, length: 0))
        controller.editor.paste(nil)

        XCTAssertTrue(gateway.lastRefusedExternalInsertion, "the policy must observe the external paste")
        XCTAssertEqual(document.session?.snapshot, before, "a refused external insertion must not mutate the source")
        XCTAssertEqual(document.sourceBytes, Data("keep me".utf8))

        // The same insertion is allowed once the ordinary policy is restored.
        gateway.clearExternalInsertionRefusal()
        gateway.inputPolicy.allowsExternalInsertion = true
        controller.editor.paste(nil)
        XCTAssertEqual(document.sourceBytes, Data("keep meEXTERNAL".utf8))
    }

    // MARK: - M20/M21: annotations, lineage and consent boundaries

    func testAnnotationsShiftThroughEditsAndRemovalKeepsSource() throws {
        let (document, controller) = try makeController("alpha beta gamma")
        let beta = try ByteRange(lowerBound: 6, upperBound: 10)
        document.addAnnotation(kind: .quotation, range: beta, description: "from X", url: "https://example.test/x")
        XCTAssertEqual(document.annotations.count, 1)
        XCTAssertEqual(document.annotations[0].range.lowerBound, 6)

        // Insert at the very start through the gateway: the annotation shifts
        // with its exact wording rather than staying on stale indexes.
        controller.editor.insertText("Z", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertEqual(document.annotations.count, 1)
        XCTAssertEqual(document.annotations[0].range.lowerBound, 7)
        XCTAssertEqual(document.annotations[0].range.upperBound, 11)
        XCTAssertFalse(document.annotations[0].isStale)
        XCTAssertEqual(document.sourceBytes, Data("Zalpha beta gamma".utf8))

        // Replacing the marked wording leaves the annotation stale, not moved
        // onto unrelated new text.
        controller.editor.setSelectedRange(NSRange(location: 7, length: 4))
        controller.editor.insertText("BETA", replacementRange: NSRange(location: 7, length: 4))
        XCTAssertEqual(document.annotations.count, 1)
        XCTAssertTrue(document.annotations[0].isStale, "replaced wording must go stale for review")

        document.removeAnnotation(document.annotations[0].id)
        XCTAssertTrue(document.annotations.isEmpty)
        XCTAssertEqual(document.sourceBytes, Data("Zalpha BETA gamma".utf8))
    }

    func testObservationHandleHonoursConsentBoundaries() async throws {
        let snapshot = try SourceSnapshot(documentID: DocumentID(), revision: Revision(0), utf8: Data("draft".utf8))
        let session = DocumentSession(snapshot: snapshot)

        // Recording off: no handle at all.
        let offHandle = try await session.finalizeObservation(reason: .close)
        XCTAssertNil(offHandle)

        // A gap or pause is honest: no continuous handle.
        session.recordingState = .gap(CaptureGapReason.storeFailure.rawValue)
        let gapHandle = try await session.finalizeObservation(reason: .save)
        XCTAssertNil(gapHandle)
        session.recordingState = .pausedLimit
        let limitHandle = try await session.finalizeObservation(reason: .limit)
        XCTAssertNil(limitHandle)

        // Observing yields a handle bound to the exact current source, not an
        // HWP approval.
        session.recordingState = .observing
        let handle = try await session.finalizeObservation(reason: .save)
        XCTAssertEqual(handle?.source, session.snapshot)
    }

    // MARK: - M15: 100k-word responsiveness measurement

    func testHundredThousandWordDocumentStaysExactAndResponsive() throws {
        var text = ""
        text.reserveCapacity(600_000)
        for line in 0..<8_334 {
            text += "line \(line) " + Array(repeating: "word", count: 11).joined(separator: " ") + "\n"
        }
        let words = 8_334 * 12
        let (document, controller) = try makeController(text)
        let editor = controller.editor
        let clock = ContinuousClock()
        func ms(_ d: Duration) -> Double { Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15 }

        let outlineStart = clock.now
        let headings = EditorOutline.items(in: try XCTUnwrap(document.session?.snapshot))
        let outlineMS = ms(outlineStart.duration(to: clock.now))

        var editMS: [Double] = []
        for _ in 0..<20 {
            let start = clock.now
            editor.insertText("x", replacementRange: NSRange(location: editor.string.utf16.count, length: 0))
            editMS.append(ms(start.duration(to: clock.now)))
        }
        let final = try XCTUnwrap(document.session?.snapshot)
        XCTAssertEqual(final.utf8, Data(text.utf8) + Data(String(repeating: "x", count: 20).utf8))
        XCTAssertEqual(Data(editor.string.utf8), final.utf8)
        XCTAssertTrue(headings.isEmpty, "a plain-word fixture has no headings")

        editMS.sort()
        print("STAGE03_PERF words=\(words) bytes=\(text.utf8.count) outlineItems=\(headings.count) "
              + "outlineMS=\(String(format: "%.1f", outlineMS)) editP95MS=\(String(format: "%.1f", editMS[18])) "
              + "editMaxMS=\(String(format: "%.1f", editMS[19]))")
    }

    // MARK: - M21: consent is a live state, not a setting read once at open

    /// Turning recording off must reach an already-open document. Before the
    /// consent notification existed the setting changed silently and an open
    /// document kept recording.
    func testConsentChangeReachesAnOpenDocument() async throws {
        let (document, _) = try makeController("Consent body.\n")
        document.consent.choose(.off)
        XCTAssertEqual(document.recordingState, .off)

        document.consent.choose(.requested)
        await settle()
        // The isolated test host has no signed Keychain store, so the honest
        // outcome is a gap. What matters is that the document reacted at all.
        XCTAssertNotEqual(document.recordingState, .off)

        document.consent.choose(.off)
        await settle()
        XCTAssertEqual(document.recordingState, .off)
    }

    /// Pause must not strand the session: resume re-enters the recording state
    /// machine instead of silently staying paused.
    func testPauseThenResumeLeavesThePausedState() async throws {
        let (document, _) = try makeController("Pause body.\n")
        document.consent.choose(.requested)
        await settle()
        document.stopRecording(pausing: true)
        XCTAssertEqual(document.recordingState, .paused)
        document.resumeRecording()
        await settle()
        XCTAssertNotEqual(document.recordingState, .paused, "Resume must leave the paused state")
    }

    // MARK: - M15/M17: a prediction is only published when it reproduces reality

    /// A predicted range that does not reproduce the live editor must not
    /// become a revision. This is the input-method-inside-existing-text case:
    /// the range is numerically valid but addresses different content.
    func testUnverifiedLiveBytesAreNotPublishedAsAPredictedRevision() throws {
        let (document, controller) = try makeController("abcdef")
        let editor = controller.editor

        _ = controller.gateway.shouldChange(in: NSRange(location: 0, length: 1), replacement: "X")
        // Make the live editor disagree with the prediction "Xbcdef".
        editor.string = "abcdefZ"
        controller.textDidChange(Notification(name: NSText.didChangeNotification, object: editor))

        let mutation = try XCTUnwrap(document.session?.lastMutation)
        XCTAssertEqual(Data(editor.string.utf8), document.sourceBytes,
                       "the published source must match what the editor actually shows")
        XCTAssertEqual(mutation.command.origin, .unknown,
                       "an unverifiable prediction is an honest gap, not native typing")
        XCTAssertEqual(mutation.command.range.lowerBound, 0)
        XCTAssertEqual(mutation.command.range.upperBound, 6)
    }

    /// Internal ancestry uses the identity of the real copy/cut operation, and
    /// falls back to an honest gap when no such token exists — never a fresh
    /// UUID that implies a lineage that was not observed.
    func testInternalAncestryUsesTheRealOperationIDOrAnHonestGap() throws {
        let (_, controller) = try makeController("alpha beta")
        let gateway = controller.gateway
        let operationID = UUID()
        XCTAssertEqual(gateway.origin(for: .pasteInternalCopy, declaredProgrammatic: nil, ancestryID: operationID),
                       .internalCopy(operationID))
        XCTAssertEqual(gateway.origin(for: .pasteInternalMove, declaredProgrammatic: nil, ancestryID: operationID),
                       .internalMove(operationID))
        XCTAssertEqual(gateway.origin(for: .pasteInternalCopy, declaredProgrammatic: nil, ancestryID: nil), .unknown)
        XCTAssertEqual(gateway.origin(for: .pasteInternalMove, declaredProgrammatic: nil, ancestryID: nil), .unknown)
    }

    private func settle(_ iterations: Int = 8) async {
        for _ in 0..<iterations { await Task.yield() }
    }
}
