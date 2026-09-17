# PLAN 06 — durable Nostr publishing, encrypted drafts and optional Quick Post

> Recovered historical preparation; read the [current recovery notice](../RECOVERY-NOTES.md) before relying on source availability or test claims.

## Outcome and entry

Own **M36–M45** after accepted Stage05. Read NOSTR in full, INPUTS, REPOSITORY-AUDIT, DATA/SECURITY and UX U10–U13. Fetch NostrShot at its pinned commit, inspect the exact source/tests, then reuse only the relevant signing/key/codec/relay/shortcut ideas. This stage is a complete product capability, not a Nostr SDK rewrite or migration of the old short-form app's UX.

## Identity and canonical event foundation

Implement one active Nostr identity with generate/import nsec or hex, read-only npub, unlock/errors and explicit removal/export. Use Keychain with distinct Writer services and this-device-only access. Do not silently read or mutate NostrShot's identity or equate Keychain failure with no identity. Keep private bytes actor-confined; views get public descriptors and actions, not a struct exposing privateKey. Never log keys, authentication payloads, drafts or private relay addresses. Switching identity freezes prior identity jobs until restored; it cannot re-sign them as someone else.

Reuse P256K/BIP340 correct raw32-byte event-ID signing. Strictly serialize/parse NIP01, handle supported escapes/Unicode exactly, reject disallowed controls without modifying the editor, recompute event IDs and verify signatures on every received event before interpretation. Extend NIP19 for npub/nsec/nevent/naddr with bounds/TLV validation. Use the pinned official specifications and test vectors. Add no custom “HWP standard” Nostr kind or undocumented signature scheme.

Port NIP44 v2 from the referenced construction with exact HKDF/ECDH/ChaCha20/HMAC/padding/authentication order. Use one secp backend, CryptoKit hashes/HMAC/HKDF where suitable and the vetted raw IETF ChaCha20 dependency, not CryptoKit ChaChaPoly. Check MAC before unpadding or revealing detailed decryption failures. Support the pinned extended-length framing beyond65535 and the app's1MiB plaintext/2MiB wire limits. The prepared helper tests are framing only, not encryption conformance. Verify official standard vectors and65535/65536/65537 payload digests with an independently pinned JS implementation. Do not call the older Swift reference audited.

## Relay correctness and persistent outbox

Replace the old publish-in-memory pattern with a durable outbox in WriterStorage. Persist the user's immutable PublishIntent before signing; persist the exact signed bytes and event ID before any send. Every retry sends that same event. A later document edit creates a new job only after another publish action. Cancellation after a possible send means stop retries, not proof of withdrawal. Store each relay's pending/accepted/rejected/unreachable response independently; a first positive ACK is success to at least one relay, not permanent network storage.

Repair NostrShot's concrete adoption risks: pending continuation registration must precede send; duplicate event IDs must coalesce or attach distinct waiters safely; cancellation/deadlines must resume waiters once; stale socket generation callbacks cannot tear down a newer connection; URL normalization must preserve path/query case. Do not use unbounded task groups waiting on uncancellable checked continuations.

Implement bounded WebSocket actors for EVENT, OK, NOTICE, REQ, returned EVENT, EOSE, CLOSED, CLOSE and NIP42 AUTH. Validate subscription IDs, identity/kind/d matches, time/size limits and signature before storage. Stop subscriptions on close, signout or cancelled fetch. Selected relay AUTH is explicit and contains no private draft body. Default no networking before Nostr opt-in. Preserve reconnect/wake behaviour without permanent warm sockets when the feature is unused. Normal tests use a deterministic local loopback relay harness with races, rejection, delayed ACK and malformed messages; live tests are explicit and use disposable keys.

## Publication UX

Build U10/U11/U12: native identity setup sheet, editable relays, account label, publish review, optional remembered one-click choice, per-relay detail and durable Outbox. Publish `kind30023` articles with stable random `d` per document/identity, explicit title and optional summary/topics/cover URL, initial published_at and monotonically later revision timestamps within the bounded clock rule. Content is exact captured Markdown bytes decoded as UTF8, not trimmed/reformatted or frontmatter-stripped. Archive the exact signed event for each publication.

On first publication show immutable source preview, public destination, identity and irreversible-publication warning. Once the user enables one-click for that document/identity, toolbar Publish directly persists a job. Never use a changing live editor buffer in an async sign callback. First ACK updates the UI but leaves the document in place. Expose naddr for latest article and nevent/exact event for the certified version; title/tags are not implicitly in the body proof.

Optional Quick Post is a menu-bar/shortcut NSPanel, not the main app shape. It uses the same durable outbox and its own recoverable draft. Optimistic close is allowed only after job durability. Failed posting appears in Outbox/notification without stealing focus or concatenating a failed note into a newer draft. Convert to document preserves text but is not fresh-composition evidence merely because the text was typed in Quick Post. Default global shortcut is configurable; no Accessibility permission or external-selection capture is required.

## NIP37 encrypted relay drafts

Implement `kind31234` addressable wrappers and `kind10013` private-relay list exactly as NOSTR.md. The inner unsigned article event is self-encrypted NIP44 JSON; no raw telemetry, deleted text, salts, paths or proof-private witness is included. Use explicit opt-in private relays with no public fallback. The10013 list's content is encrypted with empty public tags; deliver it through the selected NIP65 write relays. Addressable wrapper d/k/expiration semantics are pinned. Do not silently substitute obsolete plain kind30024 drafts for requested NIP37.

Local durability comes first; debounce2s, routine remote saves at most once30s, explicit Save Now flush,90-day expiration. Keep a signed pending wrapper immutable; coalesce only unsent newer intents without losing latest local content. On reconnection load and validate remote versions, apply highest created_at/lowest-ID tie rule, ignore expired, handle empty-content tombstones before decryption, and show conflicts rather than overwrite local dirty writing. Relay drafts restore text/metadata only; missing local composition history remains missing. Avoid timestamp ties by bounded monotonic timestamp generation. Do not emit optionalkind1234 historical checkpoints in MVP.

Delete remote draft by tombstone, with optionalkind5 best-effort requests; UI states relays may retain copies. Deleting a draft does not unpublish the article. Transport errors never fall back to cleartext or unstandardized fragmentation. Large draft/relay-limit errors preserve local text and explain the exact failed destination.

## Proof integration and verification

Attach or announce only an already verified public proof for the exact source/version. Optional HWP author-key association follows frozen interoperability semantics with distinct Nostr and Ed25519 keys. A Nostr signature alone never enables HUMAN-WRITTEN. Do not build a hosted proof service; local proof companions and optionally user-hosted exact verified bytes suffice. Publish-source and proof-source digests must match before association; no circular event/proof IDs.

Test all M36–M45, including app kill after sign/before ACK, identical retryIDs, account switch midjob, stale event/forgedsignature, private relay mismatch,65536+draft,remoteconflict,tombstone,offlinefirst,oneclick,signedplaintextdetection and keychainerrors. Use second independent Nostr client/decoder for long-form and draft vector checks; record relay retention limits, not a claim of permanence. Screenshots must cover both successful and failed publish states. No real user key or public post is needed to prove automated correctness.

## Execution contract

You are the implementing coding agent, not a planning agent. Read this PLAN and the named contracts in the current checkout, inspect current HEAD, then implement and verify the assigned stage. Do not return another roadmap. Preserve unrelated changes and all frozen protocol bytes. Resolve routine API and implementation details yourself; a discovered platform limitation must be handled honestly, not by weakening provenance or claiming an unrun test passed.

Work on a stage branch from the predecessor's accepted commit. Run relevant earlier tests as well as the new tests. Keep deterministic tests independent of live relays, Apple accounts and real author keys. Native UI acceptance requires actual macOS runs; Linux results are not Mac results. Use synthetic documents and test keys only. Commit coherent source, tests, resources and reports; do not commit build products, credentials or private writing.

Write `product/mac/evidence/STAGE-06.md` with input/output commits, changed contracts, exact commands and results, screenshots/inspection where applicable, every assigned acceptance ID, remaining genuine external blockers and next-stage state. Include a machine-readable `STAGE-06.json` mapping assigned IDs to PASS/FAIL/BLOCKED and evidence paths. No required BLOCKED/FAIL row is completion. Do not edit the acceptance matrix to excuse missing work. The next stage must be able to start from the report and repository without reconstructing this conversation.
