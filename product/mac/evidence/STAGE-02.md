# Stage 02 — document integration in progress

**Not accepted.** Stage 01 is accepted at `1fb8625`. Current source is
`78606bfad0659d3e56239d71b381aacb5afe93c4` on `implementation/stage-02`, following
`2517ab4`. All M07–M13 remain open; all 60 acceptance definitions are unchanged.

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
Selected-folder library and several file actions remain unfinished.

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

## Remaining required work

Selected-folder library, Locate/Remove references, coordinated rename/move/assets,
full close/quit/crash recovery, final conflict UI observation,
and actual iCloud/Google Drive lifecycles remain. Real encrypted-recovery acceptance needs
legitimate application signing and Keychain access; an owner signing-team question is
pending. No fabricated team ID or legacy Keychain fallback is permitted.

Every M07–M13 row is **NOT MEASURED** with its precise outstanding scope in `STAGE-02.json`.
No Stage 03 start or acceptance is implied. Next implementation work is selected-folder library and remaining file actions; no broad
verification pass is planned.
