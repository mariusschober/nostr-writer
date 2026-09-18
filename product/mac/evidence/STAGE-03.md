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
| Implementation commits | `e96e72d67288fe74d0517da285c2684e1fdb3947`, `17cb7523eaab35697e911be4b3bc895da37a857b`, `3f35d6df1c773483c21a51ab5fe8bf97e0f3762e`, `b77a0bba410845738af1fb1fb954c8307d08967b`, `61d3dbdae9879a5030fdb67a54dc7ea4885eb9cc`, `1ddd3210dd4fada8a225caa13f993331e571e682` (the Settings-window fix), `e78543906d37a285f6989079069138cdbf7d573d` (the native-assistance, undo-count and saved-status repairs) |
| Evidence commits | `4ae1454015a60cc15a654a89557771f0b3e57856` (first M14-M21 record and logs), `751879ef2dcef131a5287f7c9ae114137fa99719`, `9b4a18db4fa6b7323ae62c35133cbef6e078ed81`, the evidence refresh for the `e785439` repairs, and the commit adding this revision (reported in the handoff, since a commit cannot contain its own hash) |
| Candidate executable | `mac/.build/SignedDevelopment/Build/Products/Debug/NostrWriter.app/Contents/MacOS/NostrWriter` |
| Candidate SHA-256 (current) | `d2f868cb9507e73671ec52264018e070ee3dad362ab6d9919e7ab3c93deaa20b` |
| Candidate SHA-256 (intermediate) | `89313db33f0a04efb7b2d07251efbbab7e10f2a67ac368ee8926b8c10602b529` |
| Candidate SHA-256 (earlier) | `95efbecaecdb4fb607c7a051762226c6502b4aade82edae77341e385ef0f955f` |
| Candidate arch / signature | arm64, ad-hoc ("Sign to Run Locally"), identifier `com.mariusschober.nostrwriter.development` |
| Candidate build times | current 2026-09-18 22:22:05 +0100 (native-assistance repair); earlier 18:01:13 +0100 (settings fix) and 17:41:08 +0100 |

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

### Defect found and fixed: the Settings window collapsed to 180x64

Opening Settings (Cmd+,) in the running candidate produced a window of
180x64 pt instead of the intended 540x470, so the preferences were unusable.
Assigning an `NSHostingController` as the window's `contentViewController` let
AppKit resize the window down to the SwiftUI view's intrinsic size. Setting
`host.sizingOptions = []` and re-applying `setContentSize` restores the panel;
System Events then measured the Settings window at 540x502 (titlebar included).
This is a real Stage 03 defect that the first evidence pass had recorded only as
"not observed", so it is fixed rather than deferred. The candidate was rebuilt
after the fix (`logs/stage-03/xcodebuild-candidate-build-9b4a18d-settings.log`).

### Repairs at `e785439` and the second native session

The second session on the frozen candidate found four real defects and closed the
previous session's largest evidence gap. The repairs are all in
`e78543906d37a285f6989079069138cdbf7d573d` and the candidate was rebuilt from
them (`d2f868cb...`, 22:22:05 +0100).

1. **Services were unreachable.** The menu bar is built programmatically, and an
   `NSMenu` assembled in code has no Services submenu unless the app supplies
   one, so none of the system Services - including translation of a selected
   passage - could be reached. `AppMenus` now adds an empty Services item,
   assigns its submenu to `NSApp.servicesMenu` and lets AppKit populate it. The
   running candidate reports nine populated items
   (`logs/stage-03/services-menu-observation.txt`).
2. **The Edit menu had no Spelling and Grammar submenu**, so the standard native
   spelling routes were not reachable either. `AppMenus` now adds
   Show Spelling and Grammar (which reaches the shared `NSSpellChecker` panel
   through `AppDelegate.showSpellingAndGrammar`), Check Document Now,
   Check Spelling While Typing, Check Grammar With Spelling and
   Correct Spelling Automatically.
3. **Grammar checking was never enabled.** `WriterWindowController.install` now
   sets `editor.isGrammarCheckingEnabled = true`. Continuous spell checking was
   already on; automatic correction, text replacement, quote/dash substitution
   and text completion remain off.
4. **Undo left the document looking modified.** `applyObserved` called
   `updateChangeCount(.changeDone)` for every mutation, so undoing every edit
   still reported an unsaved document. It now calls `.changeUndone` when the
   origin is `.undo`.
5. **"Saved" was decided by revision identity, not bytes.** After an undo the
   status still read "Unsaved" even when the buffer matched the file. It now
   compares the saved snapshot's `documentID` and exact UTF-8 bytes.

The same session produced the native assistance and keyboard evidence that the
first pass could not:

- **Native spelling correction** (M18). With the app default, typing `teh `
  into an empty document left exactly `teh ` (4 bytes, `7465 6820`) - the
  negative control. After choosing Edit > Spelling and Grammar > Correct
  Spelling Automatically, the same keystrokes produced `The `. A real system
  correction ran inside the app's text view. The session also confirmed the
  Edit menu's Spelling and Grammar and Writing Tools submenus, Look Up and
  Translate for the word under the caret in the contextual menu, and the nine
  populated Services items. Details, including what was *not* exercised and why:
  `logs/stage-03/spelling-and-services-observation.txt`.
- **Keyboard matrix** (M14). The computer-use `press_key` path does not apply
  modifier flags - three probes with `["cmd"]`, `["command"]` and `["Cmd"]`
  each delivered a bare `f` and typed it into the fixture, which was then undone
  through the app's own Edit > Undo Typing. System Events *does* deliver
  modifiers, so the matrix was driven as real key events: Cmd+N created a
  document; Cmd+Z undid typed characters back to "0 words"; Cmd+Shift+F engaged
  View > Focus Writing (sidebar and toolbar gone from the accessibility tree,
  splitter at 0, status line and recovery banner retained) and toggled back; and
  Ctrl+Cmd+F entered native fullscreen (the window close/minimise buttons
  disappeared) and toggled back. View > Typewriter Scrolling was toggled on and
  off from the menu without error. Transcript:
  `logs/stage-03/keyboard-matrix-observation.txt`.
- **Non-ASCII input** (M16). System Events keystroke of Hebrew text and of an
  emoji arrived as real key events but the active German layout resolved each
  character to a plain letter, producing `aaaa aa`. No emoji, RTL or CJK input
  source is enabled on this host, so those tokens still cannot be entered
  natively here.

Both sessions' failures are kept above rather than smoothed over: the
`press_key` modifier limitation and the accidental `f` insertion are recorded
because they are how the technique was ruled out, and the fixture text was
verified restored afterwards.

### Native input matrix on the frozen candidate

With the German keyboard layout active (the host's enabled input sources are the
German layout plus PressAndHold, CharacterPalette and Ironwood), real key events
were delivered to the focused editor by activating the app and sending the
keystrokes inside the same `System Events` script, because tool calls otherwise
hold focus. The editor received `german:äöüß circumflex:ê acute:é end` exactly:
`ä ö ü ß` as direct layout characters, and `^`+`e` and `´`+`e` as real dead-key
compositions that pass through marked text and commit to `ê` and `é`
(`logs/stage-03/input-matrix-deadkeys.jpeg`). That is genuine native composition
rather than a synthetic delegate call. The text was typed into the app's untitled
scratch buffer and was not saved, so the screenshot is the evidence;
`logs/stage-03/input-matrix.md` is the seed fixture for this check. Emoji, an RTL
script and a full CJK input method were not performed.

Driving `Typewriter Scrolling`, `Toggle Inspector` and `Toggle Sidebar` through
the app's own View menu by accessibility produced no observable change in this
harness (the window's accessibility roles were unchanged), so those three are
unverified rather than judged either way. `Reduce Motion` was likewise not
exercised.

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
| The same `-only-testing` invocation, re-run on the `e785439` repair tree | **26 tests, 1 skipped, 0 failures** - `Stage03EditorTests` 13/0. Nothing else was re-run because the earlier WriterFoundation, WriterStorage, performance and conflict-helper results are unaffected by a menu/undo-count repair |
| `xcodebuild -project NostrWriter.xcodeproj -scheme NostrWriter -configuration Debug -derivedDataPath .build/SignedDevelopment -destination platform=macOS -skipPackagePluginValidation ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build` | **BUILD SUCCEEDED**; ad-hoc sign; only pre-existing `#selector`-style warnings |

Not re-run in this revision because nothing they cover changed: the
WriterFoundation suite (135 tests, 0 failures; last run at `e96e72d`, and that
package is untouched by the later commits) and the coordinated-writer
conflict-regression helper. The recorded performance measurement (100,008 words /
540,600 bytes; outline 27.0 ms; edit p95 45.7 ms, max 45.8 ms) is from the first
recorded run; no code on that path changed.

Logs live in `product/mac/evidence/logs/stage-03/`
(`xcodebuild-candidate-build-61d3dbd.log` and, after the Settings fix,
`xcodebuild-candidate-build-9b4a18d-settings.log`).

## Native observations

Interaction was driven against the real candidate with a synthetic fixture
(`logs/stage-03/editor-fixture.md`); no private draft was recorded.

The app was observed on 2026-09-18 through the Codex computer-use runtime, which
resolved and drove the signed-development candidate by path. Shell `screencapture`
remains unavailable on this host ("could not create image from display"), but the
runtime's own capture path works. The captures below were taken with the fixture
loaded: the light pass and the annotated span at candidate `95efbeca...` (built
17:41:08), the Settings panel at `89313db3...` (built 18:01:13, after the fix),
and the dark pass at the same current candidate:

| Artifact | Observation |
| --- | --- |
| `editor-1120x760-light-candidate.jpeg` | Real window titled `editor-fixture.md` at 1120x760 in light appearance; exact Markdown source on a centred measure in monospaced type, with heading (`#`/`##`), bold, inline-code, blockquote and code-fence colouring; sidebar (Open/Recent), tab bar, toolbar (Headings, Formatting, Dictate, Focus, Toggle Inspector, Preview & Export, Publish) and a status line ("41 words - Saved to stage-03") laid out without clipping or overlap. Banner reads "Recovery unavailable. Save your document to a file; your text is still editable."; indicator reads "Recording off". |
| `editor-inspector-open.jpeg` | The passage inspector toggled open: RECORDING "Recording off / No detailed revisions or deleted text are stored" with Pause/Resume and Delete Local History; DICTATION Off; SELECTED PASSAGE with Category (Quotation), Source description, Optional URL and "This material is not claimed as freshly composed."; MARKED SPANS "No marked spans."; HUMAN WRITING PROOF "NOT PROVABLE - no approved Mac capture profile and model are installed. This is not a judgment about who wrote your text." |
| `editor-inspector-marked-span.jpeg` | The blockquote passage was selected and marked as an external source (Quotation, description "Unattributed quotation for the Stage 03 fixture."). MARKED SPANS then read "Unattributed quotation for the Stage 03 fixture. / Quotation - bytes 109-147" with a remove control. |
| `editor-inspector-marked-span-after-edit.jpeg` | One character typed at the document start re-mapped the marked span to "Quotation - bytes 110-148" (an exact +1 shift), and the status changed to "41 words - Unsaved". |
| `settings-window-fixed.jpeg` | The Settings panel after the fix, measured at 540x502: Editor section with Typeface "System Mono", Size 18 pt, Measure 72 chars, a Focus segmented control (Off/Sentence/Paragraph), Typewriter scrolling off, and the note "Presentation only. The exact source bytes are never rewritten by these preferences."; Recording & Privacy with "Store writing history on this Mac" off and its explanation. |
| `editor-dark-candidate.jpeg` | The same 1120x760 window in **dark appearance** (the system was switched to Dark for the observation and restored to Light afterwards). The whole editor follows the dark system appearance - dark window chrome, sidebar, tab bar and editor surface - with the same exact source and the heading, bold, inline-code, blockquote and code-fence colours still legible against the dark background; toolbar, status line, recovery banner and "Recording off" indicator are unchanged. |
| `editor-760x556-dark-candidate.jpeg` | The window resized to its minimum frame (760x556: the contracted 760x520 content height plus the 36 pt titlebar) in dark appearance. The editor re-wraps the source instead of clipping, the sidebar narrows, the toolbar condenses its trailing controls into an overflow chevron, and the status line stays intact - the measure adapts rather than forcing horizontal truncation. |

With the fixture loaded, the native find bar was opened with Cmd+F (search field,
Replace checkbox, find next/previous) and accepted a literal query; the document
source was unchanged by the search. Native undo was exercised through the app's
own Edit menu: two characters typed at the end of the document registered a
single **"Undo Typing"** item, the menu reported it enabled, and choosing it
restored the exact fixture (41 words, caret at the end) while the on-disk file
was never written. That accidental in-memory edit and its undo are recorded here
rather than omitted. Modifier-combo shortcuts other than Cmd+F did not reach the
app through this session's computer-use `press_key` path (Cmd+Z, Ctrl+Cmd+S and a
plain letter combination produced no state change), so the remaining keyboard
matrix is left for an owner session rather than inferred from a harness artefact.

Outline navigation was exercised live: the toolbar Headings menu listed
"Stage 03 Fixture" with nested "Section One" and "Section Two" (each exposing
`navigateToHeading:`), and choosing "Section Two" moved the caret to that heading
without changing the document (the status stayed "41 words - Saved to
stage-03"). Focus Writing (Cmd+Shift+F) collapsed the sidebar and toolbar to a
full-width editor while keeping the status line and recovery banner; the
accessibility tree for that state contains only the editor split group. Those two
observations are recorded from the accessibility tree because the computer-use
runtime prunes its temporary screenshots.

The earlier recorded screenshots were captured at 16:52 against the predecessor
candidate `e7673cf3...` (built 16:41:49) and are retained as partial evidence
only, not as current-build observations: `editor-1120x760-light.png` and
`editor-1120x760-dark.png` (light and dark layout at 1120x760),
`editor-760x556-light.png` (760 pt width) and `editor-native-input-light.png`
(real key events typed text; word count 41 to 46; status "Saved to tmp" to
"Unsaved").

## Acceptance results (M14-M21)

| ID | Status | Evidence and exact gap |
| --- | --- | --- |
| M14 | **BLOCKED** | Everything except Reduce Motion is now observed. Live on the candidate: a 1120x760 light window with exact Markdown source, typography, measure, emphasis colours, sidebar, tab bar, toolbar and status line; the same window in dark appearance at 1120x760 and at the minimum 760x556 frame; the passage inspector; the Settings panel at 540x502 after fixing a real 180x64 collapse defect; outline-popup navigation that moved the caret to the chosen heading; Focus Writing; the native find bar without changing the source; and native undo restoring the exact fixture. Driven as real System Events key events: Cmd+N, Cmd+Z, Cmd+Shift+F (Focus Writing - sidebar and toolbar gone from the accessibility tree, status and recovery banner retained) and Ctrl+Cmd+F (native fullscreen - window buttons gone). View > Typewriter Scrolling toggled on and off without error. Reduce Motion is the one remaining item: the app reads `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` in `typewriterScroll()` (`WriterWindowController.swift:293`), the host has the setting off, and the accessibility domain refuses a programmatic change (`defaults write com.apple.universalaccess reduceMotion` -> "Could not write domain"), so an owner must switch it on in System Settings before the scroll-offset difference is measurable. |
| M15 | **PASS** | `testFormattingAndFindReplaceUseTheirOwnCausesAndPreserveBytes`, `testOneTypedMutationProducesExactlyOneRevision` and `testMarkedTextIsNotCommittedAsARevision` pass; the 1,000-operation Unicode replay (`seed=1592591107`, final 420 bytes, byte-equality after every operation) passes; the ShellTests undo paths still pass, and native `Edit > Undo Typing` restored the exact fixture after live typed characters; the 100,008-word / 540,600-byte fixture measured outline 27.0 ms, edit p95 45.7 ms, max 45.8 ms; real typing preserved exact source. |
| M16 | **BLOCKED** | Real native input was observed on the candidate with the German keyboard layout active: `ä ö ü ß` typed exactly, and two genuine dead-key compositions completed through marked text - `^` then `e` produced `ê`, and `´` then `e` produced `é` - captured in `logs/stage-03/input-matrix-deadkeys.jpeg`. The composition unit path also passes (`testMarkedTextIsNotCommittedAsARevision`: marked text publishes no revision, the commit is classified `nativeIMECommit`), and exact astral/combining offset handling is covered by the 1,000-operation Unicode replay. Still not performed: an emoji, an RTL script, and a full CJK input method. Re-probed this session: System Events keystroke of Hebrew text and of an emoji arrived as real key events but the active German layout resolved each character to a plain letter, producing `aaaa aa`; no emoji, RTL or CJK input source is enabled on this host (enabled: German layout, CharacterPalette, Ironwood, PressAndHold), and adding one needs System Settings. |
| M17 | **PASS** | The route inventory above is tied to implementation; `testGatewayClassifiesObservedDeliveryWithoutGuessingFromText` covers every delivery including `unknown`; `testOneTypedMutationProducesExactlyOneRevision` proves a duplicate delegate callback publishes no second revision; `testInputPolicyRefusesExternalInsertionLocally` proves the Stage 07 seam refuses external insertion without global interception. |
| M18 | **PASS** | Continuous spell checking is on (the misspelled token drew the red spelling underline) and grammar checking with spelling is now enabled by `e785439`; the Edit menu exposes Spelling and Grammar (Show Spelling and Grammar, Check Document Now, Check Spelling While Typing, Check Grammar With Spelling, Correct Spelling Automatically) and a Writing Tools submenu where previously there was no Spelling submenu; the editor's contextual menu offers Look Up and Translate for the word under the caret; the application menu has a populated Services submenu (9 items); and a real correction ran - at the default, typing `teh ` left exactly `teh ` (`7465 6820`), while after enabling Correct Spelling Automatically from the app's own menu the same keystrokes produced `The `. Provenance stays exact: `NSTextView.changeSpelling(_:)` is classified `knownAssistance(.spelling)` and an opaque mutation stays unknown, both asserted by `testGatewayClassifiesObservedDeliveryWithoutGuessingFromText`. Scope note: the native correction was the automatic path; the user-accepted panel/suggestion path is covered deterministically but was not reachable in this harness because the shared `NSSpellChecker` panel is not reported as a window and the suggestion menu did not appear for a caret or find-bar selection. See `logs/stage-03/spelling-and-services-observation.txt`. |
| M19 | **BLOCKED** | Deterministic anchor/cancellation rules pass (`testDictationAnchorCancelsRatherThanOverwritingLaterText`). `system_profiler SPAudioDataType` reports **no audio devices at all** on this host (re-checked this session), so real on-device recognition cannot be exercised here whatever the permission state: the exact missing access is an audio input device, plus a supported on-device locale and granted microphone/speech permission. The denial/unavailable/error paths were likewise not exercised live and need the owner session. |
| M20 | **PASS** | Observed in the running app: the passage inspector opened; selecting the blockquote populated SELECTED PASSAGE; filling a source description enabled "Mark External Source"; marking created a span shown as "Quotation - bytes 109-147"; and one character typed at the document start re-mapped it to "bytes 110-148" (an exact +1 shift). `testAnnotationsShiftThroughEditsAndRemovalKeepsSource` deterministically covers the shift, stale-on-replacement, removal, sticky staleness and distinct split ids; the inspector's HUMAN WRITING PROOF section shows the contracted NOT PROVABLE message and the passage notice says the material "is not claimed as freshly composed", so the UI does not imply human certainty. |
| M21 | **BLOCKED** | Deterministic parts verified: `testObservationHandleHonoursConsentBoundaries` (recording off gives no handle; gap/paused/limit give an honest nil; observing gives a handle bound to the exact source) and the `WriterStorageTests.HistoryJournalTests` set (round-trip, encryption at rest, wrong key, capacity pause without stopping writing, delete-history leaves recovery intact, and the two new interpretation-tamper cases). The live off/on/pause persistence check remains unobservable. `DocumentRecovery.openStore()`/`openHistory()` read `keychain-access-groups`, falling back to `com.apple.application-identifier`/`application-identifier`, and an ad-hoc build carries neither, so the consented journal throws `RecoveryKeyError.unavailable` before any live check can run. Two controlled experiments established *why* rather than assuming: re-signing a throwaway copy of the candidate ad-hoc **with** a `keychain-access-groups` entitlement makes macOS refuse to launch it (launchd `POSIX 163`) both with and without `app-sandbox`, while the identical re-sign **without** that entitlement launches normally - so macOS requires a real signing identity for the access group. `security find-identity -v -p codesigning` returns 0 identities (re-checked this session), and querying `login.keychain-db` explicitly also returns 0, so no Apple Development identity is currently present. A previously provisioned marker shows this worked earlier: `~/Library/Containers/com.mariusschober.nostrwriter.development/Data/Library/Application Support/NostrWriter/Development/bootstrap.json` records `accessGroup "6R2578FWBR.com.mariusschober.nostrwriter.development"`, `ready: true`. Restoring that existing identity and rebuilding with `mac/scripts/build_signed_development.sh` is the exact missing access. |

## Blockers (exact missing access, input or decision)

1. **Signing identity.** `security find-identity -v -p codesigning` returns 0
   valid identities on this host. Restore the owner's existing Apple Development
   identity/profile (no new certificate or account should be created) and rebuild
   with `WRITER_DEVELOPMENT_TEAM=<team>` via
   `mac/scripts/build_signed_development.sh`. This is required for M21's live
   consent/journal checks and for any claim about real recovery in this build.
2. **Reduce Motion only.** M14 is otherwise fully observed live. The app reads
   `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` in
   `typewriterScroll()`. The setting is off on this host and cannot be changed
   from here: `defaults write com.apple.universalaccess reduceMotion -bool true`
   is refused with "Could not write domain com.apple.universalaccess" (the
   accessibility domain is system-managed), and the key is still absent
   afterwards. The candidate's screenshots are readable - the computer-use
   runtime returns them as a file URL under the per-user temp directory - so the
   only missing piece is the owner switching Reduce Motion on in System Settings,
   after which the scroll-offset difference during typewriter scrolling is
   directly measurable.
3. **Keyboard matrix - resolved.** The limitation recorded in the previous
   revision is gone. System Events keystroke does deliver modifier keys, so
   Cmd+N, Cmd+Z, Cmd+Shift+F and Ctrl+Cmd+F were all exercised as real key
   events. Only the computer-use `press_key` path ignores modifier flags, which
   is why earlier probes typed bare letters; that is recorded, not carried
   forward as a gap.
4. **Input-method matrix.** M16 still needs an emoji, an RTL script and a full
   CJK input method. No such input source is enabled on this host and adding one
   needs System Settings (and usually a session restart); System Events keystroke
   of non-ASCII characters resolves through the German layout to plain letters.
5. **Spell/assistance session - M18 accepted with a stated scope.** A native
   spelling correction ran and the Services/Translation and Spelling routes are
   reachable in the running candidate. The only unperformed part is the
   user-accepted suggestion/panel correction, whose classification is covered
   deterministically; the shared `NSSpellChecker` panel is not exposed to the
   accessibility layer on this host.
6. **Microphone and human speech.** M19 needs an audio input device first -
   `system_profiler SPAudioDataType` reports no devices at all on this host - then
   a supported on-device locale, granted microphone/speech permission and spoken
   input, then a denial/error replay.

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
human source.

Unfinished here, each with its exact missing input: the live consented-history
round trip (a real signing identity for the keychain access group); Reduce Motion
(the system setting plus a measurable scroll comparison); native emoji/RTL/CJK
input and a real user-accepted spelling correction (an enabled input source and a
reachable spelling panel); and on-device dictation (an audio input device).
