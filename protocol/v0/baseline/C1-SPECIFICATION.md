# Human Writing Proof — Cryptographic Core 1

**Wire identifier:** `hwp-c/1`. **Publication:** 1.0.0-candidate.1, 2026-09-15. This identifier denotes this immutable candidate's semantics; incompatible corrections require a new wire identifier. This is a proposed open specification, not an adopted industry standard or an audited production implementation.

The key words MUST, MUST NOT and MAY express conformance requirements. The CDDL, this specification and the reference vectors together define the format. A contradiction between them is a defect requiring an explicit versioned correction, not permission to use whichever interpretation accepts a proof.

## 1. Exact assertion and scope

Human Writing Proof (HWP) binds a positive result of an identified Human Writing Protocol execution to exact document bytes, explicitly selected ranges, admissible captured observations and their relevant provenance. It does not independently establish a hidden cognitive state. It does not certify originality, truth, absence of AI-assisted research, non-plagiarism or an identified person's physical actions.

Only `HUMAN-WRITTEN` is an issuable appraisal result. `NOT PROVABLE`, `AI-written`, probabilities, partial successes and diagnostic strings are not valid appraisal results. A failure generates no Human Writing Proof. A verifier reports `VALID-HWP` or `NO-VALID-HWP`; the latter is a verification outcome, not a signed negative authorship claim.

A positive output MUST include its exact algorithm release, claim semantics, certified ranges, execution mode and independently selected verification-policy identifier. A selected-range proof MUST NOT be presented as a whole-document proof. `fresh-composition` and `wording-origin` are distinct algorithm-owned claims; copying previously supported wording does not establish fresh composition. The cryptographic layer never changes the behavioural algorithm's thresholds or invents evidence that it did not observe.

## 2. Mandatory construction and limits of assurance

The mandatory implementation is an **attestation-backed proof**: an independently admitted capture authority signs the actual captured commitment; an independently admitted evaluator signs the exact result/statement after executing the pinned release. The public verifier checks the signatures, role authorizations, exact bindings and scopes offline. Neither authority needs to be the original application company. Direct public-key pins provide the minimal trust model; existing attestation infrastructure can supply those pins through an independently verified appraisal.

The second implemented mode adds full disclosed recomputation through a verifier-installed implementation of that exact release. A private zero-knowledge replacement for evaluator trust has the binding contract in `docs/PRIVATE-EXECUTION.md`, but **no zero-knowledge suite is activated by this version**. Unknown modes are rejected; a fake receipt, development proof or absent verifier cannot fall back to ordinary signatures.

Capture authenticity remains an external, explicitly appraised assumption. An interface that signs arbitrary caller-supplied roots is not an admissible observer. A physically protected key alone does not authenticate the events given to it. Fabrication before commitment, compromised capture/evaluator authorities, or an attack the HWP algorithm admits may produce a cryptographically valid proof. These are not solved by increasing hash length or publishing on a blockchain. See RFC 9334 and `docs/SECURITY.md`.

Core 1 requires different keys for capture, evaluation and an attributed subject in the same assessed observation. This prevents cross-role substitution, not collusion by one operator holding several keys. Evaluator quorum counts distinct authorized keys; independence of their operators is a separate policy decision.

## 3. Exact bytes and serialization

Use RFC 8949 section 4.2.1 **core deterministic CBOR**, including bytewise lexicographic ordering of the encoded map keys. Do not use section 4.2.3 length-first ordering. Integers use shortest encoding. Strings and containers have definite lengths. Text is strict UTF-8 without Unicode normalization. No floats, undefined/simple values other than false/true/null, indefinite lengths, duplicate keys, trailing bytes or tags other than COSE_Sign1 tag 18 are permitted. Map keys are integer or text, never Boolean, array or byte string.

CBOR integer values in this implementation profile are −2^63 through 2^64−1. Unless a field is explicitly a CBOR algorithm identifier, every schema integer is an actual non-Boolean integer between 0 and 2^53−1 and within its field-specific bounds. Decoding and re-encoding MUST reproduce the supplied bytes exactly. Do not parse then silently repair a noncanonical signed input.

The generic document profile supports exact valid UTF-8 text with media type `text/plain` or `text/markdown`. A BOM, combining sequence, CRLF, trailing newline or invisible scalar is part of the bound bytes. A different export, PDF, layout, rendered HTML or normalized string is a different asset. A proof of source Markdown does not automatically attest a rendered document's visible claims.

Reference `Ref` is exactly `{ "sha256": bstr32, "size": uint }`, where the digest is SHA-256 of the entire referenced raw object and size is its octet length. Signatures, document bytes, standards/program/model files and CBOR data use the same raw-byte reference rule. Digest names inside a Ref are not negotiable. No URL, filename or mutable repository branch substitutes for a reference. All lists of references designated sorted use ascending digest bytes, with duplicates rejected.

Local defensive limits are: a serialized bundle/object ≤64 MiB; a decoded CBOR object ≤100,000 total items and depth ≤32; ≤4,096 objects per bundle; ≤64 recursively evaluated proof nodes; ≤64 captures and appraisals per statement; ≤10,000 scope ranges; a captured stream ≤1,000,000 events. Implementations MAY reject larger artifacts but MUST NOT weaken checks to accept them. The reference is not a constant-memory streaming implementation; production parsers should enforce limits before allocation.

## 4. COSE signature profile

Use RFC 9052 **tagged COSE_Sign1**, exactly:

```
18([ protected_bytes, {}, payload_bytes, signature64 ])
protected = { 1: -19, 3: "application/cbor", 4: key_id32 }
Sig_structure = [ "Signature1", protected_bytes, h'4857502d432f31', payload_bytes ]
signature = Ed25519.Sign(seed32, CBOR(Sig_structure))
```

`external_aad` is ASCII `HWP-C/1`, seven bytes; it is never empty and never inferred from a URL. This is ordinary Ed25519, not Ed25519ph, Ed25519ctx, Schnorr on secp256k1 or signing a separately hashed string. COSE algorithm −19 is the fully specified Ed25519 identifier registered by RFC 9864. The older polymorphic −8 is not accepted in this profile. The content type is the existing `application/cbor`; this specification does not claim a registered HWP media type or custom COSE header.

The entire unprotected header map MUST be empty. Protected headers MUST have exactly keys 1,3,4 and the values above. No additional critical-header mechanism is needed: every unknown field is rejected. Payload is embedded and contains a canonical HWP object with `v` and `type`, both signed. The role is determined by the exact signed payload type and external authorization, never by an unprotected display label.

Public keys use canonical COSE_Key bytes `{1:1, 3:-19, -1:6, -2:public32}` with no other parameters; `key_id32=SHA256(COSE_Key_bytes)`. Key IDs locate keys; they grant no authority. Private seeds MUST NOT appear in proofs, policies or production vectors. Test seeds in this package are intentionally public.

For deterministic cross-implementation acceptance, require canonical encodings of public point A and signature point R, both nonidentity in the prime-order subgroup; require 0≤S<L. Then verify the RFC 8032 equation, without acceptance of noncanonical, mixed-order or small-order points. This strict subset rejects negligible degenerate signatures that a broader library may admit. Signers must use normal Ed25519 keys and reject/regenerate a degenerate output before issuance. In the reference, secret operations are delegated to cryptography/OpenSSL; the public subgroup checks are explicit and tested. Backends still require independent security maintenance.

## 5. Object graph and packaging

Every HWP object other than the COSE_Key has exact text fields `v:"hwp-c/1"`, `type:<listed-type>` plus only the fields below. No unknown fields are ignored. `null` is meaningful where explicitly allowed. All referenced objects needed for the selected mode MUST be present in a complete bundle, except private openings supplied separately for a voluntary audit or disclosed-mode verification.

```
raw document + frozen release artifacts
    -> signed capture-start -> optional signed participation
    -> private event commitment -> signed capture-end
    -> complete scope -> statement
    -> signed positive appraisals + optional signed author endorsement
    -> proof root -> archive / timestamp / transport association
```

Parent proof graphs must be acyclic. No object contains a hash of its own future signature or timestamp. Author endorsement references the statement, not a proof root that would include that endorsement. Optional publication and timestamp associations reference the completed proof/package afterward.

`bundle` has `root:Ref` and `objects:[[digest32,raw_bytes],...]`, sorted by digest with no duplicates. The root references a `proof` object. Each entry's digest and any referring size must match. All references are resolved locally; verification MUST NOT fetch URLs or execute included programs. Unreferenced supplemental objects confer no authority. Removing an unreferenced supplement can produce a different package with the same proof identity; changing the proof root changes the proof identity. The digest of the exact bundle file is different from the digest of its root proof object.

`proof` has `statement:Ref`, `appraisals:[Ref,...]` (1..64, sorted, unique), and `author:Ref|null`. Each appraisal must be valid and independently authorized, and the count must meet the relying party's quorum. Core 1 rejects unknown/unauthorized extra appraisal entries rather than silently selecting a favourable subset. Packaging itself adds no additional signature; authenticated assertions bind the statement, and externally pinned root/package hashes detect changes to an archived or published instance. Removing a surplus valid appraisal may yield another valid instance under the same threshold policy; it cannot strengthen the signed claim or preserve the original root identity.

## 6. Captured evidence, commitments and optional identity participation

`capture-start` is signed by an admitted capture key and has:

* `session:bstr32`: fresh cryptographically random identifier chosen for this capture;
* `profile:Ref`: complete immutable description of the appraised capture boundary;
* `adapter:Ref`: exact normalization/evidence adapter;
* `nonce:bstr32`: fresh capture-source randomness, not by itself an independent timestamp;
* `subject:Ref|null`: intended author key, fixed before the captured process.

If subject is present, its controller signs `participation` with only `start:Ref` in addition to v/type. The capture boundary validates this participation before treating the associated process as attributable. An anonymous capture cannot later be relabelled as a newly attributed capture merely by adding a final author signature. The cryptographic association does not prove that the key holder personally operated the keyboard, nor does it prevent willingly relaying inputs.

A captured private stream consists of canonical CBOR values. Entry 0 is an adapter-defined map with `kind:"header"`; the last entry has `kind:"end"`. Intermediate values and the header/end contents are exactly defined by the pinned evidence adapter. For the HWP-A/0.3 adapter, see `docs/HWP-A03-BINDING.md`. The end entry includes enough private final-state data to reconstruct the actual result; no uncommitted final state may replace it later.

For every entry i, draw a distinct independent secret 32-byte CSPRNG salt. Define:

```
L_i = SHA256(0x00 || CBOR([
  "HWP-C/1:event", SHA256(capture_start_COSE_bytes), i, salt_i, event_CBOR_bytes
]))
```

Salt, index, domain, exact signed start and event bytes all participate. Do not publish salts in a private mode. Do not derive salts from timing, text or public keys. Deterministic test salts are not an allowed production policy. The index range is 0..n−1; n≥2. Use RFC 9162's ordered binary-tree shape: empty root SHA256(empty), singleton root L0, otherwise split at the largest power of two less than n and hash `SHA256(0x01||left||right)`. This uses the RFC tree mechanics but is not a Certificate Transparency log registration.

`capture-end` is signed by the **same capture key** and has `start:Ref`, `count:uint` (2..1,000,000), `root:bstr32`, `complete:true`, `participation:Ref|null`. The signer must atomically close its actual capture state; a caller-supplied arbitrary-root signing API violates the profile. Any observed gap or incomplete input process that the capture profile/HWP does not permit precludes a complete receipt. If start.subject is null, participation must be null; otherwise the valid subject signature must reference exactly this start.

Final root plus count detects alteration, reordering or truncation of a record relative to the signed receipt. It does not prove the collector was honest before signing. Two different signed ends for the same `(capture_key_id,session)` encountered anywhere in the evaluated graph are rejected as equivocation. Unseen forks and undisclosed retries cannot be detected by a standalone offline proof. Rechecking the same valid proof any number of times MUST remain possible.

Merkle inclusion openings contain the exact start identifier, i,n,salt,event bytes and bottom-up sibling hashes. Verify the exact root/count and exhaust the whole path. An inclusion proves membership, not completeness or a positive HWP result. Full disclosure requires all n openings in index order and matching header/terminal markers. Append-only consistency proofs use RFC 9162 section 2.1.4, including strict path exhaustion; no previous root means no append-only claim. Core 1 does not assign checkpoint or public-log credentials a certification role. A stronger witnessed-session profile must separately specify its timestamp/receipt trust and admission rules; no such claim is implied here.

## 7. Release manifest and statement

`release` has `algorithm:text` (1..128 UTF-8 characters), `claim:"fresh-composition"|"wording-origin"`, `artifacts`, and sorted `capture_profiles:[Ref,...]` (1..64). `artifacts` has exactly six references:

| Field | Required immutable content |
|---|---|
| algorithm_spec | Complete interpretation-bearing algorithm specification |
| program | Exact executable or canonical program manifest, including runtime/dependencies and deterministic entry-point definition |
| model | Exact model including feature order, numeric conventions and support artifacts |
| decision_policy | Exact threshold, approved domains and non-statistical acceptance gates |
| evidence_adapter | Normative event/record reconstruction and input encoding |
| output_contract | Exact selected-scope/result/lineage encoding and algorithm-call semantics |

A label or URL alone is not a program manifest. A manifest's transitive files must be retained for future recomputation; use a canonical manifest containing filename and Ref for every dependency and validate it in the release-specific runner. This core checks the six direct objects' bytes and external release approval, but never executes or assumes the contents of an unknown manifest. A production release's approval/recompute integration MUST also check its declared dependency closure. The fixture's opaque strings are expressly not production manifests.

`statement` has exactly:

| Field | Meaning |
|---|---|
| document:Ref | Exact final UTF-8 document bytes |
| media_type:text | text/plain or text/markdown; no implied rendering/export equivalence |
| scope:Ref | Complete range/origin map described below |
| release:Ref | One frozen algorithm release |
| captures:[Ref,...] | Sorted unique complete capture-end signatures, 1..64 |
| target_capture:Ref | Exact member of captures whose record is the assessed final target; never inferred from equal text |
| lineage:bstr32 | Salted commitment to the exact private algorithm-lineage output |
| mode:text | attested-v1 or disclosed-v1 |
| author:Ref/null | Optional author key fixed consistently with all selected observed captures |
| nonce:bstr32 | Fresh statement randomness to distinguish separately issued assessments |

The private lineage commitment is `SHA256(CBOR(["HWP-C/1:lineage", salt32, exact_lineage_bytes]))`. The evaluator computes it over the pinned output contract; an author-provided lineage digest is not enough. The voluntary witness includes the lineage salt; the exact lineage bytes are recomputed from captured records by the installed runner. Exact encoding of an algorithm's internal lineage is owned by its output contract, not guessed by the crypto verifier.

All starts' adapters must equal release.artifacts.evidence_adapter. Every capture profile must appear in the release and in the externally selected capture-authority grants. Algorithm outputs, scopes, parent references and lineage must be computed from the same captured records. No precomputed feature vectors are accepted as a substitute for that chain.

## 8. Complete scope and passage provenance

`scope` has `document:Ref`, `kind:"whole-document"|"selected-ranges"`, and `ranges:[{start:uint,end:uint,origin:array},...]`. Ranges are nonempty half-open **UTF-8 byte intervals**, ordered, adjacent and covering the entire exact document. Endpoints must be Unicode scalar boundaries. At least one certified non-whitespace scalar is required. The fixed whitespace list is in the reference, not a platform-dependent Unicode classification call.

Only three origin forms are allowed:

1. `["observed", [capture_end_Ref,...]]`: sorted nonempty references, all present in statement.captures. Each selected capture's subject must equal statement.author, including null. The evaluator attests that these captured observations support this exact range under the release.
2. `["inherited", parent_proof_Ref, parent_start, parent_end]`: allowed only for wording-origin. Recursively verify the parent under the relying policy, compare the exact parent bytes and length with the child interval, and require the full parent interval to be covered by certified parent ranges. This preserves literal wording provenance, not fresh assembly or authorship by the child subject.
3. `["excluded", reason_text]`: outside the HWP claim. Reason is ≤1,024 characters of metadata, not a certified source citation or assertion that the quotation is genuine.

A whole-document scope has no excluded range; any exclusion requires selected-ranges. Whole-document and selected-range signatures are not interchangeable. Adjacent entries may remain separate when their provenance differs. The verifier returns the exact selected intervals without inventing a per-character behavioural error guarantee. No excerpt automatically becomes a new whole-document proof: it retains its parent document binding or receives a separately evaluated derived proof.

## 9. Evaluator appraisals and issuance

`appraisal` is COSE-signed by an externally authorized evaluator and has only `statement:Ref` and `result:"HUMAN-WRITTEN"`. The signature covers every transitive exact binding in the statement. Capture keys, evaluator keys and an attributed author key must be distinct in the assessed instance.

Before signing, the evaluator must: appraise the admitted capture path; verify starts, participation, final receipts and matching commitments; reconstruct the complete records; execute the exact approved release with the required independent capture context; obtain a positive result for the exact selected scope and claim; check public origins against private lineage; and build the statement from those outputs. It must refuse incomplete/unapproved/nonqualifying results. The cryptographic library cannot stop a malicious issuer who holds an authorized private seed from lying; the security contract identifies that issuer's responsibility.

`sign_appraisal` accepts an exact computed output tuple `{document:Ref,scope:Ref,lineage:bstr32,release:Ref,captures:[Ref,...],target_capture:Ref,result:"HUMAN-WRITTEN"}` and refuses any mismatch with the statement. This tuple must come from the trusted evaluator pipeline, not a writer's request. `assemble_proof` returns a package only after complete verification against the intended relying policy. Low-level `sign` is a generic primitive and is not itself HWP issuance.

In attested-v1, the published proof's executable-computation assurance comes from the admitted evaluator signatures; the evaluator may operate in an appraised local boundary so history never leaves the device. In disclosed-v1, signatures are still required and the verifier additionally opens every captured stream and runs an independently installed implementation keyed by the exact release digest. The private disclosure has exactly `logs:[{capture:Ref,openings:[Opening,...]},...]` and `lineage_salts:[{statement:Ref,salt:bstr32},...]`; duplicate entries are rejected. Each required capture and statement has one matching entry. The installed callback is `runner(evidence, release, request)`, with evidence entries `{capture:Ref,events:[opened_CBOR_values...]}` in statement capture order, and request `{target_capture:Ref,requested_scope:Scope,lineage_salt:bstr32,artifacts:{role:exact_verified_bytes,...}}`. It reconstructs the declared target, applies only algorithm-permitted exclusions, computes actual lineage using the provided salt and returns the exact tuple above. It must not merely echo requested scope or hashes. The verifier never imports a callback or code path from the proof. A callback returning true, a different scope/model/lineage, a development/mock result or missing witness fails.

A relying verifier may voluntarily force full recomputation of an attested proof without changing its original statement or mode. This strengthens that verifier's inspection, not the historically signed claim. Partial disclosure never satisfies full recomputation.

## 10. Author and optional identified association

If statement.author is nonnull, proof.author must reference an `author-endorsement` signed by exactly that key, with `statement:Ref` and `identity:Ref|null`. It is a self-assertion of authorship and proof of key control bound to this certified contribution. Its subject must already be linked to the observed captures through start and participation. A proof cannot silently lose its required author endorsement.

If identity is nonnull, it references an independently authorized issuer's signed `identity-binding` containing `subject:Ref`, `namespace:text` (1..256) and `identifier:text` (1..1024). Its narrow meaning is that the selected identity authority associates that key controller with that identifier under the namespace; it does not establish who physically composed the text. No name string supplied by the author grants identified status. Core 1 uses direct identity-authority pins, without delegations, expiry fields or implied government/legal assurance. An issuer translating an existing credential must validate that credential separately and take responsibility for this narrower association.

Time-bounded identities, credential revocation, delegation, DID resolution, organizational representatives and legal-signature policies require additional explicitly verified credential profiles; Core 1's unbounded identity assertion cannot pretend to provide them. Optional external identities or Nostr associations not satisfying this schema remain separately labelled associations, not core identified-author evidence.

## 11. Independent verification policy

The verification policy is canonical CBOR supplied and pinned by the relying party, never selected from the proof. It has v/type plus:

`label:text`, sorted `releases:[Ref,...]`, `capture_authorities:[{profile:Ref,keys:[Ref,...]},...]` sorted by profile digest, sorted `evaluators:[Ref,...]`, `quorum:uint`, sorted unique `modes:[text,...]`, `require_author:bool`, sorted `identity_authorities:[Ref,...]`, sorted unique `denied:[digest32,...]`, `status_as_of:uint|null`.

Releases are nonempty. Each capture grant and evaluator list is nonempty. Quorum is 1..number of evaluators; it counts distinct authorized valid appraisal signatures. A denied key or required artifact makes verification fail. Every required reference must match its complete size and digest. `status_as_of` is descriptive knowledge time of this externally selected policy snapshot, not a timestamp of the proof or evidence that the snapshot is current. A policy contains no automatic approval of itself.

A raw-key grant is intentionally atemporal in this core. There is no implicit expiry clock or 'latest' online lookup. Historical and current trust decisions use different external snapshots and may disagree while the bytes/signatures remain unchanged. Applications requiring bounded key validity, live revocation status or issuance before compromise must apply the archival/time profiles and adequate external trust evidence; they must not accept a claimed local creation time as sufficient. See `docs/ARCHIVAL.md`.

## 12. Verification order and deterministic result

Apply bounded strict parsing and object-digest validation. Match the independently supplied policy pin. Match exact expected document bytes. Check release approval, artifacts and execution mode. Verify all capture signatures, same-key closure, participation, adapter/profile authorization and encountered equivocation. Verify scope partition, origins, recursive parents and subject bindings. Verify distinct evaluator signatures/quorum. Perform required or requested recomputation. Verify optional/required author and identity associations. Only then return VALID-HWP.

No failure returns a valid negative certificate or implies AI generation. The reference catches malformed inputs at its public API and reports diagnostic reasons; error wording is diagnostic, not a wire compatibility requirement. Result fields identify proof/document/release, selected intervals, original mode, whether computation was rechecked, policy digest/knowledge time, author-association class and `timestamp:"not-assessed"`. Time adapters produce separate validated time evidence; core verification does not quietly claim a time it did not check.

The exact public document, public evidence objects and selected immutable policy are sufficient for repeated attested-mode verification after the original company disappears. Disclosed-mode repeat verification additionally needs the full witness and the pinned executable/runtime implementation. An unavailable required object, policy basis, disclosed witness or accepted verifier means no valid proof under that request—not a weaker fallback.

## 13. Extensibility, durability and nonclaims

All interpretation-bearing changes require a new wire version or a new exact approved algorithm release as appropriate. New model bytes create a new release reference. Reassessment of old captured evidence is a new statement and proof; it does not overwrite the earlier verdict. Missing telemetry cannot be synthesized as migration data.

No algorithm is promised secure forever. Core 1 does not claim post-quantum signatures. For long-term use, archive exact original bytes and trust evidence, then renew their protection with established evidence-record mechanisms before relevant primitives or signing credentials become unsafe. Renewal after an undetected break cannot retroactively establish original validity. Preserve old semantics, evidence and renewal links. A hash is not storage and cannot recover lost artifacts.

Nostr, C2PA, RFC 3161, OpenTimestamps, COSE receipts and RFC 4998 serve separate association, binding, time, transparency or archival roles. Their exact boundaries are in the companion documents. None converts an unsupported process into HWP. No new blockchain, token, wallet requirement, Nostr kind number or proprietary signing algorithm is introduced.


## 14. Additional reference and resource requirements

Every Ref is checked for both hash and length, including cached parent proofs and encountered key-authority grants. Cache hits must not skip denial or reference-size checks. Unused policy grants need not be included in a proof archive; every actually used key must resolve to the exact granted bytes.

The total public bundle is bounded at64MiB, individual document bytes at1MiB, and all private disclosed event bytes plus salts together at64MiB with at most1,000,000 aggregate events. These crypto-profile limits do not change the HWP algorithm's own possibly tighter limits. Exceeding either returns no valid proof, never a weaker verification path. A native streaming implementation must enforce limits before allocating untrusted input. The reference is a conformance implementation, not a measured production performance guarantee.
