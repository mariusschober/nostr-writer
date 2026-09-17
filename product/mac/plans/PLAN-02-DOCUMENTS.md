# PLAN 02 — durable documents, local library and provider storage

> Recovered historical preparation; read the [current recovery notice](../RECOVERY-NOTES.md) before relying on source availability or test claims.

## Outcome and entry

Starting from accepted Stage01, make the app safe to use for real writing before advanced editor, publishing or proof features are added. Own **M07–M13**. Read DATA, ARCHITECTURE, SECURITY and UX U01/U02/U08/U15; inspect Stage01's actual interfaces and reports. The requirement is durable user text, not a database-centric document format or a new cloud synchronization service.

## Document lifecycle and storage model

Implement WriterDocument as an NSDocument subclass for exact UTF-8 `.md` and `.txt` files. New unsaved documents receive stable UUIDs and local recovery immediately; filenames are not identity. The editable source is not a generated preview. Do not introduce YAML metadata into the body, trim whitespace, normalize Unicode, change CRLF or remove a BOM without an explicit user transformation that creates a new revision. Invalid UTF-8 imports prompt an explicit conversion/import-copy path; never silently replace bytes with replacement characters.

Build WriterStorage with a serial SQLite actor, migrations, integrity checks and testable file operations. Keep metadata, persistent outbox scaffolding, private history indexes and recovery inside Application Support. Encrypt private writing/recovery chunks with CryptoKit AES-GCM and a randomly generated Keychain key. Do not place a plaintext per-keystroke WAL, full document logs or generated error descriptions into SQLite before encryption. Keychain unavailable/denied is not a missing key: preserve data and offer retry/read-only/export recovery rather than generate a replacement key.

Implement the DATA.md recovery protocol: ordered immutable revisions, durable commits at most one second behind active editing and at focus/save/close/sleep boundaries, positive Saved state only after the corresponding durable operation, and explicit disk-full/permission errors. Prioritize never overwriting newer content over displaying optimistic success. Use a bounded recovery journal and encrypted chunk indexes with authenticated document/revision identity. A crash between text mutation and a queued evidence write can invalidate that evidence interval; it must not fabricate it on recovery. Store source snapshots sufficient for recovery independently of full HWP telemetry budgets.

Model `MemoryRevision`, `DurableRecoveryRevision` and `SavedFileRevision` separately. A save finishing for revision n cannot mark n+2 saved. Saving a file does not imply cloud upload confirmation. The same canonical URL in two app windows shares one document session; use native document routing rather than independent editors racing against one file. Duplicate/Save As creates a new document UUID and records derivation without asserting new composition.

## File Provider integration and conflicts

Use native open/save panels, security-scoped bookmarks, NSDocument coordination and file presenter notifications. Selectable iCloud Drive and Google Drive for desktop folders are ordinary user-selected provider locations. Do not require a Google OAuth project or implement a parallel Drive API client. Do not hardcode a `~/Library/CloudStorage` provider name. Handle unavailable placeholders, evicted files, offline providers, renamed/moved directories, expired bookmarks and revoked permissions. A downloaded local file remains editable offline; expose unavailable remote content as such, not as an empty document.

Coordinate atomic source writes, then update the correct saved revision. Test a provider delivering its own write notification so the app does not interpret that echo as an external edit. A genuinely external change during a clean editor session may be reloaded after preserving the local snapshot; any external provenance remains external. A change during dirty editing shows U08 conflict UI with Keep My Version, Use External Version and Keep Both. Default Keep Both; no last-writer-wins destruction. Preserve both exact versions before either choice and never merge private histories or transfer certification through a text diff.

Rename/move within the app coordinates owned sidecar assets, bookmarks and metadata while retaining UUID. Do not sweep unrelated nearby files. Selecting an image outside the document folder copies into a managed asset directory only after an appropriate folder grant; denied access leaves the source unchanged. Document deletion uses the platform Trash flow and explicit confirmation when local unsaved work would be lost. Erasing private history is a separate action, with explicit proof/re-evaluation consequences.

## User-facing library and basic editing

Complete the native sidebar: Recent, local library folders selected by user, Search by title/body within the local index, and New/Open actions. Local body indexing is off for private history; index current document text only with normal local privacy disclosures. Do not index Nostr keys or deleted drafts. First launch can create a blank document without choosing a folder; Save As later is natural. Recent entries for missing provider files offer Locate/Remove, not a destructive empty replacement.

Implement standard dirty indicators, title/rename, File→New/Open/Save/Save As/Duplicate/Revert, close-window prompts and quit negotiation. While Stage03 will refine typography/capture, the basic NSTextView must already preserve cursor, selection and undo, including multiple windows. Recover crashed unsaved documents into explicit recovered entries. Do not automatically resume a locked focus session or enable a recording profile after a crash.

## Tests and fault injection

Use injected clock/files/Keychain/store, real temporary SQLite files and controlled failure points. Test every boundary before and after encryption write, transaction commit, atomic file replacement, bookmark resolution and metadata update. Assert byte-for-byte preservation under rapid edit/save races, closing while a save is in flight, restoring after kill, disk full, unavailable key, corrupted authentication tag and interrupted migrations. Migrations back up first and are idempotent; failed migration leaves the original usable or explicitly recoverable.

Exercise coordinated external writes with a second local process. Test local folders, actual iCloud Drive and actual Google Drive for desktop: offline edit/reconnect, evict/download, rename, dirty conflict, provider restart. Mock provider tests alone do not satisfy the real-provider acceptance rows. No provider account credentials enter source or test artifacts. Record platform/provider versions and redact filenames.

On Mac, capture the library, unsaved first document, permission error and three-way conflict flow in light/dark and VoiceOver. Ensure an error does not steal the editor's entire text or block emergency saving. Measure typing while encryption and provider callbacks run; no main-actor synchronous I/O loops. The acceptance replay should end by retrieving exact original and conflict copies from disk after app restart.

## Exit

All M07–M13 pass. A person can write offline, save to each required storage destination, close/reopen, survive a crash and resolve an actual provider conflict without losing text. The APIs expose immutable revisions and explicit failure states needed by capture, proof, export and Nostr. No future stage should have to replace the fundamental storage design to become safe.

## Execution contract

You are the implementing coding agent, not a planning agent. Read this PLAN and the named contracts in the current checkout, inspect current HEAD, then implement and verify the assigned stage. Do not return another roadmap. Preserve unrelated changes and all frozen protocol bytes. Resolve routine API and implementation details yourself; a discovered platform limitation must be handled honestly, not by weakening provenance or claiming an unrun test passed.

Work on a stage branch from the predecessor's accepted commit. Run relevant earlier tests as well as the new tests. Keep deterministic tests independent of live relays, Apple accounts and real author keys. Native UI acceptance requires actual macOS runs; Linux results are not Mac results. Use synthetic documents and test keys only. Commit coherent source, tests, resources and reports; do not commit build products, credentials or private writing.

Write `product/mac/evidence/STAGE-02.md` with input/output commits, changed contracts, exact commands and results, screenshots/inspection where applicable, every assigned acceptance ID, remaining genuine external blockers and next-stage state. Include a machine-readable `STAGE-02.json` mapping assigned IDs to PASS/FAIL/BLOCKED and evidence paths. No required BLOCKED/FAIL row is completion. Do not edit the acceptance matrix to excuse missing work. The next stage must be able to start from the report and repository without reconstructing this conversation.
