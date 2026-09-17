# Exact HWP-v0 observation-to-proof binding

**Adapter `hwp-a-v0-cbor/1`.** The normative reference is `hwp0/bridge.py`. The bridge is an actual implementation, not an evaluator-supplied callback that echoes the statement.

## 1. Lossless normalized record mapping

A source record has exactly `id, language, resolution_us, paths, observations, transactions, final_text`, under algorithm `hwp-a/v0`. All values must be JSON-compatible: null, Boolean, Unicode scalar string, safe integer, arrays and text-keyed maps. Floats, byte strings, tags, integer-keyed maps and unsafe integers cannot enter the algorithm through a CBOR conversion.

The committed events are:

```
0: {kind:"header", adapter:"hwp-a-v0-cbor/1",
    id, language, resolution_us, paths}
1..N: {kind:"observation"|"transaction", value:original_event}
N+1: {kind:"end", final_text:original_final_text}
```

The original events have contiguous combined seq values0..N−1 in exactly that order. Filtering the wrappers restores the original observations and transactions arrays without changing their per-stream i values. Header and end do not consume seq. No other wrapper fields are allowed. Every original field, including its independently observed native delivery, survives. `record_events` is a serializer, not a native collector or legacy upgrade tool.

The Merkle count is N+2. Opening verifies exact count, unique salts, consecutive index values, start binding and root before decoding records. Final text must hash to that capture's signed end.document. Record path/profile/language and resolution must satisfy its admitted signed capture profile. Correct formatting does not authenticate that source.

## 2. Target and dependency closure

Every capture maps to one record, every record ID is unique within this execution, and the statement names an exact target capture. Final text equality is never used to guess the target. For each record, collect every external copy.from_doc appearing anywhere in its transaction history, including later-deleted or excluded imports. These direct dependencies must equal exactly the corresponding start.parents capture list. A parent proof, if nonnull, must target that same captured source.

The bundle contains exactly the target and the transitive closure of those dependencies. No unrelated source can supply favourable features or retroactive source exposure. Cycles, missing sources, duplicate IDs, duplicate captured sessions and undeclared imports reject. Internal copies do not create a record edge. Kahn-sort the record graph, choosing the smallest UTF-8-encoded ID among currently dependency-ready records. The algorithm bundle has documents in that order and its original target ID. No global clock, inferred reading history or synthetic concatenation of multi-device fragments is created.

The original start of the target must commit to the exact current release. An ancestor's start may commit to a different externally admitted release, but has the same v0 adapter and an admitted compatible capture profile. New target evaluation can add conditions on those observations; it cannot rewrite the ancestor's historical proof or bypass verification of its source proof.

## 3. Admitted execution context

The outer verifier authenticates each capture key, exact profile grant, same-key start/end, positive completeness, subject participation, planned release, dependencies and exact final-state binding. Only then does the bridge construct the algorithm's TrustedInputs from those exact opened records and the exact release model/threshold/domains/claim. In that context, fresh means admitted to the original prospective capture, not “has never been verified previously”. Rechecking old bytes is permitted.

Model, decision policy, adapter, reference program and output contract are distinct exact objects. The model schema is fully validated, including unused branches and numeric types. The program and normative artifact references match the locally selected immutable interpretation. The reference supports no author-selected executable, unverified preprocessing, generic plugin callback, or supplied favourable score array. A Rust/Swift/JavaScript implementation can implement the same semantics; a valid signature is not evidence that an unreviewed implementation did so correctly.

## 4. Scope and origin validation

The public scope is an explicit input, not an output chosen by an evaluator to maximize a displayed score. Convert excluded byte intervals and their exact nonempty descriptions to the algorithm's exclusion list. This changes only what is claimed, never segmentation or root support. Execute the real algorithm. Whole scope requires its whole-document verdict; selected scope requires its contribution verdict. The relevant value must equal HUMAN-WRITTEN.

For each selected observed interval, every root must have been born in the target. Compute the union of actual required record dependencies over the interval and compare its sorted capture Refs exactly to the public origin. Internal duplicate occurrences retain wording ancestry only under wording-origin; they do not become fresh roots.

For an inherited interval, require wording-origin and an independently verified positive parent proof. Find that proof's target capture in the current source-record graph; it must be a non-target, predeclared source with the same planned parent proof Ref. Convert the parent byte interval to scalar offsets. Compare each target scalar's character and complete root set with the corresponding source scalar. This rejects attaching a different proof merely because it contains identical text. The proof verifier separately checks parent byte coverage, policy, signatures and selected ranges. Neither check substitutes for the other.

## 5. Exact outputs and acyclicity

The complete private lineage is defined in `docs/OUTPUT.md`, including the actual full successful algorithm assessment. The bridge returns:

```
{
 document:Ref(actual_final_utf8_bytes),
 scope:Ref(canonical_requested_scope),
 lineage:SHA256(CBOR(["HWP/0:lineage", salt32, private_lineage_bytes])),
 release:Ref(canonical_exact_release),
 captures:sorted_actual_capture_refs,
 target_capture:actual_target_capture_ref,
 result:"HUMAN-WRITTEN"
}
```

No field is copied as trusted truth simply because the proposed statement contains it. Target selects an input; scope requests a claim; the computation must establish both. The supplied salt randomizes a commitment but cannot alter the underlying assessment. The bridge is keyed per **release and statement**, not release alone, so nested parent and child assessments using the same release cannot overwrite each other's invocation.

The normal issuance flow computes this result and lineage first, constructs the final statement, then runs the guarded appraisal signer. The complete producer helper uses the same bridge again before signing. No final statement hash is inside its own lineage. Voluntary audit supplies the preimage and salt after the fact without changing the proof object.

## 6. Explicit boundaries

Attested public verification cannot inspect hidden source-to-parent root equality. It checks the exact assertion by admitted evaluators. Full disclosed recomputation checks the relation itself. Neither independently verifies the physical truth of a dishonest capture source's initially fabricated observations. Both require proper empirical release admission for a real positive result.

V0 does not admit opaque parent import without the source histories required by this algorithm. Source proofs and private record histories may be shared voluntarily with an evaluator; they need not be published in attested mode. A future private recursive-execution or ZK parent profile must define a new compatible computation rather than silently replacing this requirement with a hash.
