# Private verification and the exact computation boundary

## Implemented private mode

`attested-v1` is a public, independently checkable assertion by a policy-authorized evaluator about a policy-authorized captured process. The evaluator can run in an independently appraised local execution boundary; under that profile, detailed behaviour stays on the writer's device. The public verifier checks role authority, the exact input/output commitments and every required signature without contacting the original company. This is **attestation-based verification**, not a proof that removes trust in the evaluator. A regular downloadable application controlled by an adversarial author is not automatically such a boundary.

`disclosed-v1` adds complete recomputation by a relying-party-installed implementation of the exact release. It does not weaken the capture requirement. Both modes still require evaluator appraisals under HWP-C/1. The same attested proof can be voluntarily rechecked with `force_recompute=True`; neither its signed mode nor its statement changes. The output records that recomputation was additionally performed.

The witness has exact fields `logs` and `lineage_salts` as defined in SPECIFICATION.md. An entry is bound to its complete capture-end/statement Ref, including byte length. Opening paths are not a replacement for complete disclosure. All decoded event bytes must be canonical and match root and count; unknown target, missing lineage salt or missing independently installed runner fails. Extra disclosed data must not be treated as an alternative source of favourable results.

## Why an encrypted log alone is insufficient

Publishing encrypted evidence plus a classifier signature can conceal history, but independent verification without the decryption key still rests on the signer. A proof of the existence of some passing transcript is also insufficient: a simulator can choose that transcript. Any private computation construction must prove execution on the **same record** committed by the admitted capture source and on the exact algorithm release, target and scope. Public roots do not authenticate themselves.

## Reserved zero-knowledge construction — not an activated HWP-C/1 suite

The following is a precise binding/review contract for a successor execution suite. It is not a wire mode accepted by this reference and supplies no fabricated proof-system key, circuit image or benchmark. An implementation claiming ZK compatibility before fixing and reviewing all items below is nonconformant. Current mandatory issuance/verification remains fully implementable without ZK.

Let P be the exact canonical HWP statement bytes and R the exact approved release bytes. Public input is the canonical CBOR array:

`["HWP-C/ZK/1", SHA256(P), SHA256(R), document_Ref, scope_Ref, target_capture_Ref, captures, lineage_commitment, "HUMAN-WRITTEN"]`.

Every Ref includes digest and size, captures are sorted by digest, and their public root/count/start tuples are derived from the already validated signed receipts. A future proof envelope must bind those tuples as part of the circuit's public input, not merely provide them to off-circuit preprocessing. Proof-system domain/version, verification-key/image identity, public-input ABI and complete verifier artifact are independently approved alongside the algorithm release. A statement must name its exact suite; proofs are generated afterwards to avoid a circular reference.

The private witness is the ordered exact event bytes and salts for every captured record, the lineage salt, intermediate replay states if required by the prover, and any private execution metadata. The constrained program must perform all of:

1. Parse the canonical signed-input binding objects and verify equality with the public tuples. Signature verification can remain outside the proof only if the verifier checks exact equality between the receipt-derived tuples and the circuit's public inputs.
2. Recompute every salted leaf using the captured start digest and contiguous index; compute the specified tree roots and exact counts; require header and terminal records with no truncated or unaccounted events.
3. Decode through the exact pinned adapter; reconstruct the declared target and every dependency; run the exact approved replay, feature extraction, model, policy, requested-scope validation and origin propagation. No writer-supplied feature vector, score, origin map, completeness flag or executable is taken as an unconstrained oracle.
4. Compute exact final UTF-8 document bytes and scope bytes, check their Refs, and compute the exact pinned lineage-output bytes plus salted lineage commitment.
5. Emit exactly the public tuple with the positive result. No proof is emitted for a negative/nonqualifying result. Unproved pre/post-processing cannot change text, scope or policy after this equality check.

A future suite MUST fix: exact proving/verifying algorithms and versions; soundness/security parameter; Fiat–Shamir transcript and domain separation if applicable; all field/hash/commitment parameters; any setup/ceremony assumptions and retained verification data; canonical proof encoding, length limits and transcript parsing; program/image digest derivation; CPU/VM instruction semantics, public journal encoding and checked output; recursion/aggregation composition; failure handling; and non-test proof acceptance. A general zkVM name is not enough. An audited production verifier plus positive/negative cross-implementation vectors is an activation prerequisite.

For long-term verification, archive the exact verifier, specification and verification material, not just a hosted verifier URL or provider API. If a universal VM verifier is used, archive both VM verifier parameters and the exact guest program/image. A future circuit upgraded to a new model produces a new assertion; it cannot reinterpret an old one. A succinct proof generated by a remote prover may disclose the witness to that prover; zero knowledge toward the public verifier does not guarantee privacy from the prover.

## Decision

Use the implemented attested mode where the relying party has an independently defensible local evaluation/capture trust boundary; use full disclosure where voluntary inspection is required. Do not describe either as a trustless cognition proof. A zero-knowledge suite can reduce evaluator trust while preserving the same claim, but cannot remove capture assumptions or improve the behavioural classifier's accuracy. No HWP zero-knowledge prover or performance measurement is included in this package.
