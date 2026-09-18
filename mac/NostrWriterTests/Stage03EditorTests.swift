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

    // MARK: - Stage 07 input-policy seam (no global interception)

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
}
