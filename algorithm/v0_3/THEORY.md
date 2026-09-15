# Theory, counterexamples and assurance boundaries — HWP-A 0.3

This file separates deductions from empirical hypotheses. It does not claim that a cognitive process has been observed directly.

## 1. Raw-observation equivalence

Let P be the observation distribution of genuine composition, Q that of a specified nonqualifying process, and A any measurable acceptance region. Genuine coverage is P(A); false certification is Q(A). By total variation,

`Q(A) >= P(A) - TV(P,Q)`.

Equivalently, false certification plus genuine non-admission is at least `1-TV(P,Q)`. This follows immediately from `P(A)-Q(A) <= sup_B |P(B)-Q(B)|`. It applies to every deterministic rule and to randomized rules by including their randomness in the observation space.

If an adversary can submit any accepted record as an admissible observation, one accepted record supplies a false-positive construction. No nonvacuous observer-only rule has universal soundness against that input power. This is a conditional theorem about adversary capabilities, not a claim that every protected sensor can in practice be cloned. It explains why record validity, source authenticity and behavioural inference are separate obligations even in an algorithm-only specification.

Typing from an already composed sentence and typing from a memorized source can yield identical records. A person who understands a source can intentionally revise it. Nonuniform timing, revision topology, responsiveness and even semantic consistency are not unique signatures of human composition. Adding unpredictable challenges would change the experiment, not retroactively establish the origin of earlier wording. No challenge is granted certification power here.

## 2. Feature equivalence is an additional, avoidable information loss

For deterministic feature map F, `TV(F#P,F#Q) <= TV(P,Q)`. The feature classifier can never distinguish two records mapped to the same features, even when richer raw evidence could distinguish them. Training deeper trees on the same features does not recover information that F discarded.

The shipped regression constructs equal-length meaningful word substitutions while retaining motor/operation/syntax structure; every feature of every evidence unit remains identical. This is not a measured false certification by a trained detector. It is an exact limitation of this representation. Arbitrary spelling noise is not required for the example. The open attack suite must include such collisions, matched transcription and semantic staged revision. A valid release may discover that no useful threshold exists for these attacks.

There is no distribution-free "strongest classifier" without a specified alternative class, observations and loss. Neyman–Pearson optimality requires specified distributions; a four-head discriminative minimum is not automatically a likelihood-ratio test. HWP-A therefore fixes an implementable baseline and the exact falsification/release contract, rather than declaring 179 features or shallow trees optimal without evidence. Improving observations or learned representations remains an empirical comparison requiring new validation.

## 3. Origin invariants are deductive; composition is not

Induction on replay operations gives unique live atom IDs: insert/copy allocate fresh IDs; move permutes existing IDs; delete removes IDs; undo/redo restore stack-checked original ranges. Root ancestry changes only through fresh direct candidate creation or explicit unsupported insertion. Copy, move and history restoration cannot reset external ancestry. Exact prestate and final-text checks establish what the supplied transaction record reconstructs.

These facts establish invariants **of the supplied record**. They do not show that it happened in the physical world. A native delivery equality check prevents an implementation from attaching unrelated text to a recorded key event only when both sides of that binding were independently observed under the admitted path. Echoing attacker data into both fields proves nothing.

The spelling counterexample resolves a semantic mistake: a small edit distance does not bound change in meaning. Rejecting inheritance for assisted replacements is deductively safer than claiming an arbitrary distance threshold preserves composition. It increases non-admission for harmless correction; that cost is measurable.

## 4. Conservative range aggregation

Let v_r be the minimum score across all mandatory units for root r. Let v_i be the minimum score of the roots of final scalar i, with unsupported evidence mapped to bottom. Then acceptance of a document implies acceptance of every required scalar. No genuine prefix can numerically compensate for a low-scoring inserted span. Exclusions do not alter v_i, so changing scope cannot train or select favourable units.

This is an aggregation guarantee, not a localization theorem. An unobserved transcribed word inside an otherwise composition-shaped neighbourhood can still receive high contextual support. The empirical loss therefore counts any falsely admitted scalar, including tiny mixed-origin insertions, even when the overall document fails. Character-level bookkeeping is never advertised as independent character-level cognition discrimination.

The fresh-composition predicate adds a deterministic condition: a scalar must be its own sole root in the target record. A copied occurrence cannot pass merely because its ancestor passes. Wording-origin is a different question and must have a different declared claim and independently evaluated release cells.

## 5. Exact finite-family risk calibration

For fixed threshold t and fixed attack cell j, let Z_b indicate that any false scalar passes in block b, including all B adaptive attempts. Assume blocks are independent and identically distributed draws from the preregistered block-generating policy. Then K=sum Z_b is binomial(n,p_j(t)). Independence of the attempts or windows inside a block is unnecessary because the block outcome is formed first.

At target ε, the tail `Pr[Binomial(n,ε) <= K]` is a valid conservative p-value for rejecting p>=ε. The nonnegative-integer recurrence in calibration.py evaluates it exactly for rational ε and α; a rounded displayed upper bound never grants eligibility. Human coverage is handled as a binomial lower-bound test by counting failed complete task blocks at target 1−c.

For J attack cells, H genuine cells and T thresholds fixed before calibration, allocate δ/(2JT) to each attack test and δ/(2HT) to each coverage test. The union bound controls the probability that any eligible threshold violates any tested bound by δ. This permits choosing the smallest eligible threshold after seeing calibration outcomes because every candidate was included in the error allocation. It does not permit modifying features, selecting new thresholds or adding uncounted domains after seeing failures.

Cells may share participants without invalidating the union bound across cells. Within a cell, counting the same participant/adaptive state as multiple independent blocks invalidates the binomial premise. Identifiers and ledger links can detect declared overlap but cannot prove actual independence. Shared training of adversaries across nominally independent campaigns changes the generating policy; hold the policy fixed, use independently reset training/attack states, or treat a whole coordinated experiment as one block. There is no automatic clustered-binomial repair for arbitrary dependence.

Ambiguous U annotations enter adverse risk masks and cannot supply genuine-coverage successes. This bounds a worst-case interpretation of the ambiguous observed cases without asserting that those cases are actually nonhuman. Missing annotations or attempts are not negative trials and must block eligibility.

## 6. Repeated attempts, prevalence and distribution shift

A per-attempt bound p implies independent-attempt success `1-(1-p)^B`, not p. Without independence, a union bound Bp requires valid appropriate marginal/conditional bounds for the actual attack process. Adaptive optimization can destroy those premises. The baseline measures B=100 campaigns directly; it does not derive them from B=1 results.

A false-certification risk bound is conditional on the negative sampling distribution. It is not the fraction of accepted texts that are nonqualifying. Given genuine prevalence π, genuine coverage c and false certification f, the positive predictive fraction is `πc / [πc+(1-π)f]` when those quantities describe the deployment mixture. Unknown/adversarial prevalence prevents conversion to a universal confidence-per-document statement.

If deployment negative distribution Q differs from evaluated Q0 by TV at most η, then `Q(A) <= Q0(A)+η`. No estimate of η is provided. Unlimited adaptive attackers, hardware replay, unmeasured languages, different input decoders and distribution drift do not become covered because the model is open or the interval arithmetic is exact.

Calibration and final evaluation are separate statistical statements. A final independent test of one frozen threshold can give its own δ guarantee. Claiming all stages simultaneously satisfy a bound requires an explicit combined error allocation. Repeated model revisions against the same final holdout are not independent confirmations; freeze a new holdout or implement a separately specified sequential testing design.

## 7. What remains empirical

The achievable risk/coverage frontier against skilled transcription and white-box staged behaviour; adequacy of the fixed features; mobile decoder observability; useful minimum episode lengths; accessibility coverage; out-of-domain rejection; timing-resolution sensitivity; campaign dependence; label reliability and actual end-to-end capture attacks remain unmeasured here. No amount of deterministic replay testing answers them. An empty eligible set is a valid result, not permission to weaken the claim silently.

The statistical separation of fitting from finite-family testing is consistent with [Learn then Test](https://arxiv.org/html/2110.01052v5). The need for threat-aware adaptive evaluation is also illustrated by [Athalye et al.](https://proceedings.mlr.press/v80/athalye18a.html); that paper concerns other model domains and supplies no HWP accuracy estimate.
