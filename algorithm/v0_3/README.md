# HWP-A 0.3.0 — adversarially revised algorithm foundation

**Repository availability:** source-file uploads were blocked. The specification and permitted results are published here; the complete tested reference implementation is delivered separately as `HWP-A-0.3.0.zip`. Commands below apply to the complete package. See [publication status](PUBLICATION.md).

**Status: implemented reference method; no empirically validated human-writing detector or approved real-world certification release.** This is a second adversarial pass over the delivered HWP-A 0.2.0 package, not an independent third-party security audit. It covers the algorithm only.

The sole verdict values are `HUMAN-WRITTEN` and `NOT PROVABLE`. The latter does not allege AI use, copying, dishonesty, or nonhuman authorship. Every verdict also identifies its exact claim: **fresh-composition**, the default requested objective, or explicitly scoped **wording-origin**, which can preserve previously established wording ancestry but does not assert new composition or authorship of an assembly.

## Start here

Read [SPECIFICATION.md](SPECIFICATION.md) for the consolidated normative method, [AUDIT.md](AUDIT.md) for defects and counterexamples, [THEORY.md](THEORY.md) for what the assurance can and cannot mean, and [TELEMETRY.md](TELEMETRY.md) for collection and replay requirements. [FEATURES.md](FEATURES.md) defines the 179 integer features; [DATASET_PROTOCOL.md](DATASET_PROTOCOL.md) specifies the experiments and release gates. [API.md](API.md) provides executable entry points. [RESULTS.md](RESULTS.md) separates executed checks from missing empirical evidence.

```sh
cd algorithm/v0_3
python -m pip install -r requirements.txt
python -m unittest discover -s tests -v
python run_checks.py
```

The tested environment is recorded in `artifacts/results.json`. Replay, extraction and exported-model inference use integer arithmetic. Model fitting uses NumPy floating-point arithmetic; exact exported model values, not a promise about arbitrary future refits, define decisions. Statistical eligibility uses exact rational binomial tests; floating-point confidence intervals are descriptive.

## Principal changes from 0.2.0

Native input deliveries, authoritative mutations and raw input causes now share a strict total event order and explicit one-use binding. An approval flag or claimed model ID is insufficient: the trusted caller must select the exact capture records, model snapshot, threshold, path-specific domains and claim semantics. Synthetic or unknown-source control operations cannot inherit a supported process. Assisted spelling replacements receive no automatic human-origin credit. Copies preserve ancestry but cannot qualify as fresh composition. Source-exposure vetoes are causal and record-local. Full-model validation covers every branch and numeric value, including unvisited branches.

A complete preregistered ledger accounts for every attack attempt and genuine-writing task before calculating risk. Ambiguous ground truth is treated adversely for release eligibility, not silently excluded. Different input paths and genuine-writing conditions receive separate release cells. Missing attempts, incomplete labels, declared cross-phase dependencies, unsupported domains and unapproved releases fail closed.

## Important remaining boundary

A structurally valid record is not authenticated observation. The reference does not turn author-supplied `source="device"`, timestamps or `TrustedInputs` into evidence of human action. The capture-admission argument is supplied independently by a relying verifier or controlled experiment. Platforms without the required independently justified observation path remain unsupported.

All positive examples shipped here use explicitly permissive **synthetic test doubles**. They test control flow, not human detection. No participant corpus was collected and no real detector accuracy, coverage, mobile performance or adaptive-attack resistance was measured. The feature-collision regression deliberately demonstrates a limitation that training alone cannot remove from this fixed representation.

## Version preservation

The older repository implementation and earlier research remain in place. This directory is an additive, separately versioned revision. Version 0.2 observations must not be silently upgraded by inventing `seq` or `delivery` fields. New telemetry, features, thresholds, models, origin rules or claim semantics require new immutable release descriptions. An old assessment keeps its original interpretation; a later re-assessment is a separate result.
