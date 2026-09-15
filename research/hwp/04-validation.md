# 4. Adversarial validation and certification gates

Research draft · This is a falsification contract, not a claim that its experiments have been performed. Executed synthetic checks are reported separately in [results](07-results.md).

## 4.1 The first empirical question

Can authentic composition be selectively admitted while human transcription of comparable text is rejected, when writer, device, subject familiarity, input mode, and timing/edit statistics are controlled? This is the highest-value uncertainty. A classifier that fails here cannot be rescued by blockchain anchoring or a more elaborate signature system.

Published aggregate accuracy is an insufficient adoption criterion. The relevant error is **false certification**: a nonqualifying process receives HUMAN-WRITTEN. A genuine process receiving NOT PROVABLE is an availability/coverage cost, not an accusation. Both must be reported, including unsupported sessions and short passages rather than silently dropping inconvenient cases.

## 4.2 Ground truth must match the definition

Collect multiple sessions per participant, with paired or counterbalanced tasks across devices and writing conditions. Separate participant, task, source text, session, and device dependencies in the data splits. Genuine drafts and later retyping of the same wording are useful paired comparisons, but their unavoidable order and memory effects require additional counterbalanced prompt/source controls.

Qualifying conditions include unaided composition, composition after AI-assisted research, understanding an AI-provided argument and independently writing it, fluent expert writing, rough revision-heavy drafting, interruptions, and admitted input/accessibility modes. Negative conditions include ordinary transcription of human text and AI text, not just AI-generated prose.

Instructions, observed task conditions, and post-task accounts establish operational labels, not direct observation of cognition. Borderline paraphrasing, memorization, and mental rehearsal must be documented as ambiguous rather than labelled to make the model look better. Maintain a separate ambiguity set and report how often it passes. Do not train using a label that says all AI influence is nonhuman.

Participants' consent must cover the sensitivity of deleted drafts and behavioural traces. Public release should use appropriately governed data rather than publishing raw identifiable logs by default. A privacy-preserving proof is not permission to collect unrelated activity.

## 4.3 Attack matrix

| Attack family | What must be tested | What constitutes failure |
|---|---|---|
| Direct import | Clipboard, drag/drop, restored draft, programmatic text mutation | Unsupported material obtains a direct-composition origin or whole-document acceptance |
| Human transcription | Skilled, slow, fast, familiar-source, and deliberately revised copying | Acceptance beyond the released bound, including the ambiguity set |
| Simple scripted input | Constant/variable intervals, injected input through each admitted channel | Synthetic source is treated as admissible or routinely passes the model |
| Replay | Complete authentic traces, partial traces, changed content, reused commitments | Replay is accepted outside a compatible parent-provenance relationship |
| Matched statistics | Copied text with timing/edit-count distributions matched to composition | Detector's claimed relational advantage disappears or attack acceptance is excessive |
| Staged revision | Alternative drafts, deliberate mistakes, later corrections, structural changes | Cosmetic or scripted process theatre passes at unacceptable rates |
| Adaptive composition simulation | White-box optimization of the released detector with full text/edit-state knowledge | The published operational threat model understates achievable acceptance |
| Hardware-mediated input | External controllers/actuators where relevant to the declared sensor boundary | Device-origin evidence is misrepresented as human-origin evidence |
| Mixed authorship | Qualifying warm-up/introduction followed by an unsupported paragraph or sentence | Global averaging or neighbourhood borrowing conceals the unsupported span |
| Provenance laundering | Copy/move/undo, replacing words incrementally, transformed quotations, cross-document imports | Old ancestry is reset or inherited text is relabelled without compatible evidence |
| Collector compromise | Patched collector, fabricated timestamps, arbitrary-root signing API, untrusted IME | Accepted capture evidence binds only supplied data rather than the claimed acquisition path |
| Proof substitution | Authentic root plus different features/model/document/range map | Cryptography verifies without equality of all required public bindings |
| Freshness/fork grinding | Session resets, withheld checkpoints, parallel pseudonyms, repeated trials | A single-attempt test rate is marketed as an unrestricted attacker success bound |
| Social substitution | Ghostwriter, person relaying model output, another person holding the author's key | Composition is confused with named-author identity |
| Proof degradation | Unknown versions, removed artifacts, expired trust evidence, mock ZK receipts | Verifier silently downgrades to a weaker basis for HUMAN-WRITTEN |

Attack access and budgets must be stated: knowledge of weights and thresholds, number of trials, device access, ability to patch software, real-time feedback, and physical input access. A result against random timing scripts is not a result against white-box adaptive simulation.

Testing a hardware-input attack does not assert that every physical attack is practical or that every sensor can be cloned. It checks the actual boundary a profile claims to protect.

## 4.4 Evaluation discipline

Training, development/calibration, and final evaluation are disjoint. Fit feature scaling, missing-data handling, vocabularies, personalization, and thresholds without evaluation leakage. Freeze the entire pipeline before the final test. Use writer-disjoint and source/prompt-disjoint evaluation, then device-, language-, and attack-family-held-out evaluations. Randomly splitting windows from the same writer/session across train and test is not acceptable evidence of generalization.

Evaluate complete documents and independently labelled inserted spans. A word-level origin map is not evidence that the classifier has word-level discrimination. Include short inserted passages, boundary edits, quotations, and fragmented attacks. Test the exact deterministic aggregation procedure and every exemption.

Report coverage of genuine writing, false-certification counts and denominators, interval estimates, ambiguity-set admission, worst supported stratum, failures of capture completeness, out-of-domain abstention, and risk versus coverage. Report results separately by input mode and language, not only a pooled average. Unsupported strata remain unapproved.

Identity recognition is not the objective. Test on new people and on the same person across qualifying and nonqualifying tasks. Evaluate expertise, slow/fast writing, second-language writing, and assistive workflows without using health or demographic inference as a shortcut.

## 4.5 Quantifying the evidence burden

Suppose independent Bernoulli trials from a fixed, declared nonqualifying distribution produce zero false certifications. A one-sided 95% exact binomial upper bound is:

`p_upper = 1 - 0.05^(1/n)`.

To make that upper bound no larger than epsilon requires:

`n >= ceil(log(0.05) / log(1-epsilon))`.

The executed calculation gives:

| Target upper bound | Zero-failure independent trials required |
|---|---:|
| 1% | 299 |
| 0.1% | 2,995 |
| 0.01% | 29,956 |

These are per declared distribution under the model's assumptions, not a proof against all attackers. Sessions from one writer or one attack generator are correlated; counting every keystroke or window as an independent trial is invalid. Hierarchical/cluster-aware analysis and enough independent writers/attackers are required. A post-hoc choice of threshold invalidates the simple fixed-test interpretation.

For twenty prespecified families and simultaneous 95% coverage using a Bonferroni allocation, the zero-failure requirement at 0.1% is 5,989 trials per family. This is an illustrative mathematical requirement, not a proposed mandatory participant count or a claim that these trials have occurred. Nonzero failures require an appropriate binomial or dependence-aware interval rather than the zero-failure formula.

Open local classifiers also permit repeated attempts. With independent attempts each having success probability 0.001, 1,000 attempts yield:

`1 - (1 - 0.001)^1000 = 0.6323045752`.

For arbitrary dependence, a union bound is available only when the necessary per-attempt bounds actually hold; adaptive optimization may violate the calibration assumptions entirely. A release must report success by adversary budget, not imply that a low random-session rate protects against unlimited grinding.

A provisional research target might be a 0.1% upper false-certification bound with useful genuine coverage in a narrowly supported setting. It is a target to debate and test, not a chosen universal assurance level. The first experiment should measure the risk/coverage curve, not assume it can reach that target.

## 4.6 Ablations that determine whether the idea adds value

Compare timing-only, text-transaction-only, lineage-only, relational-process, and combined models. Compare the proposed model with an interpretable baseline, not only an unsuitable final-text detector. Test whether additional timestamp resolution improves decision quality after device differences are controlled.

Destroy selected cross-event dependencies while preserving timing and edit totals, and test whether the relational model detects the difference without relying on invalid-event artefacts. Then test a stronger simulator that preserves those dependencies. A gain against the first control does not establish resilience against the second.

Run genuine human transcription and genuine AI-informed composition under matched task conditions. If the model mainly detects AI influence, typing skill, or knowledge of the topic, it is optimizing the wrong objective.

Evaluate any live challenge independently: its burden on genuine writing, its marginal benefit, and attacks using human assistance or a language model. Passing a challenge cannot change the provenance of previously unproven text.

## 4.7 Certification release gates

A release can be externally approved only after all of these are evidenced: exact claim/scope semantics; a tested capture boundary; deterministic replay/lineage correctness; an independently evaluated detector; prespecified calibration; adaptive red-team results; per-stratum coverage/error disclosure; a working execution-evidence implementation; interoperable verifier tests; and privacy/security review of the resulting bundle.

The approval statement pins all artifacts by digest and identifies excluded threats. It must not approve a limited profile while displaying an unrestricted adversary-resistant badge. Models can improve without changing old proofs: new releases create new statements, while historical validity and current acceptance remain separate.

The release gate is deliberately empty in this research package. The existing 33 mechanics checks are useful but insufficient for any certification approval.

## 4.8 Decision boundary for further investment

The next justified investment is an adversarial, controlled composition-versus-transcription study using the proposed observation and lineage contract. It should include genuine AI-informed rewriting and white-box staged writing. Do not begin the writing application or invest in a costly ZK circuit before this test identifies useful separability and a credible capture profile.

If ordinary transcription is separable but adaptive attacks erase that separation, preserve the open provenance format while narrowing the assurance claim or improving the independent observation boundary. Do not compensate with a stronger-sounding signature or a more opaque score.
