# HWP integration contract — immutable semantics, honest software-only limits

> Recovered historical preparation; read the [current recovery notice](RECOVERY-NOTES.md) before relying on source availability or test claims.

## Authority and exact input

The joined authority is frozen `protocol/v0`, normative revision0.0.0/wire hwp/0, protocol definition SHA-256 `58efebeb46689cfafd597230facda03a9541d423b244d36b84cff35b2fc8c6d4`; FREEZE inventory SHA-256 `c04ded3b82a462aa22a7289a5bcbeccd5719124a4718cb5fbd4f47c297993d88`. Import/hydrate without changing those files. The historical algorithm A1, A0.3 and HWP-C1 are background, not interchangeable production engines. Protocol conformance allows an independent Swift implementation of the same exact function; it does not require shipping Python to end users.

The native integration implements P, V and R as defined by frozen `docs/CONFORMANCE.md`. T/RFC3161 inspection is supplemental and may use the provided external verifier tool in this MVP; lack of timestamp support cannot silently imply trusted time. ZK, Nostr/C2PA transport and OpenTimestamps are not activated HWP verification modes. The signed payload type/role, complete scope and exact selected external policy always survive UI simplification.

## State separation

Maintain separate values, not a single green tick:

1. Recording state: off, observing locally, interrupted, unsupported input, storage limited, complete local record.
2. Assessment availability: no empirical model; unsupported capture domain; insufficient evidence; algorithmically non-admitted; eligible under a specified independently admitted release.
3. Verification outcome: VALID-HWP/HUMAN-WRITTEN, TEST-ONLY/NOT PROVABLE, NO-VALID-HWP/NOT PROVABLE, with exact scope/claim/execution basis and reason.
4. Revision pairing: current exact bytes, earlier saved snapshot, or mismatch.

Only a real production VALID-HWP for the matching source+scope may display HUMAN-WRITTEN or enable Export Human Writing Proof. A COSE signature, local history, Nostr signature, passed focus session, test fixture or conditional score is never sufficient. “Proof unavailable” must not become “AI detected”. Imported valid proofs can be retained with source snapshots even when the current document has changed.

The native recorder on an owner-controlled software-only Mac has **not** been independently admitted. NSEvent flags, application callbacks, notarization and a Keychain key do not solve this. Record actual observable data and state that it is local experimental history. Do not manufacture v0 delivery observations by cloning post-change text, classify all sources as device, certify inferred key-up events, or designate this path evaluated. Frozen v0 has fixture/evaluated profile classes; real unvalidated product telemetry is not an excuse to fabricate evaluation evidence. Use an app-local descriptive observation envelope until all normative fields are genuinely available. Canonical export includes only faithfully observed fields and fails/marks unsupported when they are missing.

## The producer flow to implement

`finalize(snapshot, selected scope, exact release, capture/profile/subject inputs)` first freezes the actual epoch, verifies complete input/delivery/mutation order and exact final bytes, then reconstructs the v0 record. Pinned prospective release/parents/participation must exist from start. Reconstruct source graph and exact target; run replay, ancestry, 179 integer features, adequacy/support/model heads and aggregation; construct exact lineage/statement; require all independent authorities/policies; only then request allowed role signing. Run the guarded frozen-equivalent bridge, not a callback returning the proposed statement. Validate the assembled proof through the independent verifier before storing it as issued.

When those prerequisites do not exist (the shipped default), return NOT PROVABLE and create **no HWP proof/signature**. Preserve optional local experimental observations in an explicitly different file namespace, never `source.hwp`. The implementation path is not a fake success simulation; it is exercised end-to-end with conformance fixtures in test-only tooling that public-projects to NOT PROVABLE. Test seeds/fixtures are excluded from the shipping app's production resources. Future approved authorities/model/profile packages are exact, reviewed, application-release assets or explicitly selected verifier inputs, not arbitrary author edits or an unsigned downloaded JSON flag.

Prospective approval is strict: conformance candidate C can be studied; empirical release E can later bind equivalent operating artifacts and reviewed reports; new production captures start E. Old C captures cannot be relabelled E. Enforce frozen staging, parent closure, exact target capture, complete final document binding and author participation order. An unavailable/failed signing authority must not trigger a fallback to the Nostr author key.

## Native implementation details

Port the actual frozen P/V/R computation with test vectors, not only its wire parser. Use deterministic CBOR core ordering (not length-first), strict COSE Ed25519 algorithm -19/AAD `HWP/0`, canonical subgroup/nonidentity/S checks, byte-counted Refs, salted ordered Merkle commitments/counts and complete disclosure block ordering. Use CryptoKit for private Ed25519 operations and reviewed public-only arithmetic for the frozen strict check. Separate keys/services from secp256k1 Nostr keys; never reinterpret bytes across schemes.

Use exact integer types/BigInt wherever intermediate values can exceed Int64; explicit Python-compatible negative floor division, half-away rounding where specified, quantile order, UTF-8 record-ID ordering, set iteration canonicalization and unsigned digest sorting. Do not replace scalar indexes with Character counts, canonical-equivalent String equality or natural-language tokenization. Float model fitting is a research operation; inference uses the exact exported integer model and code path. Source capture size/time/resource failures preserve frozen fail-closed behaviour; asynchronous cancellation returns unfinished NOT PROVABLE, not a new scientific negative.

Every dereference verifies SHA-256 AND byte length even if cached. Parse hostile evidence with frozen depth/items/objects/byte limits before allocation; private disclosures enforce256-opening blocks except the remainder. Reject unknown object fields, modes, roles, incomplete source closure, algorithm changes, removed signatures, test-to-production downgrade and malformed model branches. No network access or code execution while verifying. Included policy bytes are not trust; the caller's independently chosen pin is mandatory.

R executes the fixed normalized record adapter and actual algorithm. Compare document, target, scope, captures, release and salted exact lineage output to the statement. Voluntary full audit of attested mode must check all witnesses, not only user-picked examples. If V sees required disclosed mode but R/witness is unavailable, reject; do not accept just because the signatures verify. Externally inherited ranges need both verified parent bytes AND actual matching ancestry from planned source captures; finding the same text elsewhere is insufficient.

## Passage and transformed-asset behaviour

The app inspector maps exact source byte intervals to readable grapheme highlights; highlights never change the signed partition. A selected-ranges proof cannot be summarized as unqualified whole-document proof. Copy/move/undo must retain roots. Application-assisted grammar, spelling, dictation, completion, translation and inserted Markdown syntax do not receive new human status through edit-distance heuristics. Quote annotations can request excluded scope without deleting their historical provenance.

V0 certifies exact source bytes only. PDF, DOCX, preview layout, title metadata and article metadata are separate objects. Exported companions contain exact source.md and a matching source.hwp when valid; generated-manifest linkage is not a v0 proof of visual equivalence. Nostr article content is the exact source UTF-8 string; attach identity/association to the exact event ID, not only replaceable naddr. These interfaces do not silently extend v0.

## Privacy, research and availability

Store history/salts locally encrypted; exports are deliberate as DATA.md describes. Attested verification can survive witness deletion but loses future recomputation; disclosed mode needs its complete witness. Archive exact source/proof/definition/release/trust artifacts, not just URLs. No promise of permanent cryptographic strength, global revocation awareness or relay permanence. Supplementary timestamps do not certify thinking duration or creation time.

The shipped release has zero empirical approvals. Native recorder studies, paired composition/transcription, adaptive simulations and representational-collision attacks remain research work; agents may build export/test mechanisms but cannot label synthetic training as validation. Per-profile/path/language/claim evaluation, complete campaign ledgers and false-scalar endpoint remain unchanged. Internal experimental candidate scores may be included only in explicit research exports; ordinary UI never encourages gaming them.

Required tests cover all frozen public/R cases, changed source and stale results, scopes/parents, misleading author key, dishonest-attestor difference, missing witness, signature malleability, data/callback substitution, future release reassignment, all resource bounds and actual current-source gate. A normal Mac session without an independently admitted profile must demonstrably never reach real issuance, even when a developer toggles every user preference.
