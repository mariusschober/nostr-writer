# Stage 02 — accepted

**Accepted on 18 September 2026. All M07–M13 PASS in their recorded scopes, including owner-confirmed VoiceOver.**
Stage 01 is accepted at `1fb8625`. Accepted implementation source is
`67302883935fcfaba2b9668a04df3aee60820fcd` on `implementation/stage-02`.
Native document/storage/provider, recovery, library and appearance evidence is recorded below. The owner subsequently confirmed working VoiceOver and directed it to pass. All 60 definitions are unchanged. **Pause before Stage 03.**
Later checkpoints below supersede earlier unobserved/blocked states only in their stated scopes.

## Implemented checkpoint

WriterStorage provides AES-GCM encrypted SQLite recovery, a bounded rolling journal,
migrations, integrity checks, coordinated source files/bookmarks, one-second scheduling,
load-only scoped Keychain access, and installation bootstrap. Bootstrap creates a key
only for an exclusively leased, new empty installation; inaccessible existing keys never
cause replacement. Private plaintext AppKit draft autosaves remain disabled. Ordinary
source saving remains available when private recovery fails.

Schema 2 adds a bounded catalog of document UUIDs, source locations, bookmarks, saved
revisions/digests and derivation links. Migration from version 1 backs up first. Recovery
bodies remain encrypted; title/bookmark/activity metadata is not anonymous. Reopening
an edited file retains its UUID and preserves a different unsaved recovery as a separate
entry before replacing its current checkpoint. Orphan recovery checkpoints remain visible.

The native sidebar now exposes New/Open, Recent, current-title/body Search, Recovered
drafts and recovery failure. Search reads current encrypted snapshots transiently; it
never indexes deleted history or keys. Recovered file-bound text opens as a new derived
copy rather than overwriting the file. Bookmark renewal requires an explicit selection.
Selected folders and reference actions are now implemented below; coordinated move/assets/Trash remain unfinished.

Native saves use immutable byte snapshots and matching change-count tokens. A bounded
queue serializes physical writes and coalesces consecutive requests for the same target;
a save of an earlier revision cannot mark later edits saved. Save As creates a new UUID
and durable derivation metadata; Duplicate starts from an in-memory copy.

Revert now first writes an independent encrypted recovery copy; failure leaves current
text open. Direct unpreserved Revert is refused. Recovery flush requests are attached to
Save, native close negotiation, window/app deactivation and system sleep notification.
Waiting for recovery is capped at five seconds without claiming unfinished commits as
durable. Native Save/Discard/Cancel remains in control of close negotiation. Full normal
quit and real system-sleep behavior have not been observed or accepted.

## Actual bounded verification

- **PASS:** 17 catalog/schema checks, 0.210 s. After adding the aggregate metadata bound,
  only the three affected catalog checks ran again: **PASS**, 0.058 s.
- **PASS:** final three native lifecycle checks, 1.175 s. Exact BOM/decomposed Unicode/
  CRLF/whitespace source after Save/Revert/Save As; pre-Revert text retained separately;
  Duplicate and Save As identity/derivation; persistent reopen with separate unsaved
  recovery; three overlapping save callers writing the latest exact bytes; native
  `canClose` callback only after latest recovery is durable. Real temporary SQLite/files
  and synthetic key only. The full app and native test target compile for arm64.
- **PASS within scope:** actual native typing → Save panel → close → Open panel → same
  exact 63-byte synthetic source. Initial Recent omission was fixed; the final Recent row,
  exact editor text and “Saved to…” state were observed. Recovery unavailable/Retry also
  appeared, while editing and file saving worked. Binary hashes and limitations are in
  `logs/stage-02/library-ui-observation.json`. This GUI observation predates the later
  lifecycle/save-queue changes; those changes are not claimed visually verified.
- **PASS:** read-only preparation/protocol checks: 69 frozen files, 326 pinned recovery
  files, all 60 criteria retained. No protocol or historical original was rewritten.
- Prior six bootstrap checks and earlier component evidence retain their original scopes.
  Existing passing broad suites and VoiceOver were not repeated.

The first boundary build was blocked before compilation by sandbox cache access. The
native build then exposed a Swift restriction on `super` in an explicitly capturing
closure; a synchronous callback helper fixed it. The next focused run passed. Earlier
catalog compile/setup corrections and the original asynchronous-save actor isolation
fix are not counted as successful tests. No test was rerun after its final passing
result without a relevant code change. This checkpoint does not use a test loop.

Commands (logs in `logs/stage-02/`):

```sh
swift test --package-path mac/Packages/WriterStorage --filter 'DocumentCatalogTests|SchemaRetentionFaultTests'
swift test --package-path mac/Packages/WriterStorage --filter DocumentCatalogTests
xcodebuild -project mac/NostrWriter.xcodeproj -scheme NostrWriter -configuration Debug -derivedDataPath mac/.build/NativeTestDerivedData -destination 'platform=macOS' -skipPackagePluginValidation ARCHS=arm64 ONLY_ACTIVE_ARCH=YES -only-testing:NostrWriterTests/ShellTests/testNativeSaveRevertAndDuplicateKeepExactBytesAndIdentity -only-testing:NostrWriterTests/ShellTests/testQueuedSavesAndCloseBoundaryPreserveLatestRevision -only-testing:NostrWriterTests/ShellTests/testPersistentIdentityReopenPreservesDifferentUnsavedRecovery test
python3 tools/check_preparation.py
python3 tools/bootstrap_protocol.py
```

## External conflict checkpoint

Native presenter notifications now schedule a bounded, separate coordinated read; the
reader excludes its own document presenter. Exact bytes distinguish own-save echoes
from external versions. Native source writes compare the last observed bytes again
inside the document accessor, without recursive coordination. An unreviewed external
change cannot silently replace the provider file.

Review Changes provides a bounded side-by-side comparison and Keep Both (default),
Keep Local, Open External Copy, and Cancel. Every applied choice first preserves both
exact versions in encrypted recovery. Keep Both creates a new dated source file at an
explicitly selected location, with a new UUID/derivation. Keep Local rechecks the external
bytes at native replacement; Open External Copy leaves the original dirty document
intact. A clean external reload preserves its previous source and records external
provenance. Key failure prevents destructive resolution and leaves ordinary Save As
available. Post-check review also clears the old conflict after a successful Save As.

Two focused native checks **PASS**, zero skips, 1.948 seconds, using a compiled second
coordinated writer process and synthetic keys. They cover all three choices, stale-save
refusal, exact preserved bytes, clean reload, own-write echo and the affected save queue.
A test-field compile error was corrected before the successful run. The final ordinary
arm64 app build **PASS** includes small later comparison geometry/Save As status changes;
those branches have not been retested. No passing native check was repeated afterward.

The single attempted UI observation is **BLOCKED**: the computer-use tool reported a
locked Mac and failed automatic unlock. The owner was asked to unlock it; no new conflict
screen or provider interaction is claimed observed. Exact logs, binary hash, scope and
limitations are in `logs/stage-02/conflict-results.json`.

```sh
xcrun swiftc mac/Packages/WriterStorage/Tools/coordinated_writer.swift -o /private/tmp/nostr-writer-coordinated-writer-stage02
NW_COORDINATED_WRITER=/private/tmp/nostr-writer-coordinated-writer-stage02 TEST_RUNNER_NW_COORDINATED_WRITER=/private/tmp/nostr-writer-coordinated-writer-stage02 xcodebuild -project mac/NostrWriter.xcodeproj -scheme NostrWriter -configuration Debug -derivedDataPath mac/.build/NativeTestDerivedData -destination 'platform=macOS' -skipPackagePluginValidation ARCHS=arm64 ONLY_ACTIVE_ARCH=YES -only-testing:NostrWriterTests/ShellTests/testExternalChangesPreserveBothSourcesAndRejectUnreviewedSave -only-testing:NostrWriterTests/ShellTests/testQueuedSavesAndCloseBoundaryPreserveLatestRevision test
```

## Selected-folder library checkpoint

The sidebar now includes Open, Pinned and explicitly selected library folders, plus
Locate/Remove actions for unavailable references and Reveal in Finder. Folder bookmarks
and optional pin/folder metadata remain private; existing catalog records still decode.
Removing a reference never deletes source or hides independently recoverable unsaved text.
Bookmark-resolved moved locations update catalog identity before reopening where possible.

Folder scans use only the selected grant, reject symlinks/escaped paths, skip hidden files
and packages, and list Markdown/text files. Body search reads current locally materialized
source, not private history or a persistent plaintext body index. Known cloud placeholders
are left for explicit native Open. Caps are disclosed through limited/unavailable messages:
16 folders, 4096 visited entries and depth 8 per folder, 64 MiB searched bytes per folder.
If private metadata is unavailable, a newly selected folder is explicitly session-only.

Three affected folder checks **PASS**, 0.022 seconds; one backward-compatible metadata
check **PASS**, 0.013 seconds. The initial run exposed two real defects: `/private/var`
aliases corrupted relative names, and skipping descendants on a non-directory omitted a
nested sibling. A small synthetic URL diagnostic identified the cause; standardization
and directory-only skipping fixed it. Only the affected folder checks ran again, once.
The final ordinary arm64 app build **PASS**. Native UI and provider use are **NOT MEASURED**;
the last computer-use result was a locked Mac and the unlock request is still pending.
See `logs/stage-02/folders-results.json` for exact scope, binary hash and limitations.

```sh
swift test --package-path mac/Packages/WriterStorage --filter 'LibraryFoldersTests|DocumentCatalogTests/testOptionalFolderMetadataReadsOlderRecordsAndRejectsSourceHistory'
swift test --package-path mac/Packages/WriterStorage --filter LibraryFoldersTests
xcodebuild -project mac/NostrWriter.xcodeproj -scheme NostrWriter -configuration Debug -derivedDataPath mac/DerivedData -destination 'platform=macOS' -skipPackagePluginValidation ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build
```

## Explicit import and quit checkpoint

File → Import Text Copy opens a separate native review window with an explicit encoding
selector and preview. It never guesses the encoding or rewrites the original. UTF-8
retains exact source bytes; UTF-16 LE/BE, Windows-1252 and Latin-1 are deliberate conversions
into a new unsaved document. Malformed input fails without replacement characters. The
preview is bounded and conversion runs off the main actor; Import remains disabled until
the current source has loaded and its selected conversion succeeds. Local metadata records
original bytes/digest, selected encoding and converted digest, without granting HWP status.
Ordinary Open rejects invalid UTF-8 and points to this explicit import-copy action.

Normal Quit now returns `terminateLater`, runs native `closeAllDocuments` negotiation,
and replies only when native document closing completes or is cancelled. This retains
per-document recovery flushes and native Save/Discard/Cancel. The app compiles; actual
multi-document quit/cancel and importer UI are **NOT MEASURED** while unlock is pending.

One focused import check **PASS**, 0.033 seconds, covering strict source decoding, exact
UTF-8 BOM/Unicode/CRLF preservation, explicit conversions, malformed UTF-16 refusal,
unchanged original file, limits and retained descriptive metadata. Final ordinary arm64
app build **PASS**. No passing check was repeated. Details and binary hash are in
`logs/stage-02/text-import-results.json`.

```sh
swift test --package-path mac/Packages/WriterStorage --filter TextImportTests
xcodebuild -project mac/NostrWriter.xcodeproj -scheme NostrWriter -configuration Debug -derivedDataPath mac/DerivedData -destination 'platform=macOS' -skipPackagePluginValidation ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build
```

## Managed-image checkpoint

Format → Insert Image copies selected PNG/JPEG bytes into a granted sibling asset folder,
then inserts a Markdown link through the native text editor. Metadata records exact image
hashes and ownership; recovery copies and duplicates retain these records. Source insertion
waits for ownership persistence and uses formatting origin, never a direct-input claim.
The 20 MiB/image, 100 MiB total, 50 MP and collision/path bounds are enforced.

Save As scans actual Markdown image nodes, selects only app-owned referenced files, and
asks before copying to a different granted folder. Relative paths remain stable, so no
source rewrite is necessary. Code examples, ordinary links and remote URLs do not authorize
file copying. Occupied destinations and changed asset hashes fail closed. Unrelated files
are never swept. Failed multi-file copies can leave completed new image copies; no cleanup
claim is made. Existing managed images in the original folder remain intact.

Two storage/import checks **PASS** (0.052 s). The native integration check completed with
one **FAIL** (1.328 s): direct native undo changed the editor but left the source snapshot
stale. All other assertions completed without additional failures. A separate focused fix
observes UndoManager completion and synchronizes exact source bytes; its isolated undo/redo
check **PASS** (0.471 s). The full flow was not repeated after this fix. The ordinary arm64
app build **PASS**. The earlier stalled run was sampled once, identifying an unnecessary
same-folder copy dialog caused by URL directory hints; canonical path comparison fixes it.
Compile API-name corrections and all attempts are retained in `logs/stage-02/assets-results.json`.

Actual image/consent/Save As UI remains **NOT MEASURED**. Native checks used synthetic
recovery keys and injected grants, not production Keychain access. Frozen preparation
checks were not repeated because this checkpoint changed no frozen or historical files.

## Rename, move and Trash checkpoint

Native Rename/Move menu actions now route through the NSDocument move override.
The coordinated operation compares exact saved bytes, refuses occupied destinations,
preserves document UUID and unsaved revision, and updates source location/bookmarks.
A move copies only owned images referenced by either current text or the last saved text;
relative links remain unchanged. Other image copies remain available to earlier documents.
File-presenter checks defer while a lifecycle transition owns the document.

Same-volume source moves use exclusive atomic rename. The cross-volume path copies native
metadata into a temporary file, verifies and synchronizes the new bytes before removing
an unchanged original, and reports partial completion explicitly. Cross-volume execution
is **NOT MEASURED**. A completed physical move is adopted even if later directory or
private-metadata persistence fails; Retry Recovery re-queues saved-location metadata.

Move to Trash explicitly confirms preservation of current writing, including unsaved text,
in a separate encrypted recovery copy. Only the source file enters platform Trash; image
files and private history remain intact. If catalog update fails after Trash, an editable
unsaved document stays open with an accurate message.

One focused native synthetic-file check **PASS** on its first attempt (1.118 s), covering
rename, same-volume folder move, stable identity/current-vs-saved state, owned-image copying,
occupied destination refusal, exact platform Trash bytes and encrypted recovery of dirty
text. Its exact synthetic Trash artifact was removed by test cleanup. Final ordinary app
build **PASS**. Safe error messages, optional returned Trash location and Retry Recovery
metadata handling were added after that check and compiled, without repeating the passing
flow. See `logs/stage-02/relocate-results.json` for commands and limits.

A fresh CUA attempt to select the built app still returned a locked Mac. No menu/panel,
permission, provider, signed Keychain or cross-volume UI observation is claimed.

## Remaining required work

Actual close/quit/crash recovery,
final import/folder/conflict UI observation,
and actual iCloud/Google Drive lifecycles remain. Real encrypted-recovery acceptance needs
legitimate application signing and Keychain access; an owner signing-team question is
pending. No fabricated team ID or legacy Keychain fallback is permitted.

Every M07–M13 row is **NOT MEASURED** with its precise outstanding scope in `STAGE-02.json`.
No Stage 03 start or acceptance is implied. The remaining stage gates are the real storage/provider and native lifecycle observations;
no broad verification pass is planned.

## Toolchain change after this checkpoint

At approximately 2026-09-18 00:56 UTC, the host replaced Xcode.app with version 27.0.
The system developer-tool wrapper then refused execution pending review/acceptance of
Apple's Xcode and SDK agreements. The preceding native check and ordinary app build had
already passed; neither result validates the newly installed compiler/SDK. Further native
builds need the owner's license decision. No agreement was accepted and no developer-path
setting was changed. Repository operations used the separately installed Command Line
Tools Git 2.50.1. The Mac also remains locked in the latest CUA observation.

## Owner-signing preparation

The optional `mac/scripts/build_signed_development.sh` accepts an explicitly supplied
`WRITER_DEVELOPMENT_TEAM` and requires an existing Apple Development identity. It keeps a
separate Debug build directory and selects a dedicated entitlement template with one
resolved application-specific Keychain group. The built-app inspector now verifies the
actual certificate team, development bundle identifier and group scope when this mode is
requested. It continues to reject unexpected entitlements and test instrumentation.
See [current development setup](../../../mac/DEVELOPMENT.md).

Shell/Python syntax, plist structure and missing-team refusal **PASS**. No signing identity
was invented or created; the host's identity query reported **0 valid identities** in the
current locked session. Real signing and Keychain behavior are **NOT MEASURED**.

`xcodebuild -version` now reports 27.0/27A266a, but a single actual build still exited 69
with the Xcode/Apple SDK license requirement. No retry followed. A fresh CUA check still
reported a locked Mac. These are current access/observation gates; Stage 03's accepted
Stage 02 prerequisite remains unsatisfied. No passing checks were rerun for this review.
Commands and boundaries are recorded in `logs/stage-02/signing-preparation-results.json`.

## Resumed Xcode 27 checkpoint — 18 September 2026

The owner resumed implementation. The Mac is accessible through CUA and Xcode
first-launch status now exits 0. One ordinary arm64 build of source `cceb94d`
**PASS** with Xcode 27.0/27A266a; no test suite was run or repeated.
The observed binary and command are recorded in
`logs/stage-02/xcode27-resume-results.json`. This supersedes the previous
license/locked-screen blockers, not any outstanding application acceptance.

An unlocked, unsandboxed identity query still reports **0 valid signing identities**.
Xcode Settings → Apple Accounts shows Sign In with no connected account. The owner
was directed to that page; signed private recovery remains **BLOCKED** on account/
certificate setup. Ad-hoc compilation does not establish Keychain runtime behavior.
No stage acceptance or Stage 03 entry is claimed.

## Signed runtime and corrected native quit — 18 September 2026

Source: `32048befffaa8d0ebc930993c98c366293add590`. Owner completed Xcode/account setup and
explicitly authorized development certificate, Mac/app registration and development profile.
Universal signed build and actual entitlement inspection **PASS**; owner identity details and
credentials are not committed. This resolves the prior signing/license/access blockers.

The signed app displayed Recovery up to date for a synthetic Unicode draft with recording off.
After the owner pressed Force Quit, the same binary reopened the recovered unsaved draft;
native Save wrote the exact 54-byte fixture. Save As updated both window and sidebar title.
Duplicate is now visible in File and creates an independent unsaved document. Quit/Cancel
preserved the open tabs. These scoped observations are **PASS**.

The first Quit/Save wrote exact bytes but hung. A single process sample found a stale recovery
handoff causing a main-actor loop. Recovery now retires cancelled/completed handoffs by token
and rejects late boundaries. Only two affected native checks ran: **2 PASS, 0 failures, 1.078 s**.
The rebuilt signed candidate then completed the same Cancel/Quit/Save flow and exited; its saved
file still matched all 54 bytes. Recent canonical aliases now appear once and reopen correctly.
Final binary SHA-256: `2364b2db7bb0a8ae3d371dfcdb388ae3a257f53d790ddfc225c30a96858d3545`.

Commands, candidate scope, earlier failure and subsequent results are recorded in
[the runtime report](logs/stage-02/signed-runtime-results.json), with the
[focused check excerpt](logs/stage-02/quit-fix-native-summary.log) and
[hang sample](logs/stage-02/quit-hang-sample.txt). No broad test suite was repeated.

M07–M13 remain **NOT MEASURED** overall: remaining import/permission/assets/library/lifecycle
interactions, actual provider lifecycles, sleep and unavailable-key observations are open.
Stage 03 remains gated. Frozen protocol, historical originals and all 60 criteria are unchanged.

## Native lifecycle observation — 18 September 2026

[Signed native observation](logs/stage-02/native-lifecycle-observation.json) records actual
explicit UTF-16 import, unchanged original, exact conversion, body search, selected-folder
listing/persistence, external conflict review and Keep Both, rename, image-grant denial and
acceptance, move with owned image, Revert, permission error/retry, same-file open, and
Trash/recovered-source saving. Each listed flow **PASS** in its recorded local scope.
The 61-byte local conflict and 36-byte external original were retained exactly. The
187-byte pre-Trash source was recovered exactly, with the owned image retained.

A small observed confirmation gap was fixed in `7308ad4`: Trash now names the specific
file. Universal signed build **PASS**; actual rebuilt prompt observed and cancelled.
No automated tests were added or rerun for this wording fix. Earlier native identity and
fault checks retain their scopes. M07 and M11 now **PASS**. Provider, remaining library/
accessibility and sleep observations remain open; Stage 02 is not accepted. The owner
authorized isolated synthetic iCloud and selected Google Drive checks and brief sync/sleep
interruptions. No real writing or account credentials enter the fixtures or reports.

## Actual cloud-provider checkpoint — 18 September

The owner authorized synthetic files in iCloud and the connected Google Drive account.
Native Drive Save, client outage/restart, remote dirty conflict with Keep Both, and
remote rename are observed. Raw remote downloads match the two retained conflict
versions exactly (96 and 77 bytes). Drive desktop is 124.0.3 and running again.
Native iCloud Save As also passes exact local-byte readback. This does not establish
server upload or the still-unobserved provider lifecycle cases.

Real provider use exposed two defects: Keep Both needed an explicit parent-folder
grant for atomic sibling creation, and the sidebar missed provider renames because
AppKit could adopt the URL after the presenter callback. Commits `b93b0a5` and
`220dc09` correct these. The first callback-only rename correction `9919ccf` failed
the actual observation; it is not counted as a pass. Final signed build and only
the affected native operations were checked. No broad suites were repeated.

Full scope, exact hashes, failed attempts, commands and remaining gaps are in
[provider-lifecycle-observation.json](logs/stage-02/provider-lifecycle-observation.json).
M09/M10 remain NOT MEASURED overall. Stage 02 remains unaccepted.

**Owner stop boundary:** finish Stage 02 acceptance, record and push evidence, then
pause before Stage 03. The full eight-stage goal remains unfinished.

### Provider lifecycle completion checkpoint

M09 and M10 now **PASS** in the recorded scopes. Both providers opened evicted
files and saved native edits while Wi-Fi was off. Wi-Fi was restored immediately;
Drive's remote 123-byte source matched exactly after reconnect. iCloud rename,
second-process dirty conflict and Keep Local retained the complete local source
and external recovery. Saving that recovered external version reproduced all
69 bytes. After a graceful iCloud sync-service restart and Writer restart, an
evicted source reopened from Recent and matched all 131 bytes, including the
offline edit. The iCloud external writer was local and coordinated; no second-device
conflict is claimed. Both sync providers and Wi-Fi are running again.

The detailed report retains unsuccessful tool attempts and the uncompleted iCloud
Keep Both folder selection. It claims only observed outcomes. No app source or
automated tests changed during this provider completion checkpoint.

## Library and final file-lifecycle checkpoint

M12 and M13 now **PASS** in the scopes detailed in
[library-final-observation.json](logs/stage-02/library-final-observation.json).
Actual missing references offered Locate/Remove/Cancel without creating empty files.
Locate restored the renamed provider source; Remove deleted only the reference.
A pin survived restart. The observed closed-provider pin failure was corrected in
`c3864b9`: pinning now changes metadata without renewing source-file access. On the
resulting signed build, closed-file Unpin and Pin worked. Light/dark library and
editor/status controls were inspected; Auto appearance was restored. Existing
owner VoiceOver acceptance remains scoped to the foundation; no new aural result
is invented for Stage 02 controls.

One new mounted-volume check **PASS**, 0.027 s, proves actual cross-device exact-byte
move, mode retention, durable completion and source removal. The native chooser
was unreliable under automation; that attempt was cancelled and is not a UI pass.
The focused adapter check used a disposable HFS+ disk image, which is now unmounted.
No passing suite was rerun. App code remains unchanged by the test-only `e08935a`.

**Remaining gate:** actual sleep/wake recovery. Owner readiness to wake/unlock the
Mac is requested. Noninteractive automatic wake scheduling required a password,
so no event was added and the Mac has not been put to sleep. Stage 02 remains
unaccepted, and Stage 03 must not begin. After Stage 02 passes, push evidence and
pause the active goal at the owner's explicit boundary.

## Final contract review and recovery timing correction

This checkpoint corrects the earlier statement that sleep was the only remaining
requirement. PLAN 02 also explicitly calls for measured typing during recovery and
provider callbacks, plus VoiceOver and light/dark observation of the library,
unsaved document, permission error and conflict flow. Foundation VoiceOver
acceptance and named accessibility controls do not establish the added controls'
spoken behavior. M13 is therefore **NOT MEASURED** until those observations exist;
this work cannot simply be deferred to Stage 08. Earlier scoped observations stay
valid and their unsuccessful attempts remain recorded.

One new native measurement found **FAIL**: a settled edit took 1,049.59 ms to reach
encrypted durable recovery because the write began at the one-second deadline.
The app now starts at 500 ms to allow encryption and commit time. Edits also mark
recovery pending immediately, and monitor updates compare current revision/digest.
Only the affected measurement ran again: **1 PASS**, 4.306 s, recovery observed at
563.73 ms. Forty native insertions into 57,344 bytes ran alongside ten file-presenter
callbacks and real encrypted recovery; insertion p95 was 41.69 ms, maximum 53.39 ms.
Exact current/editor/recovery bytes and the unchanged saved source passed. These
are measured values for this fixture, not a worst-case or remote-provider promise.

Source `1333b4c` and the universal signed build pass. The rebuilt app was observed
at a blank document with recording off and recovery up to date. Full commands,
initial failure, corrected metrics and binary hash are in
[recovery-timing-results.json](logs/stage-02/recovery-timing-results.json) and
[the bounded check output](logs/stage-02/recovery-timing-summary.log).

The VoiceOver observation did not complete: opening VoiceOver Utility stalled in
the native-control tool for 1,721 seconds, and the next control call failed with
ScreenCaptureKit error -3812. UI attempts stopped; no speech observation is claimed.
Process inspection afterward found the utility but no running VoiceOver speech
process. Sleep still awaits owner availability to wake/unlock. No new tests will
run solely while waiting, and Stage 03 remains prohibited by the owner's stop
boundary until Stage 02 passes and the goal is paused.

## Owner-assisted sleep and final screen observation

The owner replied ready and woke/unlocked the Mac. **M08 PASS:** system power logs
record actual sleep at 14:01:49 +0100 and wake at 14:02:09, 20 seconds later. The
unsaved draft and current recovery survived. Native Save reproduced the exact
61-byte fixture, SHA-256 `f31c33a2934ef73d33fbb4b871f624f89884b05527b751612109d69527a960fb`.
This closes the sleep gap; prior fault/crash/timing evidence retains its scope.

Library/unsaved document and permission warning were observed in both light and
dark. The warning left the complete dirty draft editable and the disk source
unchanged. Synthetic permissions were restored. Actual conflict screenshots then
revealed hidden comparison panels despite their presence in the accessibility tree.
Commit `6730288` assigns the accessory stack its fitting frame. One signed build
passed, and the resulting sheet visibly shows both complete versions and all four
choices in both appearances. Tab traverses the two text views. Only the affected
screen was repeated; no passing automated check was rerun. Auto appearance was
restored. Details and exact candidate scopes are in
[sleep-and-accessibility-observation.json](logs/stage-02/sleep-and-accessibility-observation.json).

**M13 remains BLOCKED:** the owner reported “I did not hear speech.” VoiceOver was
shown enabled, its speech was not muted, and Mac speakers were selected at 50%
without mute. Native automation could not select the VoiceOver/Quickstart helper;
no audible result is invented. The owner has been asked to toggle VoiceOver off/on
manually. The settings switch and prepared conflict screen remain available. This
is the sole remaining acceptance observation; Stage 03 has not started.

## Final owner confirmation and pause — 18 September 2026

After reporting system-wide VoiceOver silence, the owner first directed Stage 02
acceptance despite that issue. The owner then confirmed: **“Now it works, mark it
as passed.”** M13 is now **PASS**, based on that owner observation together with
the recorded native interaction, storage-limit, accessibility-tree and light/dark
evidence. The agent does not claim to have captured or independently heard speech.
This later confirmation supersedes the earlier blocked state and interim exception;
no acceptance definition was changed and no failed attempt is represented as a pass.

Stage 02 is **accepted**, with all M07–M13 passing in their stated scopes at source
`6730288`. Signed binary SHA-256:
`5364c150703529304517f1974d825f9b5074027f010f2f601d42d91693b44b54`.
No further tests were run for this evidence update.

Auto appearance is restored; speaker/volume/mute were unchanged. VoiceOver was
restored off before the owner's subsequent confirmation of working speech. No
further UI changes were made after that confirmation.

**Pause the goal before Stage 03**, as the owner requested. Stage 03 has not started.
Later stages and the complete 60-requirement release remain unfinished. On an
explicit future resume, start Stage 03 from this accepted source and stage evidence.
