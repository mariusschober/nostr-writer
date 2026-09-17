# HWP-A: human-writing verification algorithm

**Version 0.2.0 · executable specification · 15 September 2026**

This directory specifies and implements the algorithmic part of Human Writing Provenance. It contains no writing application, interface, publication integration, signing system or blockchain code. It extends the repository's earlier `research/hwp/02-algorithm.md` with fixed telemetry semantics, origin replay, segmentation, features, fitting, calibration and binary aggregation.

Start with [SPECIFICATION.md](SPECIFICATION.md). The implementation is runnable; the model is trainable. **No model trained on real human-writing data, measured human/transcription accuracy, admitted capture implementation, or approved HUMAN-WRITTEN release is supplied.** The test-double model is intentionally permissive and labelled `fixture`; it is not a detector.

## Technical contents

| Artifact | Purpose |
|---|---|
| [SPECIFICATION.md](SPECIFICATION.md) | Complete acceptance contract and fixed algorithm choices |
| [TELEMETRY.md](TELEMETRY.md) / [telemetry.schema.json](telemetry.schema.json) | Input records, native normalization requirements, Unicode/causal semantics |
| [FEATURES.md](FEATURES.md) | Exact fixed-point feature inventory and formulas |
| [THEORY.md](THEORY.md) | Observational boundary, lineage invariants and conditional finite-sample guarantee |
| [DATASET_PROTOCOL.md](DATASET_PROTOCOL.md) | Ground truth, annotation, splits, attack matrix, metrics and release gates |
| [API.md](API.md) | Direct Python/CLI integration and data flow |
| [RESULTS.md](RESULTS.md) | Executed results and exact limits of those results |
| [hwp_a/](hwp_a/) | Replay, features, integer inference, learning, calibration, metrics and attack mechanics |
| [tests/](tests/) | Deterministic conformance, adversarial-mechanics and statistical tests |
| [artifacts/](artifacts/) | Generated synthetic vectors, model test double and machine-readable results |

## Run

From this directory:

```sh
python -m pip install -r requirements.txt
python -m unittest discover -s tests -v
python run_experiments.py
```

The published run used Python 3.13.5, NumPy 2.3.5 and SciPy 1.17.0. Replay, feature extraction and inference use only the Python standard library; fitting and confidence-display calculations use the listed dependencies. The exported model uses integer decisions rather than a future floating-point refit.

```sh
python -m hwp_a --output rows.json extract cases.json
python -m hwp_a --output model.json fit rows.json
python -m hwp_a --output calibration.json calibrate calibration-request.json
python -m hwp_a verify artifacts/keyboard.trace.json --model artifacts/fixture-model.json
```

The last command returns NOT PROVABLE: loading an author-supplied trace and model cannot approve their capture or their inference release. The API supports the conditional positive branch only when a relying verifier separately supplies those prerequisites. There is deliberately no CLI `--trust-me` switch.

The two certification labels are HUMAN-WRITTEN and NOT PROVABLE. Quotes can be explicitly excluded from a separately scoped claim; they do not disappear from the complete document provenance map. Inherited writing retains its source origins and is not relabelled as the importing person's new composition.

## What constitutes progress from here

The computational foundation is executable and falsifiable. The next step is to instantiate it with controlled composition/transcription data and the full adaptive attack matrix, not to invent favourable thresholds or start the writing application. If no threshold meets the fixed risk/coverage requirements, the release remains noncertifying. That is a substantive experimental result, not a reason to conceal the failed family.

These materials are AI-assisted work and are not represented as HUMAN-WRITTEN. They do not imply standards-body adoption, legal certification, a security audit, or repository-wide licensing changes. No licence or patent commitment is silently granted on the owner's behalf.
