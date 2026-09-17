# HWP-A 0.2.0 — Human-writing verification algorithm

**Status:** executable algorithm specification, 15 September 2026. No empirically validated human-composition detector or approved certification release is supplied. This is an algorithm and evaluation standard, not an application, capture authenticator, identity system, or cryptographic protocol.

The normative words **MUST**, **MUST NOT**, **SHOULD** and **MAY** express conformance requirements. The accompanying implementation defines every feature and numerical operation; `TELEMETRY.md`, `FEATURES.md`, `THEORY.md`, and `DATASET_PROTOCOL.md` complete this specification. A disagreement between these documents and the implementation is a defect, not permission to choose a more favourable verdict.

## 1. The exact problem and claim

A qualifying process is genuine human composition: the person chooses and develops the wording through writing, potentially including mental preparation, revision, navigation, deletion and restructuring. Ideas learned from AI do not disqualify a process. Human transcription of predetermined wording, including wording originally written by a human, is nonqualifying. Synthetic input, replay and process simulation are nonqualifying when presented as a new human composition episode. Copying a previously supported passage can preserve its original provenance; it does not make the copier its composer.

The algorithm produces only **HUMAN-WRITTEN** or **NOT PROVABLE** as certification labels. NOT PROVABLE is neither AI-written nor an allegation of misconduct. Numeric scores and reason codes are diagnostic information, not a third certification category.

The positive claim is conditional: the exact selected text satisfies an independently admitted capture contract and a frozen, evaluated composition-inference release in its stated operating domain. It does not assert zero error against an unrestricted adversary. The observational-equivalence theorem in `THEORY.md` proves why a universal guarantee cannot be obtained merely by inspecting increasingly detailed versions of the same observable evidence.

An implementation MUST NOT silently replace the user's definition with “a person pressed the keys,” “the final prose resembles human prose,” “the author passed a challenge,” “the text was not pasted,” or “a classifier's computation was correct.” Each of those can hold for mechanical transcription.

### 1.1 The decision objective

For an explicitly registered attack regime, maximize genuine-writing admission subject to an upper false-certification bound. False certification means **any nonqualifying scalar is returned inside a HUMAN-WRITTEN range**. There is no minimum attack length exemption. The target release bounds are a 0.1% campaign false-certification rate and a 50% lower bound on complete qualifying-task coverage, with simultaneous confidence at least 95%, under the sampling assumptions specified below.

These are deliberately demanding acceptance requirements, not claimed achieved measurements. An empty admissible region is a valid result. An arbitrary low threshold chosen to make a demonstration look useful is not.

The model family in this version is precisely fixed and trainable. It is not claimed to be statistically optimal among every possible future model. Its defensible properties come from deterministic evidence handling, conservative aggregation, and full-pipeline risk calibration—not an unsupported assertion that a particular neural network or feature measures thought.

## 2. Inputs, outputs, and trust boundaries

The input is a topologically ordered bundle of complete document-version records. Each record begins from empty text, contains observations and actual text transactions, and declares its exact final text. A later version can import an earlier complete version through a recorded copy operation. Missing parent histories, opaque “already human” flags, or an arbitrary convenient start state are not accepted.

The algorithm receives three logically separate inputs:

1. The untrusted evidence bundle and exact claimed text.
2. The externally selected, frozen model artifact and threshold.
3. `TrustedInputs`: capture-admissible document IDs, allowed model domains, and whether this precise release and threshold have been independently approved.

The third input MUST NOT be populated from author-controlled JSON. A field saying `source: device` is an observation classification to be appraised, not its own evidence of authenticity. The algorithm does not implement the mechanism that authenticates a collector, validates a physical input boundary, or grants release approval.

A verifier MUST select the model, threshold, permitted domains and capture assumptions independently of the candidate. It MUST NOT let the author choose among released models after seeing their scores. A release must constrain its applicable language, input path, decoder, capture implementation and experimental conditions. Merely naming a language in the record does not authenticate that domain. An inadmissible decoder or falsely declared domain is an attack on the admission contract.

The output includes a whole-document verdict, a separately scoped contribution verdict, and a complete partition into half-open UTF-8 byte ranges. Every range retains origin type, source-document identities, exclusion status and a reason when not admitted. The detailed record and model diagnostics can remain local. No public timing history is required by this algorithm.

## 3. Canonical observation contract

### 3.1 Time, text and sequence

Times are nonnegative integer microseconds on one monotonic clock per document record, bounded by `2^53−1`. Clock resolution is explicitly declared, between 1 and 10,000 microseconds; timestamps must be integer multiples of that resolution. Observation and transaction indices are contiguous and independently start at zero. Times are nondecreasing, and a mutation cannot cite a future observation.

Direct insertions must occur within 250,000 microseconds of every cited causal commit/action. This fixed bound excludes pooled old inputs and heavily delayed/coalesced mutations from the baseline. A lagging system can therefore lose eligibility rather than fabricate a more precise causal record. An IME cites its commit, not a minutes-old first phonetic keystroke; the commit separately records its physical input basis.

Text is a sequence of Unicode scalars whose UTF-8 encoding is exact. There is no NFC/NFKC normalization, newline conversion, trimming, tab expansion, or renderer-based equivalence. UTF-16 platform positions must be converted before entering the normalized stream. A byte range that splits a scalar is invalid. Grapheme-cluster operations are represented by the actual scalar range they affect, not by pretending one grapheme is one byte or one key.

### 3.2 Input profiles

| Profile | Direct causal observation | Maximum inserted scalars per cause | Minimum distinct production episodes per evidence unit |
|---|---|---:|---:|
| keyboard | press or a valid native repeat | 8 | 16 |
| touch-tap | touch_down | 8 | 16 |
| ime | ime_commit with observed motor basis | 256 | 4 |
| gesture | gesture_end of an observed gesture | 64 | 4 |

Every evidence unit also requires at least 64 distinct candidate origin roots. Repeats of one held key share one production episode for this minimum. Preedit updates, move/copy operations, undo and redo provide no additional production episodes. These are fixed information-adequacy constants, not asserted optimum thresholds. They do not require any particular number of mistakes, pauses, minutes or revisions.

Input episodes have explicit start/update/end lifecycles. End events cannot precede their starts; input tokens cannot be reused as fresh starts. Physical keypresses can overlap. The algorithm does not reject legitimate negative inter-key flight time by assuming keys must be released one at a time.

An IME commit has a nonempty set of earlier motor press/tap observations within the same episode. Those observations cannot also be spent by a second text-producing transaction. An approved normalization adapter treats provisional preedit text as temporary input-method state and records the committed replacement once. This baseline retains preedit lifecycle events and motor observations; it does not score temporary preedit strings as successive independent revisions. Unobserved word prediction, voice dictation, generative completion and unadmitted accessibility modes are not silently treated as physical typing.

Touchscreen support is therefore explicit but conditional on obtaining the stipulated observations. An API exposing only final committed text cannot synthesize the missing motor history. Native platform adapters and hardware capture paths are not implemented in this package.

### 3.3 Interruptions and loss

Focus loss and suspend/resume are explicit, state-checked observations. They split production runs; they do not count as cognitive pauses. Any `gap` observation marks the entire document version's capture inadmissible. Complete text replay after a gap cannot cure the lost process evidence. Known interruptions without event loss can be represented without inventing activity during the interruption.

No camera, microphone, eye tracker, unrelated keystroke log, research-browser inventory or desktop recording is required. Consequently, absence of an observed source does not establish absence of a second screen, memorized wording or a collaborator.

## 4. Replay and fine-grained origin graph

Every inserted scalar occurrence receives a unique ID `document:transaction:insertion_offset`. Every candidate scalar has its own origin root. A copied occurrence receives a fresh occurrence ID but points to the existing roots. An external scalar has no candidate roots. Spelling transformations can depend on multiple prior roots.

Replay maintains the live occurrence sequence, all historical atoms, an undo/redo delta history, and an index of effects touching each root. These distinguish the current document from the chronological process that created it. Deletes remove occurrences from the live sequence but do not erase their historical origins.

### 4.1 Exact operation semantics

**Splice.** Replace scalar interval `[start,end)` with `text`. The supplied `deleted` text must match that interval exactly. An empty-to-empty mutation is invalid. `direct` creates candidate roots only when its causal observations and insertion bounds qualify; synthetic or unknown observations make the resulting text unknown/external. `paste`, `generated` and `unknown` create external origins. Candidate means eligible for behavioural examination, not HUMAN-WRITTEN.

**Copy.** Copy a nonempty interval from the current document's current state or an earlier document version's final state into position `to`. Snapshot the source interval before modifying the destination. Create fresh occurrence IDs, preserve roots and source identities, and add the destination's capture dependency. Repetition cannot manufacture new composition effort.

**Move.** Remove a nonempty interval and reinsert those exact occurrence IDs at `to`, where `to` is interpreted in the state after removal. A move is structural evidence, not fresh composition.

**Undo/redo.** Apply only the top operation of the corresponding history stack and validate its exact expected atom sequence. Restore original IDs and origin relationships. A new mutation clears redo. Neither operation makes external text candidate.

**Navigate.** Record the selected scalar interval/caret position. It can influence the next related edit's navigation feature. It neither changes text nor creates evidence roots.

**Spelling.** Permit exactly one nonrecursive local spelling transformation: old and new tokens each contain 3–32 scalars, neither contains enumerated whitespace, they differ, and Levenshtein distance is at most two. All removed scalars must be candidate atoms with no previous spelling transformation. The action must be an admitted device-origin correction command. The replacement inherits every removed root and its capture requirements; it creates no new production evidence. Chained correction, predictive insertion and correction of external ancestors cannot pass this exception.

The spelling rule is an explicit mechanical-input policy, not a theorem that edit distance preserves semantics. For example, a small spelling change can alter meaning. A release must test this exception. A generic platform replacement event is insufficient to identify it as nongenerative spelling. More permissive rewriting requires a new evaluated policy, not a broad interpretation of this one.

### 4.2 Source reuse and incremental rewriting

Every external insertion contributes its exact string to a local observed-source index. Every exact 32-scalar substring of those strings is indexed. A final substring matching an indexed substring vetoes the matching final occurrences; source roots blocked in an ancestor version remain blocked in descendants. The check is conservative and can reject independently composed common wording. It is not a general plagiarism detector or a guarantee against paraphrasing.

New direct wording can receive new candidate roots even when it replaces external wording. This avoids permanent “contamination by an idea.” The complete replacement episode, surviving external atoms, observed-source matches, and behavioural neighbourhood remain relevant. Replacing external characters one at a time is not automatically human composition. If all textual ancestry is replaced and no source match survives, discrimination depends on the behaviour model and its tested attacks; the specification does not falsely claim that the graph alone resolves hidden transcription.

### 4.3 Replay invariants

All indices, causal links, profiles, time relationships, parent dependencies, ranges and history-stack transitions must be valid. Live IDs must be unique, origin references acyclic and complete, and the reconstructed text must equal `final_text` exactly. The operation rules preserve uniqueness and lineage inductively; the reference also checks final uniqueness. The source graph establishes origin bookkeeping under the trace assumptions, not the truth of an author's mental contribution.

## 5. Pinned evidence neighbourhoods

A claimant cannot choose favourable windows, reuse copied characters as additional evidence, or omit an awkward tail. Segmentation is calculated from the complete source version before the requested certified scope is applied.

### 5.1 Production runs

A new run begins at the first profile, a profile change, a focus/suspend/loss barrier, more than 120 seconds between transactions, a transaction start more than 256 scalars from the previous caret, or a transition into or out of external insertion. These are segmentation rules, not assertions about when cognition starts and ends. Local revisions can remain in the same run. A tiny later insertion after an interruption generally cannot borrow an earlier run's sufficiency.

### 5.2 Four required views

**Birth view:** for each run, order every candidate root by creation, including roots later deleted. Form overlapping windows of width 64/stride 32 and width 256/stride 128.

**Layout view:** traverse the final state of the root's home document. Separate at external material, foreign origins and run discontinuities. Within a contiguous group, keep each distinct root once in final-position order. Form the same two window scales. Thus repeated copies cannot supply the minimum distinct origins.

**Retained view:** use those same contiguous retained-origin groups, but order their roots by original creation transaction and insertion offset before windowing. This prevents rearrangement from hiding the chronological local evidence of retained text.

**Global view:** for each source document and input profile, take all retained home roots once, sorted by birth. Examine them as one complete process unit, including process-shift features across chronological quarters.

For length `n > width`, starts are `0,stride,2*stride,… ≤ n−width` plus `n−width`. Duplicate starts are removed and sorted. If `0<n≤width`, form one unit of length `n`; it still fails adequacy when fewer than 64 roots exist. Empty groups generate no unit. Identical complete layout groups are deduplicated.

A root needs all four views. A root created and then absent from its home version cannot acquire support merely because a later candidate provides a convenient selected fragment. Capturing a supported intermediate state requires making that complete state a parent version rather than presenting an opaque historical label.

### 5.3 Which events a unit may use

For root set R, include source-document effects that created or touched a root in R. Remove copy and navigate operations from the scored event sequence; navigation already attaches to a subsequent mutation. Deletion, replacement, movement and history restoration touching R remain. Do not add a long unrelated warm-up, research interval or another paragraph simply to improve a score.

Process-gap features require adjacent original transaction indices in the same uninterrupted run. Gaps over unrelated intervening activity are censored. This prevents a selected evidence subset from turning omitted edits into favourable “thinking time.”

The global view is an additional veto, not positive credit that rescues failed local windows. Conversely, a failed global view can conservatively prevent admission of otherwise locally plausible passages. This asymmetry is deliberate.

## 6. Deterministic feature calculation

`hwp_a/features.py:extract` is the complete scalar feature map. `FEATURES.md` enumerates its exact feature names. It does not call a language model, semantic service, person-identity recognizer or final-text AI detector.

All outputs are integers in `[-10000,10000]`; Q=10000 denotes one. Fractions use floor division and clipping. Empty denominators yield zero. Missing measurements have explicit presence features. Positive count scales clip at declared caps. Quantiles use nearest-rank order statistics, not interpolation. Pearson-like correlation uses centered integer sums and an integer square root, with fewer than three pairs or zero variance yielding zero.

The feature families include operation proportions, inserted/deleted lengths, contextual production gaps, native motor dwell, navigation and revision ages, repeated touches, local/remote edit distances, repeated cancellation, bounded lexical consequences of revisions, burst size, operation transitions and within-record process shifts.

For process-gap binning, a recorded difference g has interval `[max(0,g−2r),g+2r]` where r is the declared resolution. It contributes only if that whole interval falls in one fixed bin and its upper bound is at most 30 seconds. Otherwise it is censored. Bin edges in milliseconds are 50,150,400,1000,3000,10000,30000. A pause is contextual evidence, never an observed thought.

Preceding-text context has four categories: ordinary scalar, enumerated whitespace, sentence-terminal punctuation `. ! ? 。 ！ ？`, and line separators. The classes are fixed, language-independent engineering categories; they are not a full syntactic parser.

The relational features are deliberately concrete. A replacement's later exact old→new recurrence at a distant location is counted within 64 subsequent related events. Trigram overlap compares a bounded replacement with at most 128 subsequently inserted scalars from eight events. Cancellation detects reintroducing exact recently deleted wording. These capture observable dependencies, not logical understanding of a premise. Their usefulness must survive ablation and adaptive simulation.

The schema contains no health, disability, age, gender, identity, typing-quality or subject-matter classifier. Differences associated with such factors can nevertheless affect the observed features; the evaluation must measure genuine-writing coverage rather than assume fairness.

## 7. Fully specified learning algorithm

Training domains are `input_profile | language | evidence_view`. All four views need their own trained artifacts and supported development data. A missing domain fails closed. A language/profile upgrade is not automatic transfer from another domain.

For each domain, fit four binary heads: composition versus transcription, automation, simulation and mixed origin. Each head receives H positives and the corresponding labelled negatives. An ambiguous U label is never relabelled as a negative to manufacture separability.

The reference learner uses 32 depth-two Newton-gradient trees per head, logistic loss, learning rate 0.125 and L2 leaf denominator 0.001. The initial logit is zero. Each class has total weight 0.5. Within each class, weight clusters equally, documents within a cluster equally, and units within a document equally. This is a training-weight convention, not a claim that overlapping windows are independent.

For every feature, candidate cuts are fixed from up to 16 training unique-value quantiles. Enumerate features in schema order and cuts in ascending order. Each child needs at least two rows. Split gain is

`G_L²/(H_L+λ) + G_R²/(H_R+λ) − G²/(H+λ)`.

Choose a split only if its gain exceeds the current best by more than `1e−12`; otherwise retain the earlier candidate. A leaf step is the weighted Newton ratio clipped to `[-1,1]`, multiplied by `0.125×10000`, and rounded to nearest integer with half ties away from zero. Export leaf integers in `[-1250,1250]`. Fit iterations update their logits from those exported integers. No later floating-point recalculation can change a released tree's inference.

The unit margin is the minimum of the four head sums. Each head sum is in `[-40000,40000]`. These are discriminative margins, **not posterior probabilities, p-values of human authorship, or calibrated likelihood ratios**. The minimum demands evidence against every represented behavioural family; it does not protect against families absent from evaluation.

### 7.1 Local support diagnostic

Human training vectors define per-feature scale `max(500,IQR)`. Select up to 128 distinct prototypes by deterministic farthest-first traversal, starting with the lexicographically first human training unit. Distance is the mean of integer-scaled coordinate absolute differences. Use the fifth-nearest prototype distance, or the farthest available distance when fewer than five prototypes exist.

Development data provide one lexicographically first H unit per independent cluster and domain. At least 99 such clusters are required. For candidate distance d, form `(1 + number of development distances ≥ d)/(1+n)` and require it to be strictly greater than 0.01. This is a frozen support diagnostic, not a certificate that the candidate is human. Because all units and the selected development representatives need not be exchangeable, this version makes no standalone conformal coverage claim for it. Its consequences are measured by complete-pipeline calibration.

Public feature prototypes could reveal aggregate behavioural information. A release must review model privacy; the algorithm does not equate keeping raw logs local with eliminating every possible model privacy leak.

## 8. Scores, binary verdicts and quotations

Let `s(u)` be the four-head minimum for a unit. Set it to `−10^9` when replay, capture, domain, adequacy or support checks fail. Let `U(r)` be every required unit containing root r. Then:

`root_score(r) = min{s(u): u in U(r)}`,

provided all four views exist; otherwise use the failure sentinel. A final scalar's score is the minimum of all roots it depends on, unless external/unknown origin, source reuse or any missing capture dependency forces failure. Exact root and scalar mappings are independent of the requested scope.

For threshold τ, a scalar passes only if its score is at least τ **and** the exact release and threshold are externally approved. Whole-document HUMAN-WRITTEN requires every scalar to pass, nonempty non-whitespace text, and no exclusions. The contribution verdict requires all nonexcluded scalars to pass and at least one nonexcluded non-whitespace scalar. Every selected quotation exclusion must be an ordered, nonoverlapping, nonempty scalar-aligned UTF-8 range with an explicit source identifier.

Excluding a quote does not change its origin or its own range verdict. The unqualified whole-document result remains NOT PROVABLE when exclusions exist. A supported copied passage can have inherited provenance; the output identifies its source document instead of pretending its current holder composed it. This algorithm does not identify a person or establish who controls a particular name.

The implementation coalesces adjacent range records only when their verdict, reason, exclusion, origin type and origin-document list all match. The complete byte partition can therefore represent narrow unsupported edits without averaging them into a positive paragraph. Statistical inference still uses larger fixed neighbourhoods: scalar precision of bookkeeping is not scalar certainty about cognition.

### 8.1 Complete acceptance procedure

```
validate and replay all source versions
recompute all origin graphs and observed-source matches
construct all four fixed evidence views in every source version
for each unit:
    enforce independent capture/domain admission and minimum evidence
    recompute exact features
    evaluate every frozen adversarial head and support diagnostic
propagate minimum scores through required root and derivation dependencies
veto external, unknown, reused-source and inadmissible-capture occurrences
apply the frozen calibrated threshold
partition the exact final UTF-8 text; apply scope exclusions without rescoring
return HUMAN-WRITTEN only when every required conjunct is true
otherwise return NOT PROVABLE
```

There is no secret fallback classifier, majority vote, averaged document confidence or emergency permissive mode.

## 9. Calibration and release acceptance

Training, development, calibration, final test and ambiguity partitions are separate. IDs linked by writer, source, prompt, cluster or attack campaign must not cross partitions. Dependencies across observations inside one campaign are permitted, but that campaign contributes **one** Bernoulli risk trial.

From genuine development document scores, freeze at most 32 increasing candidate thresholds before seeing calibration labels. The default grid takes up to 30 fixed rank positions, the smallest observed supported score, and `10^9`, a true reject-all threshold. No candidate is added after inspecting calibration failures.

The mandatory matrix contains eight attack families—human transcription, scripted input, replay, staged revision, adaptive simulation, mixed origin, lineage laundering and capture fabrication—at budgets B=1 and B=100 for every admitted input/language combination. The endpoint is any false scalar admitted anywhere in the campaign. Additional materially different capture paths or adversary resources require additional prespecified cells. `release.py` constructs this matrix; lower-level calibration functions permit extra experimental matrices without granting release approval.

Within an attack campaign, aggregate the maximum false-origin scalar score over every attempted history and every passage. Within a human participant cluster, use the minimum whole-document score across all prespecified qualifying tasks. This makes genuine coverage the fraction of participants whose complete task set succeeds, not a flattering average over easy windows.

For J attack cells, K human coverage cells and T threshold candidates, allocate

`α_attack = 0.025/(J×T)` and `α_human = 0.025/(K×T)`.

Use one-sided exact binomial bounds for each cell and candidate. An eligible threshold has false-certification upper bound ≤0.001 in every attack cell and coverage lower bound ≥0.50 in every human cell. A missing required cell blocks eligibility. Choose the smallest eligible threshold. If none qualifies, do not release a certifying model.

For zero observed failures in n independent fixed-distribution trials, the upper bound is `1−α^(1/n)`. For nonzero failures the reported bound uses the specified beta quantile. Eligibility itself is decided by exact rational binomial-tail tests, so floating-point rounding of a quantile cannot grant a release. Decimal probabilities are interpreted as exact decimal rationals; see `THEORY.md`. `THEORY.md` derives why the simultaneous bounds remain valid despite selecting among the fixed candidates. The guarantee is distributional and conditional; it is not a worst-case guarantee over every unobserved adversary.

A threshold passing calibration is still **not approved**. Freeze it and independently evaluate the entire pipeline on final test campaigns, with a new simultaneous confidence calculation for the single frozen threshold. A failed final test forbids release and cannot become development data for a re-run using the same supposedly untouched holdout.

## 10. Attacks, model improvement and excluded mechanisms

The included attacks execute staged transcription, causal-order-preserving retiming and bounded adaptive timing search. They retain every query and treat the search as one campaign. They are mechanics tests, not evidence against an exhaustive adversary.

Mandatory independent attack work also includes hardware-mediated input, human-assisted real-time transcription, matched process statistics, white-box history optimization, microscopic mixed insertions, source laundering, decoder mislabelling, and compromised observations. An admissible-source assertion cannot be used to remove a capture-fabrication attack from the matrix unless that assertion has actually been established by the external capture contract.

An open, local detector cannot assume it limits how many histories an adversary tries. A B=100 claim describes a tested regime; it is not a statement that actual users cannot do a million offline optimizations. Disclose query access, local computation, source access, hardware control and total attempts. Uniform unrestricted claims remain unsupported even when every registered statistical test passes.

Active writing challenges are excluded from this version. They could test responsiveness to a new task but would not establish that earlier text was composed rather than transcribed; a human can relay model answers. Cameras, biometrics and identity matching likewise do not silently supply the missing distinction. A future extra modality requires a new measurable observation contract and evaluation, not an assertion of stronger intuition.

To improve the detector, add controlled real data, identify which attacks and genuine modes change the risk/coverage frontier, and compare replacements under the same complete-pipeline acceptance contract. New feature sets, semantic encoders, segmentation, correction exceptions, model families or numeric constants require a new algorithm version and fresh calibration. Model weights can change within this algorithm version only with a new frozen release and fresh approval.

## 11. Implementation and resource conformance

The reference implementation uses Python 3.13.5; replay, feature extraction and inference use the standard library. Training uses NumPy 2.3.5 and binomial quantiles use SciPy 1.17.0. Exported integer trees define inference; bit-identical refitting across arbitrary dependency versions is not promised.

The baseline limits are 32 documents, 200,000 scalars per text object, 500,000 observations and transactions per record, 1,000,000 total atoms, 5,000,000 stored history IDs, and 1,024 causes/basis observations per action. The CLI caps input JSON at 100 MB. Exceeding a limit fails closed. An optimized rope, persistent sequence or compressed atom graph can replace the reference structures only if it gives identical origin mappings, features and verdicts on all conformance tests.

The tests and synthetic examples exercise concrete invariants and the full computational path. They are not a security audit, a fitted model on human writing, or measured population accuracy. No live capture path, human participant study or approved HUMAN-WRITTEN release is delivered in this version. Those absences are properties of the available evidence, not unspecified implementation decisions.
