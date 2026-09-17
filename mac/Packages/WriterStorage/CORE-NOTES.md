# WriterStorage source-recovery core

Preparatory code on the local, unmerged `preparation/native-cores` branch.
This is not accepted Stage 02 and is not wired into the app. Initial implementation
was delegated to DeepSeek V4.1 Flash in an isolated temporary package; Astra reviewed
and corrected the architecture, recovery races, backup safety and bounded retention.

`DocumentStore` implements `DocumentPersistence` for exact encrypted source recovery.
One actor owns one system SQLite connection. Writes use prepared statements and
explicit transactions, with verified WAL / synchronous=FULL / macOS fullfsync settings.
AES-GCM seals source before database writes using a load-only injected key provider
and fresh system-random nonces. The core never generates or replaces an installation
key. The fixed 133-byte authenticated context binds the document, recovery stream,
full UInt64 revision and chunk index, source digest/length and previous reference.
A recovery stream is not an HWP capture run and confers no authority.

With the explicit `.rollingJournal` retention policy, each commit retains the
configured newest source recovery checkpoints (default count two, minimum two).
The configuration otherwise defaults to `.keepAllCheckpoints` within the fixed
ciphertext budget; choosing rolling recovery is the app owner's explicit decision.
Older disposable checkpoints are pruned in the same transaction. Failure
rolls back the new write, pointer update and pruning together. Detailed private capture
history is a separate capability and is never placed in this table or deleted here.
The global ciphertext budget defaults to 256 MiB; if mandatory checkpoints cannot fit,
the new write fails explicitly and preserves prior recovery. The app must still expose
that failure and continue ordinary source editing/saving during Stage 02 integration.

Revisions use fixed eight-byte big-endian values rather than signed SQLite integers.
Stale/conflicting writes fail; an identical current retry returns the same commit.
Key suspension is outside transactions, and state is reread after suspension. The
index must agree with authenticated content; damaged latest recovery cannot be silently
superseded. Missing/denied/locked/mismatched keys preserve stored ciphertext. Input is
bounded to the product's 8 MiB / 1,000,000 scalar ceiling, with tighter injected bounds
allowed. Stored ciphertext is bounded before copying it out of SQLite.

Schema 1 is the first real schema. Forward migrations require a consistent SQLite
backup (including committed WAL data), independent page-count/integrity/version checks,
and a new unused destination. Failure leaves the old schema usable. No future outbox
or detailed-history table is represented by a placeholder. Supplied mutation receipts
are consistency-checked but not stored; a recovery acknowledgement attests source
recovery only, never durable capture evidence.

Verification: 46 tests passed in the preparation worktree using
`swift test --package-path mac/Packages/WriterStorage`. The raw log and exact source
hashes are in `product/mac/evidence/preparation/storage-core/`. Tests cover BOM/CRLF and
Unicode bytes across reopen, plaintext/key scans of database/WAL files, AEAD tampering,
UInt64.max, key races/denial, transaction fault points, rolling retention and rollback,
consistent migration backups, configured limits and real SQLITE_FULL induced through
a temporary SQLite page ceiling. Actual physical power loss/full disk is not measured.

`RecoveryCoordinator` schedules immutable source checkpoints on an injected monotonic
clock. The first snapshot is immediate; later edits coalesce within a maximum one-second
interval anchored to the oldest pending edit. A slow store exposes overdue recovery;
it never fabricates durability. Explicit boundaries and close await the newest source,
with bounded waiters and one store write at a time. Failed checkpoints preserve text
and pause until retry or another edit. A failed/cancelled close permits editing again;
a concurrent second close is refused. Saved-file acknowledgements remain independent
of recovery, including an older file write that completes after a newer one.

Standalone coordinated source reads/copies/replacements and scoped bookmark helpers
are also available. These operations must not be nested inside NSDocument's own file
accessors. See `product/mac/evidence/preparation/native-files/` for 13 additional tests,
including a real second local coordinated writer; sandbox/provider grants remain unmeasured.

The final scheduler ran 34 virtual-clock tests plus two composition tests using the real
encrypted store and coordinated files. They verify close/reopen recovery of unsaved
exact bytes and independent ordinary file saving while the recovery key is unavailable.
See `product/mac/evidence/preparation/recovery-scheduling/` for exact source and logs.
Virtual-clock scheduling does not measure production UI latency or actual clock timing.

`KeychainRecoveryKey` now implements load-only Security.framework access for one
configured service/account/access group, using the data-protection Keychain and
noninteractive authentication. It validates the returned identity, nonsynchronizable
WhenUnlockedThisDeviceOnly policy and 32-byte key length. Nothing is cached or
created on error. Six isolated injected-query checks passed once; no real Keychain
item was read or changed. See `product/mac/evidence/preparation/keychain-reader/`
and the separate first-creation/signing decisions in `KEY-LIFECYCLE.md` there.

Mandatory work remains: crash-safe Keychain creation and signed-app access, app attachment of
checkpoint scheduling, native NSDocument save/close/recovery UI, actual bookmark grants,
provider conflicts, library/search, outbox scaffolding, capture history, performance and
real iCloud/Google Drive acceptance. No UI/provider/Keychain/Stage 02 acceptance is claimed
by these package tests. See the unchanged PLAN 02 and M07-M13.
