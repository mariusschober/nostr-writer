# HWP-v0 behavioural computation contract

**Algorithm `hwp-a/v0`; model format `hwp-a-model/v0`.** This document is normative together with the exact incorporated definitions below. It specifies computation, not a claim of achieved accuracy.

## Incorporated definitions and explicit amendments

Use the complete replay, atom ancestry, source-veto, segmentation, adequacy, 179-feature extraction, tree inference/support, scope aggregation and statistical evaluation definitions in `baseline/A03-SPECIFICATION.md`, `baseline/A03-FEATURES.md`, `baseline/A03-TELEMETRY.md`, `baseline/A03-THEORY.md` and `baseline/A03-DATASET_PROTOCOL.md`. Those files are retained byte-for-byte. Their package/publication status, old algorithm/version identifiers, unspecified relying-party integration and standalone approval routes do not apply to v0. The authoritative feature order is `docs/FEATURE_NAMES.json`. The full precise numerical formulas are also executable in the frozen `hwp0/algorithm` source.

The following amendments are mandatory and exhaustive relative to that computation:

1. Use the new identifiers above and `hwp-a-ledger/0.3` for the unchanged evaluation-ledger syntax. Older records cannot be relabelled without proving that every required observation actually exists; the v0 transport rejects legacy markers.
2. **Every transaction**, including navigation, history restoration, copy and move, requires focused, unsuspended observation. Every bound raw cause must be no older than250000 microseconds at the transaction, and must not cross a focus/suspend/gap interruption before its native delivery. A03 applied those additional checks only to direct typing. This resolves stale-command and out-of-observation control histories.
3. Capture/release admission is supplied only by the authenticated protocol bridge after exact source/profile/release/policy checks. Author-supplied `TrustedInputs`, snapshot strings, model IDs and approved flags are not accepted by a public v0 verifier.
4. Public scopes use the exact common whitespace set, maximal partition and provenance conditions of the consolidated specification. U+2028/U+2029 are whitespace. A proof additionally requires explicit signed target final-state binding and exact provenance through predeclared parent captures/proofs.
5. The portable program manifest pins these amended source semantics. Conformance tests can grant conditional local assumptions to a synthetic model, but the public projection is TEST-ONLY/NOT PROVABLE. A production positive needs a separately admitted empirical release.

6. Experimental raw-ledger execution prevalidates the study model and its size before scoring any attempt. A missing/malformed model is a study configuration error, not a rejected attack. Descriptive metrics accept and report an explicit claim_kind, rather than silently using fresh-composition when studying wording-origin. These changes do not alter supported-model inference.

Everything else in the incorporated algorithm remains unchanged; there are no silent weights, minimum-edit requirements, semantic encoders, final-prose detectors or additional secret features. No changes to the algorithm can be smuggled in by using a different proof mode.

## Deterministic reconstruction

Initial text is empty. Every inserted scalar has `record:transaction:offset` identity. Direct, causally bound device-input insertion creates a new candidate root—not an already accepted human label. Paste, generated, unknown and assisted-spelling replacements remain unsupported. Deletion retains ancestry; move preserves IDs; copy creates a new occurrence referencing original roots; undo/redo restore original checked history. Small spelling edits cannot grant origin inheritance. This prevents known source ancestry from being erased by history manipulation, but does not prove a writer's mental source was novel.

The only supported raw profiles are keyboard, touch-tap, IME and gesture. IME motor bases and decoder deliveries must be actual observations. A platform exposing only a committed string cannot fabricate key/touch events or classify generated completions as motor decoding. New accessibility or dictation profiles require separate observable definitions and empirical admission. Unsupported does not mean nonhuman.

Native offsets are converted to Unicode scalar indices before normalized replay; final scope uses UTF-8 byte intervals. No Unicode normalization or equivalence class is permitted. Runs split on interrupted observation, more than120seconds, input-profile change, position displacement greater than256scalars, and transitions into/out of external sources. Source replay uses only earlier same-record exact32-scalar exposure shingles and propagates through real ancestry, not unrelated future bundle text.

## Fixed evidence neighbourhoods and inference

Views are birth order (including subsequently deleted roots), final layout of retained roots, retained roots in birth order, and one global retained-root set per profile. Local widths/strides are64/32 and256/128 with end-aligned tails. A short nonempty group produces its whole range but still faces adequacy. Segment selection is fixed before scoring and independent of requested exclusions.

Each required unit needs at least64 distinct roots and at least16 connected production-delivery components for keyboard/tap or4 for IME/gesture. One held key, a bulk delivery, many modifiers or repeated copying cannot manufacture distinct components. These are engineered evidence floors, not claims that64characters or16actions identify thought. Short or interrupted genuine contributions can remain NOT PROVABLE.

All179 features are integers within−10000..10000. Ratios floor before clipping; quantiles use a specified nearest rank, not interpolation; missing measurements have explicit presence flags. Features condition timings on actual event order and syntax, represent revision distance/age and bounded lexical relationships, and do not interpret pausing as thinking. The normative feature table and implementation contain every cap, histogram edge and missing-value rule.

Each domain is `profile|path|language|view`. Four discriminative heads—transcription, automation, simulation and mixed—each contain32 depth-two trees. A left branch is selected for `feature <= threshold`; each integer leaf lies in−1250..1250. The behavioural margin is the minimum of the four tree-sum margins. It is not a posterior probability or a justified likelihood ratio. The domain-specific robust-L1 support test, prototype selection, scale floors and rank comparison are as specified in the incorporated algorithm. Missing domains or inadequate/support-rejected units are bottom-valued.

A root's score is the minimum across all its mandatory units; a final scalar's score is the minimum of its roots, after ancestry, source and admission gates. Fresh-composition additionally requires that occurrence itself to be its sole target root. Threshold comparison is `score >= threshold`, with bottom=−1000000000 and threshold strictly greater than bottom. Every required scalar must pass: a good introduction cannot numerically compensate for a copied sentence. A source record is assessed in its own original neighbourhood, not a more favourable target-document window.

Replay, exported-model inference, commitment input preparation and exact statistical eligibility are deterministic. Training uses the specified floating-point fitting routine; arbitrary future refits are not required to yield the same model across hardware/runtime versions. The exported exact integer model is the interpretation-bearing artifact. Do not refit during old-proof verification.

## Empirical release contract

The fixed risk endpoint is **any falsely admitted scalar anywhere in an attack campaign**, including a short inserted or transcribed fragment in otherwise genuine text. The campaign aggregates the maximum across all registered attempts; a genuine-writing block aggregates the minimum complete-document result across all required tasks. Windows from one writer are not independent subjects. Scope selection is included in the endpoint; selecting a favourable subset cannot evade a false-scalar failure.

For every proposed path/language/claim domain, required attack families are human_transcription, scripted_input, replay, staged_revision, adaptive_simulation, mixed_origin, lineage_laundering and capture_fabrication, each at B=1 andB=100 complete attempts. Genuine cells separately cover unaided, AI-informed, fluent-expert, revision-heavy, interrupted and second-language writing. Trace-level simulation and end-to-end native-capture attacks must be reported separately. A lab fixture's assumed admission is not a test of actual source authenticity.

A complete preregistered ledger accounts for slots, attempts, blocks, dependency links, conditions and outcomes. Scientific measurements use conditional candidate decisions from the actual algorithm and admitted experimental boundary, not the public TEST-ONLY projection: counting every conformance object as a rejected attack would manufacture perfect accuracy by construction. For full binding tests, conditional TEST-ONLY success is an admission for the experiment, while never being a real issued HWP. Pending/missing/crashed tasks cannot be counted as rejected attacks. Ambiguous annotations count adversely for risk eligibility and cannot create genuine-coverage successes. Splits preserve writer/source/prompt/campaign dependencies before feature extraction. Known cross-phase reuse is rejected; actual independence remains a study-design obligation, not a fact proven by IDs.

At most32 threshold candidates are fixed using development data before calibration. The unchanged exact rational binomial tests control target risk ε=.001, coverage c=.50 and δ=.05 across every required cell and all candidate thresholds, allocating δ/2 to risk andδ/2 to coverage families. The lowest eligible threshold is selected only after every cell passes. No eligible threshold means no release. An independent fixed-threshold final evaluation is required. Two separate95% stage statements are not automatically a joint95% claim; repeat testing requires explicit lifetime accounting or new independent evidence.

The dossier's reports must allow reviewers to reproduce those calculations and inspect sampling, ambiguity, native-capture tests and complete accounting. Report hashes and approval signatures do not establish the ground truth or independence assumptions. The external curator must approve the exact model, threshold, claim, input paths, report set and threat interpretation. The current distribution contains no such production approval.

## Falsifiable limitations retained

Implementation tests are not human observations; use the executed results file for their exact scope and counts. No human participant sessions or trained real-world detector are supplied. The 179-feature map admits demonstrated exact collisions under changed meaningful wording. More complex trees cannot recover discarded information. Those collision families and adaptive staged revision remain mandatory challenges to any empirical release.

For genuine and attack observation distributions P and Q and acceptance region A,

`Q(A) >= P(A) − TV(P,Q)`.

If a permitted adversary can reproduce exactly an accepted observation, no observer-only nonvacuous rule can distinguish its different hidden cause. This does not establish that every evaluated sensor can be cloned; it fixes what a release cannot claim under a specified input power. Model/risk improvement is a scientific task with new data and versions, not stronger cryptographic wording.

## Prospective study and empirical-release staging

The final operating point is fixed in a conformance candidate before its held-out protocol trials. Trial endpoints count candidate admissions even though public conformance outputs are deliberately NOT PROVABLE; otherwise the production guard would create a meaningless zero-error study. After the trials, the empirical dossier references that earlier candidate and the actual reports. The empirical and candidate releases must have identical operational artifacts, claim, capture profiles and protocol. The normative candidate-equality rules are in SPECIFICATION.md. Production requires a new capture start naming the subsequently approved empirical release; past trial captures cannot be upgraded by changing a label. This separates study chronology from archival package hashes without weakening precommitment.
