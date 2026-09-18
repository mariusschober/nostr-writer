import XCTest
@testable import WriterFoundation

final class ObservationTests: XCTestCase {
    private func snapshot(_ text: String) throws -> SourceSnapshot {
        try SourceSnapshot(documentID: DocumentID(), revision: Revision(0), utf8: Data(text.utf8))
    }

    func testOriginCategoryIsHonestAndDoesNotGuessFromText() {
        XCTAssertEqual(EditOrigin.directNativeInput.category, .directNativeInput)
        XCTAssertEqual(EditOrigin.nativeIMECommit.category, .nativeIMECommit)
        XCTAssertEqual(EditOrigin.knownAssistance(.dictation).category, .assistance)
        XCTAssertEqual(EditOrigin.knownAssistance(.dictation).assistanceKind, .dictation)
        XCTAssertEqual(EditOrigin.findReplace.category, .findReplace)
        XCTAssertFalse(EditOrigin.unknown.category.isExplained)
        XCTAssertTrue(EditOrigin.pasteExternal.category.isExplained)
        // Internal move/copy keep a private token that is not part of the
        // persisted category, so identical text alone never carries ancestry.
        let token = UUID()
        XCTAssertEqual(EditOrigin.internalCopy(token).category, .internalCopy)
        XCTAssertEqual(EditOrigin.internalCopy(token).ancestryTokenID, token)
    }

    func testReplayReconstructsExactChainAndRejectsTampering() throws {
        let initial = try snapshot("Cafe\u{301} 😀\n")
        let epoch = CaptureEpochID()
        // Insert "!" at end; then replace "Cafe\u{301}" with "Kaffee".
        var records: [LocalEditRecord] = []
        let insertRange = try ByteRange(lowerBound: initial.utf8.count, upperBound: initial.utf8.count)
        let first = try EditCommand(id: UUID(), expectedRevision: initial.revision, range: insertRange,
                                    replacement: Data("!".utf8), origin: .directNativeInput, undoGroup: UUID())
            .applying(to: initial, completeness: .descriptiveOnly)
        records.append(LocalEditRecord(epochID: epoch, receipt: first, recordedAtEpochSeconds: 1))
        let replaceRange = try ByteRange(lowerBound: 0, upperBound: "Cafe\u{301}".utf8.count)
        let second = try EditCommand(id: UUID(), expectedRevision: first.post.revision, range: replaceRange,
                                     replacement: Data("Kaffee".utf8), origin: .directNativeInput, undoGroup: UUID())
            .applying(to: first.post, completeness: .descriptiveOnly)
        records.append(LocalEditRecord(epochID: epoch, receipt: second, recordedAtEpochSeconds: 2))

        let replayed = try LocalReplay.replay(from: initial, records: records)
        XCTAssertEqual(replayed.utf8, second.post.utf8)
        XCTAssertEqual(replayed.utf8, Data("Kaffee 😀\n!".utf8))

        // Tampering with a claimed deleted byte must fail loudly, not repair.
        let tampered = LocalEditRecord(epochID: epoch, revision: records[1].revision, range: records[1].range,
                                       deleted: Data("XXXXX".utf8), inserted: records[1].inserted,
                                       originCategory: .directNativeInput, postDigest: records[1].postDigest,
                                       recordedAtEpochSeconds: 2)
        XCTAssertThrowsError(try LocalReplay.replay(from: initial, records: [records[0], tampered]))
    }

    /// Mandatory Stage 03 evidence: 1,000 deterministic random Unicode edits
    /// replay after every operation with exact source-byte equality.
    func testThousandOperationUnicodeReplayIsExact() throws {
        let seed: UInt64 = 0x5EED_0303
        var rng = LCG(seed: seed)
        // Combining marks, astral scalars and RTL letters exercise multi-scalar
        // graphemes and surrogate pairs in both coordinate spaces.
        let corpus = "aCafe\u{301}b😀ג\u{5D0}\u{5D1}\u{5D2}üß\n—«»"
        var current = try snapshot(corpus)
        var records: [LocalEditRecord] = []
        var checkpoints: [Data] = [current.utf8]
        let epoch = CaptureEpochID()

        for index in 0..<1_000 {
            let scalars = Array(current.string.unicodeScalars)
            let range = try boundedScalarAlignedRange(in: current, rng: &rng)
            let origin = EditOriginCategory.allCases[Int(rng.next() % UInt64(EditOriginCategory.allCases.count))]
            let inserted: Data
            switch rng.next() % 3 {
            case 0: inserted = Data()
            case 1: inserted = Data(scalars.isEmpty ? "x".utf8 : String(scalars[Int(rng.next() % UInt64(scalars.count))]).utf8)
            default: inserted = Data("ä😀\u{301}z".utf8)
            }
            let command = try EditCommand(id: UUID(), expectedRevision: current.revision, range: range,
                                          replacement: inserted, origin: origin.editOrigin, undoGroup: UUID())
            let receipt = try command.applying(to: current, completeness: .descriptiveOnly)
            records.append(LocalEditRecord(epochID: epoch, receipt: receipt, recordedAtEpochSeconds: Double(index)))
            current = receipt.post

            // Replay after every operation must land on the exact live bytes.
            let replayed = try LocalReplay.replay(from: try snapshot(corpus), records: records)
            XCTAssertEqual(replayed.utf8, current.utf8, "Replay diverged at operation \(index)")
            checkpoints.append(current.utf8)
        }

        XCTAssertEqual(records.count, 1_000)
        let finalReplay = try LocalReplay.replay(from: try snapshot(corpus), records: records)
        XCTAssertEqual(finalReplay.digest, current.digest)
        print("STAGE03_REPLAY seed=\(seed) operations=\(records.count) finalBytes=\(current.utf8.count)")
    }

    func testAnnotationSurvivesUnrelatedEditsAndGoesStaleOnReplacement() throws {
        let initial = try snapshot("alpha beta gamma")
        let epoch = CaptureEpochID()
        // Annotate "beta" (bytes 6..<10).
        let beta = try ByteRange(lowerBound: 6, upperBound: 10)
        let annotation = SourceAnnotation(kind: .quotation, range: beta, description: "from X", revision: initial.revision)

        // Insert "X" at the very start: annotation shifts by one, stays bound.
        let insert = try EditCommand(id: UUID(), expectedRevision: initial.revision,
                                     range: try ByteRange(lowerBound: 0, upperBound: 0),
                                     replacement: Data("X".utf8), origin: .directNativeInput, undoGroup: UUID())
            .applying(to: initial, completeness: .descriptiveOnly)
        let insertRecord = LocalEditRecord(epochID: epoch, receipt: insert, recordedAtEpochSeconds: 0)
        var mapped = SourceLineage.map(annotation, through: [insertRecord])
        XCTAssertEqual(mapped.count, 1)
        XCTAssertEqual(mapped[0].range.lowerBound, 7)
        XCTAssertEqual(mapped[0].range.upperBound, 11)

        // Replace the (now-shifted) annotated wording itself: the wording is
        // gone, so the annotation goes stale rather than jumping to new text.
        let shifted = try XCTUnwrap(mapped.first?.range)
        let replace = try EditCommand(id: UUID(), expectedRevision: insert.post.revision, range: shifted,
                                      replacement: Data("BETA".utf8), origin: .directNativeInput, undoGroup: UUID())
            .applying(to: insert.post, completeness: .descriptiveOnly)
        let replaceRecord = LocalEditRecord(epochID: epoch, receipt: replace, recordedAtEpochSeconds: 1)
        mapped = SourceLineage.map(annotation, through: [insertRecord, replaceRecord])
        XCTAssertTrue(mapped.isEmpty, "Replacing the annotated wording must not let the exclusion jump to new text")

        // A later insert occupying the old indexes must not resurrect the
        // exclusion: a stale annotation stays stale.
        let laterInsert = try EditCommand(id: UUID(), expectedRevision: replace.post.revision,
                                          range: try ByteRange(lowerBound: 7, upperBound: 7),
                                          replacement: Data("Z".utf8), origin: .directNativeInput, undoGroup: UUID())
            .applying(to: replace.post, completeness: .descriptiveOnly)
        mapped = SourceLineage.map(annotation, through: [
            insertRecord, replaceRecord,
            LocalEditRecord(epochID: epoch, receipt: laterInsert, recordedAtEpochSeconds: 2)
        ])
        XCTAssertTrue(mapped.isEmpty, "A stale exclusion must not reattach to unrelated later text")

        // An insertion *inside* a live annotated span correctly splits it.
        let insideInsert = try EditCommand(id: UUID(), expectedRevision: initial.revision,
                                           range: try ByteRange(lowerBound: 8, upperBound: 8),
                                           replacement: Data("-".utf8), origin: .directNativeInput, undoGroup: UUID())
            .applying(to: initial, completeness: .descriptiveOnly)
        let split = SourceLineage.map(annotation, through: [LocalEditRecord(epochID: epoch, receipt: insideInsert, recordedAtEpochSeconds: 3)])
        XCTAssertEqual(split.count, 2)
        XCTAssertEqual(split.map(\.range.lowerBound), [6, 9])
    }

    func testAncestryTokenRequiresExactPayload() {
        let payload = Data("quoted passage".utf8)
        let token = AncestryToken(originCategory: .internalCopy, sourceRecordID: UUID(),
                                  payloadDigest: SourceSnapshot.sha256(payload))
        XCTAssertTrue(token.matches(payload: payload))
        XCTAssertFalse(token.matches(payload: Data("quoted passag".utf8)))
        XCTAssertFalse(token.matches(payload: Data("quoted passage ".utf8)))
    }

    // MARK: - Helpers

    /// Picks a deterministically random scalar-aligned half-open byte range that
    /// spans at most a few scalars, so 1,000 operations vary offsets across the
    /// whole document instead of converging on an empty string.
    private func boundedScalarAlignedRange(in snapshot: SourceSnapshot, rng: inout LCG) throws -> ByteRange {
        let boundaries = snapshot.scalarByteBoundaries()
        let start = Int(rng.next() % UInt64(boundaries.count))
        let span = Int(rng.next() % 4)
        let end = min(start + span, boundaries.count - 1)
        let lower = boundaries[start]
        let upper = boundaries[end]
        return try ByteRange(lowerBound: lower, upperBound: upper)
    }

    private struct LCG {
        private var state: UInt64
        init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9 : seed }
        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state >> 16
        }
    }
}

private extension EditOriginCategory {
    var editOrigin: EditOrigin {
        switch self {
        case .directNativeInput: .directNativeInput
        case .nativeIMEUpdate: .nativeIMEUpdate
        case .nativeIMECommit: .nativeIMECommit
        case .assistance: .knownAssistance(.spelling)
        case .pasteExternal: .pasteExternal
        case .internalMove: .internalMove(UUID())
        case .internalCopy: .internalCopy(UUID())
        case .undo: .undo(UUID())
        case .redo: .redo(UUID())
        case .formatting: .formatting
        case .findReplace: .findReplace
        case .externalReload: .externalReload
        case .recover: .recover
        case .unknown: .unknown
        }
    }
}

private extension SourceSnapshot {
    /// Every UTF-8 byte offset that is a Unicode scalar boundary, in order.
    func scalarByteBoundaries() -> [Int] {
        var boundaries = [0]
        var offset = 0
        for scalar in string.unicodeScalars {
            let value = scalar.value
            let length = value <= 0x7F ? 1 : value <= 0x7FF ? 2 : value <= 0xFFFF ? 3 : 4
            offset += length
            boundaries.append(offset)
        }
        return boundaries
    }
}
