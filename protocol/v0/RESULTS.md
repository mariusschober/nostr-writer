# Executed results — Human Writing Protocol v0

The frozen package executed **178 tests: 178 passed; 0 failures; 0 errors; 0 skips**. This count includes the ported algorithm/calibration suite, actual integration tests, strict crypto tests, native-control and statistical-boundary regressions, private-transport tests and timestamp checks. A randomized replay test contains2000 comparisons, not2000 independent participants.

Before reconciliation, the original A03 and C1 archives passed100 and95 tests respectively. They are separate baseline executions, not additional v0 tests. Reproduced counterexamples and the false Unicode-mismatch suspicion are recorded in the audit rather than silently counted as fixes.

The separately written JavaScript class-V verifier and binding checker passed 16 public cases, including the required refusal of disclosed mode and a deliberately lying admitted evaluator. It checks canonical encodings, authority/release/scope/target rules, signed roles and private commitment/record normalization. It is not a second behavioural implementation.

Fresh processes with PYTHONHASHSEED0 and987 produced identical vectors, also identical to the frozen vector file. The exact test IDs, environment and boundary warnings are in `vectors/results.json`. Routine checks do not overwrite frozen files.

Real participant sessions:0. Models trained on real human data:0. Evaluated native capture paths:0. Empirically approved releases:0. Real Human Writing Proofs issued:0. ZK proofs generated:0. No detector accuracy, adaptive-attack probability or guarantee of indefinite cryptographic lifetime was measured.

All conditional positive examples use public synthetic keys and fixture-only release policies. Their public outcome is TEST-ONLY/NOT PROVABLE. Attestation can accept an admitted evaluator's lie; the tested complete recomputation rejects the pasted-history example. Honest capture and empirical admission remain prerequisites, not consequences of passing these tests.
