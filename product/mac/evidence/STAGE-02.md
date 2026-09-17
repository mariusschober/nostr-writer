# Stage 02 — document integration in progress

**Not accepted.** Predecessor Stage 01 is accepted at `1fb8625`; current source is
`2517ab4835548f329b2d582c9e7a6be42127bc93` on `implementation/stage-02`. M07–M13 remain open.
All 60 mandatory acceptance rows are unchanged. No Stage 03 acceptance is implied.

## Implemented checkpoint

Imported only WriterStorage and its preparation evidence from `3cd49d6`:
AES-GCM encrypted SQLite recovery, explicit migrations/integrity/budgets, coordinated
source files and bookmarks, one-second recovery scheduling, load-only scoped Keychain
access, and new installation bootstrap. HWP preparation stays separate.

Bootstrap acquires an exclusive installation lease, commits a versioned preparing
marker before adding a key, requires an empty new installation for creation, validates
readback, then commits ready state before opening SQLite. A ready store with a missing
or denied key never creates a replacement. Six focused synthetic-Keychain/temporary-file
checks passed; actual Keychain access and bootstrap power-loss observation are not claimed.

Document windows now attach an app-owned recovery service with a bounded ordered
checkpoint handoff, pending/durable/error state and explicit retry. Ad-hoc builds without
legitimate access-group entitlement refuse key provisioning and retain ordinary source
saving. Private plaintext AppKit draft autosaves are disabled. This is recovery source
storage, not detailed consented writing history or HWP observation.

Native asynchronous saves use a locked immutable snapshot and its native change-count
token; file status is separate from recovery. Revert refreshes the live editor through
the mutation gateway. Duplicate uses an in-memory copy with a new UUID, and Save As
creates a new UUID with an in-memory derivation link. Persistent catalog/derivation and
preserve-before-Revert/Save As remain unfinished; current code is a development checkpoint.

## Actual bounded verification

- One native lifecycle check **PASS** (1.069 seconds): exact BOM/decomposed Unicode/CRLF/
  whitespace bytes after Save, Revert and Save As; duplicate source/identity and live
  editor refresh. It uses only temporary synthetic files, not provider storage.
- Six bootstrap checks **PASS** (0.046 seconds), recorded in
  `preparation/keychain-bootstrap/results.json`; no real Keychain item touched.
- Preparation and frozen checks **PASS**: 69 frozen files, 326 recovery-manifest files,
  all 60 criteria unchanged. Existing passing component suites were not rerun.
- Final app and hostless native-test sources compile for arm64 in the focused native
  invocation. The earlier ordinary-app build predates the final save fix and is not
  presented as an observed final UI artifact. New window UI is **NOT MEASURED**.

The first native attempt lacked document-type registration in its hostless test setup.
The next attempt exposed an actual asynchronous-save actor-isolation crash. The retained
crash-symbol extract identifies `WriterDocument.data(ofType:)` called from AppKit's
background writer. The fix hands over immutable bytes and a matching change-count token.
A compiler-required immutable closure capture was corrected before the final successful
run. No passing check was repeated after that success. Failures are retained, not counted
as passes.

Commands:

```sh
swift test --package-path mac/Packages/WriterStorage --filter RecoveryBootstrapTests
xcodebuild -project mac/NostrWriter.xcodeproj -scheme NostrWriter -configuration Debug -derivedDataPath mac/.build/NativeTestDerivedData -destination 'platform=macOS' -skipPackagePluginValidation ARCHS=arm64 ONLY_ACTIVE_ARCH=YES -only-testing:NostrWriterTests/ShellTests/testNativeSaveRevertAndDuplicateKeepExactBytesAndIdentity test
python3 tools/check_preparation.py
python3 tools/bootstrap_protocol.py
```

## Remaining required work

Persistent UUID/bookmark/derivation catalog, recovery entries after restart, safe close/
quit/sleep flushes, preserve-before-Revert and Save As, coalesced concurrent saves,
provider conflict copies, local library/search, rename/move/assets and real iCloud/Google
Drive observation remain. Live data-protection Keychain acceptance needs legitimate app
signing/provisioning; no fabricated team ID or legacy Keychain fallback is permitted.

M07–M13 are individually **NOT MEASURED** with exact reasons in `STAGE-02.json`.
Earlier storage component evidence is not a substitute for these app/provider criteria.
Next work is persistence and recovery lifecycle integration, not another broad test pass.
