# What the algorithm can establish

This document separates mathematical statements from empirical requirements. The counterexamples are not claims that every sophisticated simulation is already practical. The confidence calculations are not measurements of this detector's accuracy.

## 1. Observable equivalence is the governing constraint

Let C denote a genuinely composed process and A a nonqualifying process. Let E be **all admissible observations**, including motor events, text changes, navigation, timing and whatever additional modalities a future release actually obtains. Let an algorithm accept with probability a(E), allowing internal randomness.

If two processes induce the same distribution of E, then they induce the same distribution of decisions. This follows by integrating the same bounded function a against the same probability measure. More sensing helps only if it changes that equality. Increasing sampling resolution of already identical observations does not create information about the hidden cause.

For distributions P_C and P_A, define composition coverage γ=E_C[a(E)] and false-certification probability ε_A=E_A[a(E)]. By the variational characterization of total variation,

`γ − ε_A ≤ TV(P_C,P_A)`.

Equivalently, false certification plus genuine non-admission is at least `1−TV`. For identical distributions, γ=ε_A. Thus, requiring ε_A≤0.001 against an attack reproducing the composition distribution forces γ≤0.001 on that same distribution. No classifier can simultaneously evade those requirements by using an opaque score.

A stronger pointwise statement follows for an unrestricted source-controlling adversary. For every accepted observable trace that can be supplied as a fabricated trace, there exists a nonqualifying cause that the algorithm also accepts. Zero false acceptance against that class forces rejection of all such traces. This is a derivation, not a claim of failure merely because the subject is difficult or unsolved.

The implemented equality test uses one identical synthetic trace under two different alleged latent causes. Features and scores must be identical. Changing a metadata label cannot cause the verifier to acquire unobserved information. The test prevents future claims that a successful hash, label, telemetry parser or model computation has resolved hidden cognition.

### Consequence for the standard

The useful research question is whether physically credible, independently observed processes retain separable structure against particular capable adversaries. The standard can define and test a conditional acceptance region. It cannot truthfully advertise that finite passive observations universally prove the origin of a person's wording.

External capture admission can reduce the set of admissible fabricated observations. It still does not itself distinguish a genuine human transcriber from a genuine human composer. These are two separate requirements.

## 2. What exact replay proves

Assume the normalized observation/transaction record is authentic, complete and correctly attributed under its external capture contract. By induction over transactions:

- Each new occurrence ID is fresh.
- Each candidate root refers to its recorded creating action.
- Each copied occurrence has exactly its parent's origins, with an added destination dependency.
- Each move changes position but not identity.
- Each history operation restores only a previously recorded atom state.
- Each spelling derivation retains all required roots and cannot recursively create effort.
- The live state after each operation is uniquely determined by the preceding state and the operation.

The base case is the empty document. Each operation either creates fresh IDs, transports existing IDs, or applies a stack-validated inverse to exact prior IDs. The fresh-ID and history-prestate checks prevent duplicate live identity and arbitrary origin reset. Therefore, the final origin partition is deterministic, assuming those operation semantics and the authenticity premise.

This proves bookkeeping properties, not composition. A valid direct input is still only a candidate origin. Root and source preservation prevent a favourable label from being manufactured through copy/move/undo; they do not prove that a human did not read predetermined text from elsewhere.

## 3. Why the decision is conjunctive

Let U(r) be the pinned set of birth, retained, layout and global units containing root r. The threshold score is the minimum over all those units, then over every root required by a final scalar. This yields useful monotonicity properties with the **graph and unit set held fixed**:

1. Raising the threshold cannot increase admitted coverage.
2. Lowering a required unit score cannot improve any dependent scalar's verdict.
3. Removing capture or domain admission cannot create a positive result.
4. A failed required scalar prevents a whole-document positive result.
5. Excluding a quotation does not change any scalar score or origin.

These are not claims that arbitrarily editing the document can never change segmentation or features. It can. Fragmentation, rearrangement, padding and scope-selection attacks must therefore be evaluated against the complete pipeline, not dismissed by monotonicity of a fixed score vector.

A global average lacks property 4: a strong unrelated section can compensate numerically for a copied section. HWP-A forbids that compensation. Its cost is conservative false non-admission, including cases where a global process check vetoes otherwise plausible local writing.

## 4. Exact finite-sample risk control

Fix the entire feature/model/support/segmentation pipeline using training and development data. Fix the finite candidate threshold set T before examining calibration outcomes. Fix all required attack and human cells before collecting or revealing their calibration results.

For cell j and threshold t, let X_jt be the number of successful attack campaigns out of n_j independent campaigns drawn from the **specified fixed campaign distribution**. Each campaign can contain dependent, adaptive attempts. Its Bernoulli outcome is one if any falsely labelled scalar passes. Dependence inside a campaign does not invalidate the Bernoulli definition. Dependence between nominal campaigns, unregistered cherry-picking, or changing their generator based on the calibration results does invalidate the sampling argument.

The one-sided Clopper–Pearson upper confidence bound U satisfies

`Pr[p_jt > U(X_jt,n_j,α)] ≤ α`.

For X=0, `U=1−α^(1/n)`. For X=n, U=1. Otherwise it is the `(1−α)` quantile of Beta(X+1,n−X). The lower genuine-coverage bound is the α quantile of Beta(K,n−K+1), with lower bound zero for K=0.

Allocate total failure probability δ/2 across the J×|T| attack bounds and δ/2 across the K×|T| genuine-coverage bounds. By the union bound, all the statements hold simultaneously with probability at least 1−δ. Therefore, selecting any threshold whose bounds all satisfy the frozen targets preserves the guarantee. Choosing the smallest eligible threshold maximizes admission among those eligible candidates because the decision is threshold-monotone.

No independence is required between different cells or thresholds for this union bound. Independence or an appropriate sampling model is required within each cell's counted campaigns. Repeated attempts are aggregated; repeated windows are not new people.

This is a Learn-then-Test-style use of finite-family statistical testing. The general framework is described by Angelopoulos et al. [1]. The specific campaign loss, threshold grid, family matrix, abstention logic and exact integer eligibility calculation here are the HWP-A design.

### 4.1 Integer-exact eligibility, approximate display bounds

The code does not approve based on rounded beta quantiles. To establish upper risk ≤ε it checks

`Pr[Binomial(n,ε) ≤ X] ≤ α`.

For coverage ≥c it checks the analogous lower-tail probability for the number of failed human clusters at parameter `1−c`. Decimal parameters are converted to exact rationals, including the Bonferroni allocations.

For p=a/b, the binomial lower tail has integer numerator

`Σ(i=0..X) C(n,i) a^i (b−a)^(n−i)`

and denominator `b^n`. The implementation compares cross-multiplied integers and stops early when a nonnegative partial sum already exceeds the allowed probability. The recurrence between successive binomial terms is integer-exact. Unit tests compare this recurrence with direct rational summation over a grid of counts and probabilities.

Reported decimal confidence bounds use SciPy's beta quantiles for readability. They do not determine eligibility. This distinction removes floating-quantile rounding as an admission loophole; it does not remove uncertainty about labels or sampling assumptions.

### 4.2 The evidence burden

At one fixed test and α=0.05, a zero-error 0.1% upper bound needs 2,995 independent trials. Under this release matrix, the per-cell α is smaller because many cells and candidate thresholds are considered. For one admitted input/language combination, J=16 (eight families at two budgets); with 32 candidates, α_attack=0.025/512. The accompanying results compute the corresponding larger zero-failure requirement.

A cluster containing 100 attempts still contributes one campaign observation. Its success probability may be much higher than a single attempt's. The confidence bound estimates that campaign probability directly rather than multiplying a random single-attempt estimate under an unjustified independence assumption.

For illustration only, truly independent attempts each succeeding with probability 0.001 have success probability `1−0.999^1000`, about 63.23%, over 1,000 attempts. This formula is not an analysis of an adaptive white-box attacker. Such an attacker may change its success probability after every query or optimize locally without reporting any query.

## 5. What the guarantee does not say

The result is not the probability that this particular document is human. It is not a posterior that can ignore real deployment prevalence. It is not a claim about an untested language, disability/accessibility workflow, decoder, device boundary, new attack family, or indefinitely repeated local optimization.

A small support distance is not a human-origin theorem. A public simulator can target the support region. Four discriminative heads are not four independent witnesses; their minimum is not obtained by multiplying independent probabilities. Their combined effect is measured by whole-pipeline calibration.

Operational ground-truth labels also need scrutiny. A task instruction to compose does not reveal every internal mental act. Memory, prior wording and genuinely AI-informed rewriting can create ambiguous cases. The standard preserves U labels and separately reports their admission instead of redefining uncertain labels to make the confidence interval smaller.

If the unrestricted attacker can realize exactly the accepted observations, no chosen empirical distribution closes that theoretical gap. The honest result is a restricted assurance claim or no positive certification. This is why the distributed artifacts authorize no real positive certificates until both the observation assumptions and the relevant empirical claims have been substantiated.

## References

[1] Angelopoulos, Bates, Candès, Jordan and Lei, *Learn then Test: Calibrating Predictive Algorithms to Achieve Risk Control*, arXiv:2110.01052, v5 (2022). https://arxiv.org/abs/2110.01052 . Used for the statistical-testing framework, not evidence of human-writing detection accuracy.
