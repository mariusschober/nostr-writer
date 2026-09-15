# HWP-A 0.3.0 — normative human-writing verification specification

**Algorithm version:** `hwp-a/0.3`. **Implementation package:** `0.3.0`. **Model format:** `hwp-a-model/0.3`. **Ledger format:** `hwp-a-ledger/0.3`.

This document and the accompanying reference source define a directly executable method. MUST and MUST NOT are conformance requirements. They are not assertions of achieved empirical reliability. No approved certification model is included. When prose and implementation disagree, that is a conformance defect: an implementation MUST NOT silently choose the interpretation that accepts more text. Freeze the relevant release, resolve the discrepancy explicitly and add a distinguishing test.

## 1. Claim and nonclaims

The target is the process by which wording was composed. AI-informed ideas followed by independent human wording may qualify. Mechanical transcription of human or AI wording, paste, scripted input, replay and staged behavioural imitation do not qualify as fresh composition. A person may think before typing, write fluently without editing, or revise extensively; no fixed behaviour is sufficient evidence of thought.

The default claim is `fresh-composition`: accepted wording originates in qualifying candidate creation episodes in the assessed target record, with any exclusions explicitly declared. The separately evaluated claim `wording-origin` can carry ancestry from another admitted record or internal copy. It does not assert that copying was composition, that the present assembler composed the imported words, that the resulting argument was human-planned, or that an identified person authored it. Neither claim establishes originality, absence of AI influence, personhood, named-author identity or truth of the text.

Both claims use only `HUMAN-WRITTEN` or `NOT PROVABLE`. The claim identifier MUST accompany a positive result. An unqualified positive result is invalid. Exact final text and complete half-open UTF-8 range partition accompany the internal assessment. Origin resolution can be one Unicode scalar; **behavioural inference remains contextual**, never a claim to observe the mental origin of each character independently.

## 2. Algorithm inputs and trust boundary

`verify(bundle, model, threshold, context, excluded, claim_kind)` is the certification entry point. `score` computes the same threshold-independent evidence path for diagnostics and experiments. `decide` is an internal formatting/aggregation helper; calling it on invented scores is not verification.

The bundle contains exact version, topologically ordered records and target record ID. Each record contains `id`, `language`, `resolution_us`, `paths`, `observations`, `transactions` and `final_text`. All initial text starts empty. A previously written draft enters through explicit copy/paste transactions; its provenance is never inferred from a filename or initial text string. Cross-record copying references an earlier record in the bundle. Native collaboration and arbitrary concurrent merges are not admitted in this version; they require a future profile, not an invented serial history.

`TrustedInputs` is an independently supplied relying-party/laboratory argument. It identifies admissible and fresh record IDs, exact immutable record snapshots, allowed domains, the exact approved model snapshot, threshold and claim. No telemetry field may supply or override it. Exact snapshots are ordinary canonical-JSON equality checks, not a capture-authentication mechanism. IDs and Boolean approval flags alone are insufficient. Scoring takes immutable local copies before parsing to avoid caller mutation during a calculation.

For positive certification, every required record must be both admissible and fresh, and equal the independently selected record snapshot. The model must match the externally selected exact snapshot and approved threshold and have purpose `validated-release`. The purpose string alone grants nothing. This package grants no such external approval.

An accepted capture path must justify complete in-document observations, actual resolution, source labels, ordering, delivery semantics, native cause-to-mutation attribution, absence of unobserved text mutation and permitted transformations. A key-down, a protected key, a browser trust bit, the absence of visible paste, or valid JSON is not sufficient. If these assumptions cannot be justified for a platform, its output is NOT PROVABLE. This requirement is a boundary contract, not work on a cryptographic system.

## 3. Normalized observation contract

[TELEMETRY.md](TELEMETRY.md) and `telemetry.schema.json` define syntax; `replay.py` supplies cross-field/state validation that JSON Schema cannot express. Each raw observation has its own contiguous `i`, a shared total-order `seq`, quantized monotonic `t` in microseconds, `kind`, unique episode `token`, observed `source` and `profile`. Source is `device`, `synthetic` or `unknown`; it is an observed capture classification, not a writer declaration. A native `delivery` additionally carries an `effect` object.

Transactions have their own contiguous `i`, a total-order `seq`, `t`, `op`, `profile`, one-use `causes` and a one-use `delivery` reference, plus operation fields. Across raw observations and transactions, `seq` is exactly 0 through N−1. Each stream preserves this order, and timestamps are nondecreasing in total order. Ties therefore never allow future events to cause earlier mutations.

A delivery is an independently observed normalized native command/text update. Its `effect` must equal the transaction excluding `i,t,seq,delivery`, including cause references and operation-specific fields. Every referenced cause precedes the delivery; the delivery precedes the transaction. Every delivery must be consumed exactly once. No collector may manufacture this observation simply by copying the author's mutation payload. Delivery binding and an admissible decoder path are necessary to distinguish a recorded key episode from arbitrary supplied text.

Delivery-to-transaction delay is at most 250,000 microseconds. Direct raw cause-to-transaction delay has the same bound. Cause and transaction profiles agree. Required input starts, updates, repeats, IME commits and gesture completions occur while focused and unsuspended. Physical releases may complete after focus loss. Direct causes cannot cross an interruption. A capture gap disqualifies the affected record and its dependent contribution; losing focus alone is a segmentation event, not evidence of nonhuman writing.

Keyboard, touchscreen tap, IME and gesture paths remain separate. Exact `(profile, path, language, view)` model domains prevent acceptance by a different decoder that happens to use the same profile name. Autocomplete, prediction, rewrite and assisted spelling insertions are not direct candidate wording. Dictation and unsupported accessibility paths yield unsupported evidence, not an accusation. New compatible accessibility support requires its own observable contract and validation.

## 4. Replay and provenance

The canonical document is its exact Unicode scalar sequence with exact UTF-8 encoding. No normalization, newline conversion, trimming, case folding or rendering equivalence occurs. Native UTF-16 offsets must be converted by the collector. Normalized transaction positions are scalar indices; published scope offsets are byte offsets on scalar boundaries. Grapheme clusters may contain several scalars; the collector records the actual native edit without pretending one scalar equals one visible character.

For each inserted scalar create `record:transaction:offset`. A direct, properly bound device-origin insertion creates a candidate atom whose sole root is itself. Other inserted text creates unsupported/external atoms with no candidate roots. Candidate is not yet HUMAN-WRITTEN. All origins, deletions and historical alternatives remain available to replay and analysis.

- `splice`: the exact deleted string must match the live prestate. Replace the range with fresh atoms. A newly typed replacement is assessed as a new episode, never by edit-distance inheritance. Synthetic/unknown direct causes downgrade new text to unknown. Automated deletion of existing text marks the record's control process inadmissible.
- `copy`: allocate new live IDs and preserve root ancestry and required records. It creates no new composition effort. Under fresh-composition its copied occurrences are NOT PROVABLE; under wording-origin their original supported roots can carry through.
- `move`: preserve the moved atom IDs. Destination indices refer to the buffer after removing the source range. This is a relocation, not a new creation episode.
- `undo`/`redo`: require the exact top-of-stack original transaction ID and expected live subrange. Restore original atoms and ancestry. A new mutation clears redo. Undoing an import cannot turn it into typing.
- `navigate`: records selection/caret movement; it creates no text. Navigation is context for later changes, not direct evidence of composition.

Synthetic or unknown-source copy/move/undo/redo/navigation makes the control process inadmissible. Direct candidate insertions remain new candidates even when informed by earlier external ideas: there is no semantic contamination rule. However, all new wording from an assisted replacement, including the old bounded-spelling category, remains unsupported. The earlier edit-distance exception is removed because `100→900` and many factual or negation changes are small edits.

Origins retain their required record dependencies. A root's original home record supplies its creation/revision neighbourhood; moving or importing words cannot choose a more favourable history. All live IDs must be unique. Final replay must exactly reconstruct `final_text`. Invalid histories return NOT PROVABLE.

## 5. Observed-source veto

For each record, index exact 32-scalar shingles from earlier externally inserted strings in that record, recording first exposure transaction. A final matching shingle is vetoed only when every contributing root was newly created in that same record after that exposure. The veto propagates to imported descendants of those roots.

This is a conservative, explicit source-reuse rule, not a plagiarism claim. Shared stock phrases can produce non-admission. Shorter, modified, memorized, off-device or unobserved source material is not ruled out. Text from an unrelated/future record cannot retroactively establish that an earlier author saw it. No bundle-global clock or reading history is invented. The 32-scalar threshold is an engineering constant whose coverage cost must be measured, not a theoretically sufficient composition threshold.

## 6. Runs, evidence units and adequacy

Runs split at an interruption, a gap exceeding 120 seconds, input-profile changes, displacement greater than 256 scalars, or transition into/out of an external-text source. See `barrier` in `replay_document` for exact transitions. Tiny discontinuous episodes are not enlarged by a favourable requested scope.

Three local views use fixed windows of width/stride `(64,32)` and `(256,128)`, including an end-aligned final window. A shorter nonempty run yields its entire range, but must still pass adequacy. Views are:

1. **birth**: all candidate roots in each creation run, including later deleted candidates;
2. **layout**: distinct surviving home roots in their final contiguous run order;
3. **retained**: those same surviving groups sorted by creation transaction and insertion offset.

A fourth **global** unit contains all surviving home roots for each input profile. All required units are constructed before thresholding and independently of requested exclusions. Repeated copies do not manufacture unique roots. Root scores are the minimum of all units containing the root. A surviving root without every required view is unsupported. This is a deliberate conservative intersection, not independent-vote aggregation.

Every unit needs at least 64 distinct roots. It also needs at least 16 connected production deliveries for keyboard/tap or 4 for IME/gesture. Each transaction contributes at most one delivery. Transactions sharing the same physical episode token are unioned; held-key repeats and multiple modifiers cannot manufacture independent evidence. These are **production components**, not statistically independent cognitive observations. A 64-root window is not proof that its cognitive origin is identifiable. Short additions and fragmented runs can legitimately remain NOT PROVABLE.

## 7. Features and model

`FEATURE_NAMES` fixes 179 names in sorted order. `FEATURES.md` and `features.extract` define each family and arithmetic. All inference values are integers in [−10,000,10,000]; ratios, quantiles, counts, durations, equality measures and correlations use the specified integer rules. Missing evidence uses explicit presence indicators and zero numeric slots, never invented timings.

Features cover input resolution, production episodes, local pauses relative to syntax, dwell, burst roots, revision distances and ages, cancellation, bounded exact lexical relationships, operation transitions and process shifts. They do not count a pause as thought, an edit as understanding or fluent output as automation. Gap-bin boundary uncertainty is explicitly censored where implemented; not every temporal feature is interval-robust. Quantization and jitter must therefore be part of path-specific tests.

The implemented empirical model is four discriminative heads: transcription, automation, simulation and mixed-origin. Each head has 32 trees of maximum depth two. Each leaf lies in [−1250,1250]; head sums lie in [−40000,40000]. Branch left exactly when `feature <= threshold`. The unit behavioural margin is the minimum head sum. This is not a likelihood ratio, a posterior probability or a proof against an unrepresented attack family.

Fitting uses class-balanced logistic boosting with equal cluster mass, equal document mass within cluster and equal window mass within document. Training rows sort by fixed ID; cuts are deterministic training-quantile candidates. Constants are learning rate 0.125, regularization 0.001, clipped Newton step ±1, half-away-from-zero exported integer rounding, minimum two rows per branch and a 10^−12 gain tie tolerance. Source is executable in `model.py`.

Each complete domain must have H examples and all four negative heads. Missing domains are excluded. Robust L1 distance uses per-feature interquartile scale floored at 500, at most 128 deterministic farthest-first human training medoids and the fifth nearest available prototype. At least 99 separate development-cluster support references are required. The support-rank diagnostic passes only when `100*(1 + count(reference >= distance)) > 1 + n`. This rank is **not** advertised as a conditional human probability or a valid conformal guarantee for adaptively selected windows.

Every model branch, head, prototype, scale, numeric type and feature order must validate before inference, including unvisited branches. Floating-point coordinates, unknown fields, bool-as-int values, unsupported versions or incomplete domains fail closed. No trained real-world model is bundled.

The fixed representation has demonstrated collisions: different meaningful text can produce identical features on the same writing-shaped trace. The current 179-feature family and tree depth are therefore an executable baseline, not a theoretically optimal representation. A collision attack belongs in release evaluation. Replacing features or model families requires a new versioned computation and fresh validation, rather than renaming the same claim as stronger.

## 8. Verdict calculation

For each final scalar, first require all origin/capture dependencies, supported complete root neighbourhoods, no observed-source veto and the appropriate fresh-composition/wording-origin gate. Unsupported values are `SCORE_FLOOR = −10^9`. Otherwise take the minimum root margin. The threshold must be an integer strictly greater than SCORE_FLOOR. A scalar passes when its value is **greater than or equal to** the threshold and certification is enabled by the exact externally selected release.

Whole-document HUMAN-WRITTEN requires every scalar to pass, nonempty non-whitespace content and no exclusions. No length-weighted average is permitted. Exclusions form ordered, non-overlapping, nonempty UTF-8 ranges with source descriptions; they change scope but never neighbourhoods or underlying origin. Contribution HUMAN-WRITTEN requires every nonexcluded scalar to pass and at least one nonexcluded non-whitespace scalar. Whole-document verdict remains NOT PROVABLE when exclusions exist.

The output partitions the complete text into maximal adjacent ranges with equal verdict, reason, origin, original record set and exclusion state. Each range is contextual support for wording at that position, not an independently calibrated one-character cognition test. Invalid input, bad scope, unsupported evidence or absent approval returns NOT PROVABLE. A malformed release/label must abort study eligibility rather than be disguised as a successful attack rejection.

## 9. Risk, coverage and study eligibility

Use the exact full pipeline and same claim in evaluation. For a nonqualifying attempt the score is the maximum accepted-candidate score among falsely attributed scalars; a single false scalar is a failure. For an attack block take the maximum over every preregistered attempt. For a genuine-writing block take the minimum complete-document score over all required tasks. Invalid complete traces are retained as structural rejections. Missing, crashed, pending or unrecorded trials are incomplete, not automatic negative outcomes.

A frozen ledger enumerates all slots, blocks, attempt indices, dependency links, sampling contracts, phase and claim. Attempt indices must exactly cover 0..B−1. IDs and known dependency links cannot create two nominally independent blocks in the same cell. All slots need exactly one result. Record completeness cannot establish that the sampling assumptions or annotations are true.

Required release cells are path/language-specific: eight attack families (`calibration.FAMILIES`) at B=1 and B=100; and separate unaided, AI-informed, fluent-expert, revision-heavy, interrupted and second-language genuine-writing cells. `run_release` checks the case condition against its required cell. Native assistive input domains require additional evaluated paths; performance is not inferred from other modes.

Freeze up to 32 candidate thresholds using development data before calibration. Under independent identically distributed blocks for each fixed cell, evaluate a target false-certification probability ε=0.001 and genuine block coverage c=0.50 with δ=0.05. Allocate δ/2 across attack cells×candidate thresholds and δ/2 across human cells×candidate thresholds. Use exact rational binomial lower-tail tests at ε for attack failures and at 1−c for human failures. Every cell must pass. Choose the lowest eligible threshold. No eligible threshold means no release.

Final evaluation uses new, independently selected blocks and one frozen threshold. `phase_separation` checks declared cross-phase overlap; it cannot prove actual independence. Reusing a final test after tuning is prohibited. Two separately reported 95% stage statements are not automatically a joint 95% statement; the final held-out fixed-threshold statement can stand alone, or an explicit lifetime error allocation is required. No statistical routine grants external approval.

The guarantees concern repeated blocks from the declared attack-generating distribution and budget. Unlimited adaptive imitation, coordinated learning across nominal blocks and distribution shift are not covered. Confidence in a risk bound is not the probability that a particular certificate is true. Detailed proofs and counterexamples appear in THEORY.md.

## 10. Limits, reproducibility and versioning

The reference bounds records (32), observations and transactions per record (500,000 each), live text (200,000 scalars), corpus atoms (1,000,000), retained history IDs (5,000,000), evidence edges (5,000,000), indexed external scalars (1,000,000) and related-analysis edge visits (50,000,000). Canonical serialized input is capped at 100,000,000 characters and model at 20,000,000. Excess returns NOT PROVABLE; it must not select a weaker computation. Collectors must stream-enforce limits before materializing attacker-sized data. These are logical caps, not a claimed constant-time or production memory benchmark.

A native implementation may optimize data structures only while preserving specified order, values and verdicts. No speculative parallel reduction may change integer results. Fixed-point replay/inference/eligibility is deterministic. Floating-point fitting is reproducible only in the recorded environment; hardware/backend variation may yield different exports. The exported model itself is authoritative. Test-vector equality, model snapshot equality and version pinning prevent silent substitution.

New datasets can produce new model releases using the same semantics, with new exact model snapshots and calibration evidence. Feature extraction, segmentation, assistance rules, threshold comparators, telemetry, inference algorithms and claim semantics are interpretation-bearing and versioned. Older assessments must retain the exact earlier computation and scope; new verdicts do not retroactively rewrite their meaning. No evidence of later discoveries is fabricated into a historical record.
