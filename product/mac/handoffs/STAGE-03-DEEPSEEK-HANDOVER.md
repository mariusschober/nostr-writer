# Stage 03 handover — DeepSeek V4.1 Flash

Prepared 18 September 2026. This is a current implementation handover, supplementary to the recovered product contracts. It does not replace them or claim Stage 03 is implemented.

## Start here

The macOS app has accepted Stages 01 and 02. Stage 03 is the finished editor, transparent assistance and truthful local writing-history stage, covering **M14–M21**. The owner paused implementation after Stage 02. Preparing/pushing these documents does not resume that work; the [start prompt](STAGE-03-DEEPSEEK-START-PROMPT.md) is for the owner's next implementation run.

Use these four documents together:

1. This handover: repository state, architecture, existing behavior and pitfalls.
2. [Executable Stage 03 plan](STAGE-03-DEEPSEEK-PLAN.md): bounded work packages, acceptance and verification.
3. [PLAN-mode prompt](STAGE-03-DEEPSEEK-PLAN-PROMPT.md): a single planning pass if the owner wants to review the implementation approach first.
4. [Implementation start prompt](STAGE-03-DEEPSEEK-START-PROMPT.md): execute Stage 03; stop before Stage 04.

Do not use the planning prompt as a prerequisite for every implementation session. There is already a detailed plan. The start prompt can be used directly.

## Repository and accepted checkpoint

Repository: [mariusschober/nostr-writer](https://github.com/mariusschober/nostr-writer). Local workspace: `/Users/schober/Projects/Nostr Writer`.

| Reference | Meaning |
| --- | --- |
| [`implementation/stage-02`](https://github.com/mariusschober/nostr-writer/tree/implementation/stage-02) | Completed app and accepted predecessor; also carries this handover. Start here. |
| [`b8568c09530b90e28a3d1fb817335c6a980fc116`](https://github.com/mariusschober/nostr-writer/commit/b8568c09530b90e28a3d1fb817335c6a980fc116) | Accepted Stage 02 checkpoint, including final owner-confirmed VoiceOver evidence. All baseline links below are pinned here. |
| [`67302883935fcfaba2b9668a04df3aee60820fcd`](https://github.com/mariusschober/nostr-writer/commit/67302883935fcfaba2b9668a04df3aee60820fcd) | Final Stage 02 application source; later predecessor commits record observations/acceptance. |
| [`1fb862549db78b9d94c0af6d5e29210b7c37377a`](https://github.com/mariusschober/nostr-writer/commit/1fb862549db78b9d94c0af6d5e29210b7c37377a) | Accepted Stage 01 checkpoint; already included in Stage 02 ancestry. |
| [`main` at `3fdab5b1f8d75720c3025e8604f947e2307c31e2`](https://github.com/mariusschober/nostr-writer/commit/3fdab5b1f8d75720c3025e8604f947e2307c31e2) | Recovered preparation baseline at handover time. Starting here would omit the implemented app. |
| `implementation/stage-03` | Intended new implementation branch. Create from the handover tip of `implementation/stage-02` after inspecting local/remote state. It is not created by this documentation handoff. If it already exists, inspect before choosing or continuing it. |

Fetch and inspect HEAD, status, branches and remotes before switching. Preserve unrelated changes; never reset them to make checkout convenient. Confirm `b8568c0` is an ancestor and Stage 02's current ledger still says accepted. Record the full input commit in Stage 03 evidence. If subsequent changes appear on the predecessor, inspect their scope rather than assuming this snapshot describes them.

**Historical availability warnings are time-scoped.** `AGENTS.md`, `IMPLEMENTATION.md`, recovery notes, preparation reports and `product/mac/evidence/STATUS.json` retain statements from the recovered preparation state. WriterFoundation now exists. Stages 01 and 02 are accepted in their stage ledgers. Read historical documents for authority/provenance, but do not recreate Foundation, apply the old “47 tests” claim to new code, or rewrite historical originals to make them look current.

## Required context, in reading order

All links in this section describe the immutable accepted baseline. Read the corresponding current repository copies when implementing, checking differences from this commit.

**Entry and stage authority**

- [AGENTS.md](https://github.com/mariusschober/nostr-writer/blob/b8568c09530b90e28a3d1fb817335c6a980fc116/AGENTS.md), [IMPLEMENTATION.md](https://github.com/mariusschober/nostr-writer/blob/b8568c09530b90e28a3d1fb817335c6a980fc116/IMPLEMENTATION.md), [RECONCILIATION.md](https://github.com/mariusschober/nostr-writer/blob/b8568c09530b90e28a3d1fb817335c6a980fc116/RECONCILIATION.md), [RECOVERY-NOTES.md](https://github.com/mariusschober/nostr-writer/blob/b8568c09530b90e28a3d1fb817335c6a980fc116/product/mac/RECOVERY-NOTES.md).
- [Original PLAN-03-EDITOR.md](https://github.com/mariusschober/nostr-writer/blob/b8568c09530b90e28a3d1fb817335c6a980fc116/product/mac/plans/PLAN-03-EDITOR.md), [original START-03.md](https://github.com/mariusschober/nostr-writer/blob/b8568c09530b90e28a3d1fb817335c6a980fc116/product/mac/starts/START-03.md), [all 60 acceptance requirements](https://github.com/mariusschober/nostr-writer/blob/b8568c09530b90e28a3d1fb817335c6a980fc116/product/mac/contracts/acceptance.json).
- [Stage 01 evidence](https://github.com/mariusschober/nostr-writer/blob/b8568c09530b90e28a3d1fb817335c6a980fc116/product/mac/evidence/STAGE-01.md), [Stage 02 evidence](https://github.com/mariusschober/nostr-writer/blob/b8568c09530b90e28a3d1fb817335c6a980fc116/product/mac/evidence/STAGE-02.md) and [Stage 02 machine-readable acceptance](https://github.com/mariusschober/nostr-writer/blob/b8568c09530b90e28a3d1fb817335c6a980fc116/product/mac/evidence/STAGE-02.json). Read the final disposition before interpreting earlier failed/blocked checkpoints retained in those files.

**Product and implementation contracts**

- [UX.md](https://github.com/mariusschober/nostr-writer/blob/b8568c09530b90e28a3d1fb817335c6a980fc116/product/mac/UX.md) in full, especially U01–U04, U06–U08, U15 and keyboard/accessibility behavior.
- [PRODUCT.md](https://github.com/mariusschober/nostr-writer/blob/b8568c09530b90e28a3d1fb817335c6a980fc116/product/mac/PRODUCT.md), [ARCHITECTURE.md](https://github.com/mariusschober/nostr-writer/blob/b8568c09530b90e28a3d1fb817335c6a980fc116/product/mac/ARCHITECTURE.md), [interfaces.md](https://github.com/mariusschober/nostr-writer/blob/b8568c09530b90e28a3d1fb817335c6a980fc116/product/mac/contracts/interfaces.md).
- [DATA.md](https://github.com/mariusschober/nostr-writer/blob/b8568c09530b90e28a3d1fb817335c6a980fc116/product/mac/DATA.md), [SECURITY.md](https://github.com/mariusschober/nostr-writer/blob/b8568c09530b90e28a3d1fb817335c6a980fc116/product/mac/SECURITY.md), [HWP.md](https://github.com/mariusschober/nostr-writer/blob/b8568c09530b90e28a3d1fb817335c6a980fc116/product/mac/HWP.md), [FOCUS.md mutation restrictions](https://github.com/mariusschober/nostr-writer/blob/b8568c09530b90e28a3d1fb817335c6a980fc116/product/mac/FOCUS.md), [EXPORT.md Markdown grammar](https://github.com/mariusschober/nostr-writer/blob/b8568c09530b90e28a3d1fb817335c6a980fc116/product/mac/EXPORT.md).

**Frozen observation/replay authority, before writing capture code**

- [SPECIFICATION.md](https://github.com/mariusschober/nostr-writer/blob/b8568c09530b90e28a3d1fb817335c6a980fc116/protocol/v0/SPECIFICATION.md), [ALGORITHM.md](https://github.com/mariusschober/nostr-writer/blob/b8568c09530b90e28a3d1fb817335c6a980fc116/protocol/v0/docs/ALGORITHM.md), [BINDING.md](https://github.com/mariusschober/nostr-writer/blob/b8568c09530b90e28a3d1fb817335c6a980fc116/protocol/v0/docs/BINDING.md), [CONFORMANCE.md](https://github.com/mariusschober/nostr-writer/blob/b8568c09530b90e28a3d1fb817335c6a980fc116/protocol/v0/docs/CONFORMANCE.md).
- [telemetry.schema.json](https://github.com/mariusschober/nostr-writer/blob/b8568c09530b90e28a3d1fb817335c6a980fc116/protocol/v0/telemetry.schema.json), [schema.cddl](https://github.com/mariusschober/nostr-writer/blob/b8568c09530b90e28a3d1fb817335c6a980fc116/protocol/v0/schema.cddl), [frozen replay oracle](https://github.com/mariusschober/nostr-writer/blob/b8568c09530b90e28a3d1fb817335c6a980fc116/protocol/v0/hwp0/algorithm/replay.py). Read incorporated baseline material only through the joined v0 specification; do not mix historical implementations into the app.

## Existing implementation: extend it, do not replace its safe boundaries

Paths below link to the accepted code and identify the first inspection targets. Proposed new file names belong in the implementation plan; they are not claims that those files already exist.

| Existing source | What it does and what Stage 03 changes |
| --- | --- |
| [WriterWindowController.swift](https://github.com/mariusschober/nostr-writer/blob/b8568c09530b90e28a3d1fb817335c6a980fc116/mac/NostrWriter/Documents/WriterWindowController.swift) | Already uses `NSTextView(usingTextLayoutManager: true)`, native undo, basic typography, library sidebar, save/conflict status and recording-consent entry. It remains a temporary editor: whole-string `textDidChange` calls, whitespace counts, static layout and no finished observation/inspector. Extract a native editor adapter while preserving the single live text storage. Never access legacy `layoutManager`. |
| [WriterDocument.swift](https://github.com/mariusschober/nostr-writer/blob/b8568c09530b90e28a3d1fb817335c6a980fc116/mac/NostrWriter/Documents/WriterDocument.swift) | Owns NSDocument lifecycle, exact loaded/saving byte snapshots, queued immutable saves, source identity, recovery and file-presenter integration. `acceptScratchEdit` currently emits a whole-document replacement with unknown/programmatic origin. Route its callers, restore/revert/external reload and managed-image insertion through the new mutation boundary without breaking save revision ownership. |
| [DocumentSession.swift](https://github.com/mariusschober/nostr-writer/blob/b8568c09530b90e28a3d1fb817335c6a980fc116/mac/NostrWriter/Documents/DocumentSession.swift) | Main-actor immutable revision owner implementing `DocumentEditing`. `finalizeObservation` returns nil when off and otherwise throws the Stage 03-unavailable error. Replace this with a real descriptive-record lifecycle; do not make a software-only handle an HWP approval. |
| [WriterFoundation sources](https://github.com/mariusschober/nostr-writer/tree/b8568c09530b90e28a3d1fb817335c6a980fc116/mac/Packages/WriterFoundation/Sources/WriterFoundation) | Real Stage 01 types/tests: snapshots, exact coordinates, revision IDs, mutation commands/receipts, origins, completeness, typed service contracts and focus state. Extend these pure contracts for capture epochs, ancestry and annotations where needed. Preserve stale-revision rejection and scalar-aligned byte ranges. |
| [DocumentStore.swift](https://github.com/mariusschober/nostr-writer/blob/b8568c09530b90e28a3d1fb817335c6a980fc116/mac/Packages/WriterStorage/Sources/WriterStorage/DocumentStore.swift) and [SchemaMigration.swift](https://github.com/mariusschober/nostr-writer/blob/b8568c09530b90e28a3d1fb817335c6a980fc116/mac/Packages/WriterStorage/Sources/WriterStorage/SchemaMigration.swift) | Serial encrypted recovery storage, AES-GCM before SQLite, WAL durability and migration backup. Recovery batches validate receipt chains but **do not persist detailed capture history**. Rolling recovery pruning cannot be used as the writing-history retention policy. Add separately owned encrypted history storage with a safe migration. |
| [DocumentRecovery.swift](https://github.com/mariusschober/nostr-writer/blob/b8568c09530b90e28a3d1fb817335c6a980fc116/mac/NostrWriter/Documents/DocumentRecovery.swift) | Bridges actual encrypted recovery into the document, including current-revision durability checks and bounded interruption flush. Keep recovery independent of recording consent, history capacity and capture availability. |
| [DocumentFileLifecycle.swift](https://github.com/mariusschober/nostr-writer/blob/b8568c09530b90e28a3d1fb817335c6a980fc116/mac/NostrWriter/Documents/DocumentFileLifecycle.swift), [DocumentAssets.swift](https://github.com/mariusschober/nostr-writer/blob/b8568c09530b90e28a3d1fb817335c6a980fc116/mac/NostrWriter/Documents/DocumentAssets.swift) | Existing conflict preservation, folder grants and managed image insertion. File imports are unobserved wording; Markdown image syntax inserted by the app is formatting, not physical typing. Preserve these distinctions and existing permissions. |
| [RecordingConsent.swift](https://github.com/mariusschober/nostr-writer/blob/b8568c09530b90e28a3d1fb817335c6a980fc116/mac/NostrWriter/Application/RecordingConsent.swift), [SettingsWindowController.swift](https://github.com/mariusschober/nostr-writer/blob/b8568c09530b90e28a3d1fb817335c6a980fc116/mac/NostrWriter/Application/SettingsWindowController.swift), [AppMenus.swift](https://github.com/mariusschober/nostr-writer/blob/b8568c09530b90e28a3d1fb817335c6a980fc116/mac/NostrWriter/Application/AppMenus.swift) | Consent currently persists an off/requested preference and explains the unavailable capture shell. Activate only implemented recording behavior, update truthful wording, add editor/assistance preferences and native commands. Preserve existing File/Edit actions and shortcuts. |
| [AppDelegate.swift](https://github.com/mariusschober/nostr-writer/blob/b8568c09530b90e28a3d1fb817335c6a980fc116/mac/NostrWriter/Application/AppDelegate.swift) | Existing startup, library, sleep and normal quit negotiation. Wire capture/dictation interruption cancellation into this lifecycle without replacing recovery or trapping termination. |
| [WriterExport package](https://github.com/mariusschober/nostr-writer/tree/b8568c09530b90e28a3d1fb817335c6a980fc116/mac/Packages/WriterExport) | Contains the already pinned Markdown dependency and asset-reference support. Reuse the grammar/pins; do not add a competing parser, HTML preview or a full Stage 05 renderer. |
| [ShellTests.swift](https://github.com/mariusschober/nostr-writer/blob/b8568c09530b90e28a3d1fb817335c6a980fc116/mac/NostrWriterTests/ShellTests.swift) | Actual native regression seams for TextKit 2, exact bytes, undo, revisions, save/revert/duplicate, recovery, conflicts and managed assets. Extend affected coverage; do not treat test-app behavior as an observed normal signed app. |

Known foundation vocabulary: `EditOrigin`, `EditCommand`, `MutationReceipt`, `CaptureCompleteness`, `CapturedRecordHandle`, `DocumentEditing`. Origins already distinguish IME update/commit, known assistance, external paste, internal move/copy, undo/redo, formatting, find/replace, external reload, recovery and unknown. Classify from observed/declared causes, never from text shape.

### Accepted behavior that is easy to regress

- [Recovery timing fix `1333b4c`](https://github.com/mariusschober/nostr-writer/commit/1333b4cb31bcbdd7c786096cff0b97432b6f348a) uses a **500 ms** production checkpoint interval to leave write time inside the one-second durability requirement, marks pending immediately and compares current revision/digest. A focused 57,344-byte, 40-insertion run with ten presenter callbacks measured recovery at 563.73 ms and edit p95 at 41.69 ms. This is not Stage 03's 100k-word performance evidence.
- Provider renames follow the adopted `NSDocument.fileURL`; presenter callbacks can precede that adoption. Do not restore a stale URL from a callback.
- Keep Both needs an explicitly selected/granted sibling directory. Pin/Unpin changes metadata without re-reading a file or renewing its bookmark.
- The final conflict comparison fix sizes the NSStackView accessory with its fitting size. An accessibility tree containing both versions did not prove they were visibly rendered; actual light/dark observation caught and verified the fix.
- Native undo can change text outside the ordinary delegate callback. Existing undo synchronization must be integrated into the gateway, with exactly one revision per actual mutation, not silently removed or double-counted.
- NSDocument owns its coordinated read/write accessors. Do not nest an independent NSFileCoordinator around them.
- Preserve exact BOM, line endings, decomposed Unicode, bytes outside edited spans, document UUIDs and derived-copy identities. Editor display attributes and preferences must never rewrite source bytes.

## Evidence status and its limits

Stage 02's final JSON says `accepted: true`, `status: PASS`; M07–M13 pass. It includes native file/recovery/conflict/library work, real iCloud and Google Drive for desktop lifecycle observations, actual sleep/wake and final owner-confirmed VoiceOver. The owner first reported a system-wide lack of speech, then confirmed “Now it works, mark it as passed.” The final VoiceOver result is an **owner observation**, not captured audio from an agent. There is no remaining Stage 02 VoiceOver exception to fix.

The accepted normal signed app used source `6730288`; its executable SHA-256 was `5364c150703529304517f1974d825f9b5074027f010f2f601d42d91693b44b54`. Local path: `mac/.build/SignedDevelopment/Build/Products/Debug/NostrWriter.app`. Rebuilding Stage 03 creates a new candidate/hash; this hash cannot prove its behavior.

Useful evidence directory: [Stage 02 logs](https://github.com/mariusschober/nostr-writer/tree/b8568c09530b90e28a3d1fb817335c6a980fc116/product/mac/evidence/logs/stage-02). Read the scoped records if an affected subsystem needs review. In particular, cross-volume move evidence is a real mounted-volume adapter test, not a completed native cross-volume chooser journey. iCloud conflict evidence uses a second coordinated local process; Google Drive also includes an actual remote edit. Do not broaden these claims. Intel runtime, release/notarization, full editor provenance and 100k-word performance are not established by predecessor acceptance.

## Non-negotiable architecture and privacy boundaries

1. **One live editor, one revision gateway.** Native text storage owns the live editing buffer; the session publishes exact immutable snapshots. SwiftUI observes snapshots and sends explicit commands, never a stale String binding. Pure provenance/replay logic stays out of AppKit views.
2. **Descriptive local history is not HWP telemetry.** Give it a separate version namespace. Preserve actual native delivery, transaction and event distinctions. Never synthesize key-up, independent delivery, timings, parent capture or hardware authority from an edit receipt. Unknown remains unknown; normal writing still works.
3. **Ancestry follows actual operations.** Internal copy/move requires an app-issued private source token and exact live data equality. Identical text alone is insufficient. Undo/redo refer to real recorded operations. Bound annotations to exact scalar-aligned UTF-8 source lineage; mark ambiguity stale instead of moving an exclusion onto new wording.
4. **Consent gates detailed retention.** Off means no detailed revisions/deleted-text journal is persisted. Ordinary encrypted recovery still runs. Recording starts prospectively, pause/resume and gaps create boundaries, and deleting history is distinct from deleting source. Do not erase earlier consented history merely because recording is paused.
5. **History capacity cannot stop writing.** Follow DATA retention: retain until user deletes; warn at 1 GiB and pause detailed recording at 2 GiB, reserving source/recovery/outbox capacity. A Keychain or journal failure must not silently generate replacement keys or claim recording is healthy.
6. **Dictation is optional and on-device only.** Request microphone/speech access at invocation, indicate listening, support Stop, keep callbacks confined to a valid range/generation, and refuse unavailable on-device recognition. No silent cloud fallback or ambient recording.
7. **Production HWP approvals remain empty.** Display the contracted NOT PROVABLE explanation. Stage 04 owns complete native producer/verifier/recomputation and detailed-evidence interchange. Stage 03 supplies honest typed records and fixtures; it neither approves a Mac capture profile nor implements a fake always-negative substitute for the later real pipeline.
8. **Preserve protocol and history.** All 69 files under `protocol/v0/` and historical originals are immutable. Keep all 60 acceptance definitions unchanged. New app semantics belong outside the frozen protocol.

## Build, device and verification operating notes

Read [mac/DEVELOPMENT.md](https://github.com/mariusschober/nostr-writer/blob/b8568c09530b90e28a3d1fb817335c6a980fc116/mac/DEVELOPMENT.md) and [docs/VERIFICATION.md](https://github.com/mariusschober/nostr-writer/blob/b8568c09530b90e28a3d1fb817335c6a980fc116/docs/VERIFICATION.md), then inspect script side effects before execution. Stage 02 used Xcode 27.0 (27A266a) on macOS 26.6.2; record actual tools/hardware for the next run, not this historical description as a current measurement.

- `mac/scripts/build.sh` is an ordinary ad-hoc build. It does not establish real recovery Keychain access.
- `mac/scripts/build_signed_development.sh` uses `WRITER_DEVELOPMENT_TEAM` with the owner's existing configured Apple Development identity/profile. This Mac's owner already approved/completed development signing and registration. Reuse it; do not recreate certificates or place account/team credentials in public reports. A different host may need an owner access decision.
- The entitlement allowlist in `mac/scripts/inspect_app.py` must be kept consistent if an actually necessary microphone entitlement is introduced. Update both normal and development entitlement files narrowly. No AX, Input Monitoring, global input taps or new unrelated privileges. Info.plist currently has no microphone/speech usage descriptions.
- Keep native test DerivedData separate from the signed normal app. Select the exact normal app path during UI verification: multiple builds share bundle identities.
- **`mac/scripts/test.sh` runs package suites/builds before native tests even when a native `-only-testing` argument is supplied.** For a focused native check use the underlying xcodebuild invocation and the actual test names; do not accidentally rerun every suite per edit. See the plan for commands.
- Real File Provider tests and signing setup do not need to be repeated for unchanged editor-only work. Repeat only affected regressions, using synthetic fixtures.
- UI automation may time out after an action has already succeeded. Observe fresh state before retrying. In prior work VoiceOver Utility automation stalled; do not repeat that investigation. New editor VoiceOver acceptance still requires an actual new observation, by the agent where observable or explicitly attributed owner confirmation.
- Previous cloud-test permission was for synthetic test folders in the owner's selected accounts. It is not permission to upload writing history or record the microphone. Stage 03 should normally need neither cloud provider manipulation nor a Drive API integration.

## Working agreement for the next run

DeepSeek V4.1 Flash is the implementation worker. Astra owns architecture, difficult decisions and final review. Use one worker and one owner for the branch/index/build/device; do not spawn subagents. Bring a concrete architecture conflict or unresolved failure to Astra with evidence, not a broad request to redesign the product.

Give a short effort estimate and a bounded checklist, then implement. Do not spend a session generating another roadmap. Compile/run the relevant fast check before each coherent implementation handoff. After two failed attempts at the same problem, stop the retry loop, summarize the cause and change approach. Passing checks are not repeated without affected changes. Report completed application capabilities, commits or acceptance evidence; activity is not progress.

The owner's push authorization covers project work to this GitHub repository. Keep commits scoped and publish the Stage 03 branch when executing the start prompt. It does not authorize merging main, deleting branches, releasing/notarizing, publishing Nostr events or disclosing private evidence. No real drafts, keys, audio, credentials, provider contents or participant traces belong in Git. Keep the overall eight-stage goal unfinished until its mandatory requirements are actually met; Stage 03 completion is only a stage handoff.
