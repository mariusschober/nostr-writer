## Task 2

Created HWP-A 0.2.0: a 43-file algorithm specification and executable reference package, with 179 precisely defined features and 76 passing tests.

Download the complete packageReader · 
Read the technical specification · Download the additive Git patch

This iteration was not pushed to GitHub. The connector available in this session exposes reads but no repository-write action; direct Git access also failed because the execution environment could not resolve github.com. I verified that the patch applies to a clean Git repository, reran all 76 tests there, and checked that every resulting file matches the delivered package byte-for-byte. It adds algorithm/ without modifying the earlier research or cryptographic files.

What is now specified and implemented

The package fixes the decisions that the earlier research left open: telemetry fields, causal relationships, replay semantics, origin inheritance, segmentation, feature formulas, numerical precision, model fitting, support checks, threshold selection, passage aggregation, attack accounting and release eligibility.

The algorithm follows:

Validated observations → exact replay → origin graph → fixed evidence neighbourhoods → learned composition tests → calibrated binary decisions.

Text ancestry is deterministic. Every inserted character receives an origin identity. Copies retain their original ancestry without creating new composition effort; moves preserve identity; undo and redo restore the original provenance. Unsupported material does not become supported merely through rearrangement. A narrowly bounded spelling exception preserves its dependencies, and the evaluation machinery tracks negatively labelled transformations rather than hiding them behind genuine parent text.

Behavioural evidence is evaluated in four fixed views. The algorithm examines creation order, the creation order of surviving text, final document order, and the overall process. Local windows use explicit widths and overlaps, including end-aligned windows so awkward tails cannot disappear. Repeated copies cannot manufacture the required number of distinct origins. A strong introduction cannot compensate numerically for an unsupported passage.

The minimum-evidence rules are explicit: at least 64 distinct origin roots per evaluated unit, together with profile-specific production-episode requirements. These are conservative engineering choices, not claims that 64 characters reveal cognition. Short or interrupted additions can remain NOT PROVABLE even when their provenance is known exactly.

The detector is completely defined rather than delegated to an unspecified intelligence layer. It computes 179 fixed-point features covering contextual timing, actual input episodes, revision ages, navigation, operation sequences, cancellation, bounded lexical relationships between revisions, and changes within the writing process. It does not ask an external language model whether the final prose sounds human.

Four learned heads evaluate composition against transcription, automation, simulation and mixed-origin examples. Each uses 32 depth-two trees, with fixed fitting rules and integer-valued inference. Their minimum margin supplies the behavioural score. Neither that margin nor the support diagnostic is presented as a probability that a document is human.

Keyboard, touchscreen-tap, IME and gesture input have separate observation contracts and model domains. Missing input-method observations are not replaced with invented keystrokes. Native adapters and actual capture authenticity remain prerequisites; this package does not pretend that a plausible telemetry record authenticates itself.

The acceptance rule is conservative—and experimentally accountable

A character passes only when every required origin, capture, evidence and model condition passes. A whole-document HUMAN-WRITTEN result requires every required character to pass. Quotations can be excluded from a separately scoped contribution claim, but the exclusion remains explicit and does not produce an unqualified whole-document claim.

The evaluation endpoint is deliberately strict: one falsely admitted character anywhere in an attack campaign counts as a false certification. It does not disappear into a high average accuracy or a mostly genuine document.

Repeated attempts are counted together. The mandatory evaluation matrix covers eight attack families at budgets of one and 100 complete attempts for each proposed input/language domain. Overlapping windows and repeated queries are not counted as independent participants.

Threshold selection is also implemented. Candidates are fixed using development data; calibration accounts for selection among those candidates and for multiple evaluation cells. Eligibility requires every registered attack cell to satisfy the specified risk bound and every required genuine-writing cell to satisfy the coverage requirement. Missing cells block eligibility.

Importantly, eligibility decisions use exact rational binomial tests with integer arithmetic. Rounded confidence intervals cannot make a release pass. The numerical confidence bounds are displayed separately. The mathematical justification and its sampling assumptions are in 
THEORY.md.

What the tests establish—and what they do not

The 76 tests passed with zero failures, errors or skips. They exercise replay, Unicode boundaries, ancestry preservation, input-cause reuse, IME accounting, all four input profiles, segmentation, fixed-point features, both conditional decision branches, learning, dataset leakage checks, calibration, campaign aggregation and adversarial fixtures. The complete 
executed results are included.

The package also supplies staged-transcription construction, timing variation and bounded adaptive timing search. Those are executable attack mechanisms, not evidence of resistance to the complete adversarial threat model.

There are no real human participant sessions, no model trained on real human-writing traces, and no measured human-versus-transcription accuracy in this deliverable. The distributed model is an explicitly permissive test double used to exercise the pipeline and approval boundary. It cannot legitimately issue real HUMAN-WRITTEN results.

The governing theoretical constraint is preserved: when genuine composition and a nonqualifying process produce identical admissible observations, an observer cannot distinguish their hidden causes. The specification derives that boundary and defines a conditional, falsifiable assurance claim instead of asserting universal cognitive proof.

The computational algorithm and its evaluation machinery are implemented. Whether the specified false-certification target is achievable with useful genuine-writing coverage against adaptive transcription remains an empirical question. The package makes that question testable without leaving the implementation choices undefined or inventing favourable accuracy figures.
