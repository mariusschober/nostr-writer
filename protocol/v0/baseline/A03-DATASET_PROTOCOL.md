# Dataset, attack and release protocol — HWP-A 0.3

## 1. Operational labels and capture evidence

A case is exactly `id,cluster,split,links,bundle,labels,condition`. Each record's transactions are covered by ordered nonoverlapping `[start_tx,end_tx)` annotations. Labels are H, U, transcription, automation, simulation or mixed. H denotes a controlled qualifying composition condition, not an AI-content detector's opinion. U preserves unresolved mental rehearsal, close paraphrase, source memorization or other ambiguous composition/transcription cases. No author-supplied annotation controls verification.

Consent and controlled task conditions establish operational labels; they cannot make private cognition directly observable. Record instructions, source access, task order, any violations and the participant's account. An independent annotator should adjudicate conflicts without seeing model verdicts. Preserve disagreement in U. Do not turn every AI-informed task negative or train on typing speed as the task label.

The `condition` used by release evaluation is the exact preregistered attack family or genuine task condition. Control participants, prompts, source text and device/input paths across genuine writing and transcription. Include retyping one's own previous text as well as unfamiliar human and AI source text. Counterbalance other task assignments; a person's own-composition-then-transcription pair necessarily has order/memory effects and needs separate controls.

All labels are complete before eligible outcomes are counted. U is omitted from supervised fitting, remains available in an ambiguity partition, enters the adverse scalar mask for release risk, and cannot supply a genuine coverage success. Descriptive metrics report it separately. Missing labels abort eligibility for a valid attempt, rather than being scored as a failed attack.

## 2. Splits and fitting

Partitions are train, development, calibration, test and ambiguity. `links` may contain writer, source, prompt, campaign and actor ID arrays. Dependency-connected cases must stay in one partition, including external-only or empty cases that produce no features. Raw-case dependency validation happens before extraction. Unit labels inherit contributing root-creation annotations; heterogeneous negative classes form mixed, and any ambiguous contributor produces U.

Training uses the fixed four heads and all179 features. Genuine examples include all qualifying conditions rather than only heavy revision. Negative examples must include human-authored source transcription, not only AI-generated prose. Support references are separate development-cluster observations. Choose threshold candidates using development outcomes only; then freeze the complete replay, feature, model, support, scope, input-path and risk computation.

Fit-source reproducibility is useful but not equivalent to inference identity. Store sorted row IDs and partitions, dependency mapping, full exported integer model, library/runtime versions, conditions, operating domains and model-selection decisions. There is no retrospective fitting against final-evaluation failures while calling the same evaluation held out.

## 3. Mandatory attack cells

For every proposed `(profile,path,language,claim)` domain, preregister each of the following at B=1 and B=100 complete attempts per block:

| Family | Required variations and access |
|---|---|
| human_transcription | Skilled/slow/fast human copying; familiar or memorized source; permitted AI-informed writing controls; deliberate pauses, corrections and meaningful rewrites |
| scripted_input | Constant/random/learned timing; admitted-channel injections; predictive input below bulk limits; hardware-mediated input where inside the claimed threat |
| replay | Whole and partial histories; same text and substitutions; source/record ID reuse; genuinely admitted record freshness checks |
| staged_revision | Cosmetic errors/cancellation, moved paragraphs, revised premises and conclusions, externally supplied alternative drafts |
| adaptive_simulation | White-box weights/features/thresholds; conditional trace optimization; full end-to-end input-path tests; held-out generator families |
| mixed_origin | Genuine warm-up plus copied or scripted words/sentences; tiny/fragmented substitutions; boundary and end-aligned inserts; attack inside mostly genuine material |
| lineage_laundering | Copy/move/history cycles, repeated replacement, spellcheck/numerical changes, quotations, cross-record import and source-exposure timing |
| capture_fabrication | Claimed device flags, fabricated native deliveries, sequence/timestamp alteration, mutation/cause substitution and admitted-decoder compromise |

Attack access must be explicit: public model, local unlimited scoring during adversary development, per-campaign attempt budget, feedback, device/OS control, external controllers, real-time human assistance and reset rules. If a claimed capture profile accepts arbitrary fabricated records, equivalence counterexamples disqualify a nonvacuous universal claim. Do not hide these cases by treating a test-controller capture assumption as an actual end-to-end success/failure.

The implemented `adaptive_retiming` attack is labelled **conditional-trace-simulation**. It independently updates the synthetic experiment's record selection for each proposed trace so snapshot equality does not artificially defeat all attacks. It does not test capture authenticity. These simulated controls are diagnostics, not a surrogate for human transcription or hardware attacks.

## 4. Genuine coverage cells

Each proposed input/path/language/claim domain needs separate cells for unaided, AI-informed, fluent-expert, revision-heavy, interrupted and second-language composition. A participant block may contain multiple preregistered tasks; its coverage succeeds only when all pass. State unsupported populations and input paths. Additional accessibility/decoding modes are separate domains, not missing values filled from keyboard data. The default 50% minimum is an explicit initial release requirement per required condition, not an observed or ideal user experience.

Report all-document coverage, scalar/passage coverage, support rejection, insufficient-evidence rejection, capture rejection and all uncertain cases. Never remove fluent but under-observed authors from the denominator to inflate accuracy. Origin precision and behavioural inference resolution remain separate metrics.

## 5. Complete ledger and independent blocks

A ledger contains exact version, phase, claim_kind, cells and slots. Each cell declares attack/human kind, attempts_per_block and a nonempty sampling_contract. Every slot declares unique id, cell, block, zero-based attempt and known dependency links. Each completed result has id, status (`scored` or `structural-rejection`), integer score and identical claim_kind. Pending, timeout or missing data is incomplete and blocks eligibility until resolved under the preregistered protocol.

Every block must cover exactly the expected attempt indices and every slot exactly one result. Shared writer/adversary-state links within a cell belong to one block. A renaming operation cannot create independent samples. Actual independence and adherence to the frozen sampling contract require experimental evidence; metadata cannot prove them.

`run_release` computes each trial from raw cases and matching independently selected lab contexts, checks required task conditions, applies complete-ledger checks, verifies the mandatory cell matrix and calculates eligibility. `evaluate_release` is the equivalent lower-level numeric-results interface, suitable only for already independently checked study outputs. A freely edited JSON report does not approve a detector.

For attacks, aggregate max score over every non-H final scalar, then max over attempts. For genuine blocks, take the min full-document score across all required H tasks. Nonempty whitespace-only output cannot supply a document success. Any falsely admitted scalar is a failure regardless of how many true characters surround it or whether another part of the document failed.

## 6. Calibration, final test and improvement

The normative targets are ε=0.001, δ=0.05, coverage≥0.50; candidates≤32. Exact rational binomial tests and simultaneous finite-candidate correction are implemented. Report counts, independent-block denominators, threshold, each cell's bound, coverage bound, supported domains and the exact false-scalar endpoint. Numeric accuracy on overlapping windows is not a release criterion.

After calibration selects a threshold, freeze it. Final evaluation uses one threshold and independent blocks; `phase_separation` rejects declared reused IDs/links. Joint confidence across stages requires an explicit combined allocation; a separate final-test claim may stand alone. A new attack changes the empirical knowledge and may revoke present-day acceptance, but it does not rewrite what an old release computed. New features, observation contracts or claim semantics have new versions; new data-trained weights with fixed semantics have new exact model snapshots and freshly evaluated releases.

Report attack budget curves beyond B=100 as additional evidence when available. Do not extrapolate to unlimited adaptive attempts. A human-assisted simulator may overlap the genuine observable distribution; publish that finding rather than compensating with more opaque scoring. No reference test result in this package estimates the achievable risk/coverage frontier.
