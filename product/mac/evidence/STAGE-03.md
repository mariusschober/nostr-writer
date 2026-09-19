# Stage 03 evidence - editor, assistance and local writing history

Status: **BLOCKED** (implementation complete, compiling, hardened and
deterministically verified; the live consented-history path and the full native
input matrix now pass on properly signed candidates; one mandatory owner-visible
observation is outstanding). `accepted: false`. Acceptance: M14, M15, M16, M17,
M18, M20 and M21 PASS; M19 BLOCKED on owner input rather than on code. Two
residuals are recorded rather than hidden: the live Reduce Motion system-toggle
differential (the branch itself is tested), and the owner session for real
on-device dictation (its gate ordering, refused-grant states and late-callback
rejection are tested).

Revision note (2026-09-19): M21 moved from BLOCKED to PASS after the signed
candidate was built and exercised; two earlier blocker claims (no code-signing
identity, no audio devices) were corrected after being re-derived outside the
sandbox. M16 then moved from BLOCKED to PASS after the emoji, RTL and CJK rows
were re-derived against the input sources actually enabled on this host, and M14
moved from BLOCKED to PASS after the Reduce Motion branch was extracted into the
pure `TypewriterScrollPlan` and covered by a test while typewriter scrolling was
observed live on the rebuilt candidate. M19 stayed BLOCKED but its deterministic
evidence was completed: the permission gate is now injectable, the session
identity is a monotonic non-reusable token, and six tests cover the unsupported,
denied-speech, denied-microphone, late-callback and superseded-session paths.

| Reference | Value |
| --- | --- |
| Predecessor handover tip | `c1aafc90115e431fdbf7df79f67c120ae470a94a` |
| Accepted Stage 02 checkpoint | `b8568c09530b90e28a3d1fb817335c6a980fc116` |
| Accepted Stage 02 app source | `67302883935fcfaba2b9668a04df3aee60820fcd` |
| Stage 03 branch | `implementation/stage-03` |
| Implementation commits | `e96e72d67288fe74d0517da285c2684e1fdb3947`, `17cb7523eaab35697e911be4b3bc895da37a857b`, `3f35d6df1c773483c21a51ab5fe8bf97e0f3762e`, `b77a0bba410845738af1fb1fb954c8307d08967b`, `61d3dbdae9879a5030fdb67a54dc7ea4885eb9cc`, `1ddd3210dd4fada8a225caa13f993331e571e682` (the Settings-window fix), `e78543906d37a285f6989079069138cdbf7d573d` (the native-assistance, undo-count and saved-status repairs), `154f34effbef9423566f728c88757598e9e15c6f` (the testable typewriter-scroll decision and its Reduce Motion test), `d8745dcfabdcea5c9a07ea669bf91b62da5306fa` (the testable dictation gate, session token and their checks) |
| Evidence commits | `4ae1454015a60cc15a654a89557771f0b3e57856` (first M14-M21 record and logs), `751879ef2dcef131a5287f7c9ae114137fa99719`, `9b4a18db4fa6b7323ae62c35133cbef6e078ed81`, the evidence refresh for the `e785439` repairs, `ee393a3` (the raw signed consent/history session log), `b15c21b` (M14 and M16 cleared, M19 narrowed), `77d1053` (the completed M19 deterministic evidence and the new candidate), `d83fde3` (the exposed accessibility contract and the OS input capability facts), and the final commit that carries this list (reported in the handoff, since a commit cannot contain its own hash) |
| Candidate executable | `mac/.build/SignedDevelopment/Build/Products/Debug/NostrWriter.app/Contents/MacOS/NostrWriter` |
| Candidate SHA-256 (current) | `53813d4134258e62b107b23ed5471c08b1507380bad2903ca228d785625ac390` |
| Candidate SHA-256 (previous) | `8d0f7f5c83b37dd69718659dc70a05a6d923fa4313aa74f34b9fb7c3b83c1627` |
| Candidate SHA-256 (earlier signed) | `436d43caa1f0b0beb8061572674b1a77d2ef926bad43ac1d047833d2bf626392` |
| Candidate SHA-256 (earliest signed) | `d2f868cb9507e73671ec52264018e070ee3dad362ab6d9919e7ab3c93deaa20b` |
| Candidate SHA-256 (intermediate) | `89313db33f0a04efb7b2d07251efbbab7e10f2a67ac368ee8926b8c10602b529` |
| Candidate SHA-256 (earlier) | `95efbecaecdb4fb607c7a051762226c6502b4aade82edae77341e385ef0f955f` |
| Candidate arch / signature | universal (x86_64 + arm64), minos 14.0, "Apple Development: mris@tuta.io (TVV48YYFPR)", TeamIdentifier `6R2578FWBR`, hardened runtime, strict verification PASS, identifier `com.mariusschober.nostrwriter.development` |
| Candidate build times | current 2026-09-19 09:27 +0100 (signed development build; differs from the previous candidate only by the dictation gate/session refactor); previous 2026-09-19 08:55:04 +0100 (the typewriter-scroll extraction); earlier signed 2026-09-18 23:25:04 +0100; intermediate 22:22:05 +0100; earliest 18:01:13 +0100; first 17:41:08 +0100 |
| Candidate build command | `WRITER_DEVELOPMENT_TEAM=6R2578FWBR mac/scripts/build_signed_development.sh` |

Environment: macOS 26.6.2 (25G83), Xcode 27.0 (27A266a), Swift 6.4, arm64.
`security find-identity -v -p codesigning` returns **1 valid identity** when
queried outside the sandbox - "Apple Development: mris@tuta.io (TVV48YYFPR)",
OU `6R2578FWBR`. The earlier "0 valid identities" result, and the earlier
"no audio devices at all" result, were both sandbox artefacts and are corrected
here; the owner's existing identity and audio hardware were already present.
The candidate was therefore rebuilt and signed with the owner's existing team,
and its entitlements are `app-sandbox`, `device.audio-input`,
`files.user-selected.read-write`, `get-task-allow`, `network.client`,
`application-identifier = 6R2578FWBR.com.mariusschober.nostrwriter.development`,
`developer.team-identifier = 6R2578FWBR` and
`keychain-access-groups = 6R2578FWBR.com.mariusschober.nostrwriter.development`.
Recovery and the consented history journal both open under it; see M21 and
Blockers.

Two candidate identities are in play and are kept distinct. The observations
recorded in the earlier Stage 03 sessions (editor surface, Settings fix, dark
appearance, find bar, keyboard matrix, spelling/Services, annotation
interaction) were made on the ad-hoc image `d2f868cb...`, which reported
"Recovery unavailable". The consent/history observations below were made on the
current signed image `436d43ca...`, which reports "Recovery up to date" for the
same window. No source changed between them; rerun only checks affected by a
source change.

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
  which inserts visible syntax through the gateway with a formatting origin, and
  `TypewriterScrollPlan`, the pure scroll decision `typewriterScroll()` calls
  with the system Reduce Motion flag.
- `WritePreferences.swift` - typography/measure/focus/typewriter preferences
  (13-32 pt, 50-100 chars) that never touch source bytes.
- `EditorOutline.swift` - pure ATX/Setext heading reader bound to a snapshot.
- `EditorInspector.swift` - passage inspector: recording state, gaps, exact-range
  annotations, an explicit "not claimed as freshly composed" notice and the
  contracted proof-absence message.
- `DictationController.swift` - optional, explicit, on-device dictation with a
  source-bound anchor, a monotonic never-reused session token
  (`DictationGeneration`), an injectable capability gate (`DictationGate`, whose
  `.live` value is the only one that touches TCC) and no silent cloud fallback.

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
- **Non-ASCII input** (M16) - resolved later in the same session. The first probe
  recorded that a System Events keystroke of Hebrew text and of an emoji arrived
  as real key events while the active German layout resolved each character to a
  plain letter, producing `aaaa aa`; that is kept because it is how the
  German-layout path was ruled out. Re-deriving the enabled input sources - the
  input menu lists German, Arabic, `2SetHangul` and `UnicodeHexInput`, not just
  the default layout - then produced a real emoji, real RTL Arabic and real
  Hangul. See "Native input matrix on the frozen candidate" below and
  `logs/stage-03/native-input-matrix-full.txt`.

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
`logs/stage-03/input-matrix.md` is the seed fixture for this check.

The remaining rows were added later in the same session and this time saved and
read back from the file's exact bytes: the Arabic layout produced six U+0634 for
the RTL row; `UnicodeHexInput` produced U+1F642 for the emoji row; and the Korean
input method, after the same keys had first landed as literal Latin `gksrmf`
because the IME was not composing, composed U+D55C U+AE00 and three U+314B jamo,
which were committed with Return and saved. Full matrix and byte evidence:
`logs/stage-03/native-input-matrix-full.txt`.

Driving `Typewriter Scrolling`, `Toggle Inspector` and `Toggle Sidebar` through
the app's own View menu initially produced no observable accessibility change, so
they were recorded as unverified rather than judged either way. Typewriter
Scrolling was later confirmed: on the final candidate `8d0f7f5c` the menu item
turned the preference on and off (`editorTypewriterScrolling` 1, then 0), and
with it on, typing at the end of a 62-line fixture moved the editor scroll bar
0 -> 1 while the saved file gained exactly the one typed character (3373 bytes).
`Reduce Motion` is the one M14 item that remains unmeasured; the exact owner step
is recorded under Blockers, and the branch itself is now covered by
`testTypewriterScrollPlanHonoursReduceMotionWithoutMovingText`.

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
| `xcodebuild ... -derivedDataPath mac/.build/NativeTestDerivedData -only-testing:NostrWriterTests/Stage03EditorTests` on the `154f34ef` tree | **14 tests, 0 failures** - the same editor class plus the new `testTypewriterScrollPlanHonoursReduceMotionWithoutMovingText` (a first attempt at just the new test failed to compile on a `CGFloat?`/`Double` mismatch and was fixed before this run). Only this class was re-run: the change is confined to the typewriter-scroll decision in the app target, and WriterStorage/WriterFoundation do not consume it |
| `WRITER_DEVELOPMENT_TEAM=6R2578FWBR mac/scripts/build_signed_development.sh` on the `154f34ef` tree | **strict_signature_verification PASS**, universal (x86_64 + arm64), minos 14.0, binary sha256 `8d0f7f5c83b37dd69718659dc70a05a6d923fa4313aa74f34b9fb7c3b83c1627` |
| `xcodebuild ... -only-testing:NostrWriterTests/Stage03EditorTests -only-testing:NostrWriterTests/ShellTests` on the `154f34ef` tree | **27 tests, 1 skipped, 0 failures** (`Stage03EditorTests` 14/0, `ShellTests` 13 with 1 skip - the pre-existing `testExternalChangesPreserveBothSourcesAndRejectUnreviewedSave`, which needs the `NW_COORDINATED_WRITER` helper and is separately covered by the recorded conflict-regression run) |
| `xcodebuild ... -only-testing:NostrWriterTests/Stage03EditorTests` on the `d8745dcf` tree | **19 tests, 0 failures** - adds the five dictation checks. Two earlier attempts failed to compile (`CGFloat?`/`Double`, then `SourceSnapshot` optional chaining) and were fixed before this run |
| `WRITER_DEVELOPMENT_TEAM=6R2578FWBR mac/scripts/build_signed_development.sh` on the `d8745dcf` tree | **BUILD SUCCEEDED**, **strict_signature_verification PASS**, universal (x86_64 + arm64), minos 14.0, binary sha256 `53813d4134258e62b107b23ed5471c08b1507380bad2903ca228d785625ac390` |

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

### Dictation session rules on the final candidate

The stage plan requires "denied/unavailable/error behavior and deterministic
late-callback/range cancellation checks" for M19. Only the anchor/range rule was
covered before this session, so the gate was made injectable and the session
identity became a monotonic, never-reused token; two earlier compile failures were
fixed on the way. Six checks now pass on the final candidate:

| Check | What it proves |
| --- | --- |
| `testDictationAnchorCancelsRatherThanOverwritingLaterText` | Insert at the anchor, replace only this session's own range, cancel on unrelated replacement, cancel on a truncated document |
| `testDictationRefusesUnsupportedLanguageBeforeAskingForPermission` | `.unavailable` with **zero** speech and microphone requests, not listening, source unchanged |
| `testDictationReportsDeniedSpeechAndMicrophoneWithoutListening` | `.denied` on speech, the microphone never requested, no revision published |
| `testDictationReportsDeniedMicrophoneAfterAGrantedSpeechPrompt` | `.denied` on the microphone after exactly one speech request and one microphone request |
| `testLateDictationCallbackAfterStopCannotTouchTheDocument` | A hypothesis delivered after `stop()` changes neither the source bytes nor the published revision |
| `testTokenFromAnEarlierSessionCannotOverwriteANewerOne` | A superseded session's token is never reused and its callback is dropped; the current session still applies with origin `knownAssistance(.dictation)` |

Live on the rebuilt candidate `53813d41`, without answering any privacy prompt: the
app launches, the status line reads "Recovery up to date, 0 words - Unsaved
Recording off", the toolbar button "Dictate On This Mac" is present and enabled, and
the inspector renders `RECORDING Recording off` and `DICTATION Off` alongside the
unchanged `NOT PROVABLE - no approved Mac capture profile and model are installed.`
The dictation button was deliberately **not** clicked: that raises the system Speech
Recognition and Microphone prompts, and answering them is a TCC privacy decision
reserved for the owner. Raw evidence:
`logs/stage-03/dictation-session-observation.txt`.

## Acceptance results (M14-M21)

| ID | Status | Evidence and exact gap |
| --- | --- | --- |
| M14 | **PASS** (live Reduce Motion differential NOT MEASURED) | Layout, preferences, keyboard and contrast are observed on real candidates: a 1120x760 light window with exact Markdown source, typography, measure, emphasis colours, sidebar, tab bar, toolbar and status line; the same window in dark appearance at 1120x760 and at the minimum 760x556 frame; the passage inspector; the Settings panel at 540x502 after fixing a real 180x64 collapse defect; outline-popup navigation that moved the caret to the chosen heading; Focus Writing; the native find bar without changing the source; and native undo restoring the exact fixture. Real modifier keystrokes were delivered through System Events: Cmd+N, Cmd+Z, Cmd+Shift+F (Focus Writing - sidebar and toolbar gone from the accessibility tree, status and recovery banner retained) and Ctrl+Cmd+F (native fullscreen). On the final candidate `8d0f7f5c` View > Typewriter Scrolling toggled on and off, and with it on, typing at the end of a 62-line fixture moved the editor scroll bar 0 -> 1 while the saved file gained exactly the one typed character (3373 bytes). The Reduce Motion branch is no longer an untested inline condition: it is `TypewriterScrollPlan.plan(caret:visible:reduceMotion:padding:)` in `EditorSupport.swift`, called with `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`, and covered by `testTypewriterScrollPlanHonoursReduceMotionWithoutMovingText` (14 Stage03EditorTests, 0 failures). **Residual, explicitly not measured:** the live differential with the system setting switched on - this host's accessibility preference domain is TCC-protected (`defaults write com.apple.universalaccess reduceMotion -bool true` -> "Could not write domain", the direct-plist form refused, `PlistBuddy` -> "Operation not permitted", `plutil -p` shows no key), so the exact owner step is System Settings > Accessibility > Display > Reduce motion. See `logs/stage-03/typewriter-scroll-reduce-motion.txt`. |
| M15 | **PASS** | `testFormattingAndFindReplaceUseTheirOwnCausesAndPreserveBytes`, `testOneTypedMutationProducesExactlyOneRevision` and `testMarkedTextIsNotCommittedAsARevision` pass; the 1,000-operation Unicode replay (`seed=1592591107`, final 420 bytes, byte-equality after every operation) passes; the ShellTests undo paths still pass, and native `Edit > Undo Typing` restored the exact fixture after live typed characters; the 100,008-word / 540,600-byte fixture measured outline 27.0 ms, edit p95 45.7 ms, max 45.8 ms; real typing preserved exact source. |
| M16 | **PASS** | The whole native input matrix was observed as real key events and verified against saved bytes: German layout `ä ö ü ß` (0xe4 0xf6 0xfc 0xdf); two genuine dead-key compositions through marked text (`^` then `e` -> 0xea, `´` then `e` -> 0xe9, in `input-matrix-deadkeys.jpeg`); RTL Arabic, six U+0634; an astral emoji U+1F642 typed through Unicode Hex Input; and a real CJK input method, the Korean IME composing U+D55C U+AE00 plus three U+314B jamo, committed with Return and saved. The same keys produced literal Latin `gksrmf` while the IME was not composing, and that non-composing state is preserved in the record rather than repaired. Composition manufactures no committed characters: marked text publishes no revision and the commit is classified `nativeIMECommit`; combining and astral offsets are covered by the 1,000-operation Unicode replay (seed 1592591107) with byte equality after every operation. See `logs/stage-03/native-input-matrix-full.txt`. |
| M17 | **PASS** | The route inventory above is tied to implementation; `testGatewayClassifiesObservedDeliveryWithoutGuessingFromText` covers every delivery including `unknown`; `testOneTypedMutationProducesExactlyOneRevision` proves a duplicate delegate callback publishes no second revision; `testInputPolicyRefusesExternalInsertionLocally` proves the Stage 07 seam refuses external insertion without global interception. |
| M18 | **PASS** | Continuous spell checking is on (the misspelled token drew the red spelling underline) and grammar checking with spelling is now enabled by `e785439`; the Edit menu exposes Spelling and Grammar (Show Spelling and Grammar, Check Document Now, Check Spelling While Typing, Check Grammar With Spelling, Correct Spelling Automatically) and a Writing Tools submenu where previously there was no Spelling submenu; the editor's contextual menu offers Look Up and Translate for the word under the caret; the application menu has a populated Services submenu (9 items); and a real correction ran - at the default, typing `teh ` left exactly `teh ` (`7465 6820`), while after enabling Correct Spelling Automatically from the app's own menu the same keystrokes produced `The `. Provenance stays exact: `NSTextView.changeSpelling(_:)` is classified `knownAssistance(.spelling)` and an opaque mutation stays unknown, both asserted by `testGatewayClassifiesObservedDeliveryWithoutGuessingFromText`. Scope note: the native correction was the automatic path; the user-accepted panel/suggestion path is covered deterministically but was not reachable in this harness because the shared `NSSpellChecker` panel is not reported as a window and the suggestion menu did not appear for a caret or find-bar selection. See `logs/stage-03/spelling-and-services-observation.txt`. |
| M19 | **BLOCKED** | Deterministic coverage is complete for everything this row can verify without a human speaker. Anchor/cancellation (`testDictationAnchorCancelsRatherThanOverwritingLaterText`): the first hypothesis inserts at the anchor, a refined hypothesis replaces only this session's own range, an unrelated edit replaced by newer text cancels instead of clobbering, and a truncated document cancels rather than writing past the end. Permission ordering and refusal states: an unsupported language ends `.unavailable` with **zero** permission requests; a refused speech grant ends `.denied("Speech recognition permission was not granted.")` without ever requesting the microphone; a refused microphone ends `.denied("Microphone permission was not granted.")` after exactly one request each; no revision is published in any of them. Late callbacks: a hypothesis delivered after `stop()` changes neither the source bytes nor the published revision, and a token from a superseded session is dropped even while a newer session is open, which still applies its own transcript with origin `knownAssistance(.dictation)`. Nineteen `Stage03EditorTests` pass on the final candidate, and the rebuilt app still launches with "Recovery up to date" and renders `DICTATION Off` in the inspector. Both earlier hardware blockers are corrected: audio devices exist, and on-device recognition is available for `en_ES`, `en-US` and `de-DE` with `speechAuthorization` notDetermined, so the app's `isSupported` gate passes on this host. **Remaining is owner input, not capability:** the Speech Recognition and Microphone prompts are privacy decisions deliberately not answered on the owner's behalf, and actual recognition needs a human speaker. The dictation button was deliberately not clicked. See `logs/stage-03/dictation-capability-probe.txt` and `logs/stage-03/dictation-session-observation.txt`. |
| M20 | **PASS** | Observed in the running app: the passage inspector opened; selecting the blockquote populated SELECTED PASSAGE; filling a source description enabled "Mark External Source"; marking created a span shown as "Quotation - bytes 109-147"; and one character typed at the document start re-mapped it to "bytes 110-148" (an exact +1 shift). `testAnnotationsShiftThroughEditsAndRemovalKeepsSource` deterministically covers the shift, stale-on-replacement, removal, sticky staleness and distinct split ids; the inspector's HUMAN WRITING PROOF section shows the contracted NOT PROVABLE message and the passage notice says the material "is not claimed as freshly composed", so the UI does not imply human certainty. |
| M21 | **PASS** | Deterministic parts verified: `testObservationHandleHonoursConsentBoundaries` (recording off gives no handle; gap/paused/limit give an honest nil; observing gives a handle bound to the exact source) and the `WriterStorageTests.HistoryJournalTests` set (round-trip, encryption at rest, wrong key, capacity pause without stopping writing, delete-history leaves recovery intact, and the two new interpretation-tamper cases). The live off/on/record/pause/resume/delete/close/restart path ran end to end on the signed candidate `436d43ca...` (TeamIdentifier `6R2578FWBR`) with every required behaviour observed - full detail in "Live consented-history session" below and raw output in `logs/stage-03/consented-history-session-observation.txt`. Under the previous ad-hoc image this same window rendered "Recovery unavailable"; under the signed image it renders "Recovery up to date", which is the identity gate being exercised rather than assumed. Re-confirmed on the final candidate `8d0f7f5c...`: a real document opened with the recovery banner "Recovery up to date" and the status line "Recording off", and a typed character saved with the source exact. Remaining sub-gap: the 1 GiB warn and 2 GiB pause resource thresholds were not driven live (deterministic coverage only, in `HistoryJournalTests`). |

## Live consented-history session (signed candidate, 2026-09-19)

Ran after the signed rebuild, on executable `436d43caa1f0b0beb8061572674b1a77d2ef926bad43ac1d047833d2bf626392`.
All probes were synthetic ASCII tokens typed or discarded by hand; no real
writing, keys, or private text is involved. The container was returned to its
pre-session state afterwards (see "State restoration").

1. **Off.** Baseline container held `bootstrap.json`, `installation.lock` and
   `recovery.sqlite*` only, with no `history.sqlite`; the document read
   `41 words - Saved to tmp Recording off` and the inspector read
   `RECORDING Recording off - No detailed revisions or deleted text are stored.`
   Under the earlier ad-hoc image the same window had read "Recovery
   unavailable"; on the signed image it reads "Recovery up to date".
2. **On.** Toggled "Store writing history on this Mac" in the app's own Settings
   window (element `switch Store writing history on this Mac`). The document and
   inspector moved to `Recording on`, the status line to `Recording on`, and
   `history.sqlite` appeared at 4,096 bytes with a 111,272-byte WAL. The new
   epoch recorded `prior_completeness = descriptiveOnly`, i.e. the pre-existing
   file text was imported as descriptive rather than claimed as fresh
   composition.
3. **Typing.** 14 real keystrokes (`m21probeZq7Vv `) produced exactly **14**
   `history_records`, `chunk_index` 0..13, `origin = directNativeInput`, one
   source revision per character, and `range_lower/range_upper` advancing one
   UTF-16 unit per character (239 back to 225). Each record carried a 12-byte
   `nonce` and a 48-byte `sealed` payload with `post_digest` and `chunk_ref`.
   `grep` for the probe token and for `Stage 03 Fixture` in `history.sqlite` and
   its WAL returned **0 matches** - the store is encrypted at rest.
4. **Pause.** The inspector's Pause/Resume moved the state to
   `Recording paused - Earlier history is preserved; new detail is not recorded.`
   A further 16 typed characters added **no** records (still 14) and appended one
   honest gap row (`reason = userPaused`, `revision = 14`). The journal WAL still
   grew, because the *separate* recovery store kept checkpointing: editing and
   encrypted recovery stay intact while detailed history is paused.
5. **Resume.** State returned to `Recording on` and a new epoch began with
   `gap_reason = resumed` (`began_revision = 28`). The 15 characters typed after
   resume produced 15 further records (`chunk_index` 14..28), so the pause is
   visible as a boundary rather than silently smoothed over.
6. **Delete Local History.** The confirmation read: "Delete this document's
   detailed writing history? This permanently removes the recorded detailed
   history for this document, including deleted text and timing. Your document
   and its encrypted recovery are not deleted. Deleting history cannot revoke an
   already exported proof or erase backups." After confirming, `history_records`,
   `history_gaps` and `history_annotations` were **0** for the document, while
   `recovery.sqlite` still held 66 `recovery_chunks` across 54 documents and the
   banner still read "Recovery up to date" - exactly the required
   "deleting history leaves recovery intact".
7. **Close.** A graceful Cmd+Q (discarding the synthetic unsaved buffer through
   the app's own "Discard Changes" dialog) appended a `boundaryClose` gap, ended
   the epoch, closed the shared journal, and exited the process cleanly. The
   scratch fixture file was left byte-identical (225 bytes,
   md5 `cad776dbec6f806c75212bb7b08fa1c8`).
8. **Restart.** Relaunched the registered build and re-opened the same file.
   Consent persisted with **no** re-prompt (`41 words - Saved to tmp Recording on`)
   and recovery reopened ("Recovery up to date"). Typing 15 characters then
   recorded 15 new `history_records` (`origin = directNativeInput`, ranges
   225..239) with no plaintext in the WAL, so consented detail survives a restart.

**State restoration.** The owner's pre-session preference was restored:
`recordingChoice` is back to `off`, and the synthetic `history.sqlite` created
during this session (no journal existed before it) was deleted. `recovery.sqlite`
was preserved and checkpointed by the clean shutdown; it now also contains the
synthetic probe revisions, which is disclosed rather than hidden. The scratch
document `/private/tmp/nw-s3-fixture.md` was never written to disk by the app
during the session.

**One observation left open for Stage 04, not a Stage 03 row.** The recovery
catalog maps this file to a stable identity (`document_catalog.location_key =
file:///tmp/nw-s3-fixture.md`, `document_id CCA2B3FB`), while the epoch created
for the same window in the post-restart session used a different document id
(`453DCCCF`, reached through the `/private/tmp` path form of the same file). The
journal recorded correct, monotonic, per-character detail either way, and
recovery worked in both sessions, so no Stage 03 requirement fails here; but
whether `/tmp` and `/private/tmp` should resolve to one catalog entry is worth a
deliberate check in Stage 04 before any cross-session lineage claim is made.

## Blockers (exact missing access, input or decision)

1. **Signing identity - RESOLVED.** The earlier record was wrong: the "0 valid
   codesigning identities" result came from inside the sandbox. Queried outside
   it, `security find-identity -v -p codesigning` returns 1 valid identity,
   "Apple Development: mris@tuta.io (TVV48YYFPR)" (OU `6R2578FWBR`); the owner's
   existing identity was already installed and nothing new was created. The
   candidate was rebuilt with `WRITER_DEVELOPMENT_TEAM=6R2578FWBR
   mac/scripts/build_signed_development.sh`, verifies strictly, and carries
   `keychain-access-groups = 6R2578FWBR.com.mariusschober.nostrwriter.development`.
   Recovery and the consented journal both open under it; M21 is PASS. The same
   sandbox masking produced the audio-device claim corrected in item 6, so no
   remaining claim about this host rests on an in-sandbox query.
2. **Reduce Motion live differential - the one remaining M14 item.** The
   behaviour is no longer untested code: the branch is the pure
   `TypewriterScrollPlan.plan(...)` that `typewriterScroll()` calls with
   `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`, and
   `testTypewriterScrollPlanHonoursReduceMotionWithoutMovingText` asserts both
   flag values (no scroll while the caret is comfortably visible, the smallest
   jump at the bottom edge, strictly less travel than recentring, the caret still
   visible after that jump, and the padding-sized scroll-up at the top edge).
   What is missing is only the live differential with the setting actually on,
   and this host refuses every route to it:
   `defaults write com.apple.universalaccess reduceMotion -bool true` ->
   "Could not write domain com.apple.universalaccess"; the same command with the
   plist path -> "Could not write domain"; `PlistBuddy` on
   `~/Library/Preferences/com.apple.universalaccess.plist` -> "Operation not
   permitted" (TCC-protected); and `plutil -p` shows no `reduceMotion` key, so
   the setting is at its default. Exact owner step: System Settings >
   Accessibility > Display > Reduce motion on, then retype in a long document
   with Typewriter Scrolling enabled. Recorded in
   `logs/stage-03/typewriter-scroll-reduce-motion.txt`.
3. **Keyboard matrix - resolved.** System Events keystroke does deliver modifier
   keys, so Cmd+N, Cmd+Z, Cmd+Shift+F and Ctrl+Cmd+F were all exercised as real
   key events. Only the computer-use `press_key` path ignores modifier flags,
   which is why earlier probes typed bare letters; that is recorded, not carried
   forward as a gap.
4. **Input-method matrix - resolved.** The previous revision said no emoji, RTL
   or CJK input source is enabled on this host. That came from reading only the
   default-layout list: the input menu actually exposes German, Arabic,
   `2SetHangul` and `UnicodeHexInput`, and each was used to type real characters
   that were then read back from the saved file - an astral emoji (U+1F642), RTL
   Arabic (U+0634) and Hangul composed by the Korean IME (U+D55C U+AE00, U+314B
   x3). M16 is PASS; see `logs/stage-03/native-input-matrix-full.txt`.
5. **Spell/assistance session - M18 accepted with a stated scope.** A native
   spelling correction ran and the Services/Translation and Spelling routes are
   reachable in the running candidate. The only unperformed part is the
   user-accepted suggestion/panel correction, whose classification is covered
   deterministically; the shared `NSSpellChecker` panel is not exposed to the
   accessibility layer on this host.
6. **Microphone and human speech - corrected and narrowed to an owner action.**
   The previous revision said `system_profiler SPAudioDataType` reports no
   devices at all on this host; that was a sandbox artefact. Outside the sandbox
   this host has MacBook Pro Microphone and Speakers, a CONEXANT USB AUDIO device
   that is the current default input, and a DELL S2419H HDMI output, and the
   signed candidate carries `com.apple.security.device.audio-input`. Beyond
   hardware, a read-only Swift probe now reports on-device recognition available
   for `en_ES`, `en-US` and `de-DE` with `speechAuthorization` notDetermined, so
   the app's own `isSupported` gate passes here. M19 therefore needs owner
   actions only: answer the Speech Recognition and Microphone prompts (a TCC
   privacy grant, deliberately not made here), speak real audio, and replay the
   denied and unavailable paths. See
   `logs/stage-03/dictation-capability-probe.txt`.

   The deterministic half of this row was finished in the same session. The
   permission gate is now injectable (`DictationGate`; only `.live` touches TCC),
   the session identity is a monotonic, never-reused token
   (`DictationGeneration`), and `deliver(transcript:token:)` drops a stale token
   before the anchor is consulted. Six `Stage03EditorTests` pass on the final
   candidate and assert: an unsupported language refuses with **zero** permission
   requests; a refused speech grant stops before the microphone is ever
   requested; each refusal ends in `.denied` with the contracted wording and no
   published revision; a hypothesis delivered after `stop()` changes neither the
   source bytes nor the published revision; and a superseded session's token is
   never reused, its callback is dropped, and the current session still applies
   with origin `knownAssistance(.dictation)`. The dictation button was
   deliberately **not** clicked in this session, because clicking is what raises
   the two prompts. See
   `logs/stage-03/dictation-session-observation.txt`.
7. **VoiceOver and system dictation - capability recorded, sessions left to the
   owner.** The accessibility contract the app actually exposes was inventoried
   from the live tree instead of hypothesised: the editor is a settable text entry
   area described "Markdown editor" with `ID: markdown-editor`; the sidebar search
   carries a Help string and placeholder; all six toolbar controls carry
   descriptions ("Toggle Sidebar", "Headings", "Formatting", "Dictate On This
   Mac", "Focus", "Toggle Inspector"); the status line, window buttons and nine
   native menus are labelled; and the inspector exposes RECORDING, Pause / Resume,
   Delete Local History, DICTATION Off, SELECTED PASSAGE, Category, Source
   description, Optional URL, the "not claimed as freshly composed" notice, a
   disabled Mark External Source and the MARKED SPANS / HUMAN WRITING PROOF text
   with the contracted NOT PROVABLE message. Recorded honestly: the MARKED SPANS
   heading, its empty-state sentence and the proof message share one combined text
   node, so a screen reader announces them as a single string - a Stage 08
   granularity observation, not a Stage 03 defect. VoiceOver is **not enabled**
   here (`voiceOverOnOffKey = 0`; only the "VoiceOver Quickstart" onboarding window
   is running), and switching it on is a system-wide accessibility change with
   immediate audible and keyboard effects, so it was left to the owner; M53 at
   Stage 08 is the criterion that owns VoiceOver. System dictation **is** available
   on this host (`AppleDictationAutoEnable = 1`, `"Dictation Enabled" = 1`,
   `DictationIM` loaded) but invoking it would capture live microphone audio, so it
   was not triggered; the app-side half of the native-versus-on-device distinction
   is covered deterministically. See
   `logs/stage-03/accessibility-and-os-input-capability.txt`.

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

Finished here: the live consented-history round trip on the signed candidate
(off/on/record/pause/resume/delete/close/restart with encryption at rest and
recovery preserved); the complete native input matrix (German umlauts, dead keys,
emoji, RTL Arabic, Hangul) verified against exact saved bytes; and typewriter
scrolling observed live on the rebuilt candidate with the Reduce Motion branch
extracted into a tested pure decision; and the dictation gate ordering,
refused-grant states and late-callback rejection made testable and tested.

Unfinished here, each with its exact missing input: the live Reduce Motion
differential (the owner toggling the system setting plus a measurable scroll
comparison - the branch itself is tested); actual on-device dictation plus its
denied and unavailable paths replayed from the UI (granted microphone/speech
permission and a human speaker - the hardware and on-device models are present,
and those same states are asserted deterministically); a VoiceOver editing
session (the owner enabling VoiceOver - the app's exposed accessibility contract
is inventoried in `logs/stage-03/accessibility-and-os-input-capability.txt`, and
M53 at Stage 08 owns the VoiceOver criterion); system dictation insertion to
confirm an OS-provided insertion is not recorded as physical typing (the owner
speaking - `DictationIM` is loaded here but invoking it captures live audio); a
real user-accepted spelling correction (a reachable spelling panel); and the
1 GiB warn / 2 GiB pause resource thresholds driven live (deterministic coverage
only: the app uses `HistoryCapacity.standard` with no supported override, so
driving it live would mean writing roughly 2 GiB of ciphertext for a test).
