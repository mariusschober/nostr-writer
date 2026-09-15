# Second-pass adversarial audit and disposition

**Reviewed input:** the complete delivered HWP-A 0.2.0 archive, whose original 76 tests passed before changes. **Repository context:** main was `987400709908ab3b83c34c32cdc5eba077dd4209`, containing a different legacy A1 implementation; its `algorithm/reference.py` was also inspected. The full nine-file legacy repository implementation is not represented as exhaustively audited. This is a separate adversarial pass by the same assistant, not an external independent audit.

Positive reproductions below use an explicitly permissive conditional fixture model. They demonstrate implementation/claim errors independent of classifier quality, not achieved attacks on a trained human-writing model.

| Finding | Why it matters | Disposition and regression |
|---|---|---|
| Bounded spelling could change `100` to `900` and inherit HUMAN-WRITTEN roots | Edit distance does not preserve meaning or human composition | Removed assisted replacement inheritance. `test_numeric_spelling_not_inherited`, `test_letter_spelling_not_inherited` |
| Approval Boolean/threshold did not bind the chosen model | Relabelled or substituted model could inherit approval in a careless integration | Exact independently supplied model snapshot, threshold, domains and claim required. Model substitution tests |
| Claimed record ID was not sufficient to bind admission | Another trace with the same ID could receive an existing admission decision | Exact record snapshots and fresh-record set; snapshot substitution tests |
| Separate event streams did not establish a unique order on equal timestamps | Future causes or inconsistent focus ordering could be fabricated at the same tick | Contiguous total `seq`, strict cause→delivery→transaction ordering; timeline tests |
| Raw input could be associated with arbitrary text without independent native delivery | Physical-looking actions need not explain claimed wording | One-use native delivery effect binding; delivery mismatch, missing/unused delivery tests. Actual capture-path authenticity still external |
| A held-key repeat could occur outside focus | Source and chronology checks were not sufficient | State machine rejects out-of-observation repeat/IME/gesture/update and cross-interruption direct causes |
| Synthetic control actions could operate on previously supported words | Origin inheritance could conceal automated assembly/deletion | Unsafe-control state vetoes dependent process; synthetic control/deletion tests |
| Internal/external copies confused preserved wording with fresh composition | Accepted ancestors could imply the assembler composed them | Default fresh-composition rejects copied occurrences; separately evaluated wording-origin preserves literal ancestry |
| Unrelated/future source text could taint an earlier target | Noncausal bundle-global source inference produced false non-admission | Same-record prior exposure index and ancestry propagation; future/unrelated-source regression |
| Only visited tree branches/numerics were necessarily checked | Hidden malformed model payloads made behaviour path-dependent | Complete recursive artifact validation before inference; hidden-branch/float/bool tests |
| Counting raw causes overstated production evidence | Multiple modifiers, repeat pulses or one bulk transaction could inflate adequacy | One production-delivery component per connected physical episode, not cause count |
| Data links could disappear with empty/external-only feature extraction | Writer/source leakage could evade post-extraction checks | Case-level dependency validation before extraction; leakage tests |
| Ambiguous annotations could be dropped from the risk endpoint | Good-looking risk could depend on how borderline cases were omitted | U is adverse for eligibility and separate in descriptive reports; annotation-completeness tests |
| B=100 or all-task labels did not prove complete accounting | Missing attempts and tasks can artificially improve risk/coverage | Frozen slot ledger, exact attempt budgets, no pending outcomes, one result per slot, declared dependency checks |
| A pooled genuine-writing cell could hide poor AI-informed/expert coverage | Intended qualifying users could be excluded without visibility | Separate six-condition genuine-writing cells per profile/path/language; case-condition checking |
| Known cross-phase dependencies not explicitly checked | Final evaluation could be reused or correlated with calibration | `phase_separation` plus declared dependency checks; actual independence remains a study obligation |
| Unbounded repeated scans/evidence allocations | A valid-shaped trace could exhaust resources before verdict | Cached motor durations, bounded history/effect/source/analysis work, early size checks; limit tests. No production memory benchmark claimed |
| Meaningful text substitutions leave all 179 features identical | Representation omits information; deeper fitting cannot recover it | Exact collision regression retained, mandatory attack evaluation, no claim of an optimal semantic detector. **Not solved by current feature family** |
| Passing a valid record was conflated with observing real composition | A perfect parser cannot authenticate a fabricated record or hidden mental cause | Explicit capture boundary and equivalence theorem. **No universal observer-only guarantee** |

## Reproduced old counterexamples

`artifacts/v02-counterexamples.json` records the actual old conditional outputs: numeric spelling and model substitution returned HUMAN-WRITTEN, a later unrelated source flipped a genuine-shaped target to NOT PROVABLE, and a repeat outside focus passed old structural replay. Sixteen corresponding feature units remained identical under an alphabet substitution. The new tests additionally preserve a collision using ordinary meaningful word replacements.

The old-generation reproduction script is archived alongside its outputs and requires the original 0.2.0 source directory. New regressions build 0.3 synthetic records directly; they do not invent missing observations for real 0.2 captures.

## Decisions not justified as empirical facts

The 64-root minimum, 16/4 production components, 32-scalar source veto, 120-second run boundary, 250-ms cause bound, four heads, 32 shallow trees, 0.1% target, 50% coverage target and B=100 campaign remain explicit engineering/release choices. They were not estimated from human data. Every choice has deterministic semantics so an experiment can reject it. There is no hidden "human score" whose calibration is deferred to intuition.

An automatic spelling exemption, nominal model IDs, incomplete attempts and future source exposure were resolvable errors and have been removed. Behavioural separability, actual independent capture, realistic campaign sampling and label ambiguity cannot be repaired by assertion. The revision preserves those uncertainties and prevents their absence from being treated as successful verification.
