# Stage 03 evidence - editor, assistance and local writing history

Status: **BLOCKED** (implementation complete, compiling, hardened and
deterministically verified; mandatory native and owner observations
outstanding). `accepted: false`.

| Reference | Value |
| --- | --- |
| Predecessor handover tip | `c1aafc90115e431fdbf7df79f67c120ae470a94a` |
| Accepted Stage 02 checkpoint | `b8568c09530b90e28a3d1fb817335c6a980fc116` |
| Accepted Stage 02 app source | `67302883935fcfaba2b9668a04df3aee60820fcd` |
| Stage 03 branch | `implementation/stage-03` |
| Implementation commits | `e96e72d67288fe74d0517da285c2684e1fdb3947`, `17cb7523eaab35697e911be4b3bc895da37a857b`, `3f35d6df1c773483c21a51ab5fe8bf97e0f3762e`, `b77a0bba410845738af1fb1fb954c8307d08967b`, `61d3dbdae9879a5030fdb67a54dc7ea4885eb9cc` |
| Evidence commits | `4ae1454015a60cc15a654a89557771f0b3e57856` (first M14-M21 record and logs) and the commit adding this revision |
| Candidate executable | `mac/.build/SignedDevelopment/Build/Products/Debug/NostrWriter.app/Contents/MacOS/NostrWriter` |
| Candidate SHA-256 | `95efbecaecdb4fb607c7a051762226c6502b4aade82edae77341e385ef0f955f` |
| Candidate arch / signature | arm64, ad-hoc ("Sign to Run Locally"), identifier `com.mariusschober.nostrwriter.development` |
| Candidate build time | 2026-09-18 17:41:08 +0100 |

Environment: macOS 26.6.2 (25G83), Xcode 27.0 (27A266a), Swift 6.4, arm64.
`security find-identity -v -p codesigning` returned **0 valid identities**, so the
required Apple Development-signed candidate could not be produced. The candidate
above is an ad-hoc build whose entitlements are `app-sandbox`,
`device.audio-input`, `files.user-selected.read-write`, `get-task-allow` and
`network.client` - deliberately without `application-identifier` or
`keychain-access-groups`. The consequences are recorded under M21 and Blockers.

## What was implemented

New app-layer sources under `mac/NostrWriter/Editor/`:

- `MarkdownTextView.swift` - the single live TextKit 2 editor view; it observes
  actual native delivery (typed input, marked-text composition and commit,
  spelling assistance, copy/cut, internal vs external paste, drop) and never
  owns revisions, history or physical-typing certainty.
- `EditorMutationGateway.swift` - the one revision/cause gateway. Commits at
  most one receipt per real mutation, keeps an observed cause even when the
  range is editor-local, and records unexplained changes as capture gaps. Hosts
  the narrow Stage 07 input-policy seam.
- `EditorSupport.swift` - presentation-only Markdown emphasis and focus
  highlight (TextKit 2 rendering attributes) plus `EditorCommands.Formatting`,
  which inserts visible syntax through the gateway with a formatting origin.
- `WritePreferences.swift` - typography/measure/focus/typewriter preferences
  (13-32 pt, 50-100 chars) that never touch source bytes.
- `EditorOutline.swift` - pure ATX/Setext heading reader bound to a snapshot.
- `EditorInspector.swift` - passage inspector: recording state, gaps, exact-range
  annotations, an explicit "not claimed as freshly composed" notice and the
  contracted proof-absence message.
- `DictationController.swift` - optional, explicit, on-device dictation with a
  source-bound anchor, generation token and no silent cloud fallback.

Modified app/packages: `WriterWindowController` (editor adapter, chrome, outline,
inspector wiring, commands, sleep/close cancellation, coalesced presentation
refresh), `WriterDocument` (single `applyObserved` mutation boundary, annotation
lineage, consented history lifecycle, delete), `DocumentSession`
(`apply(_:completeness:)`, real `finalizeObservation`), `DocumentRecovery`
(history journal opening), `AppMenus`, `SettingsWindowController`,
`WriterFoundation` (`EditOrigin.cut/.drop`, `EditOriginCategory.cut/.drop`),
`WriterStorage` (`RecoveryBootstrap.openHistoryJournal`), entitlements,
`Info.plist` (microphone/speech purpose), `project.yml`, `inspect_app.py`.

## Stage 03 repair at `61d3dbd`

The first recorded candidate predated three later implementation commits, so its
evidence did not describe HEAD. This revision closes that gap and one real
weakness in the journal:

- **Authenticated interpretation.** The journal sealed each record's
  deleted/inserted text but left the record's *interpretation* - its range,
  observed cause, assistance kind and resulting digest - in unauthenticated
  plaintext columns, and the annotation AAD covered only document and revision.
  Rewriting any of those values left the row decrypting cleanly while silently
  changing what it claimed happened. The AAD is now version 2 and binds the full
  interpretation, with length-prefixed fields so concatenation is unambiguous.
- **Sticky staleness and distinct split ids.** An annotation whose wording was
  replaced stays stale until the owner resolves it (a later unrelated edit no
  longer silently clears it), and a split annotation becomes separate
  annotations with separate ids rather than fragments that overwrite each other.
- **Tamper tests.** Two new `WriterStorageTests` cases assert that rewriting a
  record's `origin` and an annotation's `range_upper` both break authenticated
  decryption (`HistoryError.corrupt`).
- **Removed an unrequested dead file.** `EditorStatus.swift` was never referenced
  and was absent from the generated project; it was removed rather than shipped
  as unused surface.

The AAD version bump changes the journal's on-disk framing. The journal is new in
Stage 03 and unreleased, so no migration path is required; a database written by
the earlier Stage 03 code is now correctly reported as corrupt rather than
silently reinterpreted.

### M17 route inventory (each route to its gateway entry)

| Observed route | Delivery observed | Recorded cause |
| --- | --- | --- |
| Typing / insertion at the caret | `insertText` with no marked text | `directNativeInput` |
| Input-method composition | `setMarkedText` | `nativeIMEUpdate` (no revision published) |
| Input-method commit / `unmarkText` | held-composition latch | `nativeIMECommit` |
| Spelling acceptance | `changeSpelling` | `knownAssistance(.spelling)` |
| Cut | `cut` | `cut` |
| Copy then in-app paste | private ancestry token + payload equality | `internalCopy` / `internalMove` |
| External paste | no matching private token | `pasteExternal` |
| Drag and drop | `performDragOperation` | `drop` |
| Native undo / redo | `NSUndoManagerDidUndo/RedoChange` | `undo` / `redo` |
| Formatting command, managed image link | `performProgrammatic(origin: .formatting)` | `formatting` |
| Find bar replace / replace-all | `performFindPanelAction`, declared | `findReplace` |
| File open / external adoption / recovery | `applyObserved(..., .descriptiveOnly)` | `externalReload` / `recover` |
| Unattributable change | no delivery, no declaration | `unknown` to `CaptureGap(opaqueInput)` |

## Commands actually run and results

| Command (repository root unless noted) | Result |
| --- | --- |
| `python3 tools/check_preparation.py` | PASS - frozen protocol 69 files, 67 inventoried, `freeze_sha256 c04ded3b...d88`, snapshot 326 files, 60 acceptance definitions retained |
| `python3 tools/bootstrap_protocol.py` | PASS - same freeze identity; read-only verification |
| `git status --porcelain protocol/ history/` | empty - frozen protocol and history bytes unchanged |
| `swift test --package-path mac/Packages/WriterStorage --scratch-path mac/.build/WriterStorage` | **126 tests, 2 skipped, 0 failures** (includes the two new tamper tests) |
| `xcodebuild ... -only-testing:NostrWriterTests/Stage03EditorTests -only-testing:NostrWriterTests/ShellTests` | **26 tests, 1 skipped, 0 failures** - `Stage03EditorTests` 13/0; `ShellTests` 13 with 1 skip (`testExternalChangesPreserveBothSourcesAndRejectUnreviewedSave`, helper env missing) |
| `xcodebuild -project NostrWriter.xcodeproj -scheme NostrWriter -configuration Debug -derivedDataPath .build/SignedDevelopment -destination platform=macOS -skipPackagePluginValidation ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build` | **BUILD SUCCEEDED**; ad-hoc sign; only pre-existing `#selector`-style warnings |

Not re-run in this revision because nothing they cover changed: the
WriterFoundation suite (135 tests, 0 failures; last run at `e96e72d`, and that
package is untouched by the later commits) and the coordinated-writer
conflict-regression helper. The recorded performance measurement (100,008 words /
540,600 bytes; outline 27.0 ms; edit p95 45.7 ms, max 45.8 ms) is from the first
recorded run; no code on that path changed.

Logs live in `product/mac/evidence/logs/stage-03/`
(`xcodebuild-candidate-build-61d3dbd.log` is this revision's candidate build).

## Native observations

Interaction was driven against the real candidate with a synthetic fixture
(`logs/stage-03/editor-fixture.md`); no private draft was recorded.

At the final candidate `95efbeca...` it was observed on 2026-09-18 that launching
the app with the fixture produced a real window titled `editor-fixture.md` at
1120x760 (origin 304,195). **Pixel capture of that window is BLOCKED**: the
capturing process has no Screen Recording permission (`screencapture` returned
"could not create image from display"). The instance was quit afterwards.

The four screenshots below were captured earlier at 16:52 against the predecessor
candidate `e7673cf3...` (built 16:41:49), which predates the consent-lifecycle
and gateway changes. They are retained as partial layout evidence only, **not as
current-build observations**:

| Artifact | Observation |
| --- | --- |
| `editor-1120x760-light.png` | Real window titled `nw-s3-fixture.md` at 1120x760 in light appearance; exact Markdown source, heading/blockquote/inline-code emphasis, sidebar/tab bar/toolbar and a status line ("41 words - Saved to tmp") laid out without clipping. Banner reads "Recovery unavailable. Save your document to a file; your text is still editable."; indicator reads "Recording off". |
| `editor-1120x760-dark.png` | Same window in dark appearance; source, emphasis colours and status text stay legible. |
| `editor-760x556-light.png` | Window constrained to 760 pt width; the measure narrows and long lines wrap; nothing clips or overlaps. |
| `editor-native-input-light.png` | Real system key events inserted `Typed natively into Stage 03.`; the word count moved 41 to 46 and the status changed `Saved to tmp` to `Unsaved`. |

## Acceptance results (M14-M21)

| ID | Status | Evidence and exact gap |
| --- | --- | --- |
| M14 | **BLOCKED** | Partial: real window, typography, chrome, measure adaptation and contrast were observed at 1120x760 (light and dark) and at 760 pt width, with real native typing (screenshots above, predecessor candidate), and the final candidate is confirmed to open a real 1120x760 window. Not observed: the Settings preferences window, Reduce Motion behaviour, focus mode and typewriter scrolling interaction, outline-popup navigation, and the full keyboard matrix, and no current-build pixel capture is possible without Screen Recording permission. These need an interactive owner-visible GUI session. |
| M15 | **PASS** | `testFormattingAndFindReplaceUseTheirOwnCausesAndPreserveBytes`, `testOneTypedMutationProducesExactlyOneRevision` and `testMarkedTextIsNotCommittedAsARevision` pass; the 1,000-operation Unicode replay (`seed=1592591107`, final 420 bytes, byte-equality after every operation) passes; the ShellTests undo paths still pass; the 100,008-word / 540,600-byte fixture measured outline 27.0 ms, edit p95 45.7 ms, max 45.8 ms; real typing preserved exact source. |
| M16 | **BLOCKED** | The composition unit path passes (`testMarkedTextIsNotCommittedAsARevision`: marked text publishes no revision, the commit is classified `nativeIMECommit`, and the case reports BLOCKED when the headless host has no marked-text support). The required real input matrix - US and German layouts, dead keys, at least one real IME, emoji and RTL - was not performed. Needs an owner-visible session with the German and CJK input sources enabled. |
| M17 | **PASS** | The route inventory above is tied to implementation; `testGatewayClassifiesObservedDeliveryWithoutGuessingFromText` covers every delivery including `unknown`; `testOneTypedMutationProducesExactlyOneRevision` proves a duplicate delegate callback publishes no second revision; `testInputPolicyRefusesExternalInsertionLocally` proves the Stage 07 seam refuses external insertion without global interception. |
| M18 | **BLOCKED** | Deterministic parts verified: continuous spell checking on, automatic spelling correction / text replacement / quote / dash substitution / text completion all off, `writingToolsBehavior = .none` on macOS 15+, and spelling acceptance classified `knownAssistance(.spelling)`. The required native spell-correction and Services/Writing-Tools observations were not performed and need an owner-visible session. |
| M19 | **BLOCKED** | Deterministic anchor/cancellation rules pass (`testDictationAnchorCancelsRatherThanOverwritingLaterText`). Real on-device recognition needs a microphone, spoken audio and speech-recognition permission, so it needs an owner session; denial/unavailable/error paths were not exercised live. |
| M20 | **BLOCKED** | Deterministic lineage verified (`testAnnotationsShiftThroughEditsAndRemovalKeepsSource`: an insertion at index 0 shifts the annotation exactly, replacing its wording marks it stale rather than moving the exclusion, removal leaves source intact; staleness is now sticky and split fragments get distinct ids). The inspector UI and an actual annotation interaction were not captured - the agent could not open the inspector in this session - so the required actual interaction is outstanding. |
| M21 | **BLOCKED** | Deterministic parts verified: `testObservationHandleHonoursConsentBoundaries` (recording off gives no handle; gap/paused/limit give an honest nil; observing gives a handle bound to the exact source) and the `WriterStorageTests.HistoryJournalTests` (round-trip, encryption at rest, wrong key, capacity pause without stopping writing, delete-history leaves recovery intact, and the two new interpretation-tamper cases). The live off/on/pause persistence check could not run: the ad-hoc candidate has no keychain access group, so the app itself reported "Recovery unavailable" and the encrypted journal could not be opened. Needs a properly signed candidate. |

## Blockers (exact missing access, input or decision)

1. **Signing identity.** `security find-identity -v -p codesigning` returns 0
   valid identities on this host. Restore the owner's existing Apple Development
   identity/profile (no new certificate or account should be created) and rebuild
   with `WRITER_DEVELOPMENT_TEAM=<team>` via
   `mac/scripts/build_signed_development.sh`. This is required for M21's live
   consent/journal checks and for any claim about real recovery in this build.
2. **Screen Recording permission.** The capturing process cannot take screen
   images (`screencapture` fails with "could not create image from display"), so
   M14's current-build pixel evidence cannot be produced. Grant Screen Recording
   to the observing app, or capture the window during an owner-visible session.
3. **Interactive GUI session (owner-visible).** M14's remaining checks (Settings
   preferences, Reduce Motion, focus/typewriter, outline navigation, keyboard
   matrix) and M20's annotation interaction need an attentive session on the
   console; scripted AX/coordinate control was only partly effective here.
4. **Input-method matrix.** M16 needs the German and at least one CJK input
   source enabled and typed into the editor, plus emoji and RTL.
5. **Spell/assistance session.** M18 needs an actual spelling correction and a
   Services/Writing Tools availability check.
6. **Microphone and human speech.** M19 needs a supported on-device locale,
   granted microphone/speech permission and spoken input, then a denial/error
   replay.

## Independent work completed while blocked

Source, tests and evidence above: the mutation gateway, the finished editor
surface, assistance/annotation/dictation logic, consented encrypted history
wiring and the interpretation-authentication repair - plus the deterministic
suites and the rebuilt candidate. No production HWP approval is claimed; the
production approval set stays empty and the app shows only the contracted NOT
PROVABLE message.

## Stage 04 handoff

The descriptive journal schema (`HistoryJournal`, schema v3; AAD version 2),
`LocalEditRecord`, `CaptureEpoch`, `CaptureGap`, `SourceLineage` and
`SourceAnnotation` are real, tested interfaces with fixture logs under
`logs/stage-03/`. Stage 04 receives honest typed records and the unchanged empty
production approval state, not a claim that software-only capture authenticates a
human source. Unfinished here: the live consented-history round trip and every
owner-observed input method.
