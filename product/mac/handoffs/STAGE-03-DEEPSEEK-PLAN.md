# Stage 03 execution plan — editor, assistance and local writing history

This is an implementation plan for DeepSeek V4.1 Flash, based on accepted Stage 02 at `b8568c09530b90e28a3d1fb817335c6a980fc116`. Read the [handover](STAGE-03-DEEPSEEK-HANDOVER.md) for pinned GitHub sources and the [original Stage 03 contract](../plans/PLAN-03-EDITOR.md) for authority. This plan adds sequencing and file ownership; it does not reduce that contract.

## Outcome, limits and effort

Deliver an integrated native long-form Markdown editor whose exact source, caret, undo, recovery and local provenance remain correct across native input, deliberate transformations and asynchronous assistance. Complete M14–M21, record actual evidence, and hand off to Astra for final review. Stop before Stage 04.

Planning allowance: one bounded initial pass, approximately 20–30 minutes after the required reading. Implementation estimate: **18–30 focused engineering hours plus any unavailable native-input/owner observation time**, provisional until the first integrated gateway is compiled. This is a multi-session stage, not a short UI styling task: detailed consented history and native input observation are currently missing. Re-estimate after work package 1 if a concrete platform/storage issue changes the range. Reduce unneeded abstractions and repeated checks, never the mandatory acceptance scope.

Six integrated work packages follow. The first milestone is working source mutation through the existing document/recovery pipeline; avoid building disconnected frameworks before the app uses them. Commit coherent steps and keep a concise evidence note as work happens.

Out of scope: HWP approval/training/native cryptographic implementation (Stage 04); paginated PDF/DOCX/export renderer (Stage 05); Nostr identity/relays/publication (Stage 06); locked-session enforcement/sound/global restrictions (Stage 07); full release/distribution matrix (Stage 08). Normal editor focus and future input-gate seams are in scope. Detailed-evidence interchange remains Stage 04: any unfinished action must clearly explain availability, not pretend an export succeeded.

## Architecture decisions to retain

- Evolve the existing `WriterDocument` → `DocumentSession` → immutable `SourceSnapshot` path. Put a native `EditorMutationGateway` between actual input/app commands and revision publication. A native NSTextView subclass/adapter may be needed for input-method and delivery hooks; do not introduce a second live text buffer or SwiftUI write-back path.
- Keep text storage ownership, native undo and IME semantics intact. Capture before/after state and observed delivery in the gateway; commit exactly one receipt for each real mutation. An observer must not replay that mutation into the same text storage again. Programmatic operations enter through explicit commands and the same boundary.
- Maintain typed UTF-16, scalar and UTF-8 conversions. A visible grapheme may contain multiple scalar ranges; persisted scope is exact and scalar-aligned. Preserve bytes outside the edited span, including BOM/line-ending conventions, without opportunistic normalization.
- Add pure local observation/ancestry/annotation types to WriterFoundation as needed, encrypted persistence to WriterStorage, and native editor/assistance/inspector components to the app. Proposed folders `mac/NostrWriter/Editor`, `Observation`, `Assistance` and `Inspector` are organizational suggestions, not requirements for new packages.
- Use immutable revision plus document identity and a generation token for asynchronous jobs. Parser/search jobs discard stale results. Dictation additionally owns a validated insertion range; cancellation/rebase rules must never overwrite unrelated newer text.
- Distinguish app-descriptive records from frozen HWP canonical evidence. A record contains available facts and explicit gaps, not repaired fictional observations. Freeze any prospective eligible release/profile at run start; ordinary unapproved app observation must stay labelled unapproved.
- Keep detailed history separate from evictable recovery checkpoints. One serialized writer/migration owner must preserve predecessor recovery and avoid main-thread database work. Define a truthful record-flush/finalization boundary; a record handle cannot claim bytes that failed to persist.

## 0. Establish the input and bounded checks

Read the handover's entry documents, full UX and assigned contracts. Inspect HEAD, status, untracked files and remote references. Verify Stage 02 accepted status and ancestry. Create `implementation/stage-03` from the current handover tip of `implementation/stage-02`, preserving unrelated work. Record full input SHA, actual Xcode/macOS/hardware and the selected normal build path.

Read checker scripts, then run `python3 tools/check_preparation.py` and `python3 tools/bootstrap_protocol.py` once as required by AGENTS. They check prepared/frozen inputs; do not run the entire protocol test suite as a substitute for editor work. If a freeze mismatch occurs, stop edits to affected authority, report it and do not rebuild its manifest.

Use the acceptance table below as the checklist. Inspect the affected existing tests to select regression coverage once. Do not repeat accepted Stage 02 cloud/signing/VoiceOver setup as an entry ritual. If the stage begins in PLAN mode only, perform read-only inspection and propose commands; defer checks with output side effects until implementation is authorized.

## 1. Integrate exact mutation and consented local history

Primary files: existing `WriterWindowController.swift`, `WriterDocument.swift`, `DocumentSession.swift`, WriterFoundation `SourceSnapshot.swift`, `Coordinates.swift`, `ServiceContracts.swift`; new gateway/observation types and affected tests. Then WriterStorage history persistence/migration and `RecordingConsent.swift`/`DocumentRecovery.swift` integration.

1. Trace all actual source-changing routes before replacing `acceptScratchEdit`: direct input and marked text, native undo/redo, cut/paste/drop, formatting/image insertion, find/replace, Services/accessibility/system changes, opening/importing/reverting/recovering/external file adoption. Preserve the document's queued immutable saves and exact change tokens.
2. Connect the gateway to the existing live TextKit 2 editor first. Record pre/post revisions, actual selection/ranges, declared operation and available delivery cause IDs. Missing or inconsistent evidence creates a capture gap while keeping the new source editable and recoverable. Do not call every one-character change physical typing.
3. Treat IME update/commit/cancel and dead-key input according to actual native delivery, without manufacturing intermediate committed characters. Display-only syntax/focus attributes do not create revisions. Search fields, menus and non-document input do not enter document history.
4. Implement local replay and root ancestry for insertion/deletion/replacement, exact move/copy and undo/redo. Private internal-paste tokens bind a real source record plus exact current payload; stale tokens/mismatches use external origin. Cross-document import never earns ancestry solely from matching text.
5. Add a separately versioned encrypted journal with actual initial source/boundaries and ordered receipts sufficient for local replay. Existing RecoveryBatch receipt validation does not implement this. Use an additive, safely backed-up migration and preserve ordinary recovery even when detailed-history persistence fails. Follow DATA's AES-GCM framing: fresh random nonce per chunk; authenticated format version, document UUID, recording UUID, monotonic chunk index and previous committed chunk reference. Use append-before-ack durability within the contracted checkpoint window and at save/close/finalization; an incomplete chunk is a gap. Do not log source/deleted text in plaintext or silently replace an unavailable key.
6. Wire explicit consent to active sessions. Recording off persists no detailed journal; turning it on starts a prospective epoch, with pre-existing text imported/unknown. Pause, consent changes, restart, input-path/release changes and gaps establish honest boundaries. Finish `finalizeObservation` as a real local-record operation; retain proof ineligibility unless separately justified by the frozen contract.
7. Implement retention/resource states: warn at 1 GiB, pause detailed history at 2 GiB, keep current text/recovery capacity and editing usable. Do not silently prune history or fabricate continuity after a pause. Existing retained history survives pause; explicit deletion is separate.

Checkpoint: real typing, edit, undo, save and encrypted recovery use the new integrated path; off/on/gap behavior is truthful. A focused deterministic replay test and affected existing source/recovery regression pass. Astra reviews the mutation ownership, persistence/consent and evidence distinction at this concrete checkpoint if available; no second speculative architecture exercise is needed.

## 2. Finish the long-form editor and Markdown navigation

Primary files: editor adapter/view, `WriterWindowController.swift`, `AppMenus.swift`, editor preferences in Settings; existing pinned Markdown parse boundary in WriterExport or a shared service using that dependency.

- Default 1120×760 pt, minimum 760×520; sidebar 232 pt and inspector 288 pt, both resizable/collapsible. Center a preferred 72-character measure with at least 28 pt horizontal margin and 32 pt top inset. The measure adapts when side panels consume space; never force clipping at the minimum window size.
- Default System Mono 18 pt, approximately 1.5 line height. Offer System Mono/System Sans/Georgia, size 13–32 and measure 50–100. Use native semantic colors, focus rings and accessible toolbar targets. Attributes/preferences/zoom preserve exact source.
- Implement sentence/paragraph focus and optional typewriter scrolling near 45% viewport height during actual editing. Preserve contrast, selection, find results and marked text; honor Reduce Motion, manual scrolling and accessibility navigation. Cmd-Shift-F toggles ordinary chrome focus; Escape exits immediately. Ctrl-Cmd-F remains native fullscreen.
- Add non-destructive syntax emphasis for the EXPORT grammar, actual ATX/Setext outline and source navigation. Reuse locked parser versions; do not implement a competing regex interpretation for structure. Unsupported content remains editable source. No web preview or auto-generated prose pane.
- Implement native Cmd-F literal/case/whole-word search. Replace All shows its match count and applies one reversible semantic command with find/replace origin. Formatting inserts visible syntax through the gateway with formatting origin. Preserve caret/selection and sensible native undo groups.
- Use `NLTokenizer`-based word segmentation and separate selection counts; do not equate product word counts to HWP scalar/root counts. Keep status layout stable while save/recording states update.
- Make outline/highlight/search work cancellable and revision-bound. An old parser result cannot set selection, alter text or paint misleading spans over a new revision.

Checkpoint: normal writing, formatting, find/replace, outline and focus are usable in a running build; source remains exact. Run changed editor/command tests once, defer the complete visual matrix to the frozen final candidate.

## 3. Deliver the passage inspector and source annotations

Primary files: new inspector/annotation components, pure ancestry/range mapping, encrypted annotation metadata, document menu/selection integration.

- Show recording off/on/paused/unavailable, actual origin categories and gaps. Selecting a span shows its exact source/category and bound range. Optional visual expansion to a grapheme does not expand persisted claim scope.
- Implement Document → Mark External Source for a selection. Categories: quotation, citation/reference, assisted, imported. Require a plain source description, allow an optional URL, show selected text and “This material is not claimed as freshly composed.” Markdown quotation syntax alone does not establish attribution.
- Map annotations through the same real lineage as edits/copies/moves/undo. Splits, replacement and deletion must either yield correctly bound surviving ranges or an explicit stale annotation needing review. Removing a label never erases imported ancestry. A later replacement must not inherit a favorable exclusion merely by occupying old character indexes.
- Provide Pause/Resume and explicit Delete Local History. Explain lost future recomputation and that deleting local history cannot revoke an already exported proof. Preserve source, recovery and unrelated documents; handle any required metadata invalidation truthfully.
- Use the exact current proof-absence message: “NOT PROVABLE — no approved Mac capture profile and model are installed.” No human percentage, AI accusation or production badge. Later proof/disclosure actions must state their actual unavailable stage; do not implement a fake successful export.

Checkpoint: selection → annotation → edit/undo → inspector behaves correctly and survives a normal reopen where persistence is intended. Scope/ancestry checks cover unrelated replacement and stale range cases.

## 4. Integrate native assistance and optional on-device dictation

Primary files: native editor input hooks, new assistance/dictation controller, `AppMenus.swift`, Settings, Info.plist, entitlement files and signature inspector if a necessary entitlement changes.

- Preserve usable spelling/grammar indications. Accepted replacement is assisted; an opaque system mutation is unknown/unsupported. Automatic replacements, smart punctuation, completion and generative Writing Tools changes are off by default. Guard API availability; do not pretend older macOS has newer controls.
- Services/translation and accessibility insertion stay usable in ordinary writing, with origin based on observable facts. Add explicit input-policy seams for Stage 07 and verify blocked external-insertion commands without enabling global interception or locked-session UI now.
- Offer explicit on-device dictation only for supported system/language combinations. Request mic/speech permission at invocation, show a persistent listening indicator and Stop, and report denial/unavailability clearly. Never silently choose cloud recognition.
- Dictation owns a source-bound insertion anchor and operation generation. Interim hypotheses update only that operation's still-valid range. On unrelated edits, use a provably safe rebase or cancel; never overwrite later typing. Stop/cancel/error/sleep/wake/document switch/close invalidates late callbacks. Resulting text is known assistance, with current proof limits shown.
- Keep native system dictation/opaque insertion classification distinct from the app's explicitly on-device feature. An OS-provided insertion does not prove how the OS processed audio. Record native matrix observations accordingly.
- Add only required microphone/speech purpose descriptions and narrowly necessary sandbox entitlements. Reuse existing signing. Do not request microphone access at launch or add global input monitoring/Accessibility permissions.

Checkpoint: real native spell replacement and supported on-device dictation have correct ranges/origins; denial and delayed-callback paths preserve newer text. No real audio/private transcripts are committed.

## 5. Freeze one candidate, verify the required matrix, record the handoff

Integrate the completed work, compile with the current strict Swift 6 settings and preserve macOS 14+ and declared universal architecture build support. Resolve actual code failures before device acceptance. Pin source commit and executable hash, then use one normal signed candidate for the required observations below. If source changes, repeat only checks whose behavior was affected and record which observations came from which candidate.

Do not introduce arbitrary pass thresholds or claim a fast automated run covers a native route it did not execute. Use the product's existing performance bounds; record fixture bytes/words, hardware and timings. A mandatory unavailable observation is BLOCKED with the exact required access/input/owner action, while independent work continues.

### Acceptance mapping (unchanged requirements)

| ID | Required result | Minimum evidence in this stage |
| --- | --- | --- |
| M14 | Finished TextKit 2 long editor, typography, chrome, focus/typewriter options and outline work. | Real interaction and screenshots at 1120×760 and 760×520, light/dark; verify layout, preferences, keyboard, contrast and Reduce Motion behavior. |
| M15 | Markdown editing/find/replace/format/undo preserve source and responsive caret/selection. | Editor command/undo checks plus deterministic randomized replay; actual 100k-word responsiveness measurement. |
| M16 | IME/dead-key/emoji/RTL/Unicode offsets work without synthetic capture invention. | Native input matrix, exact replay/coordinate checks and honest classification of supported/opaque paths. |
| M17 | All app mutation routes use one revision/cause gateway; unexplained input marks a gap rather than physical typing. | Route inventory tied to implementation, malformed/unknown-event adversarial checks and no duplicate revisions from native callbacks. |
| M18 | Spelling/grammar/controlled system assistance remains usable with exact assisted/unknown provenance. | Native spell correction/Services observations, availability and default-control checks, assisted/unknown span evidence. |
| M19 | Optional on-device dictation is range-anchored, permission-aware and cancellation-safe with no silent cloud fallback. | Actual supported recognition plus denied/unavailable/error behavior and deterministic late-callback/range cancellation checks. |
| M20 | Quote/external-source annotations and passage inspector preserve exact boundaries and do not imply human certainty. | Actual annotation/inspector interaction and scope mapping through edits, move/copy/undo; unrelated replacement/stale cases. |
| M21 | Consent changes, capture gaps/resources and stale async rendering are handled without losing writing. | Off/on/pause persistence checks, resource/store failures, stale render/parser/dictation races and truthful UI states with editing/recovery intact. |

### Bounded verification batches

1. **Pure/native regression batch during implementation:** deterministic 1,000 random Unicode operations with seed recorded, replay after every operation and exact source-byte equality. Cover insert/delete/replace, undo/redo/move/copy, selections, combining/astral characters, malformed intervals and capture gaps. Add focused stale SwiftUI/parser, IME cancellation, delayed dictation, pasted quotation, find/replace, external restore and Stage 07 input-gate cases. Exercise affected predecessor exact-byte/undo/recovery boundaries once. The specified random replay is mandatory, not an invitation to repeatedly increase seeds/test counts after a pass.
2. **One real-input session on the candidate:** US and German layouts/dead keys; at least one actual IME; emoji and RTL; VoiceOver editing; spell correction; app on-device dictation and native system dictation; Services/Writing Tools availability. Note actual OS capabilities and unavailable paths. Synthetic delegate calls alone cannot pass these observations. Batch high-contrast, Reduce Motion and keyboard checks into this session.
3. **One performance/visual session:** 100k-word fixture with actual timings, responsive caret/selection/scrolling/outline and recovery interaction. Capture actual editor, inspector, annotation and relevant error states at both required window sizes/appearances. Combine observations where one artifact proves several requirements; do not invent a larger permutation matrix. Screenshots supplement interaction, never replace it.
4. **Final scoped review:** actual signature/entitlements if changed, exact frozen/protected path diff and all M14–M21 evidence. Do not rerun unaffected full protocol/provider suites or passing batches. Astra reviews final integrated code and evidence; no additional reviewer agent is needed.

### Focused commands and script caveat

Run commands from the repository root and inspect scripts first. Use actual test names selected from changed code. These examples are recipes, not recorded execution evidence:

```sh
python3 tools/check_preparation.py
python3 tools/bootstrap_protocol.py
swift test --package-path mac/Packages/WriterFoundation --filter ACTUAL_TEST_NAME
swift test --package-path mac/Packages/WriterStorage --filter ACTUAL_TEST_NAME
```

`mac/scripts/test.sh` runs broad prerequisite package checks before native tests. Once dependencies are resolved at their committed pins, a focused native invocation can use:

```sh
xcodebuild -project mac/NostrWriter.xcodeproj -scheme NostrWriter \
  -configuration Debug -derivedDataPath mac/.build/NativeTestDerivedData \
  -clonedSourcePackagesDirPath mac/DerivedData/SourcePackages \
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile \
  -skipPackageUpdates -destination 'platform=macOS' \
  -skipPackagePluginValidation ARCHS=arm64 ONLY_ACTIVE_ARCH=YES test \
  -only-testing:NostrWriterTests/ShellTests/ACTUAL_TEST_NAME \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 30 \
  -maximum-test-execution-time-allowance 30
```

Replace `ACTUAL_TEST_NAME`; it is not a runnable test identifier. Use an existing scheme/class/method and adjust architecture to actual host. A fresh clone must resolve pinned packages first using the existing build setup. Keep the test build separate from the normal signed build. Tests requiring `NW_COORDINATED_WRITER` and `TEST_RUNNER_NW_COORDINATED_WRITER` need the existing synthetic coordinated-writer helper; a skipped prerequisite is not a passed regression.

For the normal app, use `mac/scripts/build_signed_development.sh` with the actual existing `WRITER_DEVELOPMENT_TEAM` configured locally. Never put a private key or certificate/account secret in the command/report. Preserve locked package revisions and the actual minimum OS; do not turn off strict concurrency or the sandbox to make checks pass.

## Completion record

Write `product/mac/evidence/STAGE-03.md` and `.json`; put synthetic supporting artifacts under `product/mac/evidence/logs/stage-03/` or an explicitly linked evidence directory outside frozen paths. Include:

- Full predecessor/input commit, implementation candidate commit(s), output/evidence commit and executable hash. Since an evidence commit cannot contain its own final hash, record the implementation hash inside it and report the resulting evidence commit in the handoff; do not use an unresolved placeholder as claimed provenance.
- Changes to app contracts/schema, actual commands, results, environment, test seed/fixture sizes and native observations with their candidate identity.
- Every M14–M21 row as PASS, FAIL, NOT MEASURED or BLOCKED with reason and paths. Preserve earlier failures as scoped history; clearly identify their corrected results. Unsupported observations, screenshots of inaccessible content and historical test claims are not current passes.
- Exact remaining access/decision/observation needed, plus work completed independently. `accepted` remains false while any mandatory row lacks the required pass; do not weaken `acceptance.json` or call Stage 03 complete because a budget is exhausted.
- Stage 04 handoff: descriptive journal/schema/fixtures, capture limitations, immutable source/record interfaces and unchanged empty production approval state. Do not implement Stage 04 during this handoff.

Before commit/push, inspect the diff for private text/audio/keys, unrelated files and any frozen/history change. Commit coherent code, tests, resources and truthful evidence to `implementation/stage-03`; push that branch to `origin`. Do not merge or publish a release. After final Astra review, stop at the Stage 03 boundary.
