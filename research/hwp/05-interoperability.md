# 5. Nostr, provenance standards, and long-term verification

Research draft · Adapter designs only. No Nostr event, blockchain transaction, time attestation, or C2PA credential was issued as part of this research.

## 5.1 Recommended division of responsibility

Use a transport-independent HWP evidence bundle as the authoritative object. Use Nostr for optional pseudonymous association, discovery, and replication; C2PA for a compatible assertion inside supported content-provenance workflows; and a final OpenTimestamps proof for optional decentralized existence anchoring. None of these should determine whether a writing process qualifies.

This division avoids a new chain, a token, compulsory wallet use, or dependence on a particular relay. It also makes the core proof usable without Nostr or blockchain.

## 5.2 Nostr binding

NIP-01 events have a content-derived event ID and a secp256k1 Schnorr signature, using the BIP-340 signature scheme [S13](06-sources.md#s13), [S16](06-sources.md#s16). The HWP envelope's Ed25519 key is separate. Do not reinterpret the same secret/public-key bytes as interchangeable across schemes.

A Nostr author may sign an association that references the HWP envelope digest, exact document digest, and a particular article event ID. Verification checks both signatures and all equality bindings. A Nostr signature proves that the key endorsed that association, not that its holder composed the text.

NIP-23 long-form articles are addressable and editable. Preserve the exact event ID and event bytes for the certified version, not only an `naddr`/address that can resolve to a later revision [S14](06-sources.md#s14). The text object's bytes are the decoded event content encoded as UTF-8 under the declared profile. Titles and other claimed metadata need their own explicit inclusion/binding; they are not silently covered by hashing the content string.

Avoid circular references. The simplest sequence is: finalize exact text and HWP proof; publish or identify the article event; then issue a separate signed association referring to both. Alternatively, a statement can bind an already-existing article event, provided that event did not depend on the future proof's hash.

Use an ordinary signed discovery note for an experiment, or NIP-94 file metadata when announcing an actual hosted bundle. NIP-94 uses kind 1063 and its `x` field is the SHA-256 digest of the file bytes [S15](06-sources.md#s15). Hash the exact serialized file being served, not a different canonical object or a custom domain-separated digest. Distinguish the envelope's content identifier from the containing archive's file digest.

No new NIP number or event kind is assigned here. A future standardized HWP event needs review in the Nostr extension process. A custom tag convention is not already a NIP. Relay acceptance, `created_at`, and possession of an event ID do not establish trusted creation time, global ordering, permanent storage, or human authorship.

Keep local/mirrored copies of the exact article version, association events, envelope, and supporting artifacts. Replication improves availability; it does not improve the truth of an unsupported claim.

## 5.3 C2PA integration

C2PA supplies an asset-provenance structure with signed assertions and content bindings; validating its structure is not a judgment that the underlying real-world assertions are true [S12](06-sources.md#s12). HWP can be carried as a namespaced custom assertion that identifies the HWP statement/envelope, scope, profile, execution evidence, and declared limitations.

A conforming C2PA adapter must use the chosen C2PA version's actual manifest, assertion, signing, hard-binding, and credential/trust requirements. An HWP JSON file placed beside a document is not automatically a C2PA credential. An arbitrary self-signed HWP Ed25519 envelope is not automatically accepted by C2PA's trust ecosystem.

A transformed or exported asset receives its own exact-byte/content binding and references its source text and relevant transformations. Embedding a manifest changes the file; use the format's supported C2PA binding mechanism rather than naive recursive whole-file hashing. This draft does not assert rendering equivalence between source text and every export format.

The initial proof remains independently meaningful outside C2PA. This prevents a future C2PA vendor service or account from becoming mandatory for verifying the HWP evidence.

## 5.4 Timestamp choices

An RFC 3161 timestamp authority can sign a digest-based time attestation. It requires trust in the authority and its archived credential/status evidence [S18](06-sources.md#s18). OpenTimestamps provides a format for establishing prior existence with independently verifiable Bitcoin anchoring [S17](06-sources.md#s17).

For HWP, anchor the completed signed envelope or a precisely identified archive digest. The anchor attests that those bytes existed before the relevant chain/time bound. It does not prove that the text was composed then, that the writer spent the claimed duration, that observations are genuine, or that the author owns the ideas.

A pending calendar response is not a completed independent Bitcoin proof. Retain an upgraded/final proof containing the necessary chain attestation, plus the information needed to validate against an accepted chain. Verifying from a self-selected unvalidated block header is insufficient; independent validation needs an appropriate Bitcoin chain-validation basis. Blockchain time is not an exact wall-clock creation measurement.

Batch commitments are sufficient for cost efficiency. There is no reason to send keystrokes, drafts, or per-paragraph transactions to a public blockchain. Never put raw behavioural history on-chain.

## 5.5 Company-independent survival

Archive the exact document and scope map; canonical statements and signatures; proof verifier/program identifiers; public model, replay, and policy artifacts; required attestation chains and issuance-time endorsements/status evidence; final timestamp proofs; and relevant transport associations. Publish a complete format specification and test vectors, and arrange independent mirrors.

A content hash verifies a file that is available. It cannot recover a file that everyone has lost. An immutable proof is not an immutable hosting service. Offline verification must not call the original company to resolve an essential policy version or fetch the only copy of a verification key.

Historical cryptographic validity and present-day trust must be separately recorded. Later discoveries can make an old capture profile unacceptable even when the original signature still verifies. Offline evidence can support an as-of assessment, not knowledge of all future revocations. Renew evidence before relevant algorithms become unsafe, retaining the chain of renewal rather than replacing history; RFC 4998 provides established evidence-renewal concepts [S19](06-sources.md#s19).

The open-standard ambition also needs appropriate publication/reuse licensing, version governance, interoperable independent implementations, and review of patent commitments before adoption. These governance decisions are not silently established by publishing this research repository.
