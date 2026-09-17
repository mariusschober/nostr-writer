# Data, evaluation and iterative improvement contract

This protocol tells an implementation team exactly how to instantiate, test, attack and improve HWP-A. It does not represent human experiments already performed. All shipped histories are synthetic fixtures.

## 1. Operational labels

Use six unit labels: **H**, **transcription**, **automation**, **simulation**, **mixed**, and **U**. H is independently composed wording under the qualifying task conditions. It includes genuine composition after permitted AI research or after understanding an AI-generated argument. It is not “no AI involvement.” Transcription includes human retyping of human or machine wording. Automation means scripted production without the qualifying human composition. Simulation includes staged alternative drafts, fabricated pauses, planned corrections and other simulated composing behaviour. Mixed includes more than one negative process family; a unit mixing H with one negative family retains that negative family label.

U means ground truth is genuinely unresolved. Examples include uncertain memory of prior wording, poorly observed task compliance and borderline rewriting whose relation to a prepared text cannot be established. U never becomes a convenient negative label. U-origin admission is a separate ambiguity result. It cannot be used to lower an estimated false-certification rate by silently deleting difficult negative trials.

The labels refer to creation transactions, not whether final wording sounds human. Observe the task condition, sources provided, permitted assistance, actual process and a post-task account. Preserve disagreement and protocol deviations. A task instruction and a participant's statement do not make hidden cognition directly observable; the standard's limitations remain explicit.

## 2. Raw annotated case format

A dataset is a JSON array of objects with exactly:

```
{
  "id":"case-001",
  "cluster":"independent-participant-or-campaign-001",
  "split":"train",
  "links":{
    "writer":["writer-001"],
    "source":["source-family-001"],
    "prompt":["prompt-family-001"],
    "campaign":["campaign-001"]
  },
  "condition":"genuine independent composition after AI-informed research",
  "bundle": {"version":"hwp-a/0.2", "documents":[], "target":"d"},
  "labels":[
    {"document":"d","start_tx":0,"end_tx":120,"label":"H"}
  ]
}
```

The illustrative empty documents array above must be replaced by actual valid records. Each document's labels form an ordered, complete, nonoverlapping partition of **all** transaction indices. Every creation, including later-deleted material, has an operational label. Include source-version labels for imported roots. `dataset.extract_case` reconstructs all origins and features from raw traces; callers must not hand-label conveniently selected accepted windows.

For an evidence unit, inspect the labels of its roots' creation transactions and every retained spelling derivation that depends on those roots. A negative transformation must not disappear behind positive parent labels. All H gives H. Any U gives U. One negative family plus optional H gives that family. Multiple negative families give mixed. U units are quarantined from supervised training and are retained in the dedicated ambiguity partition. A one-character transcription insertion is represented by its one creating transaction and remains a false-origin scalar even inside a long genuine document.

Free-text condition strings and dependency identifiers are metadata only. They are not model features. A corpus MUST record source-language, input path, decoder version, clock quality and capture-admission conditions in its study manifest. The algorithm's allowed-domain selection must match that manifest rather than trust a mutable author declaration.

## 3. Independent partitions

Use five partitions: training, development, calibration, final test and ambiguity. Plan approximately 60/15/15/10 proportions among nonambiguous cases only as an initial collection allocation; the required confidence counts, not these percentages, determine sufficiency. Small corpora cannot evade the evidence burden by achieving attractive percentages.

Before assignment, connect records sharing a writer, source-text family, prompt family or campaign. Assign complete connected components, never individual windows, to a partition. Prefer to design distinct participant/source/prompt cohorts in advance; ubiquitous shared prompts can otherwise create one giant inseparable component. The code rejects shared declared identifiers across partitions. It cannot discover a deliberately omitted dependency; auditing the study manifest remains necessary.

Use paired composition/transcription tasks within participant cohorts to control typing skill, familiarity and device behaviour. Keep both sides of a pair in the same partition. Counterbalance task order and use distinct source/prompt families between partitions. Retyping one's own prior essay has memory/order effects; include unfamiliar-source transcription and counterbalanced human-written and model-written sources rather than treating one pairing as definitive.

Training fits weights, scales, prototype selection and trees. Development sets the support reference and finite threshold grid. Calibration sees the complete frozen pipeline and all fixed candidates. Final test evaluates the one frozen selected threshold. No transform, event filter, exception, feature or domain rule may be retuned using final-test outcomes while retaining that same test as independent evidence.

## 4. Required genuine conditions

The genuine cohort must include fluent expert writing with few revisions, exploratory revision-heavy composition, slow and fast writers, second-language writing within admitted domains, ordinary interruptions, permitted AI-informed composition, source quotations, restructuring, parent-version imports, and the admitted input modes. A correction-free fluent writer is not inherently less human than a revision-heavy writer.

Keep unsupported capture, low-resolution clocks, short passages and assistance-mode exclusions in coverage reporting. Do not evaluate only easy sessions that survived preprocessing. For strict release coverage, each prespecified participant cluster succeeds only when every required qualifying task in that cluster receives the appropriate complete claim. The default `release.py` coverage cell uses complete unquoted qualifying documents; quotation/scoped-claim coverage is an additional prespecified cell when that use case is advertised.

Separate device/input conditions and languages. An aggregate desktop result does not authorize a touchscreen or IME model. Do not infer health, disability or identity from motor patterns; assess coverage for consenting relevant cohorts without making those attributes authenticity evidence.

The task conditions may include participants who naturally work with assistive tools. A baseline exclusion is an unsupported mode, not a statement that their writing is nonhuman. Report this denominator explicitly.

## 5. Mandatory attack matrix

For each admitted input/language domain, collect all eight families at budgets **1 and 100 complete attempts per campaign**. The endpoint is admission of any falsely attributed scalar, not just an entirely false document. Additional campaign computation, wall-clock effort, hardware access, source access and model-query access must be fixed and disclosed; B does not capture all white-box offline search costs.

| Family | Required attack variants |
|---|---|
| human_transcription | Human and AI source texts; skilled, slow, familiar and unfamiliar-source retyping; deliberate pausing; corrections; second-screen and human-assisted relaying |
| scripted_input | Constant/jittered timing; observed synthetic events; event injection through each declared path; keyboard-repeat abuse; batched and delayed input |
| replay | Identical full traces, partial replays, changed final text, replayed text under fresh input, genuine parent imports distinguished from new composition claims |
| staged_revision | Planned typos, cancelled edits, alternative drafts, paragraph moves, repeated delete/retype, meaningful-looking later corrections |
| adaptive_simulation | Released features/weights/thresholds available; all-query timing optimization; valid-history structural search; complete-state feedback; human/model-assisted task simulation |
| mixed_origin | Genuine prefix/suffix with 1,4,16,64 and 256-scalar nonqualifying insertions; multiple fragments; boundaries, punctuation and later small edits; genuine warm-up/deleted padding |
| lineage_laundering | Paste/move/copy/undo/redo; character-by-character replacement; repeated parent imports; inherited-root duplication; spelling chains; transformed quotations |
| capture_fabrication | Invented times/causes, dropped events, future/reused inputs, profile/decoder mislabelling, source-origin relabelling and compromised collector claims, subject to the actual admitted boundary |

Hardware actuators and external controllers belong in the appropriate scripted/simulated/capture cells when a claim includes that threat. A person typing every character is not excluded from the negative set merely because motor origin is physically genuine. A cooperating person who actually composes original wording is different: this algorithm proves neither their identity nor the ownership of a name.

The shipped `attacks.py` implements only staged-transcription construction, causal-order-preserving retiming and bounded adaptive timing search. These are testable baseline attack mechanisms, not substitutes for the full matrix. An incomplete attack family cannot be declared complete because the easy baseline was rejected.

## 6. Campaign accounting and accuracy

For every attempt, calculate the exact scalar score vector using the frozen full pipeline. Map each final scalar to its source-creation label. For an attack campaign take the maximum score among all known false-origin scalars across all attempts. At threshold τ, that campaign is a false certification exactly when this maximum is at least τ. Invalid attempts contribute no successful false certification, but remain in the campaign log and budget.

Never count multiple windows, multiple queries or repeated attempts from the same campaign as independent risk trials. Never retain only the successful best trace while reporting failed trials from another distribution as its denominator. The same rule applies to white-box search: disclose precomputation and all candidate selection, not just network requests.

For genuine participant coverage, aggregate the minimum relevant complete-document score across the prespecified task set. A failed capture or insufficient-evidence genuine task is a non-admission, not an excluded observation. Confidence bounds use independent participant clusters, not characters.

Report at least: counts and denominators per required cell; any-false-scalar campaign rate and simultaneous upper bound; complete qualifying-task coverage and lower bound; whole-document false-admission rate; admitted qualifying/false/U scalar totals; unsupported/malformed/capture-failure counts; ambiguity admission; and coverage by input/language/task condition. Include false-origin span localization with exact UTF-8 offsets. A one-character false-positive range is a failure, even if its overlap with a larger labelled attack span looks small.

`metrics.evaluate_cases` supplies descriptive candidate confusion/coverage counts and retains known task-condition denominators for invalid attempts. Unlabelled invalid attempts remain explicitly unresolved. For release evidence, use `dataset.risk_record` and the complete preregistered denominator ledger: malformed genuine tasks must remain coverage failures. Benchmark precision depends on the benchmark mixture and must not be displayed as the probability that an individual certificate is truthful.

## 7. Calibration and final test

Run the fixed `release.evaluation_cells` matrix. Missing family data blocks eligibility. Freeze at most 32 threshold candidates from development scores. Apply exact one-sided binomial tests at 0.1% attack-campaign risk and 50% qualifying-cluster coverage with the simultaneous 95% allocation described in `THEORY.md`. Passing arithmetic returns eligibility, not approval.

An independent final-test cohort must repeat every advertised cell at the chosen threshold, with the same targets and a fresh 95% simultaneous allocation for a single threshold. A failure blocks release. Revisions create a new candidate release and require a fresh untouched final cohort. Comparing many releases on one repeatedly inspected holdout needs a separately justified sequential error budget or a new holdout; the default does not provide optional-stopping immunity.

Cells with zero observed errors still need enough independent campaigns. The `zero_failure_n` function computes the requirement at the actual multiple-testing allocation. Thousands of windows from a few writers cannot provide thousands of independent people. A claim about rare false certification should not be released simply because the study is too small to observe one.

## 8. Falsification and improvement experiments

Run controlled ablations with the same split and attack accounting: timing only; transactions and lineage only; relational features without motor timing; the full fixed feature map; and more expressive challenger models. Preserve the actual threshold selection and full-document/passage acceptance pipeline in every comparison.

Build matched-statistics attacks that preserve pause and edit-count distributions while changing cross-event dependencies, then stronger attacks that preserve those dependencies too. If an advantage disappears when invalid traces are removed, it was a replay-validation advantage rather than behavioural separability. If the model mainly recognizes writers, genres or input tools, participant/source-disjoint testing should reveal it.

Prioritize improvements by changes in the worst admitted risk/coverage cell, not overall accuracy on an easy mixture. A genuinely better model admits more qualifying writers at the same supported campaign risk, or lowers that risk at comparable coverage. New features or models must earn their complexity on untouched data. A public detector must be attacked after its full weights and decision rules are exposed.

## 9. Dataset governance and reproducibility

Store consented raw events, deleted wording and source histories in appropriately controlled research storage. Do not collect unrelated activity. Release public fixtures and derived benchmarks only with the necessary permissions and privacy review. Model prototypes and detailed event timing can have privacy implications even without a person's name.

An experimental release archive must include: protocol and collection versions; exact code/model/threshold; operating domains; capture assumptions; raw-data access or governed audit route; dependency/split ledger; root labels and disputes; complete campaign attempts; candidate-grid provenance; calibration and untouched test outputs; attack generator versions and budgets; and reported limitations. This is a reproducibility requirement, not a request to add a cryptographic system in this assignment.
