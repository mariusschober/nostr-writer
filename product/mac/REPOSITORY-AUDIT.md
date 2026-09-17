# Repository reconciliation and adoption audit

> Recovered historical preparation; read the [current recovery notice](RECOVERY-NOTES.md) before relying on source availability or test claims.

Prepared 16 September 2026. This is a source-grounded product review, not a third-party security audit or a claim that a Mac application was built here. Both repository trees were inspected at pinned commits. Relevant Mac signing, relay, key, editor, dictation, lifecycle and package source was read in full. The complete supplied joined protocol package was inspected and exercised. Android was inventoried only to avoid importing its product architecture into the Mac MVP.

## nostr-writer: choose the joined authority

Remote main was `c53e794a11aa801b553af462fe5da33593e12eee`. It contains legacy A1 code, A0.3 documentary research and HWP-C1 source. The prior joined `protocol/v0` freeze was absent remotely. The supplied final v0 archive is the authoritative integration input; exact identities and the self-contained checkout bootstrap are in INPUTS.md. Do not combine the old algorithm entry point, newer prose and a synthetic crypto callback and call that v0.

The original package contains 69 files. Its large interchange vector is deterministic. Preparation preserves frozen sources byte-for-byte and verifies regeneration against the original digest. The source archive parts and bootstrap make the complete freeze available from an ordinary clone, without a conversation attachment. Earlier progress output mentioned 174 tests; the final freeze contains 178. This preparation reran all 178 in four partitions, checked the freeze, passed the independent Node checker and regenerated identical vectors. No normative manifest was rebuilt.

The production policy admits no releases. Conformance positives are TEST-ONLY / NOT PROVABLE. No evaluated native Mac capture path or real model validation is established. V trusts evaluator assertions; R additionally recomputes. Source proofs do not certify PDF/DOCX rendering. These facts determine honest product states; they are not implementation problems to conceal with a green badge.

## NostrShot: preserve mechanisms, replace assumptions

Pin: `cf28e9652dc8eb7bbd85008163071820cd781998`. Its Mac package is a Swift 6.1/macOS 14 menu-bar app named NostrBar, with P256K 0.23.2 and KeyboardShortcuts 3.0.1. Preserve owner-source attribution and actual third-party notices. Repository metadata does not itself grant a blanket third-party relicensing right. The existing app is a starting point for relevant capabilities, not Writer's shape.

| Inspected source | Adoption decision |
|---|---|
| `Nostr/NostrEvent.swift` | Reuse correct raw 32-byte BIP-340 signing and canonical serialization concepts. Add required kinds/tags, strict received-event validation and forbidden-control handling. Never trim certified source. |
| `Nostr/Keys.swift` | Reuse scalar validation, nsec/hex parsing and secure generation. Keep private bytes out of UI-owned identity values. |
| `Nostr/RelayConnection.swift` | Preserve useful reconnect/generation/ping ideas. Repair send-before-ACK-registration, duplicate-ID continuation replacement, uncancellable connection waits and stale-generation receive failures. Reproduce these cases with deterministic tests. |
| `Nostr/RelayPool.swift` | First-ACK feedback is useful, but durable per-relay outcomes are required. Existing URL normalization lowercases the entire URL and removes the query; preserve case-sensitive paths and queries. |
| `Nostr/RelayMessages.swift` | Existing code parses OK/NOTICE and ignores EVENT/EOSE/CLOSED. Draft retrieval needs a full bounded subscription codec, verification and AUTH handling. |
| `Storage/KeychainStore.swift`, `KeyManager.swift` | Retain this-device-only Keychain intent. Distinguish denied, locked, missing and corrupt states; get currently collapses errors into nil and removal ignores failure. Never replace an inaccessible encryption key. |
| `UI/ComposerController.swift` | Pending notes are in memory; text is trimmed and cleared before a durable publish job exists. Failure may merge old text into a newer draft. Writer persists intent and signed bytes first and keeps failures separate. |
| `UI/ComposerTextView.swift` | Preserve live text-view ownership. Do not carry over whole-String external feedback, vertically centered short-note layout or legacy layout-manager access into the TextKit 2 editor. |
| `UI/Dictation.swift` | Preserve just-in-time permissions and on-device requirement. Add stable range anchoring and cancellation generations so late transcripts cannot replace the whole document. |
| `Package.swift`, `Package.resolved` | Preserve the known initial crypto/shortcut pins. Create a normal checked-in Xcode document app, not an accessory app renamed from its build script. |
| Existing architecture and tests | Kind-1 test patterns are useful, not evidence that long-form publishing, NIP37 drafts, HWP, OOXML or File Provider lifecycle already exists. |

These are static findings and implementation obligations. No Mac runtime exploitation, relay-load test, Apple-account test or native NostrShot build was performed on this Linux preparation host. Agents must validate adoption on Mac rather than treating this review as runtime evidence.

## Product contradictions resolved

Assistance can be allowed while its new wording remains unproved. Recording is not certification. Focus is voluntary friction, not attestation. A local file write is not cloud-upload confirmation. A relay ACK is not permanent storage. A key signature is not a verified typist. A source proof is not a rendered-export proof. A restored remote draft supplies text, not missing composition history.

Software completion includes the complete native conditional P/V/R pipeline and an honest unavailable-certification state under the empty approval set. It does not permit an always-NP stub or fabricated scientific approval. Future empirical evidence can activate a new release without rewriting old captures.

## Intentionally not built during preparation

No Writer UI application, focus controller, networking client, export engine, trained detector, new cryptographic protocol or backend was built. Product Design's Work/browser workflow was not run in this chat; detailed textual UX contracts and acceptance states are supplied. No native visual test or notarization is claimed. The small Swift Foundation kernels pass portable tests but do not establish macOS platform behaviour.
