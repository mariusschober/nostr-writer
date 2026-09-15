# Executed results — HWP-A 0.3.0

The original delivered 0.2.0 package passed its 76 existing tests before this audit. Its reproduced counterexamples are archived in `artifacts/v02-counterexamples.json`. The original archive identity is in `artifacts/baseline.json`.

The revised suite executed **100 tests: 100 passed, zero failures, zero errors, zero skips**. This includes four normalized input profiles, total-order delivery/cause bindings, copied-origin/fresh-composition separation, assisted replacement rejection, exact model/record selection, unvisited model-branch validation, source chronology, Unicode, complete trial ledgers, per-condition release cells, dataset leakage and rational-binomial checks. One test performs 2,000 randomized splice/replay comparisons; they are not 2,000 independent human trials.

`run_checks.py` regenerates the full test IDs, output and deterministic feature vectors. Separate fresh Python processes with `PYTHONHASHSEED=0` and `PYTHONHASHSEED=987` produced byte-identical stable inference-vector JSON for all four synthetic input profiles. Exported inference uses integers; this does not promise identical floating-point model refits across arbitrary platforms. Python compilation checks also passed.

The exact meaningful-text feature-collision test remains positive: different wording can yield identical 179-feature vectors. This is a documented limitation, not a repaired issue or evidence of trained-model robustness. The positive HUMAN-WRITTEN control-flow tests use a deliberately permissive synthetic model under explicit test-controller assumptions. They must not be interpreted as certification of the generated text.

**Real human participant sessions: 0. Models trained on real human data: 0. Native capture paths tested: 0. Empirically approved releases: 0.** Human/transcription accuracy, adversarial false-certification probability, genuine-writing coverage and end-to-end capture resistance were not measured. No confidence bound on those unobserved quantities is claimed.

The runnable package is implementation-ready for controlled evidence collection, deterministic replay/inference, attack construction and evaluation. It is not an empirically validated detector, independent security audit, accepted standards-body standard or a production capture implementation.
