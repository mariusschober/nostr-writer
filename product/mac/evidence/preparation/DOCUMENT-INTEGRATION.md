# Document integration decisions — 17 September 2026

Architecture review only, not Stage 02 implementation or acceptance. Read the
unchanged PLAN-02, DATA, ARCHITECTURE, SECURITY and UX U01/U02/U08/U15. Reviewed
Stage 01 source candidate `ddac4a3` and preparation source through `1c3d381`.
Stage 01's remaining acceptance gates are hosted CI and observed spoken
VoiceOver navigation. All 60 requirements remain mandatory.

## Ownership and application attachment

`WriterDocument` currently creates an in-memory session, reads strict UTF-8 and
provides exact snapshot bytes to native saving. Its scratch editor adapter has
no recovery attachment, durable UUID catalog, conflict handling or Keychain
lifecycle. Preserve that honest distinction when applying the prepared storage
components. Do not enable autosave or announce durable recovery merely because
those components compile.

One main-actor `DocumentSession` owns edits and immutable snapshots. Its ordered
recovery handoff must preserve revision ordering; independent unstructured tasks
per keystroke can arrive out of order even when each snapshot is immutable.
The prepared recovery actor may coalesce disposable source checkpoints, never
detailed capture history or a publication intent. Recovery remains available
when optional detailed recording is off.

The application attaches one recovery coordinator per document UUID and one
serial store connection. Recovered documents retain identity and resume above
the recorded revision; a new document creates a new UUID before its first edit.
Save As/Duplicate creates a new UUID with an explicit derivation link. Rename or
move of the same file retains identity. Native document routing owns repeated
opens of the same canonical file, rather than creating racing sessions.

## Save, close and conflict boundaries

NSDocument owns its coordinated source callbacks. The standalone coordinated
file helpers are for separate source-copy/import operations; do not call them
inside an already coordinated NSDocument read/write accessor.

Capture an immutable revision for each save and acknowledge only that revision
after the real native write completes. Keep memory, encrypted recovery and saved
file state separate. A recovery failure leaves ordinary Save available; a
successful file write cannot imply current recovery or remote provider upload.
Out-of-order file completion must leave an honest dirty state and schedule the
newest save, never silently mark newer memory saved.

Before closing, serialize pending editor handoffs and negotiate the native save
decision while text remains available. Then flush the newest accepted snapshot
through `RecoveryCoordinator.close()`. If recovery fails, expose Retry and
ordinary source saving without destroying the document session. A cancelled or
failed close permits editing again. App termination needs a bounded asynchronous
negotiation; no blocking SQLite, encryption or provider loop on the main actor.

Provider notifications first distinguish a same-byte echo of the exact saved
revision from a genuinely external version. Preserve both exact versions before
any conflict choice. Use the detailed U08 labels: Keep Both (default), Keep Local
and Open External Copy. Timestamps inform the comparison but never pick a winner.
External/recovered text remains imported provenance. A clean reload must update
the live session through its mutation path, not merely the loading buffer.

## Key lifecycle and remaining work

The store's key provider is intentionally load-only. A production Keychain
adapter must distinguish absent, locked, denied and malformed entries, use a
dedicated WhenUnlockedThisDeviceOnly installation key, and never replace a key
because an existing store cannot be decrypted. First creation requires an
explicitly new private-store state; an empty query alone does not establish that
old encrypted material is absent. Retry preserves ciphertext and source editing.
Development and release services remain separate from Nostr/HWP keys.

Remaining application work includes the persistent identity/bookmark catalog,
Keychain lifecycle, save/close/recovery UI, external conflict copies, library and
local search, owned assets, durable outbox scaffolding and actual provider access.
Real iCloud Drive and Google Drive for desktop observations require their real
accounts and granted synthetic test folders. Do not substitute component tests
for those observations.

No new build or test run was performed for this documentation-only review. The
user requested minimal testing and no testing loops. Reuse the recorded passing
component evidence until an implementation change affects it; once integration
is authorized by accepted predecessor evidence, run only the checks needed for
the changed behavior and mandatory stage acceptance.
